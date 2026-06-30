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
local Throttle = require(ReplicatedStorage.Shared.Util.Throttle)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local PlaceService = {}

local requestTravel: RemoteEvent
local travelComplete: RemoteEvent
local travelGate: (Player) -> boolean

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
	if not travelGate(player) then
		return
	end
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
	if dest == "Home" and not player:GetAttribute("QuestActive") then
		-- Returning home costs followers (carbon footprint); arriving at the Airport is free. Quest trips
		-- are exempt -- flying to the city to run an errand isn't a holiday (QuestService sets the flag).
		FollowerService:Deduct(player, Config.Travel.CarbonFootprintLoss, "carbon-footprint")
	end
	travelComplete:FireClient(player, true, nil, dest)

	traveling[player] = false
end

-- Quest fast travel: moves `player` to `zoneName` (optionally to an explicit `position` instead of the
-- zone's default drop-off) WITHOUT the carbon-footprint follower loss -- that loss is a cab penalty,
-- not a quest action. QuestService calls this so PlaceService stays the single owner of player
-- location/teleport.
function PlaceService:TravelTo(player: Player, zoneName: string, position: Vector3?)
	local profile = DataService:GetProfile(player)
	if not profile or traveling[player] then
		return
	end
	traveling[player] = true
	if position then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.CFrame = CFrame.new(position)
		end
	else
		teleport(player, zoneName)
	end
	setLocation(player, zoneName)
	profile.Data.Stats.TripsTaken += 1
	travelComplete:FireClient(player, true, nil, zoneName)
	traveling[player] = false
end

function PlaceService:Init()
	requestTravel = Net.Event("RequestTravel")
	travelComplete = Net.Event("TravelComplete")
	travelGate = Throttle.perPlayer(Config.Travel.RequestRatePerSec, Config.Travel.RequestBurst)
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
