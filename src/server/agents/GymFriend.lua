--!strict
-- GymFriend: an Agent that lives in the gym. It exercises at its home station, then walks to its
-- fixed spot in a break group for a rest, looping forever (spell lengths come from
-- Shared.Logic.Routine, ~5 min each, jittered). Friends start at a random point in the cycle (a
-- "shift") so they don't all rest at once, and each rests at a distinct slot in its group facing the
-- group centre, so the groups read as friends chatting -- not one pile. The workout animation is
-- chosen by its Type. The branching chat + befriending are driven by GymFriendService, which calls
-- :interrupt()/:resume() so a friend pauses to face the player mid-routine and then carries on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GymFriendsCfg = require(ReplicatedStorage.Shared.Config.GymFriends)
local Routine = require(ReplicatedStorage.Shared.Logic.Routine)
local Agent = require(script.Parent.Agent)

type FriendDef = GymFriendsCfg.FriendDef

local GymFriend = setmetatable({}, { __index = Agent })
GymFriend.__index = GymFriend

export type GymFriend = Agent.Agent & {
	def: FriendDef,
	exerciseAnim: string,
	breakSpot: Vector3, -- this friend's distinct slot in its break group
	breakCenter: Vector3, -- the group centre it turns to face (so the group chats inward)
	rng: Random,
}

-- Wraps a prepared model (already seated at its station). `breakSpot`/`breakCenter` come from the
-- friend's assigned lounge group (GymFriendService computes them from Config.GymFriends.LoungeGroups).
function GymFriend.new(model: Model, def: FriendDef, breakSpot: Vector3, breakCenter: Vector3): GymFriend
	local self = Agent.new({
		model = model,
		walkSpeed = GymFriendsCfg.WalkSpeed,
		collisionGroup = GymFriendsCfg.CollisionGroup,
		walkAnim = GymFriendsCfg.Animations.Walk,
	}) :: any
	self.def = def
	self.exerciseAnim = GymFriendsCfg.Animations[def.Type]
	self.breakSpot = breakSpot
	self.breakCenter = breakCenter
	self.rng = Random.new()
	return setmetatable(self, GymFriend)
end

function GymFriend.routine(self: GymFriend)
	local cfg: Routine.Config = { exercise = GymFriendsCfg.Exercise, rest = GymFriendsCfg.Rest }
	local roll = function(min: number, max: number): number
		return self.rng:NextInteger(min, max)
	end

	-- Shift: begin at a random point in the cycle so the friends aren't in lockstep (they shouldn't
	-- all break at once). After this, independent jittered durations keep them desynced.
	local state: Routine.State
	local duration: number
	if self.rng:NextInteger(1, 2) == 1 then
		state, duration = "exercise", self.rng:NextInteger(0, cfg.exercise.max)
	else
		state, duration = "break", self.rng:NextInteger(0, cfg.rest.max)
	end

	while self:isAlive() do
		if state == "exercise" then
			self:walkTo(self.def.Station, self.def.Yaw)
			if self:isAlive() then
				self:playLoop(self.exerciseAnim)
			end
		else
			self:walkTo(self.breakSpot)
			if self:isAlive() then
				self:face(self.breakCenter)
				self:playLoop(GymFriendsCfg.Animations.Break)
			end
		end
		self:hold(duration)
		state, duration = Routine.next(state, cfg, roll)
	end
end

return GymFriend
