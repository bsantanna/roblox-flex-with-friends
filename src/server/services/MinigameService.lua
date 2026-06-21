--!strict
-- MinigameService: the generic NPC-minigame framework. It owns the shared lifecycle every NPC
-- minigame follows and hands off only the game-specific play to a plugin:
--
--   Request(player, npcId, model)
--     1. validate: profile · no active session (one game at a time) · unlock gate
--     2. NpcActor walks the NPC to its arena, facing the approach
--     3. ReadyZone: a green disc appears in front of the NPC; the player must step onto it
--        (MinigameAwaitReady -> client hint; ReadyTimeoutSeconds to arrive or the game aborts)
--     4. the NPC explains the rules in a speech bubble (visible to all) and the player gets a Start
--        button (MinigameInstructions -> MinigameConfirmStart; ConfirmTimeoutSeconds or it aborts)
--     5. game:begin(session) — the plugin runs its rounds, awards followers, fires its own UI remotes
--     6. the plugin calls session.finish() (or a disconnect/timeout aborts) -> NPC walks home, clear
--
-- Plugins live under minigame/games/ and are auto-registered by their NpcId; each owns its gameplay
-- remotes/logic and implements only begin()/abort(). Shared NPC motion/posing is minigame/NpcActor;
-- the ready-zone is minigame/ReadyZone. Tunables: Config.Minigame (cross-game) + Config.Npc[npcId].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SpeechBubble = require(ReplicatedStorage.Shared.Util.SpeechBubble)
local DataService = require(script.Parent.DataService)
local NpcActor = require(script.Parent.minigame.NpcActor)
local NpcPromptService = require(script.Parent.NpcPromptService)
local ReadyZone = require(script.Parent.minigame.ReadyZone)

local MinigameService = {}

-- A plugin: declares which NPC hosts it and runs the actual game when handed a session.
-- Init/Start are optional — some modules (like the SimonSays factory) don't need them.
-- We always guard with type() before calling.
export type Game = {
	Id: string,
	NpcId: string,
	begin: (self: any, session: Session) -> (),
	abort: (self: any, session: Session) -> (),
	Init: () -> (),
	Start: () -> (),
}

export type Session = {
	player: Player,
	npcId: string,
	model: Model?,
	actor: NpcActor.NpcActor?,
	choreActor: NpcActor.NpcActor?, -- chore patrol actor from DialogService (shared with chore)
	citizenWalkActor: NpcActor.NpcActor?, -- citizen walk actor from DialogService (shared with citizen walk)
	game: Game,
	def: any, -- full Config.Npc entry (for chore check, etc.)
	homePosition: Vector3, -- where the NPC walks back to when the session ends
	homeYaw: number,
	phase: "pregame" | "instructions" | "playing",
	confirmed: boolean,
	alive: boolean, -- flipped false the moment the session ends; plugin loops check it to stop
	state: any, -- plugin-private gameplay state
	finish: () -> (), -- the plugin calls this on normal game over -> NPC walks home, session clears
}

local awaitReady: RemoteEvent
local instructionsEvent: RemoteEvent
local confirmStart: RemoteEvent
local aborted: RemoteEvent

-- One game at a time: the NPC is a single shared model that physically walks to the arena.
local active: Session? = nil
-- npcId -> plugin, built from minigame/games/ at Init.
local gamesByNpc: { [string]: Game } = {}

local function npcRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

-- Ends the session: stops the plugin if it was mid-play (interrupted), walks the NPC home, clears
-- the slot. interrupted=false is the plugin's own normal game-over; true is a timeout/disconnect.
local function endSession(session: Session, interrupted: boolean)
	if active ~= session then
		return
	end
	active = nil
	session.alive = false

	-- Restore the NPC's "Talk" prompt so the player can interact again.
	NpcPromptService:Show(session.npcId)

	if interrupted and session.phase == "playing" then
		session.game:abort(session)
	end

	local actor = session.actor
	if actor then
		task.spawn(function()
			actor:walkTo(session.homePosition, session.homeYaw)
			-- Resume chore patrol after the NPC walks home.
			if session.choreActor then
				NpcActor.resumeChore(session.choreActor)
			end
			-- Resume citizen walk after the NPC walks home.
			if session.citizenWalkActor then
				NpcActor.resumeCitizenWalk(session.citizenWalkActor)
			end
		end)
	end
end

