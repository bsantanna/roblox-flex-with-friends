--!strict
-- Client HUD tunables: the dev cheat console (DevConsoleController) and the cellphone (PhoneMenuController).

local Ui = {}

-- Dev cheat console (DevConsoleController): typing Sequence on the keyboard toggles a console
-- that can set the follower count. The server accepts SetFollowers only in Studio.
Ui.DevConsole = {
	Sequence = { "Up", "Up", "Down", "Down", "Left", "Right", "Left", "Right", "B", "A" },
	MaxFollowers = 1000000, -- server-side clamp on a cheated value
}

-- The cellphone HUD (PhoneMenuController): a GTA-style phone summoned from a corner button. The
-- phone art is the uploaded Phone01 image; the on-screen buttons (close / left / ok / right) are
-- baked into that art, so the controller overlays invisible click zones on them. Every rect below
-- is { x, y, width, height } in *scale* coordinates relative to the phone image (0..1), measured
-- from the cropped Phone01.png (485x624). Tune these if the art changes.
Ui.UI = {
	Phone = {
		Asset = "Phone01", -- key into ReplicatedStorage.Shared.SceneryAssetIds
		AspectRatio = 485 / 624, -- width / height of the cropped art
		HeightScale = 0.46, -- phone height as a fraction of the viewport height
		-- Invisible click zones over the art's baked-in buttons.
		Zones = {
			Close = { 0.666, 0.05, 0.198, 0.152 },
			Left = { 0.10, 0.78, 0.21, 0.15 },
			Ok = { 0.38, 0.75, 0.23, 0.18 },
			Right = { 0.70, 0.78, 0.21, 0.15 },
		},
		-- The teal screen area where carousel content / the social view render.
		Screen = { 0.25, 0.28, 0.58, 0.34 },
		-- Carousel functionalities, in order. `action` is matched in PhoneMenuController.
		Items = {
			{ emoji = "📷", label = "Take Photo", action = "Photo" },
			{ emoji = "👥", label = "Invite Friends", action = "Invite" },
			{ emoji = "🚕", label = "Call a Cab", action = "Cab" },
			{ emoji = "🤩", label = "Social Media", action = "Social" },
			{ emoji = "🛍️", label = "Shop", action = "Shop" },
		},
	},
}

return Ui
