--!strict
-- Campaign place client: plain debug panel for the data layer (marks, classes, guide,
-- campaign day/state, in-game server list). No styled UI until the style bible is approved.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Guide = require(Shared.Config.Guide)
local DebugUi = require(Shared.DebugUi)

local player = Players.LocalPlayer
task.spawn(require(script.AdminPanel).start) -- F2 admin panel (Studio / owner only)
local gui = DebugUi.screen(player:WaitForChild("PlayerGui"), "DataDebug")

-- left: player data
local left = DebugUi.panel(gui, 0, 0, 280, 560)
local marksLabel = DebugUi.label(left, "Loading save...", 36)
local unlockLabel = DebugUi.label(left, "", 36)
DebugUi.button(left, "+10 marks (debug)", function()
	Net.wait("DebugGrant"):FireServer(10)
end)
DebugUi.button(left, "+100 marks (debug)", function()
	Net.wait("DebugGrant"):FireServer(100)
end)
local guideButton: TextButton
DebugUi.label(left, "Classes (click to pick):")
local classList = DebugUi.scroll(left, 200)
local gunLabel = DebugUi.label(left, "", 60)

-- right: campaign and server list
local right = DebugUi.panel(gui, 1, 0, 300, 420)
right.Position = UDim2.new(1, -308, 0, 8)
local campaignLabel = DebugUi.label(right, "Campaign: ...", 36)
local statusLabel = DebugUi.label(right, "", 36)
DebugUi.button(right, "Refresh server list", function()
	Net.wait("ListRequest"):FireServer()
end)
local list = DebugUi.scroll(right, 220)
local resetButton = DebugUi.button(right, "Reset campaign (private owner)", function()
	Net.wait("ResetCampaign"):FireServer()
end)
resetButton.Visible = false

-- guide (heavily advised on first play; finishing it grants the release code)
local guideFrame = DebugUi.panel(gui, 0.5, 0.3, 360, 160)
guideFrame.Position = UDim2.new(0.5, -180, 0.3, 0)
guideFrame.Visible = false
local guideText = DebugUi.label(guideFrame, "", 80)
local page = 1
local function showPage()
	guideText.Text = `({page}/{#Guide.Pages}) {Guide.Pages[page]}`
end
DebugUi.button(guideFrame, "Next", function()
	if page < #Guide.Pages then
		page += 1
		showPage()
	else
		Net.wait("GuideFinish"):FireServer()
		guideFrame.Visible = false
	end
end)
DebugUi.button(guideFrame, "Later", function()
	guideFrame.Visible = false
end)
guideButton = DebugUi.button(left, "Open guide", function()
	page = 1
	showPage()
	guideFrame.Visible = true
end)

local firstState = true
Net.wait("DataState").OnClientEvent:Connect(function(s)
	marksLabel.Text =
		`Marks: {s.marks}   Class: {s.class}\nRank patch: {s.rank.family} {s.rank.count}`
	if #s.newlyUnlocked > 0 then
		local names = {}
		for _, u in s.newlyUnlocked do
			table.insert(names, u.kind .. " " .. u.id)
		end
		unlockLabel.Text = "Unlocked: " .. table.concat(names, ", ")
	end
	gunLabel.Text = "Guns: "
		.. table.concat(s.guns, ", ")
		.. "\nSpawn items: "
		.. table.concat(s.spawnItems, ", ")
	guideButton.Text = if s.guideDone then "Guide (read)" else "Open guide (+100 marks)"
	DebugUi.clear(classList)
	for _, c in s.classes do
		local mark = if c.id == s.class then "> " elseif c.open then "  " else "[locked] "
		DebugUi.button(classList, `{mark}{c.id} ({c.marks})`, function()
			Net.wait("PickClass"):FireServer(c.id)
		end)
	end
	if firstState and not s.guideDone then
		unlockLabel.Text = Guide.Prompt
		page = 1
		showPage()
		guideFrame.Visible = true
	end
	firstState = false
end)

Net.wait("CampaignState").OnClientEvent:Connect(function(c)
	if c == nil then
		return
	end
	local hour = math.floor(c.fraction * 24)
	campaignLabel.Text = `Campaign {string.sub(c.id, 1, 12)} · Day {c.day} ({hour}h after dawn)\n`
		.. `{c.state} · {c.players} player(s){if c.private then " · private" else ""}{if c.mock
			then " · mock stores"
			else ""}`
	resetButton.Visible = c.private and (c.owner == player.UserId)
end)

Net.wait("Status").OnClientEvent:Connect(function(text)
	statusLabel.Text = tostring(text)
end)

Net.wait("ListRows").OnClientEvent:Connect(function(rows)
	DebugUi.clear(list)
	if #rows == 0 then
		DebugUi.label(list, "(no other servers listed)")
	end
	for _, row in rows do
		DebugUi.button(list, DebugUi.rowText(row), function()
			Net.wait("JoinRequest"):FireServer(row.id)
		end)
	end
end)
