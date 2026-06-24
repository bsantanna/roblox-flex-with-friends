--!strict
-- Network contract: every RemoteEvent/RemoteFunction is declared here by name so the
-- full client<->server surface is greppable in one place. Add new remotes to EVENTS /
-- FUNCTIONS below, never as loose Instances. Server handlers must validate every payload.
-- See references/architecture.md (Networking contract).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Server -> client and client -> server events.
local EVENTS = {
	"FollowerChanged", -- server -> client: (followers: number)
	"RequestTravel", -- client -> server: () -- call a cab; server flips the player Home <-> Airport
	"TravelComplete", -- server -> client: (success: boolean, reason: string?, placeId: string?)
	"RequestPhotoCapture", -- client -> server: ()
	"PhotoResult", -- server -> client: (success: boolean, reward: number, coop: boolean, reason: string?)
	"UnlockNpc", -- server -> client: (npcId: string)
	"DialogLine", -- server -> client: (text: string, index: number, total: number, choices: {string}?, npcId: string?) -- npcId enables client to show NPC name
	"DialogAdvance", -- client -> server: () -- advance past a plain line
	"DialogChoose", -- client -> server: (choiceIndex: number) -- pick a branch-line choice
	"DialogEnd", -- server -> client: () -- dismiss the dialog UI
	"SetFollowers", -- client -> server: (value: number) -- dev cheat; server accepts in Studio only
	"GrantAllTrophies", -- client -> server: () -- dev cheat; Studio only
	-- Generic NPC-minigame pre-game flow (MinigameService); every minigame reuses these.
	"MinigameAwaitReady", -- server -> client: () -- pre-game: head to the green ready-zone in front of the NPC
	"MinigameInstructions", -- server -> client: (instructions: string) -- show the rules + a Start button
	"MinigameConfirmStart", -- client -> server: () -- player confirmed the instructions; begin play
	"MinigameAborted", -- server -> client: () -- pre-game timed out / cancelled; dismiss the pre-game UI
	-- Simon Says gameplay (the PersonalTrainer minigame plugin owns these).
	"TrainerShowStepNumber", -- server -> client: (stepNumber: number, round: number, maxRounds: number) -- show the step number (1-based index)
	"TrainerShowStep", -- server -> client: (arrow: string, round: number, maxRounds: number) -- light this arrow during the show
	"TrainerInputPhase", -- server -> client: (timeoutSeconds: number) -- show done; server now accepts inputs
	"TrainerPoseInput", -- client -> server: (arrow: string) -- one arrow per fire during the input phase
	"TrainerRoundResult", -- server -> client: (correct: boolean, reward: number) -- reward > 0 means round cleared
	"TrainerRoundFeedback", -- server -> client: (sequence: {string}) -- between-round success: the just-cleared order, shown as emojis
	"TrainerGameOver", -- server -> client: (totalReward: number, roundsCompleted: number, cleared: boolean, sequence: {string}) -- sequence is the final/failed round's correct order
	-- Rock-Paper-Scissors gameplay (the minigame plugin owned by any npcId hosts these).
	"RpsPickPhase", -- server -> client: (choices: {string}, timeoutSeconds: number, npcId: string) -- round open: show the hand buttons
	"RpsPlayerChoice", -- client -> server: (choice: string) -- the player's hand for this round
	"RpsReveal", -- server -> client: (playerChoice: string, opponentChoice: string, outcome: string, reelSeconds: number, playerWins: number, opponentWins: number, roundReward: number) -- spin the reel onto opponentChoice, then show the outcome/score
	"RpsGameOver", -- server -> client: (won: boolean, playerWins: number, opponentWins: number, totalReward: number, npcId: string) -- match decided
	-- Quick Draw gameplay (the Forest sage's reaction-duel plugin owns these).
	"QuickDrawCountdown", -- server -> client: (round: number, maxRounds: number) -- a draw begins; brace, watch for the signal
	"QuickDrawSignal", -- server -> client: (windowSeconds: number) -- DRAW! the player must press within the window
	"QuickDrawPress", -- client -> server: () -- the player struck (server times it against the signal)
	"QuickDrawResult", -- server -> client: (outcome: string, roundReward: number, roundsWon: number) -- outcome: "win" | "slow" | "falsestart"
	"QuickDrawGameOver", -- server -> client: (won: boolean, roundsWon: number, totalReward: number, npcId: string) -- duel decided
	-- Memory gameplay (the Nurse's recognition-memory plugin owns these).
	"MemoryShowTargets", -- server -> client: (targets: {string}, round: number, maxRounds: number) -- flash these emojis to memorize
	"MemoryRecallPhase", -- server -> client: (grid: {string}, timeoutSeconds: number, round: number, maxRounds: number) -- show the 4x4 grid; accept a selection
	"MemorySubmit", -- client -> server: (selectedIndices: {number}) -- the cells the player picked
	"MemoryRoundResult", -- server -> client: (correct: boolean, reward: number) -- reward > 0 means round cleared
	"MemoryGameOver", -- server -> client: (totalReward: number, roundsCompleted: number, cleared: boolean) -- game decided
	-- Tic-Tac-Toe gameplay (the HomeBuilder's best-of-three plugin owns these).
	"TttGameStart", -- server -> client: (board: {string}, gameNumber: number, playerWins: number, opponentWins: number) -- a fresh board; your turn (you're X)
	"TttMove", -- client -> server: (cell: number) -- the 1-9 cell the player marks
	"TttUpdate", -- server -> client: (board: {string}, yourTurn: boolean) -- board after a move; yourTurn false means the NPC is thinking
	"TttGameResult", -- server -> client: (board: {string}, result: string, playerWins: number, opponentWins: number) -- result: "win" | "lose" | "draw"
	"TttGameOver", -- server -> client: (won: boolean, playerWins: number, opponentWins: number, totalReward: number, npcId: string) -- match decided
	-- Trophy rewards (TrophyService).
	"TrophyEarned", -- server -> client: (trophies: { [string]: true }) -- full trophy map on join or new award
	"TrophyUnlocked", -- server -> client: (Id: string, Name: string, Emoji: string) -- one-shot toast for new trophy
	"FriendDialogLine", -- server -> client: (text: string, choices: {string}) -- gym-friend line + answer options
	"FriendDialogChoose", -- client -> server: (choiceIndex: number) -- pick an answer
	"FriendDialogEnd", -- server -> client: () -- dismiss the friend dialog UI
	"OpenNpcEditor", -- server -> client: (npcId: string) -- first meeting: open the "create your friend" editor
	"SaveNpcOutfit", -- client -> server: (npcId: string, outfit: OutfitData) -- save the created look (validated server-side)
	"NpcOutfitSync", -- server -> client: (outfits: { [string]: OutfitData }) -- this player's saved NPC looks
	-- Quest 002 "The Pilot's Forgotten Packages" (QuestService / QuestController / CutsceneController).
	"QuestState", -- server -> client: (questId: string, phase: string, collected: number, total: number, deadline: number?) -- the one HUD/state sync
	"QuestAccept", -- client -> server: () -- accept the Pilot's offer
	"QuestDecline", -- client -> server: () -- decline the offer
	"RequestCollectPackage", -- client -> server: (index: number) -- triggered a beacon; server validates proximity
	"CutscenePlay", -- server -> client: (sequenceId: string, reward: number?) -- take camera control, play a named cutscene; reward (>0) shows on the Ending's Mission Complete banner
	"CutsceneDone", -- client -> server: () -- cutscene finished/skipped; lets the server sequence the next beat
}

-- Request/response functions.
local FUNCTIONS: { string } = {}

local Net = {}

local remotes: Folder? = nil

local function getRemotes(): Folder
	if remotes then
		return remotes
	end

	local folder: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			for _, name in EVENTS do
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
			for _, name in FUNCTIONS do
				local fn = Instance.new("RemoteFunction")
				fn.Name = name
				fn.Parent = folder
			end
			folder.Parent = ReplicatedStorage
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: any
	end

	remotes = folder
	return folder
end

function Net.Event(name: string): RemoteEvent
	local remote = getRemotes():WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `Net: '{name}' is not a RemoteEvent`)
	return remote
end

function Net.Function(name: string): RemoteFunction
	local remote = getRemotes():WaitForChild(name)
	assert(remote:IsA("RemoteFunction"), `Net: '{name}' is not a RemoteFunction`)
	return remote
end

return Net
