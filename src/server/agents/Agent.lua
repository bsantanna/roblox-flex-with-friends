--!strict
-- Agent: a reusable base class for a simple "mini-AI" world actor -- a Humanoid model that walks,
-- plays looping animations, and runs a behaviour loop, with a dialog interrupt that freezes it to
-- face a player and then resumes. GymFriend subclasses it; other ambient actors (shoppers,
-- pedestrians, ...) can reuse the same engine. Server-side: the server owns these NPCs, so all
-- movement and animation is driven here. Subclasses override :routine() and call :start().

local Agent = {}
Agent.__index = Agent

type AgentFields = {
	model: Model,
	humanoid: Humanoid?, -- nil for a non-rig fallback body (then it teleports instead of walking)
	animator: Animator?,
	root: BasePart,
	walkSpeed: number,
	walkAnim: string?, -- looped while walking
	alive: boolean,
	interrupted: boolean, -- true while a dialog has the agent paused
	loopTrack: AnimationTrack?,
	loopAnimId: string?,
}

export type Agent = typeof(setmetatable({} :: AgentFields, Agent))

export type Props = {
	model: Model,
	walkSpeed: number,
	collisionGroup: string?, -- assigned to every BasePart so instances don't shove each other
	walkAnim: string?,
}

local MOVE_TIMEOUT = 8 -- seconds before giving up on a MoveTo (blocked path), so the loop never hangs
local ARRIVE_RADIUS = 2 -- studs from the target that counts as "arrived"

local function loadTrack(animator: Animator, animId: string): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	return animator:LoadAnimation(anim)
end

function Agent.new(props: Props): Agent
	local model = props.model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = (
		model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChildWhichIsA("BasePart")
	) :: BasePart
	assert(root, "Agent: model has no BasePart")

	local animator: Animator? = nil
	if humanoid then
		humanoid.WalkSpeed = props.walkSpeed
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			local created = Instance.new("Animator")
			created.Parent = humanoid
			animator = created
		end
	end

	if props.collisionGroup then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = props.collisionGroup
			end
		end
	end

	return setmetatable({
		model = model,
		humanoid = humanoid,
		animator = animator,
		root = root,
		walkSpeed = props.walkSpeed,
		walkAnim = props.walkAnim,
		alive = true,
		interrupted = false,
		loopTrack = nil,
		loopAnimId = nil,
	}, Agent)
end

function Agent.isAlive(self: Agent): boolean
	return self.alive and self.model.Parent ~= nil
end

-- Plays `animId` on a loop, replacing any current loop. No-op if it is already the current loop or
-- the rig has no Animator (a fallback body). The current loop is also mirrored to a "LoopAnim" model
-- attribute so per-player client cosmetic rigs (which replace a hidden server rig) can play the same
-- animation -- see client NpcAppearanceController.
function Agent.playLoop(self: Agent, animId: string)
	if self.loopAnimId == animId and self.loopTrack then
		return
	end
	self:stopLoop()
	self.model:SetAttribute("LoopAnim", animId)
	local animator = self.animator
	if not animator then
		return
	end
	local track = loadTrack(animator, animId)
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	self.loopTrack = track
	self.loopAnimId = animId
end

function Agent.stopLoop(self: Agent)
	if self.loopTrack then
		self.loopTrack:Stop()
		self.loopTrack = nil
		self.loopAnimId = nil
	end
	self.model:SetAttribute("LoopAnim", "")
end

-- Walks to `position` on the current floor (plays the walk loop while moving) and, with `faceYaw`,
-- turns to that facing on arrival. Blocks the calling coroutine; pauses in place while interrupted
-- and resumes toward the target afterwards. Returns whether the agent is still alive at the end.
function Agent.walkTo(self: Agent, position: Vector3, faceYaw: number?): boolean
	local humanoid = self.humanoid
	local target = Vector3.new(position.X, self.root.Position.Y, position.Z)

	local function arrived(): boolean
		local p = self.root.Position
		return (Vector3.new(p.X, target.Y, p.Z) - target).Magnitude <= ARRIVE_RADIUS
	end

	if humanoid and not arrived() then
		if self.walkAnim then
			self:playLoop(self.walkAnim)
		end
		local started = os.clock()
		while self.alive and not arrived() do
			if self.interrupted then
				humanoid:Move(Vector3.zero)
				self:stopLoop()
				repeat
					task.wait(0.1)
				until (not self.interrupted) or not self.alive
				if not self.alive then
					break
				end
				if self.walkAnim then
					self:playLoop(self.walkAnim)
				end
				started = os.clock()
			end
			if os.clock() - started > MOVE_TIMEOUT then
				break
			end
			humanoid:MoveTo(target)
			task.wait(0.2)
		end
		humanoid:Move(Vector3.zero)
		self:stopLoop()
	elseif not humanoid then
		self.model:PivotTo(CFrame.new(target) * CFrame.Angles(0, math.rad(faceYaw or 0), 0))
	end

	if faceYaw and self.alive then
		self.model:PivotTo(CFrame.new(self.root.Position) * CFrame.Angles(0, math.rad(faceYaw), 0))
	end
	return self.alive
end

-- Waits `seconds`, but pauses the countdown while interrupted so a chat doesn't burn the timer.
function Agent.hold(self: Agent, seconds: number)
	local remaining = seconds
	while self.alive and remaining > 0 do
		local dt = task.wait(0.2)
		if not self.interrupted then
			remaining -= dt
		end
	end
end

-- Pivots in place to face the (flat) point `target`.
function Agent.face(self: Agent, target: Vector3)
	local pos = self.root.Position
	local look = Vector3.new(target.X, pos.Y, target.Z)
	if (look - pos).Magnitude > 0.1 then
		self.model:PivotTo(CFrame.lookAt(pos, look))
	end
end

-- Freezes the agent (the routine's walk/hold pause) and, given a point, turns it to face there.
-- Used by a dialog service so the NPC stops to talk to a player.
function Agent.interrupt(self: Agent, faceTarget: Vector3?)
	self.interrupted = true
	local humanoid = self.humanoid
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
	if faceTarget then
		self:face(faceTarget)
	end
end

function Agent.resume(self: Agent)
	self.interrupted = false
end

-- Starts the behaviour loop in its own thread. Subclasses implement :routine() (the loop body),
-- which should guard on self:isAlive() and may block (walk/hold).
function Agent.start(self: Agent)
	task.spawn(function()
		self:routine()
	end)
end

-- Default behaviour: nothing. Subclasses override.
function Agent.routine(_self: Agent) end

function Agent.destroy(self: Agent)
	self.alive = false
	self:stopLoop()
	self.model:Destroy()
end

return Agent
