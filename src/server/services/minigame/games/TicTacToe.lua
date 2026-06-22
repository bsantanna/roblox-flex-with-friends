--!strict
-- TicTacToe: a reusable tic-tac-toe minigame factory (the HomeBuilder hosts it).
-- Call TicTacToe.create(npcId) for any NPC whose Config defines a TicTacToe subtable (MinigameService
-- registers it by ConfigKey). The framework handles pre-game (walk-out, ready-zone, instructions,
-- Start); the plugin owns the play: the player (X) and the SERVER-controlled NPC (O) alternate moves
-- on a 3x3 board, best-two-of-three with drawn games replayed. The server is authoritative — it holds
-- the board, validates each tap, and plays the NPC's reply. Shared.Logic.TicTacToe provides the pure
-- win detection, NPC move selection, and match math. Tunables live in Config.Npc.<npcId>.TicTacToe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local TttLogic = require(ReplicatedStorage.Shared.Logic.TicTacToe)

local servicesFolder = script.Parent.Parent.Parent
local FollowerService = require(servicesFolder.FollowerService)
local TrophyService = require(servicesFolder.TrophyService)

local rng = Random.new()

local TicTacToeModule = {}
-- MinigameService registers this factory only for NPCs whose Config has a TicTacToe subtable.
TicTacToeModule.ConfigKey = "TicTacToe"

local function emptyBoard(): { string }
	return { "", "", "", "", "", "", "", "", "" }
end

function TicTacToeModule.create(npcId: string)
	local TttGame = {}
	TttGame.Id = npcId .. "Ttt"
	TttGame.NpcId = npcId

	-- The session currently being played (one game at a time); set in begin, cleared on game over/abort.
	local current: any? = nil

	local function def()
		-- Registered only for NPCs whose Config has a TicTacToe subtable, so this is never nil.
		return assert(Config.Npc[npcId].TicTacToe, "TicTacToe def missing for " .. npcId)
	end

	local startGame -- forward declaration (resolveIfOver schedules the next game)

	local function endMatch(session: any, won: boolean)
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
			Net.Event("TttGameOver")
				:FireClient(session.player, won, st.playerWins, st.opponentWins, st.totalReward, npcId)
		end
		session.finish()
	end

	-- If the current board is decided (a line or a full board), score it, tell the client, and after
	-- RevealSeconds either end the match or start the next game. Returns true when the game is over.
	local function resolveIfOver(session: any): boolean
		local d = def()
		local st = session.state
		local board = st.board
		local mark = TttLogic.winner(board)
		if not mark and not TttLogic.isFull(board) then
			return false
		end

		st.phase = "reveal"
		local result: string
		if mark == d.PlayerMark then
			result = "win"
			st.playerWins += 1
			st.totalReward += d.BaseReward
			FollowerService:Award(session.player, d.BaseReward, npcId:lower() .. "-game")
		elseif mark == d.NpcMark then
			result = "lose"
			st.opponentWins += 1
		else
			result = "draw" -- full board, no line: replays
		end

		if session.player.Parent then
			Net.Event("TttGameResult"):FireClient(session.player, board, result, st.playerWins, st.opponentWins)
		end

		task.delay(d.RevealSeconds, function()
			if not session.alive or current ~= session or st.phase ~= "reveal" then
				return
			end
			local winner = TttLogic.matchWinner(st.playerWins, st.opponentWins, d.WinsNeeded)
			if winner ~= nil then
				endMatch(session, winner == "player")
			else
				startGame(session)
			end
		end)
		return true
	end

	-- Opens the player's turn: arms the move deadline and a watcher that forfeits the match if the
	-- player never moves. The "your turn" signal itself rides on TttGameStart / TttUpdate.
	local function openMove(session: any)
		local d = def()
		local st = session.state
		st.phase = "play"
		st.deadline = os.clock() + d.MoveTimeoutSeconds
		local deadline = st.deadline
		task.delay(d.MoveTimeoutSeconds + 0.5, function()
			if current == session and st.phase == "play" and st.deadline == deadline then
				endMatch(session, false)
			end
		end)
	end

	function startGame(session: any)
		local d = def()
		local st = session.state
		st.phase = "wait"
		task.spawn(function()
			if st.started then
				task.wait(d.RoundDelaySeconds)
			end
			if not session.alive or current ~= session then
				return
			end
			st.started = true
			st.board = emptyBoard()
			if session.player.Parent then
				Net.Event("TttGameStart"):FireClient(
					session.player,
					st.board,
					st.playerWins + st.opponentWins + 1,
					st.playerWins,
					st.opponentWins
				)
			end
			openMove(session)
		end)
	end

	local function onMove(player: Player, cell: unknown)
		local session = current
		if not session or session.player ~= player or not session.alive then
			return
		end
		local st = session.state
		if st.phase ~= "play" then
			return
		end
		local d = def()
		if type(cell) ~= "number" or cell % 1 ~= 0 or cell < 1 or cell > 9 or st.board[cell] ~= "" then
			return
		end
		if os.clock() > st.deadline then
			endMatch(session, false)
			return
		end

		st.board[cell] = d.PlayerMark
		if resolveIfOver(session) then
			return
		end

		-- The NPC replies after a short beat so the player sees their move land first.
		st.phase = "thinking"
		if session.player.Parent then
			Net.Event("TttUpdate"):FireClient(session.player, st.board, false)
		end
		task.delay(d.NpcMoveDelaySeconds, function()
			if not session.alive or current ~= session or (st.phase :: string) ~= "thinking" then
				return
			end
			local aiCell = TttLogic.aiMove(function(min: number, max: number)
				return rng:NextInteger(min, max)
			end, st.board, d.NpcMark, d.PlayerMark)
			st.board[aiCell] = d.NpcMark
			if resolveIfOver(session) then
				return
			end
			if session.player.Parent then
				Net.Event("TttUpdate"):FireClient(session.player, st.board, true)
			end
			openMove(session)
		end)
	end

	function TttGame:begin(session: any)
		current = session
		session.state = {
			phase = "wait",
			started = false,
			board = emptyBoard(),
			playerWins = 0,
			opponentWins = 0,
			totalReward = 0,
			deadline = 0,
		}
		startGame(session)
	end

	function TttGame:abort(session: any)
		if current == session then
			current = nil
		end
	end

	function TttGame:Init()
		-- Nothing to pre-bind; remotes are shared (Net.Event returns cached singleton).
	end

	function TttGame:Start()
		Net.Event("TttMove").OnServerEvent:Connect(onMove)
	end

	return TttGame
end

return TicTacToeModule
