--!strict
-- Pure branching-dialog navigation, free of Roblox globals so it is unit-testable under Lune.
-- A tree is a set of nodes; each node carries the NPC's line plus the player's answer choices, and
-- every choice either points to the next node (the NPC's reply) or, with no target, closes the
-- conversation when picked. This generalises Logic.Dialog (a fixed line list + one conditional
-- branch) into the open-ended, choose-your-reply chats the gym friends use.

local DialogTree = {}

export type Choice = {
	label: string, -- the player's answer, shown as a button
	next: string?, -- id of the node to advance to (the NPC's reply); nil closes the chat when picked
}

export type Node = {
	text: string, -- what the NPC says, shown in the speech bubble
	choices: { Choice }, -- the player's possible answers
}

export type Tree = {
	start: string, -- id of the opening node
	nodes: { [string]: Node },
}

-- The node registered at `id`, or nil if there is none.
function DialogTree.node(tree: Tree, id: string): Node?
	return tree.nodes[id]
end

-- The opening node, where every conversation begins.
function DialogTree.startNode(tree: Tree): Node?
	return tree.nodes[tree.start]
end

-- The choice labels of a node, in order (what the player sees as buttons).
function DialogTree.labels(node: Node): { string }
	local out = table.create(#node.choices)
	for i, choice in node.choices do
		out[i] = choice.label
	end
	return out
end

-- Resolve picking choice `choiceIndex` at `nodeId`. Returns:
--   ok=false            -> the node or index was invalid (caller ignores the input)
--   ok=true,  next=nil  -> a valid closing choice (caller ends the conversation)
--   ok=true,  next=id   -> advance to that node
function DialogTree.choose(tree: Tree, nodeId: string, choiceIndex: number): (boolean, string?)
	local node = tree.nodes[nodeId]
	if not node then
		return false, nil
	end
	if choiceIndex % 1 ~= 0 or choiceIndex < 1 or choiceIndex > #node.choices then
		return false, nil
	end
	return true, node.choices[choiceIndex].next
end

return DialogTree
