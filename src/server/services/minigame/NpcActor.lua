--!strict
-- NpcActor: drives one NPC model for a minigame — glides it across a flat floor with a walk
-- animation and plays timed poses on it. Generic over any NPC minigame so they all move and pose
-- the same way (extracted from the trainer pose-memory game). The model's root must be anchored:
-- PivotTo carries the jointed limbs, and the floor is assumed level (the pivot Y is preserved while
-- walking). A later walkTo supersedes one still in flight, so the latest destination always wins.
--
-- Farm chore patrol: NPCs with a chore config wander between chore points, playing chore animations
-- (Action priority) when arrived, then gliding to the next chore or the home spawn. The chore cycle
-- is a background task that can be paused/stopped by external callers (e.g. when a minigame starts).
--
-- Citizen walk: NPCs that patrol the town sidewalks wander between random waypoints. Like chore
-- patrol, the walk can be paused (dialog/minigame starts) and resumed (game ends).

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
		-- Chore patrol state.
		_choreCycleId: thread?,
		_chorePause: boolean,
		_choreWaypoints: { { position: Vector3, animationId: string, delaySeconds: number } }?,
		_choreIndex: number,
		-- Citizen walk (sidewalk patrol for non-chore NPCs).
		_citizenWalkId: thread?,
		_citizenWalkPause: boolean,
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
		-- Chore patrol.
		_choreCycleId = nil,
		_chorePause = false,
		_choreWaypoints = nil,
		_choreIndex = 0,
		-- Citizen walk.
		_citizenWalkId = nil,
		_citizenWalkPause = false,
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

-- Chore patrol ---------------------------------------------------------------------------

-- Moves the NPC from its current position to `targetFeet` (same Y plane, no turning).
-- Used internally by chore patrol for short hops between chore points.
local function glideTo(self: NpcActor, targetFeet: Vector3, durationSeconds: number)
	self:_stopWalk()

	local startCF = self.model:GetPivot()
	local startPos = startCF.Position
	local endPos = Vector3.new(targetFeet.X, startPos.Y, targetFeet.Z)
	local moveDir = endPos - startPos
	local moving = moveDir.Magnitude > 0.5
	if not moving then
		return
	end
	local travelRot = CFrame.lookAt(Vector3.zero, moveDir).Rotation

	if self.animator then
		local track = self.animator:LoadAnimation(getAnimation(self.walkAnimationId))
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement
		track:Play()
		self._walkTrack = track
	end

	local t = 0
	while t < durationSeconds do
		-- Check pause flag so the NPC stops mid-glide when chore/citizen walk is paused.
		if self._chorePause or self._citizenWalkPause then
			self:_stopWalk()
			return
		end
		local dt = task.wait()
		t = math.min(t + dt, durationSeconds)
		self.model:PivotTo(CFrame.new(startPos:Lerp(endPos, t / durationSeconds)) * travelRot)
	end
	self:_stopWalk()
end

-- Plays a chore animation at the given position. The NPC glides to the position, stops,
-- plays the chore animation, then idles. Yields.
local function performChore(
	self: NpcActor,
	chore: { position: Vector3, animationId: string, delaySeconds: number },
	durationSeconds: number
)
	glideTo(self, chore.position, durationSeconds)

	local choreAnim = getAnimation(chore.animationId)
	if self.animator and choreAnim then
		local track = self.animator:LoadAnimation(choreAnim)
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		task.wait(chore.delaySeconds)
		track:Stop()
	end

	task.wait(0.5) -- brief pause between chores
end

-- Runs the chore loop in the background. Yields when paused by `PauseChore`.
local function choreLoop(self: NpcActor, homePos: Vector3)
	-- Idling at the home position before starting chores
	glideTo(self, homePos, 0.5)

	local waypoints = self._choreWaypoints
	if not waypoints or #waypoints == 0 then
		return
	end

	while self._chorePause == false do
		for i, chore in waypoints do
			if self._chorePause then
				break
			end
			self._choreIndex = i
			performChore(self, chore, self.moveSeconds)
		end

		-- Pause at home position until unpause (e.g. minigame ends) or loop restarts.
		-- Yield until the chore is resumed.
		while self._chorePause do
			task.wait(0.25)
		end
	end
end

