--!strict
-- OutfitBuilder: turns an OutfitData record into a Roblox HumanoidDescription / rig, so the same
-- saved look renders identically wherever it is applied -- the server's shared default NPC rig and
-- (later) each client's per-player cosmetic rig. An otherwise-empty HumanoidDescription is the
-- classic blocky avatar, so we override only what the outfit specifies: BodyColor is one packed
-- 0xRRGGBB applied to all six body parts (the "block" look) and Shirt/Pants are classic template ids
-- (0 = none). Accessories are stored on the record but applied in the full-catalog step (later); not
-- rendered yet. CreateHumanoidModelFromDescription exists on both server and client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type OutfitData = Types.OutfitData

local OutfitBuilder = {}

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
	return desc
end

-- A fresh R15 rig wearing `outfit`.
function OutfitBuilder.buildModel(outfit: OutfitData): Model
	return Players:CreateHumanoidModelFromDescription(OutfitBuilder.describe(outfit), Enum.HumanoidRigType.R15)
end

return OutfitBuilder
