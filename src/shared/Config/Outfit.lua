--!strict
-- NPC outfit defaults + the first-meeting "create your friend" editor (OutfitService, NpcEditor).

local Types = require(script.Parent.Parent.Types)

local Outfit = {}

-- The "default lego block" look every customizable NPC wears the first time you meet it, before
-- you create their outfit: a neutral grey blocky avatar, no clothing or accessories. Stored as the
-- friend's OutfitData until the player customizes it. BefriendReward (Config.GymFriends) is awarded
-- once when the outfit is first saved.
Outfit.DefaultNpcOutfit = {
	BodyColor = 0xA3A3A3, -- neutral grey "unpainted block"
	Shirt = 0,
	Pants = 0,
	Accessories = {},
} :: Types.OutfitData

-- The first-meeting "create your friend" editor. The body-colour palette below is applied as the
-- single block colour; ClothingSlots and AccessorySlots drive the AvatarEditorService catalog tabs the
-- player browses to dress the friend. The server validates every saved value (BodyColor against this
-- list, and each clothing/accessory id against its slot's catalog category) so a tampered client can't
-- set an arbitrary look. Each accessory slot equips into one HumanoidDescription <Slot>Accessory.
type ClothingSlot = { Label: string, Category: Enum.AvatarAssetType, Field: string }
type AccessorySlot = { Label: string, Category: Enum.AvatarAssetType, Type: Enum.AccessoryType }
Outfit.OutfitEditor = {
	BodyColors = {
		0xA3A3A3, -- grey
		0xD9B38C, -- tan
		0xF2CDA0, -- light skin
		0x8C5A3B, -- brown
		0xE05A5A, -- red
		0xE0913B, -- orange
		0xE8D44D, -- yellow
		0x5AB85A, -- green
		0x4DA6E0, -- blue
		0x8C5AE0, -- purple
		0xE05AAE, -- pink
		0x2E2E2E, -- charcoal
	} :: { number },
	-- Classic clothing tabs: the catalog category to browse -> the OutfitData field it fills.
	ClothingSlots = {
		{ Label = "Shirt", Category = Enum.AvatarAssetType.Shirt, Field = "Shirt" },
		{ Label = "Pants", Category = Enum.AvatarAssetType.Pants, Field = "Pants" },
	} :: { ClothingSlot },
	-- Accessory tabs: the catalog category to browse -> the slot it equips into (one item per slot).
	AccessorySlots = {
		{ Label = "Hats", Category = Enum.AvatarAssetType.Hat, Type = Enum.AccessoryType.Hat },
		{ Label = "Hair", Category = Enum.AvatarAssetType.HairAccessory, Type = Enum.AccessoryType.Hair },
		{ Label = "Face", Category = Enum.AvatarAssetType.FaceAccessory, Type = Enum.AccessoryType.Face },
		{ Label = "Neck", Category = Enum.AvatarAssetType.NeckAccessory, Type = Enum.AccessoryType.Neck },
		{ Label = "Shoulder", Category = Enum.AvatarAssetType.ShoulderAccessory, Type = Enum.AccessoryType.Shoulder },
		{ Label = "Front", Category = Enum.AvatarAssetType.FrontAccessory, Type = Enum.AccessoryType.Front },
		{ Label = "Back", Category = Enum.AvatarAssetType.BackAccessory, Type = Enum.AccessoryType.Back },
		{ Label = "Waist", Category = Enum.AvatarAssetType.WaistAccessory, Type = Enum.AccessoryType.Waist },
	} :: { AccessorySlot },
}

return Outfit