-- Starts the chore patrol loop for this NPC. `homePos` is where the NPC idles;
-- `waypoints` is an ordered list of chore points to visit. The loop runs in the
-- background and can be paused/stopped with the methods below.
-- No-op if the NPC has no animator or no waypoints.
function NpcActor.startChorePatrol(
	npcActor: NpcActor,
	homePos: Vector3,
	waypoints: { { position: Vector3, animationId: string, delaySeconds: number } }
)
	-- Cancel any existing chore cycle
	npcActor:_stopChore()

	npcActor._choreWaypoints = waypoints
	npcActor._chorePause = false
	npcActor._choreIndex = 1

	if not npcActor.animator or not waypoints or #waypoints == 0 then
		return
	end

	npcActor._choreCycleId = task.spawn(function()
		choreLoop(npcActor, homePos)
	end)
end

-- Pauses the chore loop (e.g. when a minigame starts). The NPC stays where it is.
-- The loop can be resumed with `ResumeChore`.
function NpcActor.pauseChore(npcActor: NpcActor)
	npcActor._chorePause = true
end

-- Resumes the chore loop after it was paused.
function NpcActor.resumeChore(npcActor: NpcActor)
	npcActor._chorePause = false
end

-- Stops the chore loop entirely (e.g. when the game shuts down).
function NpcActor._stopChore(npcActor: NpcActor)
	if npcActor._choreCycleId then
		task.cancel(npcActor._choreCycleId)
		npcActor._choreCycleId = nil
	end
	npcActor._chorePause = false
end

-- Citizen walk loop --------------------------------------------------------------------------

-- Internal: random-waypoint sidewalk walk. Glides to a random waypoint, pauses,
-- then picks another random waypoint (avoiding the one just left). Runs forever
-- until stopCitizenWalk is called. Can be paused/resumed with the API below.
local function _citizenWalkLoop(
	self: NpcActor,
	waypoints: { Vector3 },
	walkSpeed: number,
	_pauseMin: number,
	pauseMax: number
)
	local prevIdx = 0
	while true do
		-- Yield while paused (same pattern as chore patrol) so the loop never
		-- exits — it just blocks until resumed.
		while self._citizenWalkPause do
			task.wait(0.25)
		end

		-- Pick a random waypoint different from the one we just left.
		local nextIdx
		repeat
			nextIdx = math.random(1, #waypoints)
		until nextIdx ~= prevIdx or #waypoints == 1
		prevIdx = nextIdx

		-- Compute glide duration from distance and walkSpeed.
		local cf = self.model:GetPivot()
		local dist = (waypoints[nextIdx] - Vector3.new(cf.Position.X, 0, cf.Position.Z)).Magnitude
		local duration = if dist > 0.5 then dist / walkSpeed else 0

		-- Glide to the waypoint.
		glideTo(self, waypoints[nextIdx], duration)

		-- Wait at the waypoint for a random duration, but yield so pause can interrupt.
		local elapsed = 0
		while elapsed < pauseMax do
			if self._citizenWalkPause then
				break
			end
			task.wait(0.25)
			elapsed += 0.25
		end
	end
end

-- Starts a citizen walk for this NPC. `waypoints` is a list of Vector3 positions the NPC
-- visits in random order. `walkSpeed` is in studs per second (3 is a casual pace).
-- `pauseMin` and `pauseMax` control the random delay at each waypoint.
function NpcActor.startCitizenWalk(
	self: NpcActor,
	waypoints: { Vector3 },
	walkSpeed: number,
	pauseMin: number,
	pauseMax: number
)
	-- Cancel any existing citizen walk.
	NpcActor.stopCitizenWalk(self)

	if not self.animator or not waypoints or #waypoints == 0 then
		return
	end

	self._citizenWalkPause = false
	self._citizenWalkId = task.spawn(function()
		_citizenWalkLoop(self, waypoints, walkSpeed, pauseMin, pauseMax)
	end)
end

-- Pauses the citizen walk loop (e.g. when a minigame starts). The NPC stays where it is.
-- The walk can be resumed with `resumeCitizenWalk`.
function NpcActor.pauseCitizenWalk(self: NpcActor)
	self._citizenWalkPause = true
end

-- Resumes the citizen walk after it was paused.
function NpcActor.resumeCitizenWalk(self: NpcActor)
	self._citizenWalkPause = false
end

-- Stops the citizen walk loop entirely (e.g. when the game shuts down).
function NpcActor.stopCitizenWalk(self: NpcActor)
	if self._citizenWalkId then
		task.cancel(self._citizenWalkId)
		self._citizenWalkId = nil
	end
	self._citizenWalkPause = false
end

return NpcActor
