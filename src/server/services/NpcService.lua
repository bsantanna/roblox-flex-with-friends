--!strict
-- NpcService: tracks which NPCs a player has unlocked across all Config.Npc entries.
-- When a player reaches the follower threshold for any NPC, the unlock is recorded (persisted)
-- and the player is notified. See doc/002_implementation_plan.md (1.6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)

local NpcService = {}

local unlockNpc: any

local function checkUnlocks(player: Player, followers: number)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	for npcId, def in Config.Npc do
		if followers >= def.UnlockFollowers and not table.find(profile.Data.UnlockedNpcs, npcId) then
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
	DataService:OnProfileLoaded(function(player: Player, profile)
		checkUnlocks(player, profile.Data.Followers)
	end)

	FollowerService:OnChanged(function(player: Player, followers: number)
		checkUnlocks(player, followers)
	end)
end

return NpcService
