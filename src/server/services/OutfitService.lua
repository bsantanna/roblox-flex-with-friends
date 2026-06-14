--!strict
-- OutfitService: the single writer of Profile.Data.Friends -- the per-player map of customizable NPC
-- id -> the outfit the player created for that NPC the first time they met it. A key being present
-- means the player has befriended that NPC (which gates first-meet vs friend dialog). The first-meet
-- editor saves a look here (SaveOutfit): it validates the untrusted client payload, stores the look,
-- and awards Config.GymFriends.BefriendReward followers, once each. Each player's map is replicated to
-- their own client (NpcOutfitSync) so the client can render their custom NPCs. Other code asks here
-- (IsFriend / GetOutfit / SaveOutfit); it never touches the map directly.
-- See docs/dev/npc/003_npc_char_creation.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Analytics = require(ReplicatedStorage.Shared.Util.Analytics)
local GymFriendsCfg = require(ReplicatedStorage.Shared.Config.GymFriends)
local DataService = require(script.Parent.DataService)
local FollowerService = require(script.Parent.FollowerService)

type OutfitData = Types.OutfitData
type OutfitAccessory = Types.OutfitAccessory

local OutfitService = {}

-- Validation tables, built once from the editor config: which catalog AssetType a saved id must be.
-- GetBatchItemDetails returns AssetType as a string equal to the AvatarAssetType name ("Shirt",
-- "Hat", "HairAccessory", ...), so we compare against each slot's catalog category Name.
local ACCESSORY_EXPECTED: { [number]: string } = {} -- Enum.AccessoryType value -> AssetType name
for _, slot in Config.OutfitEditor.AccessorySlots do
	ACCESSORY_EXPECTED[slot.Type.Value] = slot.Category.Name
end
local CLOTHING_EXPECTED: { [string]: string } = {} -- OutfitData field -> AssetType name
for _, slot in Config.OutfitEditor.ClothingSlots do
	CLOTHING_EXPECTED[slot.Field] = slot.Category.Name
end

local npcOutfitSync: RemoteEvent

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

-- A clean OutfitData built from untrusted client input, or nil if invalid. Yields: validates every
-- non-zero clothing/accessory id against the catalog in one GetBatchItemDetails batch, so a tampered
-- client can't smuggle in arbitrary or wrong-slot asset ids. Fail-closed -- any missing/mismatched id
-- (or a failed catalog call) rejects the whole save. The body colour must be one of the palette, and
-- accessories are capped to one per known slot.
local function sanitize(raw: unknown): OutfitData?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: any
	local bodyColor = r.BodyColor
	if type(bodyColor) ~= "number" or not table.find(Config.OutfitEditor.BodyColors, bodyColor) then
		return nil
	end
	local shirt = if type(r.Shirt) == "number" and r.Shirt > 0 then r.Shirt else 0
	local pants = if type(r.Pants) == "number" and r.Pants > 0 then r.Pants else 0

	-- One accessory per known slot (last wins); unknown slots and non-positive ids are dropped.
	local accBySlot: { [number]: number } = {}
	if type(r.Accessories) == "table" then
		for _, entry in r.Accessories do
			if type(entry) == "table" then
				local id, slotType = (entry :: any).AssetId, (entry :: any).Type
				if type(id) == "number" and id > 0 and type(slotType) == "number" and ACCESSORY_EXPECTED[slotType] then
					accBySlot[slotType] = id
				end
			end
		end
	end

	-- Catalog-validate every non-zero id at once (id -> the AssetType name it must report).
	local expected: { [number]: string } = {}
	local toCheck: { number } = {}
	if shirt > 0 then
		expected[shirt] = CLOTHING_EXPECTED.Shirt
		table.insert(toCheck, shirt)
	end
	if pants > 0 then
		expected[pants] = CLOTHING_EXPECTED.Pants
		table.insert(toCheck, pants)
	end
	for slotType, id in accBySlot do
		expected[id] = ACCESSORY_EXPECTED[slotType]
		table.insert(toCheck, id)
	end
	if #toCheck > 0 then
		local ok, details = pcall(function()
			return AvatarEditorService:GetBatchItemDetails(toCheck, Enum.AvatarItemType.Asset)
		end)
		if not ok or type(details) ~= "table" then
			return nil
		end
		local actual: { [number]: string } = {}
		for _, item in details do
			actual[(item :: any).Id] = (item :: any).AssetType
		end
		for id, name in expected do
			if actual[id] ~= name then
				return nil -- a missing or wrong-slot id rejects the whole save
			end
		end
	end

	local accessories: { OutfitAccessory } = {}
	for slotType, id in accBySlot do
		table.insert(accessories, { AssetId = id, Type = slotType })
	end
	return { BodyColor = bodyColor, Shirt = shirt, Pants = pants, Accessories = accessories }
end

local function syncToClient(player: Player)
	local profile = DataService:GetProfile(player)
	if profile then
		npcOutfitSync:FireClient(player, profile.Data.Friends)
	end
end

function OutfitService:Init()
	npcOutfitSync = Net.Event("NpcOutfitSync")
end

function OutfitService:Start()
	-- Replicate each player's saved looks once their profile is loaded (empty map for a new player,
	-- which tells the client to render every NPC as the shared default).
	DataService:OnProfileLoaded(function(player: Player)
		syncToClient(player)
	end)
end

function OutfitService:IsFriend(player: Player, npcId: string): boolean
	local profile = DataService:GetProfile(player)
	return profile ~= nil and profile.Data.Friends[npcId] ~= nil
end

function OutfitService:GetOutfit(player: Player, npcId: string): OutfitData?
	local profile = DataService:GetProfile(player)
	return if profile then profile.Data.Friends[npcId] else nil
end

-- Befriend `npcId` for `player`, storing `outfit` (or a copy of the default look), the first time
-- only: writes the record and awards BefriendReward followers. Returns whether this newly befriended
-- them (false if they already were, so the reward is granted exactly once per NPC).
function OutfitService:Befriend(player: Player, npcId: string, outfit: OutfitData?): boolean
	local profile = DataService:GetProfile(player)
	if not profile or profile.Data.Friends[npcId] ~= nil then
		return false
	end
	profile.Data.Friends[npcId] = copyOutfit(outfit or Config.DefaultNpcOutfit)
	FollowerService:Award(player, GymFriendsCfg.BefriendReward, "npc-friend:" .. npcId)
	Analytics.event(player, "NpcBefriended", nil, npcId)
	return true
end

-- Handle a first-meeting editor save: validate the client payload, befriend (once) with the created
-- look, and replicate it back. Returns whether this completed a new first meeting (so the caller can
-- play the greeting); false if the input was invalid or they were already a friend.
function OutfitService:SaveOutfit(player: Player, npcId: string, raw: unknown): boolean
	if self:IsFriend(player, npcId) then
		return false -- already befriended: skip the catalog validation web call entirely
	end
	local clean = sanitize(raw)
	if not clean then
		return false
	end
	local befriended = self:Befriend(player, npcId, clean)
	if befriended then
		syncToClient(player)
	end
	return befriended
end

return OutfitService
