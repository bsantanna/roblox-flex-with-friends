--!strict
-- OutfitBuilder: turns an OutfitData record into a Roblox HumanoidDescription / rig, so the same
-- saved look renders identically wherever it is applied -- the server's shared default NPC rig and
-- each client's per-player cosmetic rig. An otherwise-empty HumanoidDescription is the classic blocky
-- avatar, so we override only what the outfit specifies: BodyColor is one packed 0xRRGGBB applied to
-- all six body parts (the "block" look), Shirt/Pants are classic template ids (0 = none), and each
-- accessory is written into its slot's HumanoidDescription <Slot>Accessory id string (the path that
-- reliably renders rigid catalog accessories -- SetAccessories silently drops them).
-- CreateHumanoidModelFromDescription exists on both server and client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type OutfitData = Types.OutfitData

local OutfitBuilder = {}

-- Enum.AccessoryType value -> the HumanoidDescription string property the accessory equips into.
-- (Note ShouldersAccessory is plural.) An accessory whose Type isn't here is ignored.
local ACCESSORY_PROPERTY: { [number]: string } = {
	[Enum.AccessoryType.Hat.Value] = "HatAccessory",
	[Enum.AccessoryType.Hair.Value] = "HairAccessory",
	[Enum.AccessoryType.Face.Value] = "FaceAccessory",
	[Enum.AccessoryType.Neck.Value] = "NeckAccessory",
	[Enum.AccessoryType.Shoulder.Value] = "ShouldersAccessory",
	[Enum.AccessoryType.Front.Value] = "FrontAccessory",
	[Enum.AccessoryType.Back.Value] = "BackAccessory",
	[Enum.AccessoryType.Waist.Value] = "WaistAccessory",
}

local function unpackColor(packed: number): Color3
	return Color3.fromRGB(
		bit32.band(bit32.rshift(packed, 16), 0xFF),
		bit32.band(bit32.rshift(packed, 8), 0xFF),
		bit32.band(packed, 0xFF)
	)
end

-- A HumanoidDescription for `outfit`. Left empty everywhere the outfit doesn't specify, which yields
-- the classic blocky body.
function OutfitBuilder.describe(outfit: OutfitData): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local color = unpackColor(outfit.BodyColor)
	desc.HeadColor = color
	desc.TorsoColor = color
	desc.LeftArmColor = color
	desc.RightArmColor = color
	desc.LeftLegColor = color
	desc.RightLegColor = color
	if outfit.Shirt > 0 then
		desc.Shirt = outfit.Shirt
	end
	if outfit.Pants > 0 then
		desc.Pants = outfit.Pants
	end
	-- Group accessory ids by the slot property (a slot can hold several layered ids, comma-separated).
	local bySlot: { [string]: { string } } = {}
	for _, acc in outfit.Accessories do
		local prop = ACCESSORY_PROPERTY[acc.Type]
		if prop and acc.AssetId > 0 then
			local ids = bySlot[prop] or {}
			table.insert(ids, tostring(acc.AssetId))
			bySlot[prop] = ids
		end
	end
	for prop, ids in bySlot do
		(desc :: any)[prop] = table.concat(ids, ",")
	end
	return desc
end

-- A fresh R15 rig wearing `outfit`.
function OutfitBuilder.buildModel(outfit: OutfitData): Model
	return Players:CreateHumanoidModelFromDescription(OutfitBuilder.describe(outfit), Enum.HumanoidRigType.R15)
end

return OutfitBuilder
