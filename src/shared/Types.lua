--!strict
-- Shared type definitions. See doc/002_implementation_plan.md (Core data model).

local Types = {}

export type Stats = {
	PhotosTaken: number,
	TripsTaken: number,
	FriendsInvited: number,
}

-- A player's saved look for one customizable NPC: the outfit they created when they first met it.
-- Serializes the parts of a HumanoidDescription the editor can set, so a rig can be rebuilt from it.
-- Accessory entries carry the catalog AccessoryType (Enum.AccessoryType value) so they equip in the
-- right slot. BodyColor is a packed 0xRRGGBB applied to every body part (a single "block" colour).
export type OutfitAccessory = {
	AssetId: number,
	Type: number, -- Enum.AccessoryType value
}
export type OutfitData = {
	BodyColor: number, -- packed 0xRRGGBB, applied to all six body parts
	Shirt: number, -- classic shirt template asset id; 0 = none
	Pants: number, -- classic pants template asset id; 0 = none
	Accessories: { OutfitAccessory },
}

export type ProfileData = {
	Followers: number, -- the scoreboard number; FollowerService is the single writer
	Reputation: number, -- 0..100, affects follower swings at places
	UnlockedPlaces: { string },
	UnlockedNpcs: { string },
	Stats: Stats,
	Trophies: { [string]: true }, -- trophyId -> true (earned)
	LastSeen: number, -- os.time(), for offline decay
	CompanionNpc: string?, -- NPC currently traveling with the player
	InvitedFriends: { number }, -- userIds this player has already been rewarded for inviting
	ClaimedReferral: boolean, -- whether this player has claimed their one-time invited-join bonus
	Friends: { [string]: OutfitData }, -- customizable NPC id -> the look the player created for it
	-- (key present == befriended; gates first-meet vs friend dialog). Written only by OutfitService.
}

-- Minimal shim over ProfileStore's Profile<T>. The Wally wrapper module re-exports
-- the package via `return require(...)`, which drops its exported types, so we type
-- the members DataService uses here. `Data` is what consumers actually read.
export type PlayerProfile = {
	Data: ProfileData,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> { Disconnect: (self: any) -> () } },
}

return Types
