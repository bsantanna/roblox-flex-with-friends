--!strict
-- DataService: ProfileStore session wrapper. Loads a profile on join, releases it
-- on leave, and exposes GetProfile(player). Single source of persisted player data.
-- See doc/002_implementation_plan.md (1.1 Data persistence).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type Profile = Types.PlayerProfile

local DataService = {}

local store: any
local profiles: { [Player]: Profile } = {}
local profileLoadedCallbacks: { (Player, Profile) -> () } = {}

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`player_{player.UserId}`, {}) :: Profile?

	if profile == nil then
		-- Session could not be started (another server holds the lock, or DataStore error).
		player:Kick("Could not load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data session was ended. Please rejoin.")
	end)

	if player.Parent == Players then
		profiles[player] = profile
		for _, callback in profileLoadedCallbacks do
			task.spawn(callback, player, profile)
		end
	else
		-- Player left while the profile was loading; don't leak the session lock.
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function DataService:Init()
	store = ProfileStore.New(Config.DataStoreName, Config.ProfileTemplate)
end

function DataService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function DataService:GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Register a callback run with (player, profile) once a profile is loaded. Also fired
-- immediately for any player whose profile is already loaded, so registration order is safe.
function DataService:OnProfileLoaded(callback: (Player, Profile) -> ())
	table.insert(profileLoadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

return DataService
