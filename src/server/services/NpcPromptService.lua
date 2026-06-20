--!strict
-- NpcPromptService: hides/shows NPC ProximityPrompts to prevent concurrent minigames.
-- Populated by DialogService at start-up; consumed by MinigameService at session end.

local NpcPromptService = {}

-- npcId -> ProximityPrompt mapping. Populated by DialogService at start.
local prompts: { [string]: ProximityPrompt? } = {}

-- Called by DialogService at startup to register prompts for each NPC.
function NpcPromptService.Register(npcId: string, prompt: ProximityPrompt)
	prompts[npcId] = prompt
end

-- Hide the "Talk" prompt on an NPC.
function NpcPromptService:Hide(npcId: string)
	local prompt = prompts[npcId]
	if prompt then
		(prompt :: any).Visible = false
	end
end

-- Show the "Talk" prompt on an NPC.
function NpcPromptService:Show(npcId: string)
	local prompt = prompts[npcId]
	if prompt then
		(prompt :: any).Visible = true
	end
end

return NpcPromptService
