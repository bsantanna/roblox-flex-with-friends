--!strict
-- Shared types for the gym-friend roster. Lives apart from init.lua so the per-workout roster
-- modules (Runners/Cyclists/Lifters/Floor) can annotate their returns without a circular require.

local DialogTree = require(script.Parent.Parent.Parent.Logic.DialogTree)

export type FriendDef = {
	Id: string, -- stable id; the persisted "befriended" key (ProfileData.Friends)
	Name: string, -- display name (ProximityPrompt + name tag)
	Gender: "male" | "female",
	Type: "Runner" | "Cyclist" | "Lifter" | "Floor", -- selects the workout animation
	Station: Vector3, -- where they stand to exercise (a gym equipment spot, floor surface y=23)
	Yaw: number, -- facing while exercising (0 looks -Z), matched to the equipment
	Intro: DialogTree.Tree, -- first meeting
	Friend: DialogTree.Tree, -- once befriended
}

export type LoungeGroup = {
	center: Vector3, -- the spot the group gathers around; each member takes a distinct slot in a ring
	members: { string }, -- friend Ids assigned to this group (a fixed slot each, so they never overlap)
}

return {}
