--!strict
-- PlaceService: server-authoritative cab travel. The cab is a binary shuttle -- it flips the player
-- between Home and the Airport based on where they currently are: from Home it drops them inside the
-- arrivals terminal (the airport safe zone); from the Airport it brings them back Home, applying the
-- carbon-footprint follower loss. Onward flights to other Places are reserved for a later system.
-- Tracks the player's current zone and Stats.TripsTaken. See doc/002_implementation_plan.md (1.4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local PlaceService = {}

local requestTravel: RemoteEvent
local travelComplete: RemoteEvent

local location: { [Player]: string } = {} -- current zone per player ("Home" or "Airport")
local traveling: { [Player]: boolean } = {} -- guards against concurrent travel

local function setLocation(player: Player, zoneName: string)
	location[player] = zoneName
	player:SetAttribute("CurrentPlace", zoneName)
end

-- Where the cab drops a player off in each zone. Home is the spawn plaza; the Airport drop-off is
-- inside the arrivals terminal (its centre + the configured spawn offset), the airport safe zone.
local function dropOff(zoneName: string): Vector3
	if zoneName == "Airport" then
		local T = Config.Terminal
		return Config.Zones.Airport + T.Offset + T.SpawnOffset + Vector3.new(0, 5, 0)
	end
	return Config.Zones[zoneName] + Vector3.new(0, 5, 0)
end

local function teleport(player: Player, zoneName: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(dropOff(zoneName))
	end
end

local function onRequestTravel(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile or traveling[player] then
		return
	end

	-- The cab flips the player between Home and the Airport based on where they are now.
	local current = location[player] or "Home"
	local dest = if current == "Home" then "Airport" else "Home"

	traveling[player] = true

	teleport(player, dest)
	setLocation(player, dest)
	profile.Data.Stats.TripsTaken += 1
	if dest == "Home" then
		-- Returning home costs followers (carbon footprint); arriving at the Airport is free.
		FollowerService:Deduct(player, Config.Travel.CarbonFootprintLoss, "carbon-footprint")
	end
	travelComplete:FireClient(player, true, nil, dest)

	traveling[player] = false
end

function PlaceService:Init()
	requestTravel = Net.Event("RequestTravel")
	travelComplete = Net.Event("TravelComplete")
end

function PlaceService:Start()
	DataService:OnProfileLoaded(function(player: Player, profile)
		setLocation(player, "Home")
		player:SetAttribute("UnlockedPlaces", table.concat(profile.Data.UnlockedPlaces, ","))
	end)

	requestTravel.OnServerEvent:Connect(onRequestTravel)

	Players.PlayerRemoving:Connect(function(player: Player)
		location[player] = nil
		traveling[player] = nil
	end)
end

return PlaceService
