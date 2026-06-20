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
	"RequestTravel", -- client -> server: (placeId: string)
	"TravelComplete", -- server -> client: (success: boolean, reason: string?, placeId: string?)
	"StartMinigame", -- server -> client: (kind: string, durationSeconds: number)
	"MinigameInput", -- client -> server: () -- player acted (e.g. boarded)
	"RequestPhotoCapture", -- client -> server: ()
	"PhotoResult", -- server -> client: (success: boolean, reward: number, coop: boolean, reason: string?)
	"UnlockNpc", -- server -> client: (npcId: string)
	"DialogLine", -- server -> client: (text: string, index: number, total: number, choices: {string}?)
	"DialogAdvance", -- client -> server: () -- advance past a plain line
	"DialogChoose", -- client -> server: (choiceIndex: number) -- pick a branch-line choice
	"DialogEnd", -- server -> client: () -- dismiss the dialog UI
	"SetFollowers", -- client -> server: (value: number) -- dev cheat; server accepts in Studio only
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
	-- Rock-Paper-Scissors gameplay (the Cowboy minigame plugin owns these).
	"RpsPickPhase", -- server -> client: (choices: {string}, timeoutSeconds: number) -- round open: show the hand buttons
	"RpsPlayerChoice", -- client -> server: (choice: string) -- the player's hand for this round
	"RpsReveal", -- server -> client: (playerChoice: string, opponentChoice: string, outcome: string, reelSeconds: number, playerWins: number, opponentWins: number, roundReward: number) -- spin the reel onto opponentChoice, then show the outcome/score
	"RpsGameOver", -- server -> client: (won: boolean, playerWins: number, opponentWins: number, totalReward: number) -- match decided
	-- Trophy rewards (TrophyService).
	"TrophyEarned", -- server -> client: (trophies: { [string]: true }) -- full trophy map on join or new award
	"TrophyUnlocked", -- server -> client: (Id: string, Name: string, Emoji: string) -- one-shot toast for new trophy
	"FriendDialogLine", -- server -> client: (text: string, choices: {string}) -- gym-friend line + answer options
	"FriendDialogChoose", -- client -> server: (choiceIndex: number) -- pick an answer
	"FriendDialogEnd", -- server -> client: () -- dismiss the friend dialog UI
	"OpenNpcEditor", -- server -> client: (npcId: string) -- first meeting: open the "create your friend" editor
	"SaveNpcOutfit", -- client -> server: (npcId: string, outfit: OutfitData) -- save the created look (validated server-side)
	"NpcOutfitSync", -- server -> client: (outfits: { [string]: OutfitData }) -- this player's saved NPC looks
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
