--!strict
-- Gym-friend roster and AI/dialog tunables (Config.GymFriends). Twelve NPCs, four workout types x
-- three people, each with a name, gender, a home station on the opened first floor, and two
-- branching dialog trees: Intro (first meeting -- they introduce themselves; befriending them on
-- close awards BefriendReward followers) and Friend (they already know you). They all spawn with the
-- shared "default lego block" look (Config.DefaultNpcOutfit); a player who customizes one sees their
-- own version, rendered client-side. GymFriendService spawns them, runs the exercise/break routine
-- (Shared.Logic.Routine) with natural Humanoid walking, and runs the conversations
-- (Shared.Logic.DialogTree). Positions and the placeholder animation ids are tuned by looking in
-- Studio and swapped for real workout uploads later (doc 002).
--
-- The roster itself lives in four per-workout modules (Runners/Cyclists/Lifters/Floor); the shared
-- FriendDef/LoungeGroup types live in Defs (so those modules can annotate without a require cycle).

local Defs = require(script.Defs)

export type FriendDef = Defs.FriendDef
export type LoungeGroup = Defs.LoungeGroup

local GymFriends = {}

GymFriends.BefriendReward = 40 -- followers granted the first time you chat with each friend (once each)
GymFriends.Exercise = { min = 240, max = 360 } -- seconds exercising before a break (~5 min, jittered)
GymFriends.Rest = { min = 240, max = 360 } -- seconds on break before exercising again (~5 min, jittered)
GymFriends.WalkSpeed = 9 -- studs/sec; a relaxed gym wander (default 16 looks like sprinting)
GymFriends.CollisionGroup = "GymNpc" -- friends don't collide with each other; equipment is "GymProp"
GymFriends.EquipmentGroup = "GymProp" -- the gym equipment group friends pass through (no MoveTo snags)
GymFriends.PromptDistance = 12 -- studs the Talk prompt is reachable from
GymFriends.DialogTimeout = 30 -- seconds of inactivity before a conversation closes itself

-- Spawn line. Friends spawn along the gym's south entry edge (by their station's X column) and their
-- first mission is to walk to their station, staying north of the stairwell hole (Z in [-37.5, -19.1])
-- so the straight walk never crosses the shaft. Movement is anchored CFrame walking on a fixed Y plane
-- (see Agent.walkTo), so they never fall through the floor and need no walk pad or fall watchdog.
GymFriends.EntryZ = -40 -- spawn line at the gym's south entry edge (north of the stair hole)

-- Placeholder workout animations: confirmed-loadable Roblox defaults/emotes (already used by the
-- trainer) standing in for real push-up/cycling/lifting uploads -- swap the ids when those exist.
GymFriends.Animations = {
	Walk = "rbxassetid://913402848", -- default R15 walk (between station and lounge)
	Break = "rbxassetid://507770239", -- wave emote -- friendly idle while resting
	Runner = "rbxassetid://913376220", -- default R15 run, in place on the treadmill
	Cyclist = "rbxassetid://507771019", -- dance emote (stand-in for pedalling)
	Lifter = "rbxassetid://507770677", -- cheer emote (stand-in for lifting)
	Floor = "rbxassetid://507770453", -- point emote (stand-in for floor work)
}

-- Break groups: where friends gather to rest and chat, in five distinct corners of the gym. Each
-- friend has a fixed group (and a fixed slot within it -- GymFriendService rings the members around
-- the centre facing inward), so a break reads as a little huddle of friends, not one pile, and two
-- friends never claim the same spot. Every centre sits at Z <= -57 -- well clear of the stairwell
-- hole (Z in [-37.5, -19.1]) -- so the straight walk from a station never crosses the shaft and no
-- one falls. Tuned by looking in Studio. Groups of three and two as requested.
GymFriends.LoungeGroups = {
	{ center = Vector3.new(-22, 23, -57), members = { "maya", "lucas", "bianca" } },
	{ center = Vector3.new(-46, 23, -78), members = { "priya", "diego" } },
	{ center = Vector3.new(-9, 23, -78), members = { "marcus", "hana" } },
	{ center = Vector3.new(-22, 23, -103), members = { "theo", "sofia", "noah" } },
	{ center = Vector3.new(-46, 23, -120), members = { "aisha", "sam" } },
} :: { Defs.LoungeGroup }

-- Two-answer Intro/Friend trees per NPC live in the per-workout roster modules; assemble them into
-- the flat Friends list the service iterates.
local roster: { Defs.FriendDef } = {}
for _, group in { require(script.Runners), require(script.Cyclists), require(script.Lifters), require(script.Floor) } do
	for _, friend in group do
		table.insert(roster, friend)
	end
end
GymFriends.Friends = roster

return GymFriends
