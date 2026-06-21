--!strict
-- NpcService: tracks which NPCs a player has unlocked across all Config.Npc entries.
-- When a player reaches the follower threshold for any NPC, the unlock is recorded (persisted)
-- and the player is notified. See doc/002_implementation_plan.md (1.6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local TrophyService = require(script.Parent.TrophyService)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)

local NpcService = {}

local unlockNpc: any

-- True when the player owns every trophy the NPC requires (or it requires none). Some NPCs gate on
-- trophies earned from other NPCs' minigames, chaining them together (e.g. the Forest sage needs the
-- Farmer's farmhand trophy).
local function hasRequiredTrophies(profile, def): boolean
	if not def.RequiredTrophies then
		return true
	end
	for _, trophyId in def.RequiredTrophies do
		if not profile.Data.Trophies[trophyId] then
			return false
		end
	end
	return true
end

-- Records any NPC whose follower + trophy gate the player now satisfies. Runs on profile load, on
-- follower changes, and on trophy awards, since any of those can newly satisfy a gate.
local function checkUnlocks(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local followers = profile.Data.Followers
	for npcId, def in Config.Npc do
		if
			followers >= def.UnlockFollowers
			and hasRequiredTrophies(profile, def)
			and not table.find(profile.Data.UnlockedNpcs, npcId)
		then
			table.insert(profile.Data.UnlockedNpcs, npcId)
			unlockNpc:FireClient(player, npcId)
			Analytics.event(player, "NpcUnlocked", nil, npcId)
		end
	end
end

function NpcService:Init()
	unlockNpc = Net.Event("UnlockNpc")
end

function NpcService:Start()
	DataService:OnProfileLoaded(function(player: Player, _profile)
		checkUnlocks(player)
	end)

	FollowerService:OnChanged(function(player: Player, _followers: number)
		checkUnlocks(player)
	end)

	-- Earning a trophy can satisfy a trophy gate, so re-evaluate unlocks then too.
	TrophyService:OnAwarded(function(player: Player)
		checkUnlocks(player)
	end)
end

return NpcService
