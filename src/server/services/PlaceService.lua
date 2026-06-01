--!strict
-- PlaceService: server-authoritative travel between zones. Validates the destination is a real,
-- unlocked place; for outbound trips runs the Airport boarding minigame (a timed press the server
-- owns) before moving the player and awarding arrival followers; traveling Home applies the
-- carbon-footprint follower loss. Tracks the player's current zone and Stats.TripsTaken.
-- See doc/002_implementation_plan.md (1.4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

local PlaceService = {}

local requestTravel: RemoteEvent
local travelComplete: RemoteEvent
local startMinigame: RemoteEvent
local minigameInput: RemoteEvent

local location: { [Player]: string } = {} -- current zone per player
local traveling: { [Player]: boolean } = {} -- guards against concurrent travel
local boardedAt: { [Player]: number } = {} -- set when a player fires MinigameInput

local function setLocation(player: Player, zoneName: string)
	location[player] = zoneName
	player:SetAttribute("CurrentPlace", zoneName)
end

local function teleport(player: Player, zoneName: string)
	local origin = Config.Zones[zoneName]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if origin and root and root:IsA("BasePart") then
		root.CFrame = CFrame.new(origin + Vector3.new(0, 5, 0))
	end
end

-- Yields until the player boards within the window. Returns true on success, false on timeout.
local function runBoardingMinigame(player: Player): boolean
	boardedAt[player] = nil
	startMinigame:FireClient(player, "AirportBoarding", Config.Travel.MinigameWindow)

	local started = os.clock()
	while os.clock() - started < Config.Travel.MinigameWindow do
		if boardedAt[player] then
			return true
		end
		task.wait()
	end
	return false
end

local function onRequestTravel(player: Player, placeId: unknown)
	if type(placeId) ~= "string" then
		return
	end

	local profile = DataService:GetProfile(player)
	if not profile or traveling[player] then
		return
	end

	local place = Config.Places[placeId]
	if not place then
		travelComplete:FireClient(player, false, "Unknown destination")
		return
	end
	if not table.find(profile.Data.UnlockedPlaces, placeId) then
		travelComplete:FireClient(player, false, "That place is locked")
		return
	end

	local current = location[player] or "Home"
	if placeId == current then
		travelComplete:FireClient(player, false, "You are already there")
		return
	end

	traveling[player] = true

	if placeId == "Home" then
		-- Returning home: no minigame, apply the carbon-footprint loss.
		teleport(player, "Home")
		FollowerService:Deduct(player, Config.Travel.CarbonFootprintLoss, "carbon-footprint")
		setLocation(player, "Home")
		profile.Data.Stats.TripsTaken += 1
		travelComplete:FireClient(player, true, nil, "Home")
	else
		-- Outbound: board at the Airport, then fly to the destination.
		teleport(player, "Airport")
		local boarded = runBoardingMinigame(player)
		if not boarded then
			teleport(player, current)
			travelComplete:FireClient(player, false, "You missed the flight")
		else
			teleport(player, placeId)
			FollowerService:Award(player, place.Arrival, "arrival:" .. placeId)
			setLocation(player, placeId)
			profile.Data.Stats.TripsTaken += 1
			travelComplete:FireClient(player, true, nil, placeId)
		end
	end

	traveling[player] = false
end

function PlaceService:Init()
	requestTravel = Net.Event("RequestTravel")
	travelComplete = Net.Event("TravelComplete")
	startMinigame = Net.Event("StartMinigame")
	minigameInput = Net.Event("MinigameInput")
end

function PlaceService:Start()
	DataService:OnProfileLoaded(function(player: Player, profile)
		setLocation(player, "Home")
		player:SetAttribute("UnlockedPlaces", table.concat(profile.Data.UnlockedPlaces, ","))
	end)

	requestTravel.OnServerEvent:Connect(onRequestTravel)

	minigameInput.OnServerEvent:Connect(function(player: Player)
		boardedAt[player] = os.clock()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		location[player] = nil
		traveling[player] = nil
		boardedAt[player] = nil
	end)
end

return PlaceService
