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
