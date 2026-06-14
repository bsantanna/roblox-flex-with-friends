--!strict
-- Pure routine cycle for a gym-goer agent, free of Roblox globals so it is unit-testable under Lune.
-- The agent alternates between exercising and resting; each spell lasts a randomised duration drawn
-- from its configured [min, max] band so the NPCs never move in lockstep. This is logic only -- the
-- Agent/GymFriend runtime drives the actual walking and animation from these decisions.

local Routine = {}

export type State = "exercise" | "break"

export type Band = { min: number, max: number }

export type Config = {
	exercise: Band, -- how long an exercise spell lasts
	rest: Band, -- how long a break spell lasts (the "break" state)
}

-- A random duration within [band.min, band.max] from the supplied integer roller (rng(min, max)).
local function pick(rng: (number, number) -> number, band: Band): number
	return rng(band.min, band.max)
end

-- The first spell when an agent starts its day: exercising, for a randomised duration.
function Routine.first(cfg: Config, rng: (number, number) -> number): (State, number)
	return "exercise", pick(rng, cfg.exercise)
end

-- The spell that follows `state` (exercise <-> break) and how long to stay in it.
function Routine.next(state: State, cfg: Config, rng: (number, number) -> number): (State, number)
	if state == "exercise" then
		return "break", pick(rng, cfg.rest)
	end
	return "exercise", pick(rng, cfg.exercise)
end

return Routine
