--!strict
-- Memory: a reusable recognition-memory minigame factory (the Nurse hosts it).
-- Call Memory.create(npcId) to get a game plugin for any NPC with a Memory subtable in Config.
-- The framework handles pre-game (walk-out, ready-zone, instructions, Start); the plugin owns the play.
-- Each round flashes a set of target emojis, then shows a 4x4 grid (the targets + distractors) and
-- the player taps the ones they saw. Shared.Logic.Memory provides grid generation, grading, and
-- reward math; the plugin reads tunables from Config.Npc.<npcId>.Memory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local MemoryLogic = require(ReplicatedStorage.Shared.Logic.Memory)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)
local TrophyService = require(servicesFolder.TrophyService)

local rng = Random.new()

local MemoryModule = {}
-- MinigameService registers this factory only for NPCs whose Config has a Memory subtable.
MemoryModule.ConfigKey = "Memory"

function MemoryModule.create(npcId: string)
	local MemoryGame = {}
	MemoryGame.Id = npcId .. "Memory"
	MemoryGame.NpcId = npcId

	-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
	-- Shared across all Memory instances since MinigameService only runs one game at a time.
	local current: any? = nil

	local function def()
		-- Registered only for NPCs whose Config has a Memory subtable, so this is never nil.
		return assert(Config.Npc[npcId].Memory, "Memory def missing for " .. npcId)
	end

	local function endGame(session: any, roundsCompleted: number, cleared: boolean)
		if current ~= session then
			return
		end
		if cleared then
			TrophyService:AwardTrophy(session.player, session.npcId)
		end
		current = nil
		if session.player.Parent then
			Net.Event("MemoryGameOver"):FireClient(session.player, session.state.totalReward, roundsCompleted, cleared)
		end
		session.finish()
	end

	local function startRound(session: any)
		local d = def()
		local st = session.state
		st.phase = "show"
		st.targetCount = MemoryLogic.targetCount(d.StartTargets, st.round)
		local round = MemoryLogic.buildRound(function(min: number, max: number)
			return rng:NextInteger(min, max)
		end, d.Emojis, st.targetCount, d.GridSize)
		st.grid = round.grid
		st.targetIndices = round.targetIndices

		task.spawn(function()
			if st.round > 1 then
				task.wait(d.RoundDelaySeconds)
			end
			if not session.alive or current ~= session then
				return
			end
			-- Flash the targets to memorize.
			local targets = table.create(st.targetCount)
			for i, cell in st.targetIndices do
				targets[i] = st.grid[cell]
			end
			Net.Event("MemoryShowTargets"):FireClient(session.player, targets, st.round, d.Rounds)
			task.wait(d.ShowSeconds)
			if not session.alive or current ~= session then
				return
			end
			-- Reveal the grid and open the selection window.
			st.phase = "recall"
			st.deadline = os.clock() + d.SelectTimeoutSeconds
			Net.Event("MemoryRecallPhase")
				:FireClient(session.player, st.grid, d.SelectTimeoutSeconds, st.round, d.Rounds)

			-- Round-scoped timeout watcher.
			local deadline = st.deadline
			task.delay(d.SelectTimeoutSeconds + 0.5, function()
				if current == session and st.phase == "recall" and st.deadline == deadline then
					endGame(session, st.round - 1, false)
				end
			end)
		end)
	end

	local function onSubmit(player: Player, selected: unknown)
		local session = current
		if not session or session.player ~= player or not session.alive then
			return
		end
		local st = session.state
		if st.phase ~= "recall" then
			return
		end
		local d = def()

		-- Validate the payload: exactly targetCount distinct cell indices, each in range.
		if type(selected) ~= "table" then
			return
		end
		local indices = selected :: { unknown }
		if #indices ~= st.targetCount then
			return
		end
		local seen: { [number]: boolean } = {}
		local cells: { number } = {}
		for _, idx in indices do
			if type(idx) ~= "number" or idx % 1 ~= 0 or idx < 1 or idx > d.GridSize or seen[idx] then
				return
			end
			seen[idx] = true
			table.insert(cells, idx)
		end
		if os.clock() > st.deadline then
			endGame(session, st.round - 1, false)
			return
		end

		st.phase = "graded" -- close the window so a second submit can't double-grade
		if not MemoryLogic.grade(st.targetIndices, cells) then
			Net.Event("MemoryRoundResult"):FireClient(player, false, 0)
			endGame(session, st.round - 1, false)
			return
		end

		local reward = MemoryLogic.roundReward(d.BaseReward, d.RewardPerRound, st.round)
		st.totalReward += reward
		FollowerService:Award(player, reward, npcId:lower() .. "-memory")
		Net.Event("MemoryRoundResult"):FireClient(player, true, reward)

		if st.round >= d.Rounds then
			endGame(session, st.round, true)
		else
			st.round += 1
			startRound(session)
		end
	end

	function MemoryGame:begin(session: any)
		current = session
		session.state = {
			phase = "show",
			round = 1,
			targetCount = 0,
			grid = {},
			targetIndices = {},
			totalReward = 0,
			deadline = 0,
		}
		startRound(session)
	end

	function MemoryGame:abort(session: any)
		if current == session then
			current = nil
		end
	end

	function MemoryGame:Init()
		-- Nothing to pre-bind; remotes are shared (Net.Event returns cached singleton).
	end

	function MemoryGame:Start()
		Net.Event("MemorySubmit").OnServerEvent:Connect(onSubmit)
	end

	return MemoryGame
end

return MemoryModule
