--!strict
-- Pure key-sequence (Konami-style) matching, free of Roblox globals so it is unit-testable
-- under Lune. The caller owns the history window and feeds one key name at a time.

local KeySequence = {}

-- Appends `key` to `history` (without mutating it), trims the window to the sequence length,
-- and reports whether the window now equals `sequence`. Returns (matched, newHistory).
function KeySequence.push(history: { string }, key: string, sequence: { string }): (boolean, { string })
	local window = table.clone(history)
	table.insert(window, key)
	while #window > #sequence do
		table.remove(window, 1)
	end

	if #window < #sequence then
		return false, window
	end
	for i, expected in sequence do
		if window[i] ~= expected then
			return false, window
		end
	end
	return true, window
end

return KeySequence
