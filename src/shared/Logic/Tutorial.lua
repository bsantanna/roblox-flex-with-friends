--!strict
-- Pure onboarding state machine for the core loop's first follower reward: open the phone, take a
-- photo. Free of Roblox globals so it's Lune-testable; the client HintController feeds it observed
-- progress and renders the returned step's hint. A player who has ever taken a photo is "done", so
-- returning players never see the tutorial (no extra persisted flag needed).

local Tutorial = {}

export type Progress = {
	phoneOpened: boolean, -- has the player opened the phone this session
	photosTaken: number, -- lifetime photos (from Stats.PhotosTaken)
}

export type Step = "open_phone" | "take_photo" | "done"

-- The current onboarding step for the given progress.
function Tutorial.step(progress: Progress): Step
	if progress.photosTaken >= 1 then
		return "done"
	end
	if not progress.phoneOpened then
		return "open_phone"
	end
	return "take_photo"
end

-- The on-screen hint for a step ("done" has no hint).
function Tutorial.hint(step: Step): string?
	if step == "open_phone" then
		return "Tap 📲 to open your phone"
	elseif step == "take_photo" then
		return "Pick 📷 Take Photo to earn your first followers"
	end
	return nil
end

return Tutorial
