--!strict
-- Thin wrapper over AnalyticsService so gameplay code emits funnel events without caring about the
-- platform API or whether analytics is available (it no-ops in Studio / unpublished places). One
-- optional string detail is carried in CustomField01.

local AnalyticsService = game:GetService("AnalyticsService")

local Log = require(script.Parent.Log)

local Analytics = {}

function Analytics.event(player: Player, name: string, value: number?, detail: string?)
	local fields = if detail then { CustomField01 = detail } else nil
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
	if not ok then
		Log.warn("Analytics", `LogCustomEvent failed: {err}`)
	end
end

return Analytics
