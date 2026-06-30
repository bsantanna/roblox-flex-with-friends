--!strict
-- TrophyService: manages earned trophies per player profile and notifies the client
-- so the Social Modal grid can display them. A trophy is defined by an npcId that maps to
-- a trophy id, display name, and emoji. When a minigame is fully cleared the SimonSays
-- plugin calls AwardTrophy(player, npcId).
--
-- Trophy IDs are unique strings (e.g. "personal_trainer_strength", "farmer_farmhand")
-- that survive across sessions because they are stored in Profile.Data.Trophies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DataService = require(script.Parent.DataService)
local Net = require(ReplicatedStorage.Shared.Net)

local TrophyService = {}

-- Trophy definitions keyed by npcId. Each defines the reward a player earns on full clearance.
local TROPHY_DEFS: { [string]: { Id: string, Name: string, Emoji: string } } = {
	PersonalTrainer = {
		Id = "personal_trainer_strength",
		Name = "Strength",
		Emoji = "\u{1F4AA}", -- strong-arm emoji
	},
	Farmer = {
		Id = "farmer_farmhand",
		Name = "Fresh Milk",
		Emoji = "\u{1F95B}", -- milk bottle emoji
	},
	Cowboy = {
		Id = "cowboy_roundup",
		Name = "Cowboy",
		Emoji = "\u{1F404}", -- cow emoji
	},
	Rancher = {
		Id = "rancher_wrangler",
		Name = "Wrangler",
		Emoji = "\u{1F40E}", -- horse emoji
	},
	Postman = {
		Id = "postman_swiftpost",
		Name = "Swift Post",
		Emoji = "\u{1F4E6}", -- letter emoji
	},
	Sage = {
		Id = "sage_quickdraw",
		Name = "Fast Hands",
		Emoji = "\u{26A1}", -- high voltage / lightning emoji
	},
	TaxiDriver = {
		Id = "taxi_driver_mobility",
		Name = "Mobility",
		Emoji = "\u{1F695}", -- taxi emoji
	},
	Policeman = {
		Id = "policeman_protection",
		Name = "Protection",
		Emoji = "\u{1F46E}", -- police officer emoji
	},
	Firefighter = {
		Id = "firefighter_bravery",
		Name = "Bravery",
		Emoji = "\u{1F692}", -- fire engine emoji
	},
	Gardener = {
		Id = "gardener_caretaking",
		Name = "Caretaking",
		Emoji = "\u{1F331}", -- seedling emoji
	},
	HomeBuilder = {
		Id = "home_builder_nicehome",
		Name = "Nice Home",
		Emoji = "\u{1F3E0}", -- house emoji
	},
	Nurse = {
		Id = "nurse_healthy",
		Name = "Healthy",
		Emoji = "\u{1FA7A}", -- stethoscope emoji
	},
	TruckDriver = {
		Id = "truck_driver_heavyduty",
		Name = "Heavy Duty",
		Emoji = "\u{1F69A}", -- delivery truck emoji
	},
	-- Airport-terminal NPCs (the second collectible chain). Their trophies show in the Social Modal's
	-- Airport tab (PhoneMenuController.TROPHY_ZONE).
	Athlete = {
		Id = "athlete_speed",
		Name = "Speed",
		Emoji = "\u{1F3C3}", -- runner emoji
	},
	Chef = {
		Id = "chef_secret_sauce",
		Name = "Secret Sauce",
		Emoji = "\u{1F9C5}", -- onion emoji
	},
	Singer = {
		Id = "singer_confidence",
		Name = "Confidence",
		Emoji = "\u{1F3A4}", -- microphone emoji
	},
	Violinist = {
		Id = "violinist_refinement",
		Name = "Refinement",
		Emoji = "\u{1F3BB}", -- violin emoji
	},
	DJ = {
		Id = "dj_grooves",
		Name = "Grooves",
		Emoji = "\u{1F3A7}", -- headphone emoji
	},
	Ballerina = {
		Id = "ballerina_swiftness",
		Name = "Swiftness",
		Emoji = "\u{1FA70}", -- ballet shoes emoji
	},
	Pianist = {
		Id = "pianist_talent",
		Name = "Talent",
		Emoji = "\u{1F3B9}", -- musical keyboard emoji
	},
	Archeologist = {
		Id = "archeologist_relic",
		Name = "Relic",
		Emoji = "\u{1F9B4}", -- bone emoji
	},
	-- Quest 002 "The Pilot's Forgotten Packages" completion trophy (awarded by QuestService on delivery).
	-- Shows in the Social Modal's Airport tab.
	Pilot = {
		Id = "pilot_delivery",
		Name = "Delivery Hero",
		Emoji = "\u{2708}", -- airplane emoji
	},
	-- Quest 003 "Tim's Lost Lunch Box" completion trophy (awarded by QuestService on delivery).
	-- Shows in the Social Modal's City tab.
	FirstQuest = {
		Id = "kindness",
		Name = "Kindness",
		Emoji = "\u{2B50}", -- star emoji
	},
}

local trophyEarned: RemoteEvent
local trophyUnlocked: RemoteEvent
local awardedCallbacks: { (Player) -> () } = {}
local grantTrophiesRemote: RemoteEvent

function TrophyService:Init()
	trophyEarned = Net.Event("TrophyEarned")
	trophyUnlocked = Net.Event("TrophyUnlocked")
	grantTrophiesRemote = Net.Event("GrantAllTrophies")
end

function TrophyService:Start()
	-- Seed any already-online players with their existing trophies so the UI populates.
	for _, player in Players:GetPlayers() do
		task.spawn(TrophyService._seedPlayer, self, player)
	end

	-- Dev cheat (debug mode): grant all trophies on command. Studio only.
	grantTrophiesRemote.OnServerEvent:Connect(function(player: Player)
		if not RunService:IsStudio() then
			return
		end
		TrophyService:GrantAll(player)
	end)
end

function TrophyService:_seedPlayer(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end
	-- Fire the trophy list so the client can populate the grid immediately.
	trophyEarned:FireClient(player, profile.Data.Trophies :: { [string]: true })
end

--- Award a trophy to `player` for completing the minigame hosted by NPC `npcId`.
--- If the player already has this trophy (or the npcId is unknown), this is a no-op.
function TrophyService:AwardTrophy(player: Player, npcId: string)
	local def = TROPHY_DEFS[npcId]
	if not def then
		return
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	-- Already earned — no-op.
	if profile.Data.Trophies[def.Id] then
		return
	end

	profile.Data.Trophies[def.Id] = true

	-- Notify client so the grid updates in real-time.
	trophyEarned:FireClient(player, profile.Data.Trophies :: { [string]: true })

	-- One-shot toast notification with trophy definition.
	trophyUnlocked:FireClient(player, def.Id, def.Name, def.Emoji)

	-- Let listeners (e.g. NpcService's trophy-gated unlocks) react to the new trophy.
	for _, callback in awardedCallbacks do
		task.spawn(callback, player)
	end
end

-- Register a callback run with (player) whenever that player earns a new trophy.
function TrophyService:OnAwarded(callback: (Player) -> ())
	table.insert(awardedCallbacks, callback)
end

--- Grant every trophy to `player`. Only used by the debug cheat — Studio only.
--- Routes through AwardTrophy so toasts and trophy-gated unlock callbacks fire as if earned.
function TrophyService:GrantAll(player: Player)
	for npcId in TROPHY_DEFS do
		TrophyService:AwardTrophy(player, npcId)
	end
end

return TrophyService
