--!strict
-- A comic speech bubble over a world part: a white rounded bubble + downward tail + dialog text,
-- built fully transparent so it can be faded in. Shared by the NPC dialog services (the personal
-- trainer in DialogService and the gym friends in GymFriendService) so the bubble looks identical
-- everywhere. It is a server-side BillboardGui parented to the NPC, so every nearby player sees the
-- line (Mario-Party style); same visual pattern as TrafficService's balloon.

local TweenService = game:GetService("TweenService")

local SpeechBubble = {}
SpeechBubble.__index = SpeechBubble

local BG = Color3.fromRGB(250, 250, 245)
local INK = Color3.fromRGB(35, 30, 30)
local FADE = 0.25 -- seconds for the fade in/out
local TWEEN_IN = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Fade = { inst: Instance, prop: string }

export type SpeechBubble = typeof(setmetatable(
	{} :: { gui: BillboardGui, label: TextLabel, fades: { Fade } },
	SpeechBubble
))

-- Builds the bubble over `root`, fully transparent and ready to :show().
function SpeechBubble.create(root: BasePart): SpeechBubble
	local gui = Instance.new("BillboardGui")
	gui.Name = "DialogBubble"
	gui.Size = UDim2.fromOffset(280, 120)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120

	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.5, 0.78)
	tail.Size = UDim2.fromScale(0.18, 0.42)
	tail.Rotation = 45
	tail.BackgroundColor3 = BG
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	tail.Parent = gui
	local tstroke = Instance.new("UIStroke")
	tstroke.Thickness = 3
	tstroke.Color = INK
	tstroke.Transparency = 1
	tstroke.Parent = tail

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.Position = UDim2.fromScale(0.5, 0)
	bubble.Size = UDim2.fromScale(1, 0.78)
	bubble.BackgroundColor3 = BG
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 2
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.24, 0)
	corner.Parent = bubble
	local bstroke = Instance.new("UIStroke")
	bstroke.Thickness = 3
	bstroke.Color = INK
	bstroke.Transparency = 1
	bstroke.Parent = bubble

	-- Seam: a border-less BG strip over the neck that erases the bubble's bottom-border
	-- segment where the tail attaches, so the outline flows from bubble into tail with no
	-- line cutting across. Sits above the bubble (2) but below the text (4).
	local seam = Instance.new("Frame")
	seam.Name = "Seam"
	seam.AnchorPoint = Vector2.new(0.5, 0.5)
	seam.Position = UDim2.fromScale(0.5, 0.78)
	seam.Size = UDim2.fromScale(0.26, 0.05)
	seam.BackgroundColor3 = BG
	seam.BackgroundTransparency = 1
	seam.BorderSizePixel = 0
	seam.ZIndex = 3
	seam.Parent = gui

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.9, 0.8)
	text.BackgroundTransparency = 1
	text.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	text.Text = ""
	text.TextWrapped = true
	text.TextScaled = true
	text.TextColor3 = INK
	text.TextTransparency = 1
	text.ZIndex = 4 -- BillboardGui ZIndex is Global; must beat the bubble (2) and seam (3)
	text.Parent = bubble

	local fades: { Fade } = {
		{ inst = bubble, prop = "BackgroundTransparency" },
		{ inst = bstroke, prop = "Transparency" },
		{ inst = tail, prop = "BackgroundTransparency" },
		{ inst = tstroke, prop = "Transparency" },
		{ inst = seam, prop = "BackgroundTransparency" },
		{ inst = text, prop = "TextTransparency" },
	}

	gui.Adornee = root
	gui.Parent = root
	return setmetatable({ gui = gui, label = text, fades = fades }, SpeechBubble)
end

local function tween(self: SpeechBubble, info: TweenInfo, transparency: number)
	for _, f in self.fades do
		TweenService:Create(f.inst, info, { [f.prop] = transparency }):Play()
	end
end

-- Sets the line shown in the bubble.
function SpeechBubble.setText(self: SpeechBubble, line: string)
	self.label.Text = line
end

-- Fades the bubble in.
function SpeechBubble.show(self: SpeechBubble)
	tween(self, TWEEN_IN, 0)
end

-- Fades the bubble out and destroys it once the fade completes.
function SpeechBubble.hide(self: SpeechBubble)
	tween(self, TWEEN_OUT, 1)
	local gui = self.gui
	task.delay(FADE, function()
		gui:Destroy()
	end)
end

return SpeechBubble
