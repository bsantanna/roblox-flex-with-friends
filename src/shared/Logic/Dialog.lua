--!strict
-- Pure NPC-dialog flow, free of Roblox globals so it is unit-testable under Lune.
-- A dialog is a fixed list of lines followed by one branch line: the qualified line (with its
-- choices) when the player meets the gate, otherwise the gate line (with its choices).

local Dialog = {}

export type Def = {
	lines: { string },
	qualifiedLine: string,
	gateLine: string,
	qualifiedChoices: { string },
	gateChoices: { string },
}

export type Step = {
	text: string,
	index: number,
	total: number,
	-- nil while plain lines advance; the branch line carries the choices to offer.
	choices: { string }?,
}

-- Total steps a session walks through: every plain line plus the branch line.
function Dialog.total(def: Def): number
	return #def.lines + 1
end

-- The step to show at 1-based `index`, or nil once the dialog is over.
function Dialog.step(def: Def, qualified: boolean, index: number): Step?
	local total = Dialog.total(def)
	if index < 1 or index > total then
		return nil
	end
	if index <= #def.lines then
		return { text = def.lines[index], index = index, total = total }
	end
	if qualified then
		return { text = def.qualifiedLine, index = index, total = total, choices = def.qualifiedChoices }
	end
	return { text = def.gateLine, index = index, total = total, choices = def.gateChoices }
end

return Dialog
