--!strict
-- NpcService: tracks which NPCs a player has unlocked. The Personal Trainer unlock is recorded
-- once the player reaches the Config follower threshold (persists) and the player is notified;
-- the trainer itself always stands in the world (spawned by DialogService) and its dialog
-- branches on this unlock. See doc/002_implementation_plan.md (1.6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)

local NpcService = {}

local unlockNpc: RemoteEvent

local function checkUnlock(player: Player, followers: number)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local def = Config.Npc.PersonalTrainer
	if followers >= def.UnlockFollowers and not table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") then
		table.insert(profile.Data.UnlockedNpcs, "PersonalTrainer")
		unlockNpc:FireClient(player, "PersonalTrainer")
		Analytics.event(player, "NpcUnlocked", nil, "PersonalTrainer")
	end
end

function NpcService:Init()
	unlockNpc = Net.Event("UnlockNpc")
end

function NpcService:Start()
	DataService:OnProfileLoaded(function(player: Player, profile)
		checkUnlock(player, profile.Data.Followers)
	end)

	FollowerService:OnChanged(function(player: Player, followers: number)
		checkUnlock(player, followers)
	end)
end

return NpcService
