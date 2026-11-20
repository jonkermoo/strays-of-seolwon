--!strict
-- M1 style test: light/weather toggle (keys 1-9 or the buttons, bottom left). Applies the
-- STYLE-BIBLE §9 presets on the client and draws the NVG overlay (green, grain, dual-tube
-- vignette). Test scene only: the real weather system replaces this after M1.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Light = require(ReplicatedStorage.Shared.StyleTest.Light)

local StyleToggle = {}

local function nvgOverlay(gui: ScreenGui): Frame
	local root = Instance.new("Frame")
	root.Name = "NVG"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	-- binocular mask: one pill shape (two overlapping tube strokes drew over each other's view)
	local tube = Instance.new("Frame")
	tube.AnchorPoint = Vector2.new(0.5, 0.5)
	tube.Position = UDim2.fromScale(0.5, 0.5)
	tube.Size = UDim2.fromScale(1.5, 0.94)
	tube.SizeConstraint = Enum.SizeConstraint.RelativeYY
	tube.BackgroundTransparency = 1
	tube.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = tube
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 900
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.02
	stroke.Parent = tube
	-- grain: a few hundred tiny flickering dots
	local grain = Instance.new("Frame")
	grain.Name = "Grain"
	grain.Size = UDim2.fromScale(1, 1)
	grain.BackgroundTransparency = 1
	grain.Parent = root
	local dots = {}
	for _ = 1, 260 do
		local d = Instance.new("Frame")
		d.BorderSizePixel = 0
		d.Size = UDim2.fromOffset(2, 2)
		d.BackgroundColor3 = Color3.fromRGB(170, 255, 180)
		d.Parent = grain
		table.insert(dots, d)
	end
	RunService.RenderStepped:Connect(function()
		if not root.Visible then
			return
		end
		for _, d in dots do
			d.Position = UDim2.fromScale(math.random(), math.random())
			d.BackgroundTransparency = 0.55 + math.random() * 0.4
		end
	end)
	return root
end

function StyleToggle.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "StyleToggle"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local nvg = nvgOverlay(gui)
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 8, 1, -40)
	bar.Size = UDim2.fromOffset(9 * 84, 32)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.Parent = bar
	local current = "Day"
	local function set(name: string)
		current = name
		local pr = Light.apply(name)
		Light.weather(pr.weather, (workspace.CurrentCamera :: Camera).CFrame.Position, workspace)
		nvg.Visible = pr.nvg == true
	end
	for i, name in Light.Order do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(80, 28)
		b.BackgroundColor3 = Color3.fromRGB(30, 33, 34)
		b.BackgroundTransparency = 0.25
		b.TextColor3 = Color3.fromRGB(200, 204, 203)
		b.Font = Enum.Font.RobotoMono
		b.TextSize = 13
		b.Text = `{i} {name}`
		b.Parent = bar
		b.Activated:Connect(function()
			set(name)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local n = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		if n >= 1 and n <= #Light.Order then
			set(Light.Order[n])
		end
	end)
	-- weather follows the camera
	RunService.Heartbeat:Connect(function()
		local w = workspace:FindFirstChild("StyleWeather") :: BasePart?
		if w then
			w.CFrame = CFrame.new(
				(workspace.CurrentCamera :: Camera).CFrame.Position + Vector3.new(0, 40, 0)
			)
		end
	end)
	set(current)
end

return StyleToggle
