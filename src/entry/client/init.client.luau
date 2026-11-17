--!strict
-- Entry place client: plain debug menu (Play = auto-match, server list). No styled UI yet.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local DebugUi = require(Shared.DebugUi)

local player = Players.LocalPlayer
local gui = DebugUi.screen(player:WaitForChild("PlayerGui"), "EntryDebug")
local panel = DebugUi.panel(gui, 0.5, 0.15, 340, 420)
panel.Position = UDim2.new(0.5, -170, 0.15, 0)

DebugUi.label(panel, "Strays of Seolwon (debug menu)")
local statusLabel = DebugUi.label(panel, "", 36)
DebugUi.button(panel, "Play (auto-match)", function()
	statusLabel.Text = "Matching..."
	Net.wait("MatchRequest"):FireServer()
end)
DebugUi.button(panel, "Refresh server list", function()
	Net.wait("ListRequest"):FireServer()
end)
local list = DebugUi.scroll(panel, 280)

Net.wait("Status").OnClientEvent:Connect(function(text)
	statusLabel.Text = tostring(text)
end)

Net.wait("ListRows").OnClientEvent:Connect(function(rows)
	DebugUi.clear(list)
	if #rows == 0 then
		DebugUi.label(list, "(no servers yet: Play starts one)")
	end
	for _, row in rows do
		DebugUi.button(list, DebugUi.rowText(row), function()
			Net.wait("JoinRequest"):FireServer(row.id)
		end)
	end
end)

Net.wait("ListRequest"):FireServer()