-- The pre-game flow (runs in its own thread; it yields). Each step re-checks session.alive so a
-- disconnect mid-flow stops it.
local function runPregame(session: Session, def)
	local mg = Config.Minigame

	-- 1. Walk the NPC out to its arena.
	if session.actor then
		session.actor:walkTo(def.ArenaPosition, def.SpawnYaw)
	end
	if not session.alive then
		return
	end

	-- 2. Ready-zone: a disc in front of the NPC (along its facing) the player must step onto.
	local facing = CFrame.Angles(0, math.rad(def.SpawnYaw), 0).LookVector
	local center = def.ArenaPosition + facing * mg.ReadyZone.Offset
	local zone = ReadyZone.create(center, mg.ReadyZone.Radius, mg.ReadyZone.Color, mg.ReadyZone.Height)
	if session.player.Parent then
		awaitReady:FireClient(session.player)
	end

	local entered = false
	local deadline = os.clock() + mg.ReadyTimeoutSeconds
	while session.alive and os.clock() < deadline do
		local character = session.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and zone:contains((root :: BasePart).Position) then
			entered = true
			break
		end
		task.wait(0.1)
	end
	zone:destroy()
	if not session.alive then
		return
	end
	if not entered then
		if session.player.Parent then
			aborted:FireClient(session.player)
		end
		endSession(session, true)
		return
	end

	-- 3. Instructions in the NPC's speech bubble (all see) + a Start button on the player's screen.
	local root = npcRoot(session.model)
	local bubble = if root then SpeechBubble.create(root) else nil
	if bubble then
		bubble:setText(def.Instructions)
		bubble:show()
	end
	if session.player.Parent then
		instructionsEvent:FireClient(session.player, def.Instructions)
	end

	session.phase = "instructions"
	local confirmDeadline = os.clock() + mg.ConfirmTimeoutSeconds
	while session.alive and not session.confirmed and os.clock() < confirmDeadline do
		task.wait(0.1)
	end
	if bubble then
		bubble:hide()
	end
	if not session.alive then
		return
	end
	if not session.confirmed then
		if session.player.Parent then
			aborted:FireClient(session.player)
		end
		endSession(session, true)
		return
	end

	-- 4. Play: hand off to the plugin. It awards followers and fires its own UI remotes, then calls
	-- session.finish() (already wired to endSession) when the game is over.
	session.phase = "playing"
	session.game:begin(session)
end

-- Starts a minigame for `player` at NPC `npcId`. Called by DialogService after the Train choice;
-- the unlock check repeats here as defense in depth. `model` is the NPC (nil-safe: a fallback body
-- just won't walk/pose). `choreActor` is the chore patrol NpcActor from DialogService (for chore
-- pause/resume — the minigame's own actor instance is for walkTo/arena movement). `citizenActor` is
-- the citizen walk NpcActor from DialogService (for citizen walk pause/resume). No-op if a game
-- is already running.
function MinigameService:Request(
	player: Player,
	npcId: string,
	model: Model?,
	choreActor: NpcActor.NpcActor?,
	citizenActor: NpcActor.NpcActor?
)
	if active then
		return
	end
	local plugin = gamesByNpc[npcId]
	local def = Config.Npc[npcId]
	if not plugin or not def then
		return
	end
	local profile = DataService:GetProfile(player)
	if not profile or not table.find(profile.Data.UnlockedNpcs, npcId) then
		return
	end

	local session: Session = {
		player = player,
		npcId = npcId,
		model = model,
		def = def,
		actor = if model then NpcActor.new(model, def.MoveSeconds, def.WalkAnimation) else nil,
		choreActor = choreActor,
		citizenWalkActor = citizenActor,
		game = plugin,
		homePosition = def.SpawnPosition,
		homeYaw = def.SpawnYaw,
		phase = "pregame",
		confirmed = false,
		alive = true,
		state = nil,
		finish = nil :: any,
	}
	session.finish = function()
		endSession(session, false)
	end
	active = session

	-- Hide the NPC's "Talk" prompt for the whole session; endSession restores it on any outcome.
	NpcPromptService:Hide(npcId)

	-- Pause chore patrol so the NPC doesn't wander while the minigame is running.
	if def["Chore"] and session.choreActor then
		NpcActor.pauseChore(session.choreActor)
	end

	-- Pause citizen walk so the NPC doesn't wander while the minigame is running.
	if def["CitizenWalk"] and session.citizenWalkActor then
		NpcActor.pauseCitizenWalk(session.citizenWalkActor)
	end

	task.spawn(runPregame, session, def)
end

local function onConfirmStart(player: Player)
	local s = active
	if s and s.player == player and s.phase == "instructions" then
		s.confirmed = true
	end
end

function MinigameService:Init()
	awaitReady = Net.Event("MinigameAwaitReady")
	instructionsEvent = Net.Event("MinigameInstructions")
	confirmStart = Net.Event("MinigameConfirmStart")
	aborted = Net.Event("MinigameAborted")

	-- Register every plugin under minigame/games/ by its NpcId, and Init it (generic loader, so the
	-- dynamic require is cast like Bootstrap does). Some modules export a `create` factory function
	-- (e.g. SimonSays) — call it for every Config.Npc entry to get a game instance per NPC.
	for _, child in script.Parent.minigame.games:GetChildren() do
		if child:IsA("ModuleScript") then
			local plugin: any = (require :: any)(child)
			if type(plugin.create) == "function" then
				-- Factory module: instantiate one game per NPC whose Config has the factory's subtable
				-- (plugin.ConfigKey). This keeps two factories from clobbering each other in gamesByNpc —
				-- each only claims the NPCs it's actually configured for. A nil key means "every NPC".
				local key = plugin.ConfigKey
				for npcId, npcDef in Config.Npc do
					if key == nil or (npcDef :: any)[key] ~= nil then
						local game = plugin.create(npcId)
						gamesByNpc[npcId] = game
						if type((game :: any).Init) == "function" then
							(game :: any).Init()
						end
					end
				end
			else
				-- Direct game module: register as-is.
				local game: Game = plugin
				gamesByNpc[game.NpcId] = game
				if type((game :: any).Init) == "function" then
					(game :: any).Init()
				end
			end
		end
	end
end

function MinigameService:Start()
	confirmStart.OnServerEvent:Connect(onConfirmStart)

	for _, plugin in gamesByNpc do
		if type((plugin :: any).Start) == "function" then
			(plugin :: any):Start()
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		local s = active
		if s and s.player == player then
			endSession(s, true)
		end
	end)
end

return MinigameService
