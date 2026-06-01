--!strict
-- Shared type definitions. See doc/002_implementation_plan.md (Core data model).

local Types = {}

export type Stats = {
	PhotosTaken: number,
	TripsTaken: number,
	FriendsInvited: number,
}

export type ProfileData = {
	Followers: number, -- the scoreboard number; FollowerService is the single writer
	Reputation: number, -- 0..100, affects follower swings at places
	UnlockedPlaces: { string },
	UnlockedNpcs: { string },
	Stats: Stats,
	LastSeen: number, -- os.time(), for offline decay
	CompanionNpc: string?, -- NPC currently traveling with the player
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
