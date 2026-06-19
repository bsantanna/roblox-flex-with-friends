--!strict
-- NpcActor: drives one NPC model for a minigame — glides it across a flat floor with a walk
-- animation and plays timed poses on it. Generic over any NPC minigame so they all move and pose
-- the same way (extracted from the trainer pose-memory game). The model's root must be anchored:
-- PivotTo carries the jointed limbs, and the floor is assumed level (the pivot Y is preserved while
-- walking). A later walkTo supersedes one still in flight, so the latest destination always wins.

local NpcActor = {}
NpcActor.__index = NpcActor

local TURN_SECONDS = 0.3 -- time to pivot to the final facing after arriving

-- One reusable Animation instance per asset id, shared across actors; tracks load per play.
local animations: { [string]: Animation } = {}
local function getAnimation(animationId: string): Animation
	local cached = animations[animationId]
	if cached then
		return cached
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	animations[animationId] = animation
	return animation
end

-- Plays `animationId` on an Animator for `seconds`; no-op without an Animator/id (e.g. the NPC's
-- red-box fallback body). Module-level so it serves both NPC and player posing.
function NpcActor.pose(animator: Animator?, animationId: string?, seconds: number)
	if not animator or not animationId then
		return
	end
	local track = animator:LoadAnimation(getAnimation(animationId))
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	task.delay(seconds, function()
		track:Stop()
	end)
end

-- Poses a player's own character for `seconds` (used to mirror correct inputs back to the player).
function NpcActor.posePlayer(player: Player, animationId: string?, seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	NpcActor.pose(animator, animationId, seconds)
end

export type NpcActor = typeof(setmetatable(
	{} :: {
		model: Model,
		animator: Animator?,
		moveSeconds: number,
		walkAnimationId: string,
		_moveGen: number,
		_walkTrack: AnimationTrack?,
	},
	NpcActor
))

local function getAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

-- Wraps `model`; `moveSeconds`/`walkAnimationId` tune the glide between post and arena.
function NpcActor.new(model: Model, moveSeconds: number, walkAnimationId: string): NpcActor
	return setmetatable({
		model = model,
		animator = getAnimator(model),
		moveSeconds = moveSeconds,
		walkAnimationId = walkAnimationId,
		_moveGen = 0,
		_walkTrack = nil,
	}, NpcActor)
end

-- Poses the NPC for `seconds` (skips silently when the rig has no Animator / no pose).
function NpcActor.poseNpc(self: NpcActor, animationId: string?, seconds: number)
	NpcActor.pose(self.animator, animationId, seconds)
end

function NpcActor._stopWalk(self: NpcActor)
	if self._walkTrack then
		self._walkTrack:Stop()
		self._walkTrack = nil
	end
end

-- Glides the model from its current spot to targetFeet on the same flat floor, facing the direction
-- of travel with the walk animation, then turns in place to finalYaw (degrees around Y). Yields.
function NpcActor.walkTo(self: NpcActor, targetFeet: Vector3, finalYaw: number)
	self._moveGen += 1
	local myGen = self._moveGen
	self:_stopWalk()

	local startCF = self.model:GetPivot()
	local startPos = startCF.Position
	local endPos = Vector3.new(targetFeet.X, startPos.Y, targetFeet.Z)
	local moveDir = endPos - startPos
	local moving = moveDir.Magnitude > 0.5
	local travelRot = if moving then CFrame.lookAt(Vector3.zero, moveDir).Rotation else startCF.Rotation
	local finalRot = CFrame.Angles(0, math.rad(finalYaw), 0)

	if self.animator and moving then
		local track = self.animator:LoadAnimation(getAnimation(self.walkAnimationId))
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement
		track:Play()
		self._walkTrack = track
	end

	local t = 0
	while t < self.moveSeconds do
		local dt = task.wait()
		if myGen ~= self._moveGen then
			return
		end
		t = math.min(t + dt, self.moveSeconds)
		self.model:PivotTo(CFrame.new(startPos:Lerp(endPos, t / self.moveSeconds)) * travelRot)
	end
	self:_stopWalk()

	-- Turn in place to the final facing (no-op when already aligned, e.g. walking home).
	t = 0
	while t < TURN_SECONDS do
		local dt = task.wait()
		if myGen ~= self._moveGen then
			return
		end
		t = math.min(t + dt, TURN_SECONDS)
		self.model:PivotTo(CFrame.new(endPos) * travelRot:Lerp(finalRot, t / TURN_SECONDS))
	end
	if myGen == self._moveGen then
		self.model:PivotTo(CFrame.new(endPos) * finalRot)
	end
end

return NpcActor
