--!strict
-- M2 clip gallery (style-test branch only): a row of Strays riflemen (client-side copies of ReplicatedStorage.
-- StyleSoldier, the player's own kit and block-out rifle) each showing one movement clip, labelled, so every clip of
-- ANIMATION-GUIDE §3 can be watched side by side from any angle in both cameras. One-shots repeat with a pause.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MoveTest = require(script.Parent.MoveTest)

local Gallery = {}

type Rig = {
	model: Model,
	tracks: { [string]: AnimationTrack },
	body: string?,
	hold: string?,
	lean: number,
	rootJoint: Motor6D,
	rightHip: Motor6D,
	leftHip: Motor6D,
	root: BasePart,
	base: CFrame,
}

local function loops(rig: Rig, body: string?, hold: string?, fade: number?)
	local f = fade or 0.13
	if rig.body ~= body then
		if rig.body then
			rig.tracks[rig.body]:Stop(f)
		end
		if body then
			rig.tracks[body]:Play(f)
		end
		rig.body = body
	end
	if rig.hold ~= hold then
		if rig.hold then
			rig.tracks[rig.hold]:Stop(f)
		end
		if hold then
			rig.tracks[hold]:Play(f)
		end
		rig.hold = hold
	end
end

local function once(rig: Rig, name: string): number
	local t = rig.tracks[name]
	t:Play(0.05)
	return t.Length
end

-- each entry: label and a routine run forever on the rig
local ENTRIES: { { string } | any } = {
	{
		"Idle (breathing)",
		function(r: Rig)
			loops(r, "Idle", "HoldIdle")
		end,
	},
	{
		"Walk 12",
		function(r: Rig)
			loops(r, "Walk", "HoldWalk")
		end,
	},
	{
		"Sprint 20",
		function(r: Rig)
			loops(r, "Sprint", "HoldSprint")
		end,
	},
	{
		"Sprint start / stop",
		function(r: Rig)
			while true do
				loops(r, "Idle", "HoldIdle")
				task.wait(1)
				loops(r, "Sprint", "HoldSprint", 0.15)
				once(r, "SprintStart")
				task.wait(1.6)
				loops(r, "Idle", "HoldIdle", 0.1)
				once(r, "SprintStop")
				task.wait(0.4)
			end
		end,
	},
	{
		"Crouch (low ready)",
		function(r: Rig)
			loops(r, "CrouchIdle", "HoldCrouch")
		end,
	},
	{
		"Crouch walk 7",
		function(r: Rig)
			loops(r, "CrouchWalk", "HoldCrouchWalk")
		end,
	},
	{
		"Stand <-> crouch 0.20 s",
		function(r: Rig)
			while true do
				loops(r, "Idle", "HoldIdle", 0)
				task.wait(1.2)
				once(r, "StandToCrouch")
				loops(r, "CrouchIdle", "HoldCrouch", 0.1)
				task.wait(1.4)
				once(r, "CrouchToStand")
				loops(r, "Idle", "HoldIdle", 0.1)
				task.wait(0.2)
			end
		end,
	},
	{
		"Prone",
		function(r: Rig)
			loops(r, "ProneIdle", "HoldProne")
		end,
	},
	{
		"Crawl 3",
		function(r: Rig)
			loops(r, "Crawl", "HoldCrawl")
		end,
	},
	{
		"Stand <-> prone 0.45 / 0.55 s",
		function(r: Rig)
			while true do
				loops(r, "Idle", "HoldIdle", 0)
				task.wait(1.2)
				once(r, "StandToProne")
				loops(r, "ProneIdle", "HoldProne", 0.1)
				task.wait(1.6)
				once(r, "ProneToStand")
				loops(r, "Idle", "HoldIdle", 0.1)
				task.wait(0.4)
			end
		end,
	},
	{
		"Crouch <-> prone 0.35 s",
		function(r: Rig)
			while true do
				loops(r, "CrouchIdle", "HoldCrouch", 0)
				task.wait(1.2)
				once(r, "CrouchToProne")
				loops(r, "ProneIdle", "HoldProne", 0.1)
				task.wait(1.4)
				once(r, "ProneToCrouch")
				loops(r, "CrouchIdle", "HoldCrouch", 0.1)
				task.wait(0.2)
			end
		end,
	},
	{
		"Jump, fall, short land",
		function(r: Rig)
			while true do
				loops(r, "Idle", "HoldIdle", 0.1)
				task.wait(1.2)
				loops(r, "Jump", "HoldIdle", 0.05)
				task.wait(0.2)
				loops(r, "Fall", "HoldIdle", 0.1)
				task.wait(0.35)
				loops(r, "Idle", "HoldIdle", 0.05)
				once(r, "LandShort")
				task.wait(0.3)
			end
		end,
	},
	{
		"Long fall land 0.35 s",
		function(r: Rig)
			while true do
				loops(r, "Fall", "HoldIdle", 0.1)
				task.wait(0.8)
				loops(r, "Idle", "HoldIdle", 0.05)
				once(r, "LandLong")
				task.wait(1.4)
			end
		end,
	},
	{
		"Vault hop 0.45 s (in place)",
		function(r: Rig)
			while true do
				loops(r, "Walk", "HoldWalk", 0.1)
				task.wait(0.7)
				once(r, "VaultHop")
				task.wait(0.45)
				task.wait(0.7)
			end
		end,
	},
	{
		"Mantle 0.80 s (in place)",
		function(r: Rig)
			while true do
				loops(r, "Idle", "HoldIdle", 0.1)
				task.wait(1)
				once(r, "Mantle")
				task.wait(1.4)
			end
		end,
	},
	{
		"Lean Q / E (standing)",
		function(r: Rig)
			loops(r, "Idle", "HoldIdle")
			while true do
				for _, a in { -1, 0, 1, 0 } do
					local from, t0 = r.lean, os.clock()
					local len = if a == 0 then 0.12 else 0.15
					while os.clock() - t0 < len do
						r.lean = from + (a - from) * ((os.clock() - t0) / len)
						task.wait()
					end
					r.lean = a
					task.wait(1)
				end
			end
		end,
	},
	{
		"Lean (crouched)",
		function(r: Rig)
			loops(r, "CrouchIdle", "HoldCrouch")
			while true do
				for _, a in { -1, 0, 1, 0 } do
					local from, t0 = r.lean, os.clock()
					local len = if a == 0 then 0.12 else 0.15
					while os.clock() - t0 < len do
						r.lean = from + (a - from) * ((os.clock() - t0) / len)
						task.wait()
					end
					r.lean = a
					task.wait(1)
				end
			end
		end,
	},
	{
		"Limp, one leg 8",
		function(r: Rig)
			loops(r, "LimpOne", "HoldWalk")
		end,
	},
	{
		"Limp, both legs 5",
		function(r: Rig)
			loops(r, "LimpBoth", "HoldWalk")
		end,
	},
	{
		"Swim (breaststroke)",
		function(r: Rig)
			loops(r, "Swim", nil)
		end,
	},
	{
		"Tread water",
		function(r: Rig)
			loops(r, "Tread", nil)
		end,
	},
	{
		"Turn in place (shuffle)",
		function(r: Rig)
			loops(r, "Idle", "HoldIdle")
			local yaw = 0
			while true do
				task.wait(1.5)
				yaw += 60
				local from, t0 = r.root.CFrame, os.clock()
				once(r, "TurnShuffle")
				while os.clock() - t0 < 0.3 do
					r.root.CFrame = from:Lerp(
						r.base * CFrame.Angles(0, math.rad(yaw), 0),
						(os.clock() - t0) / 0.3
					)
					task.wait()
				end
				r.root.CFrame = r.base * CFrame.Angles(0, math.rad(yaw), 0)
			end
		end,
	},
}
Gallery.entries = ENTRIES

local function label(part: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(180, 28)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 60
	bb.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 0.5
	t.BackgroundColor3 = Color3.new(0, 0, 0)
	t.TextColor3 = Color3.fromRGB(210, 214, 210)
	t.Font = Enum.Font.Code
	t.TextSize = 13
	t.Text = text
	t.Parent = bb
end

function Gallery.start()
	local ids = MoveTest.register()
	local template = ReplicatedStorage:WaitForChild("StyleSoldier", 30) :: Model?
	local spawn = workspace:WaitForChild("M2Spawn", 30) :: BasePart?
	if not template or not spawn then
		warn("[Gallery] no StyleSoldier / M2Spawn")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "M2Gallery"
	folder.Parent = workspace
	local rigs: { Rig } = {}
	-- two rows facing the spawn, 6 studs apart, starting 10 studs to the spawn's side
	local origin = (spawn :: BasePart).CFrame
		* CFrame.new(-10, 0, -14)
		* CFrame.Angles(0, math.pi, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, Players.LocalPlayer.Character :: any }
	for i, entry in ENTRIES do
		local row, col = (i - 1) // 11, (i - 1) % 11
		local at = origin * CFrame.new(-col * 6, 0, row * 9)
		local hit =
			workspace:Raycast(at.Position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
		local ground = if hit then hit.Position.Y else at.Position.Y - 3
		local base = (at - at.Position) + Vector3.new(at.Position.X, ground + 3, at.Position.Z)
		local m = (template :: Model):Clone()
		m.Name = "M2_" .. i
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
		root.Anchored = true
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false -- walk through the gallery
				d.CanQuery = false
				d.CollisionGroup = "StyleBody" -- the server's group that collides with nothing (Humanoids force Torso/Head on)
			end
		end
		m:PivotTo(base)
		local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		m.Parent = folder
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		local tracks = {}
		for name, id in ids do
			local a = Instance.new("Animation")
			a.AnimationId = id
			tracks[name] = (animator :: Animator):LoadAnimation(a)
		end
		local torso = m:FindFirstChild("Torso") :: BasePart
		local rig: Rig = {
			model = m,
			tracks = tracks,
			body = nil,
			hold = nil,
			lean = 0,
			rootJoint = root:FindFirstChild("RootJoint") :: Motor6D,
			rightHip = torso:FindFirstChild("Right Hip") :: Motor6D,
			leftHip = torso:FindFirstChild("Left Hip") :: Motor6D,
			root = root,
			base = base,
		}
		table.insert(rigs, rig)
		label(m:FindFirstChild("Head") :: BasePart, entry[1])
		task.spawn(entry[2], rig)
	end
	RunService.PreSimulation:Connect(function()
		for _, r in rigs do
			MoveTest.applyLean(r, r.lean)
		end
	end)
end

return Gallery
