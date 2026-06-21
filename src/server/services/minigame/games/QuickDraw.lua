--!strict
-- QuickDraw: a reaction-duel minigame factory (the Forest sage's game).
-- Call QuickDraw.create(npcId) for any NPC whose Config defines a QuickDraw subtable (MinigameService
-- registers it by ConfigKey). The framework handles pre-game (walk-out, ready-zone, instructions,
-- Start); the plugin owns the play: each round, after a random suspense the NPC "draws" and the player
-- must press within a window. The SERVER times the reaction against its own clock (never trusts a
-- client-claimed time), so a press is judged purely by when it arrives. A press before the signal is a
-- false start. Best reaction wins the draw; one miss ends the duel. Win every draw for the bonus +
-- trophy. Shared.Logic.QuickDraw provides the pure delay/judge math.
-- The plugin reads from Config.Npc.<npcId>.QuickDraw for game-specific values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local QuickDrawLogic = require(ReplicatedStorage.Shared.Logic.QuickDraw)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)
local TrophyService = require(servicesFolder.TrophyService)

local rng = Random.new()

-- Extra wait after the react window before the round auto-resolves as "slow", so a press arriving a
-- touch late (network jitter) still registers rather than racing the timeout.
local SLOW_GRACE = 0.5

local QuickDrawModule = {}
-- MinigameService registers this factory only for NPCs whose Config has a QuickDraw subtable.
QuickDrawModule.ConfigKey = "QuickDraw"

function QuickDrawModule.create(npcId: string)
	local QuickDrawGame = {}
	QuickDrawGame.Id = npcId .. "QuickDraw"
	QuickDrawGame.NpcId = npcId

	-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
	local current: any? = nil

	local function def()
		-- Registered only for NPCs whose Config has a QuickDraw subtable, so this is never nil.
		return assert(Config.Npc[npcId].QuickDraw, "QuickDraw def missing for " .. npcId)
	end

	local function endGame(session: any, won: boolean)
		if current ~= session then
			return
		end
		local d = def()
		local st = session.state
		if won then
			st.totalReward += d.MatchBonus
			FollowerService:Award(session.player, d.MatchBonus, npcId:lower() .. "-duel")
			TrophyService:AwardTrophy(session.player, session.npcId)
		end
		current = nil
		if session.player.Parent then
			Net.Event("QuickDrawGameOver"):FireClient(session.player, won, st.roundsWon, st.totalReward, npcId)
		end
		session.finish()
	end

	local startRound: (session: any) -> ()

	-- Settles the current draw exactly once (a press and the slow-timeout can both fire). outcome is
	-- "win" (in time), "slow" (too late / no press), or "falsestart" (pressed before the signal).
	local function resolveRound(session: any, outcome: string)
		local st = session.state
		if current ~= session or st.resolved then
			return
		end
		st.resolved = true
		st.phase = "reveal"
		local d = def()

		local roundReward = 0
		if outcome == "win" then
			st.roundsWon += 1
			roundReward = d.BaseReward
			st.totalReward += roundReward
			FollowerService:Award(session.player, roundReward, npcId:lower() .. "-draw")
		end

		if session.player.Parent then
			Net.Event("QuickDrawResult"):FireClient(session.player, outcome, roundReward, st.roundsWon)
		end

		task.delay(d.RevealSeconds, function()
			if current ~= session or not session.alive then
				return
			end
			if outcome ~= "win" then
				endGame(session, false) -- one miss ends the duel
			elseif st.roundsWon >= d.Rounds then
				endGame(session, true) -- swept every draw
			else
				st.round += 1
				startRound(session)
			end
		end)
	end

	function startRound(session: any)
		local d = def()
		local st = session.state
		st.phase = "brace"
		st.resolved = false

		task.spawn(function()
			if st.round > 1 then
				task.wait(d.RoundDelaySeconds)
			end
			if not session.alive or current ~= session then
				return
			end
			-- Suspense: from here a press is a false start, until the signal flips us to "draw".
			st.phase = "aim"
			Net.Event("QuickDrawCountdown"):FireClient(session.player, st.round, d.Rounds)
			task.wait(QuickDrawLogic.signalDelay(rng:NextNumber(), d.MinDelaySeconds, d.MaxDelaySeconds))
			if not session.alive or current ~= session or st.resolved then
				return
			end

			-- DRAW: stamp the signal on the server clock; the press is judged against this.
			st.phase = "draw"
			st.signalAt = os.clock()
			if session.actor then
				session.actor:poseNpc(d.DrawPose, d.RevealSeconds)
			end
			Net.Event("QuickDrawSignal"):FireClient(session.player, d.ReactWindowSeconds)

			-- No press in time auto-resolves the draw as a loss.
			local signal = st.signalAt
			task.delay(d.ReactWindowSeconds + SLOW_GRACE, function()
				if current == session and st.phase == "draw" and st.signalAt == signal and not st.resolved then
					resolveRound(session, "slow")
				end
			end)
		end)
	end

	local function onPress(player: Player)
		local session = current
		if not session or session.player ~= player or not session.alive then
			return
		end
		local st = session.state
		if st.phase == "draw" then
			local elapsed = os.clock() - st.signalAt
			resolveRound(session, QuickDrawLogic.judge(elapsed, def().ReactWindowSeconds))
		elseif st.phase == "brace" or st.phase == "aim" then
			resolveRound(session, "falsestart")
		end
		-- presses during "reveal" are ignored
	end

	function QuickDrawGame:begin(session: any)
		current = session
		session.state = {
			phase = "brace",
			round = 1,
			roundsWon = 0,
			totalReward = 0,
			signalAt = 0,
			resolved = false,
		}
		startRound(session)
	end

	function QuickDrawGame:abort(session: any)
		if current == session then
			current = nil
		end
	end

	function QuickDrawGame:Init()
		-- Nothing to pre-bind; remotes are shared (Net.Event returns cached singleton).
	end

	function QuickDrawGame:Start()
		Net.Event("QuickDrawPress").OnServerEvent:Connect(onPress)
	end

	return QuickDrawGame
end

return QuickDrawModule
