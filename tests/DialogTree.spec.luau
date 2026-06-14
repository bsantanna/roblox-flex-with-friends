--!strict
local framework = require("./framework")
local DialogTree = require("../src/shared/Logic/DialogTree")
local test = framework.test
local expect = framework.expect

local TREE: DialogTree.Tree = {
	start = "greet",
	nodes = {
		greet = {
			text = "Hey, new here?",
			choices = {
				{ label = "Yeah!", next = "reply_yes" },
				{ label = "Just looking", next = "reply_no" },
				{ label = "Bye", next = nil },
			},
		},
		reply_yes = {
			text = "Welcome! Let's be friends.",
			choices = { { label = "Thanks!", next = nil } },
		},
		reply_no = {
			text = "Cool, enjoy the gym!",
			choices = { { label = "Will do", next = nil } },
		},
	},
}

test("startNode returns the opening node", function()
	local node = DialogTree.startNode(TREE)
	assert(node, "start node expected")
	expect(node.text).toEqual("Hey, new here?")
end)

test("node returns a node by id and nil for a missing id", function()
	local n = DialogTree.node(TREE, "reply_yes")
	assert(n, "node expected")
	expect(n.text).toEqual("Welcome! Let's be friends.")
	expect(DialogTree.node(TREE, "nope") == nil).toBeTrue()
end)

test("labels lists the choice labels in order", function()
	local node = DialogTree.startNode(TREE)
	assert(node, "node expected")
	local labels = DialogTree.labels(node)
	expect(#labels).toEqual(3)
	expect(labels[1]).toEqual("Yeah!")
	expect(labels[3]).toEqual("Bye")
end)

test("choose advances to the linked node", function()
	local ok, nextId = DialogTree.choose(TREE, "greet", 1)
	expect(ok).toBeTrue()
	expect(nextId).toEqual("reply_yes")
end)

test("choose on a closing choice is valid with no next node", function()
	local ok, nextId = DialogTree.choose(TREE, "greet", 3)
	expect(ok).toBeTrue()
	expect(nextId == nil).toBeTrue()
end)

test("choose rejects an out-of-range index or a missing node", function()
	expect((DialogTree.choose(TREE, "greet", 9))).toBeFalse()
	expect((DialogTree.choose(TREE, "ghost", 1))).toBeFalse()
end)
