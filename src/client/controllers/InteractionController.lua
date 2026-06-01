--!strict
-- InteractionController: routes ProximityPrompt triggers (Phone / Computer / Cab) to client
-- handlers. Other controllers register via OnInteract(name, fn) — e.g. TravelController hooks
-- "Cab" to open the travel picker. Also records the last interaction as a LocalPlayer attribute
-- so the wiring is observable.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InteractionController = {}

local handlers: { [string]: () -> () } = {}

-- Register a handler for an interaction prompt by name. Replaces any existing handler.
function InteractionController:OnInteract(name: string, handler: () -> ())
	handlers[name] = handler
end

function InteractionController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer then
			return
		end

		Players.LocalPlayer:SetAttribute("LastInteraction", prompt.Name)

		local handler = handlers[prompt.Name]
		if handler then
			handler()
		end
	end)
end

return InteractionController
