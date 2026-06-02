--!strict
-- NpcService: tracks which NPCs a player has unlocked and spawns them. The Personal Trainer
-- unlocks once the player reaches the Config follower threshold; on unlock it is recorded in
-- the profile (persists), the player is notified, and the trainer is spawned in Home.
-- See doc/002_implementation_plan.md (1.6).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)

local NpcService = {}

local unlockNpc: RemoteEvent
local trainerSpawned = false

local function spawnTrainer()
	if trainerSpawned then
		return
	end
	trainerSpawned = true

	local home = Workspace:WaitForChild("World"):WaitForChild("Home")
	local def = Config.Npc.PersonalTrainer
	local position = Config.Zones.Home + def.SpawnOffset + Vector3.new(0, 2.5, 0)

	local model = Instance.new("Model")
	model.Name = "PersonalTrainer"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 5, 2)
	body.Position = position
	body.Anchored = true
	body.Color = Color3.fromRGB(200, 90, 90)
	body.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Trainer"
	prompt.ActionText = "Train"
	prompt.ObjectText = "Personal Trainer"
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = body

	model.PrimaryPart = body
	model.Parent = home
end

local function checkUnlock(player: Player, followers: number)
	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local def = Config.Npc.PersonalTrainer
	if followers >= def.UnlockFollowers and not table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") then
		table.insert(profile.Data.UnlockedNpcs, "PersonalTrainer")
		unlockNpc:FireClient(player, "PersonalTrainer")
		spawnTrainer()
		Analytics.event(player, "NpcUnlocked", nil, "PersonalTrainer")
	end
end

function NpcService:Init()
	unlockNpc = Net.Event("UnlockNpc")
end

function NpcService:Start()
	DataService:OnProfileLoaded(function(player: Player, profile)
		-- Already unlocked from a previous session: make sure the trainer exists.
		if table.find(profile.Data.UnlockedNpcs, "PersonalTrainer") then
			spawnTrainer()
		else
			checkUnlock(player, profile.Data.Followers)
		end
	end)

	FollowerService:OnChanged(function(player: Player, followers: number)
		checkUnlock(player, followers)
	end)
end

return NpcService
