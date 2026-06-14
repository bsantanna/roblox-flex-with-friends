--!strict
-- OutfitService: the single writer of Profile.Data.Friends -- the per-player map of customizable NPC
-- id -> the outfit the player created for that NPC the first time they met it. A key being present
-- means the player has befriended that NPC (which gates first-meet vs friend dialog). Befriending an
-- NPC the first time stores the look and awards Config.GymFriends.BefriendReward followers, once each.
-- Other code asks here (IsFriend / GetOutfit / Befriend); it never touches the map directly.
-- See doc/002_implementation_plan.md and docs/dev/npc/003_npc_char_creation.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)
local GymFriendsCfg = require(ReplicatedStorage.Shared.Config.GymFriends)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

type OutfitData = Types.OutfitData

local OutfitService = {}

-- A fresh, independent copy of an outfit, so each friend's stored look is its own table (mutating
-- one never aliases another, and the Config default is never mutated).
local function copyOutfit(outfit: OutfitData): OutfitData
	local accessories = table.create(#outfit.Accessories)
	for i, acc in outfit.Accessories do
		accessories[i] = { AssetId = acc.AssetId, Type = acc.Type }
	end
	return {
		BodyColor = outfit.BodyColor,
		Shirt = outfit.Shirt,
		Pants = outfit.Pants,
		Accessories = accessories,
	}
end

function OutfitService:IsFriend(player: Player, npcId: string): boolean
	local profile = DataService:GetProfile(player)
	return profile ~= nil and profile.Data.Friends[npcId] ~= nil
end

function OutfitService:GetOutfit(player: Player, npcId: string): OutfitData?
	local profile = DataService:GetProfile(player)
	return if profile then profile.Data.Friends[npcId] else nil
end

-- Befriend `npcId` for `player`, storing `outfit` (or a copy of the default look). The first time
-- only: writes the record and awards BefriendReward followers. A no-op if already a friend, so the
-- reward is granted exactly once per NPC.
function OutfitService:Befriend(player: Player, npcId: string, outfit: OutfitData?)
	local profile = DataService:GetProfile(player)
	if not profile or profile.Data.Friends[npcId] ~= nil then
		return
	end
	profile.Data.Friends[npcId] = copyOutfit(outfit or Config.DefaultNpcOutfit)
	FollowerService:Award(player, GymFriendsCfg.BefriendReward, "npc-friend:" .. npcId)
	Analytics.event(player, "NpcBefriended", nil, npcId)
end

return OutfitService
