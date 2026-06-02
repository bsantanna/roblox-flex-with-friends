--!strict
-- CoreUiController: hides the Roblox core UI (chat, player list, self-view, the topbar cluster)
-- so only the game's own interface shows. The leftmost Roblox menu button is platform-mandated
-- and cannot be removed in-experience.

local StarterGui = game:GetService("StarterGui")

local CoreUiController = {}

function CoreUiController:Start()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

	-- The SetCore("TopbarEnabled") binding registers asynchronously on the client; retry until it
	-- takes (it throws until the core scripts are ready).
	task.spawn(function()
		while not pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end) do
			task.wait(0.1)
		end
	end)
end

return CoreUiController
