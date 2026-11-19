--!strict
-- F2 admin panel (Studio, or the game's owner): fast movement to get round the greybox.
-- Fly (WASD, Space up, Ctrl down), speed presets, noclip, teleport to any place, Ctrl+click
-- teleport, and a readout of map position, grid cell and season zone. Plain debug UI only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local DebugUi = require(Shared.DebugUi)
local Data = require(Shared.Map.Data)
local Geo = require(Shared.Map.Geo)(Data)

local AdminPanel = {}

local SPEEDS = { 16, 60, 150, 400, 1000 }
local KIND_ORDER = {
	"hq",
	"aoi",
	"enemy",
	"gated",
	"dock",
	"fb",
	"truck",
	"veh",
	"hum",
	"gun",
	"apc",
	"apcg",
	"tank",
	"key",
	"manual",
	"bp",
	"kp",
	"rare",
	"radio",
	"power",
	"cut",
	"misc",
}

function AdminPanel.allowed(player: Player): boolean
	return RunService:IsStudio() or player.UserId == game.CreatorId
end

function AdminPanel.start()
	local player = Players.LocalPlayer
	if not AdminPanel.allowed(player) then
		return
	end
	local camera = workspace.CurrentCamera
	local gui = DebugUi.screen(player:WaitForChild("PlayerGui"), "AdminPanel")
	gui.Enabled = false
	local panel = DebugUi.panel(gui, 0, 0, 300, 640)
	panel.Position = UDim2.new(0.5, -150, 0, 8)

	local speed = 150
	local flying, noclip = false, false
	local readout = DebugUi.label(panel, "", 54)
	local state = DebugUi.label(panel, "", 18)

	local function character(): (Model?, BasePart?, Humanoid?)
		local c = player.Character
		if not c then
			return nil
		end
		return c,
			c:FindFirstChild("HumanoidRootPart") :: BasePart?,
			c:FindFirstChildOfClass("Humanoid")
	end

	-- fly rig (made on demand, removed when flying stops)
	local att: Attachment?, lv: LinearVelocity?, ao: AlignOrientation?
	local function stopFly()
		flying = false
		for _, o in { lv, ao, att } :: { Instance? } do
			if o then
				o:Destroy()
			end
		end
		att, lv, ao = nil, nil, nil
		local _, _, hum = character()
		if hum then
			hum.PlatformStand = false
		end
	end
	local function startFly()
		local _, root, hum = character()
		if not (root and hum) then
			return
		end
		flying = true
		hum.PlatformStand = true
		local a = Instance.new("Attachment")
		a.Parent = root
		local v = Instance.new("LinearVelocity")
		v.Attachment0 = a
		v.RelativeTo = Enum.ActuatorRelativeTo.World
		v.MaxForce = math.huge
		v.VectorVelocity = Vector3.zero
		v.Parent = root
		local o = Instance.new("AlignOrientation")
		o.Mode = Enum.OrientationAlignmentMode.OneAttachment
		o.Attachment0 = a
		o.RigidityEnabled = true
		o.Parent = root
		att, lv, ao = a, v, o
	end

	local function applySpeed()
		local _, _, hum = character()
		if hum then
			hum.WalkSpeed = speed
		end
	end

	local function teleport(x: number, y: number, z: number?)
		local c = character()
		if not c then
			return
		end
		local gy = z or Geo.roadHeight(x, y)
		local X, Z = Geo.world(x, y)
		c:PivotTo(CFrame.new(X, gy + 6, Z))
	end

	DebugUi.label(panel, "F2 toggles. Fly: WASD, Space up, Ctrl down. Ctrl+click: teleport.", 36)
	local flyButton: TextButton
	flyButton = DebugUi.button(panel, "Fly: off", function()
		if flying then
			stopFly()
		else
			startFly()
		end
		flyButton.Text = if flying then "Fly: ON" else "Fly: off"
	end)
	local noclipButton: TextButton
	noclipButton = DebugUi.button(panel, "Noclip: off", function()
		noclip = not noclip
		noclipButton.Text = if noclip then "Noclip: ON" else "Noclip: off"
	end)
	local speedButton: TextButton
	speedButton = DebugUi.button(panel, `Speed: {speed}`, function()
		local i = table.find(SPEEDS, speed) or 0
		speed = SPEEDS[i % #SPEEDS + 1]
		speedButton.Text = `Speed: {speed}`
		applySpeed()
	end)
	DebugUi.button(panel, "Up 600 (look down), fly on", function()
		local _, root = character()
		if root then
			if not flying then
				startFly()
				flyButton.Text = "Fly: ON"
			end
			root.CFrame = CFrame.new(root.Position + Vector3.new(0, 600, 0))
		end
	end)
	DebugUi.button(panel, "Back to HQ 1", function()
		local p = Data.Nodes.HQ1
		teleport(p[1], p[2])
	end)

	DebugUi.label(panel, "Teleport to:")
	local list = DebugUi.scroll(panel, 330)
	local places = table.clone(Data.Places)
	table.sort(places, function(a: any, b: any)
		local ia, ib = table.find(KIND_ORDER, a.kind) or 99, table.find(KIND_ORDER, b.kind) or 99
		if ia ~= ib then
			return ia < ib
		end
		return a.name < b.name
	end)
	for _, pl in places do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -12, 0, 20)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Text = ` [{pl.kind}] {pl.name}`
		b.Parent = list
		b.Activated:Connect(function()
			teleport(pl.pos[1], pl.pos[2] + 25)
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.F2 then
			gui.Enabled = not gui.Enabled
			return
		end
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		then
			local m = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(m.X, m.Y)
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { player.Character :: Instance }
			params.FilterType = Enum.RaycastFilterType.Exclude
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 20000, params)
			if hit then
				local mx, my = Geo.map(hit.Position.X, hit.Position.Z)
				teleport(mx, my, hit.Position.Y)
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		stopFly()
		flyButton.Text = "Fly: off"
		task.wait()
		applySpeed()
	end)
	applySpeed()

	RunService.Stepped:Connect(function()
		if noclip and player.Character then
			for _, d in player.Character:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local _, root = character()
		if flying and lv and ao and root then
			local cf = camera.CFrame
			local dir = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then
				dir += cf.LookVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then
				dir -= cf.LookVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then
				dir += cf.RightVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then
				dir -= cf.RightVector
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				dir += Vector3.yAxis
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				dir -= Vector3.yAxis
			end
			lv.VectorVelocity = if dir.Magnitude > 0 then dir.Unit * speed else Vector3.zero
			ao.CFrame =
				CFrame.lookAt(Vector3.zero, Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z))
		end
		if gui.Enabled and root then
			local p = root.Position
			local mx, my = Geo.map(p.X, p.Z)
			readout.Text = string.format(
				"Map x %d, y %d (Y %d)\n%s · %s · %s",
				mx,
				my,
				p.Y,
				Geo.cell(mx, my),
				Geo.zone(mx, my),
				if Geo.isLand(mx, my) then "land" else "water"
			)
			state.Text = `speed {speed}{if flying then " · flying" else ""}{if noclip
				then " · noclip"
				else ""}`
		end
	end)
end

return AdminPanel
