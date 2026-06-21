--!strict
-- RockPaperScissors: a reusable Rock-Paper-Scissors luck minigame factory.
-- Call RockPaperScissors.create(npcId) for any NPC whose Config defines a RockPaperScissors subtable
-- (MinigameService registers it by ConfigKey). The framework handles pre-game (walk-out, ready-zone,
-- instructions, Start); the plugin owns the play: the player picks a hand, the SERVER picks the
-- opponent's hand at random (the client reel is pure flair that lands on it), best-two-of-three with
-- ties replayed. Shared.Logic.RockPaperScissors provides the pure resolution math.
-- The plugin reads from Config.Npc.<npcId>.RockPaperScissors for game-specific values.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RpsLogic = require(ReplicatedStorage.Shared.Logic.RockPaperScissors)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)
local TrophyService = require(servicesFolder.TrophyService)

local rng = Random.new()

local RockPaperScissorsModule = {}
-- MinigameService registers this factory only for NPCs whose Config has a RockPaperScissors subtable.
RockPaperScissorsModule.ConfigKey = "RockPaperScissors"

function RockPaperScissorsModule.create(npcId: string)
	local RpsGame = {}
	RpsGame.Id = npcId .. "Rps"
	RpsGame.NpcId = npcId

	-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
	local current: any? = nil

	local function def()
		-- Registered only for NPCs whose Config has a RockPaperScissors subtable, so this is never nil.
		return assert(Config.Npc[npcId].RockPaperScissors, "RockPaperScissors def missing for " .. npcId)
	end

	local function endGame(session: any, won: boolean)
		if current ~= session then
			return
		end
		local d = def()
		local st = session.state
		if won then
			st.totalReward += d.MatchBonus
			FollowerService:Award(session.player, d.MatchBonus, npcId:lower() .. "-match")
			TrophyService:AwardTrophy(session.player, session.npcId)
		end
		current = nil
		if session.player.Parent then
			Net.Event("RpsGameOver")
				:FireClient(session.player, won, st.playerWins, st.opponentWins, st.totalReward, npcId)
		end
		session.finish()
	end

	local function startRound(session: any)
		local d = def()
		local st = session.state
		st.phase = "wait"

		task.spawn(function()
			if st.round > 1 then
				task.wait(d.RoundDelaySeconds)
			end
			if not session.alive or current ~= session then
				return
			end
			st.phase = "pick"
			st.deadline = os.clock() + d.InputTimeoutSeconds
			Net.Event("RpsPickPhase"):FireClient(session.player, d.Choices, d.InputTimeoutSeconds, npcId)

			-- Round-scoped timeout: no pick in time ends the match as a loss.
			local deadline = st.deadline
			task.delay(d.InputTimeoutSeconds + 0.5, function()
				if current == session and st.phase == "pick" and st.deadline == deadline then
					endGame(session, false)
				end
			end)
		end)
	end

	local function onChoice(player: Player, choice: unknown)
		local session = current
		if not session or session.player ~= player or not session.alive then
			return
		end
		local st = session.state
		if st.phase ~= "pick" then
			return
		end
		local d = def()
		if type(choice) ~= "string" or not table.find(d.Choices, choice) then
			return
		end
		if os.clock() > st.deadline then
			endGame(session, false)
			return
		end

		st.phase = "reveal"
		local opponent = RpsLogic.pick(function(min: number, max: number)
			return rng:NextInteger(min, max)
		end, d.Choices)
		local outcome = RpsLogic.resolve(choice, opponent)

		if session.actor then
			session.actor:poseNpc(d.Poses[opponent], d.ReelSeconds + d.RevealSeconds)
		end

		local roundReward = 0
		if outcome == "win" then
			st.playerWins += 1
			roundReward = d.BaseReward
			st.totalReward += roundReward
			FollowerService:Award(player, roundReward, npcId:lower() .. "-round")
		elseif outcome == "lose" then
			st.opponentWins += 1
		end
		-- "tie": no score change; the round replays.

		if session.player.Parent then
			Net.Event("RpsReveal")
				:FireClient(
					player,
					choice,
					opponent,
					outcome,
					d.ReelSeconds,
					st.playerWins,
					st.opponentWins,
					roundReward
				)
		end

		-- After the reel spins and the result is shown, advance: end the match, or play the next round
		-- (a tie replays the same round number).
		local snapshot = st.round
		task.delay(d.ReelSeconds + d.RevealSeconds, function()
			local st2 = session.state
			if not session.alive or current ~= session or st2.round ~= snapshot or st2.phase ~= "reveal" then
				return
			end
			local winner = RpsLogic.matchWinner(st2.playerWins, st2.opponentWins, d.WinsNeeded)
			if winner ~= nil then
				endGame(session, winner == "player")
			else
				if outcome ~= "tie" then
					st2.round += 1
				end
				startRound(session)
			end
		end)
	end

	function RpsGame:begin(session: any)
		current = session
		session.state = {
			phase = "wait",
			round = 1,
			playerWins = 0,
			opponentWins = 0,
			totalReward = 0,
			deadline = 0,
		}
		startRound(session)
	end

	function RpsGame:abort(session: any)
		if current == session then
			current = nil
		end
	end

	function RpsGame:Init()
		-- Nothing to pre-bind; remotes are shared (Net.Event returns cached singleton).
	end

	function RpsGame:Start()
		Net.Event("RpsPlayerChoice").OnServerEvent:Connect(onChoice)
	end

	return RpsGame
end

return RockPaperScissorsModule
