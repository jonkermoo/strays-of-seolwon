--!strict
-- M2 first-person view (style-test only; user 2026-11-25: "use a different first person screen for the client when
-- you're in first person so we have more creative liberty"). In first person the body's own arms and rifle stay
-- hidden (Roblox hides the character) and this draws a client-only copy instead: the carried rifle and two slim
-- forearms (0.5 stud, ANIMATION-GUIDE §5.3) under the camera, placed in camera space.
-- Numbers come from the approved gun-positioning draft (jarvis notes/ideas/korea-pve/gun-positioning/, data at the top
-- of gun-positioning.html): holds, hand points, arm roots, the mount between holds (muzzle leads, arc, long gentle stop,
-- no overshoot), breathing sway (aim x0.3), turn lag and recoil.
local ViewModel = {}
ViewModel.__index = ViewModel

local M = 1 / 0.28 -- metres to studs
local D = math.pi / 180

-- holds for the draft's gun root (the test rifle's first origin), camera space, metres and degrees (pitch up, yaw left,
-- roll left), Euler YXZ like the draft. "aim" is computed from the rifle's Aim point instead.
local HOLDS: { [string]: { pos: Vector3, rot: Vector3 } } = {
	hip = { pos = Vector3.new(0.15, -0.165, -0.30), rot = Vector3.new(1, 2.5, -3) },
	ready = { pos = Vector3.new(0.16, -0.215, -0.27), rot = Vector3.new(-14, 6, -8) },
	safe = { pos = Vector3.new(0.14, -0.215, -0.26), rot = Vector3.new(-24, 38, -25) },
	sprint = { pos = Vector3.new(0.10, -0.29, -0.27), rot = Vector3.new(30, 55, -45) },
}
-- the draft's root in the rifles' current gun space (grip origin moved 19 mm back, 20 mm down on 2026-11-25)
local DRAFT_ROOT = Vector3.new(0, 0.020, -0.019) * M
-- hold-to-hold times (s), the draft's table
local TRANS: { [string]: number } = {
	["ready>aim"] = 0.36,
	["hip>aim"] = 0.26,
	["safe>aim"] = 0.55,
	["sprint>aim"] = 0.50,
	["aim>hip"] = 0.26,
	["aim>ready"] = 0.34,
	["ready>hip"] = 0.24,
	["hip>ready"] = 0.26,
	["safe>hip"] = 0.48,
	["safe>ready"] = 0.42,
	["ready>safe"] = 0.70,
	["hip>safe"] = 0.72,
	["aim>safe"] = 0.75,
	["ready>sprint"] = 0.40,
	["hip>sprint"] = 0.40,
	["aim>sprint"] = 0.42,
	["safe>sprint"] = 0.45,
	["sprint>ready"] = 0.36,
	["sprint>hip"] = 0.40,
	["sprint>safe"] = 0.55,
}
local DEFAULT_T = 0.35
-- per rifle: points in its gun space (studs). M5 moves these into the weapon config.
local RIFLES: { [string]: { aim: Vector3, right: Vector3, left: Vector3 } } = {
	TestRifle = { -- jarvis rifle_import/rig/test_rifle.gun.json (measured on the model)
		aim = Vector3.new(0, 0.4495, 0.2573),
		right = Vector3.new(0, -0.2036, 0.0832),
		left = Vector3.new(0, 0.0875, -1.2979),
	},
	BlockoutRifle = { -- Blockout.luau: sight line 0.36 up, grip block, handguard underside 3/4 forward
		aim = Vector3.new(0, 0.36, 0.5),
		right = Vector3.new(0, -0.15, 0.06),
		left = Vector3.new(0, 0.0, -1.47),
	},
}
-- first-person forearms: roots below the screen (camera space, metres), 0.5 x 2 studs, 75% of the angle to the gun kept
local FROM_R = Vector3.new(0.21, -0.532, 0.126) * M
local FROM_L = Vector3.new(-0.34, -0.50, -0.02) * M
local ARM_W, ARM_L, FOLLOW = 0.5, 2, 0.75
-- going prone or getting up the left hand leaves the gun and goes down to the ground (user 2026-11-25: "when we prone or
-- get up, we put an arm down"), out of view at the lower left (camera space, metres); when is the body clip's (armDown)
local DOWN_L = Vector3.new(-0.30, -0.80, -0.35) * M
-- breathing (gun only, never the camera): pitch 0.6 deg, yaw 0.25 deg, 4 s; aiming keeps x0.3
local BREATH = { pitch = 0.6, yaw = 0.25, period = 4, aim = 0.3 }
-- turn lag (§4.1): the gun trails the view up to 3 deg and settles in ~0.15 s
local LAG = { max = 3, rate = 20 }

type Pose = { pos: Vector3, rot: Vector3 }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
-- cubic-bezier(0.42, 0, 0.18, 1): zero speed at both ends, a long gentle stop
local function settle(x: number): number
	x = clamp01(x)
	local X1, X2 = 0.42, 0.18
	local t = x
	for _ = 1, 8 do
		local bx = 3 * (1 - t) ^ 2 * t * X1 + 3 * (1 - t) * t * t * X2 + t ^ 3 - x
		local d = 3 * (1 - t) ^ 2 * X1 + 6 * (1 - t) * t * (X2 - X1) + 3 * t * t * (1 - X2)
		if math.abs(d) < 1e-6 then
			break
		end
		t = clamp01(t - bx / d)
	end
	return 3 * (1 - t) * t * t + t ^ 3
end
local function turnAt(s: number): number
	return settle(s / 0.8)
end
local function moveAt(s: number): number
	return settle((s - 0.12) / 0.88)
end
-- quadratic arc: rise (or drop) first, then across
local function arcPos(a: Vector3, b: Vector3, u: number): Vector3
	local c = Vector3.new(a.X + (b.X - a.X) * 0.2, b.Y + (a.Y - b.Y) * 0.2, (a.Z + b.Z) / 2)
	return a * (1 - u) ^ 2 + c * (2 * (1 - u) * u) + b * (u * u)
end
local function cf(p: Pose): CFrame
	return CFrame.new(p.pos) * CFrame.fromEulerAnglesYXZ(p.rot.X * D, p.rot.Y * D, p.rot.Z * D)
end

local function prep(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

export type ViewModel = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		parts: { BasePart },
		offsets: { CFrame },
		arms: { Right: BasePart, Left: BasePart },
		points: { aim: Vector3, right: Vector3, left: Vector3 },
		holds: { [string]: Pose },
		armDir: { Right: Vector3, Left: Vector3 },
		target: string,
		from: Pose?,
		fromName: string,
		t: number,
		dur: number,
		clock: number,
		lagX: number,
		lagY: number,
		lastLook: Vector3?,
		shown: boolean,
	},
	ViewModel
))

-- builds the first-person copy for `char` (its carried rifle "TestRifle" or "BlockoutRifle", its shirt and skin)
function ViewModel.new(char: Model): ViewModel?
	local source = char:FindFirstChild("TestRifle") or char:FindFirstChild("BlockoutRifle")
	if not (source and source:IsA("Model") and source.PrimaryPart) then
		return nil
	end
	local points = RIFLES[source.Name] or RIFLES.BlockoutRifle
	local model = Instance.new("Model")
	model.Name = "M2ViewModel"
	-- the rifle: every part keeps its offset from the root and is moved with it (no joints, no physics)
	local rifle = (source :: Model):Clone()
	local root = rifle.PrimaryPart :: BasePart
	local parts, offsets = {}, {}
	for _, d in rifle:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in rifle:GetDescendants() do
		if d:IsA("BasePart") then
			prep(d)
			d.LocalTransparencyModifier = 0
			table.insert(parts, d)
			table.insert(offsets, root.CFrame:ToObjectSpace(d.CFrame))
		end
	end
	rifle.Parent = model
	-- the arms: a Humanoid model so the rifleman's shirt maps onto them (sleeves on the slim forearm)
	local hum = Instance.new("Humanoid")
	hum.RequiresNeck = false
	hum.EvaluateStateMachine = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = model
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(0.2, 0.2, 0.2)
	torso.Transparency = 1
	prep(torso)
	torso.Parent = model
	local arms = {}
	for _, side in { "Right", "Left" } do
		local src = char:FindFirstChild(side .. " Arm")
		local a = Instance.new("Part")
		a.Name = side .. " Arm"
		a.Size = Vector3.new(ARM_W, ARM_L, ARM_W)
		a.Color = if src and src:IsA("BasePart") then src.Color else Color3.fromRGB(180, 140, 110)
		a.Material = Enum.Material.SmoothPlastic
		prep(a)
		a.Parent = model
		arms[side] = a
	end
	for _, c in char:GetChildren() do
		if c:IsA("Shirt") or c:IsA("BodyColors") then
			c:Clone().Parent = model
		end
	end
	model.PrimaryPart = torso
	local self = setmetatable({
		model = model,
		root = root,
		parts = parts,
		offsets = offsets,
		arms = arms :: any,
		points = points,
		holds = {},
		armDir = { Right = Vector3.zero, Left = Vector3.zero },
		target = "ready",
		from = nil,
		fromName = "ready",
		t = 0,
		dur = 1,
		clock = 0,
		lagX = 0,
		lagY = 0,
		lastLook = nil,
		shown = false,
	}, ViewModel)
	-- holds for this rifle's root: the draft holds moved to its origin, aim from its Aim point
	for name, h in HOLDS do
		local m = cf({ pos = h.pos * M, rot = h.rot }) * CFrame.new(DRAFT_ROOT)
		local rx, ry, rz = m:ToEulerAnglesYXZ()
		self.holds[name] = { pos = m.Position, rot = Vector3.new(rx / D, ry / D, rz / D) }
	end
	self.holds.aim = { pos = -points.aim, rot = Vector3.zero }
	-- each forearm's angle to the gun, taken in low ready
	local ready = cf(self.holds.ready)
	self.armDir.Right = ready:VectorToObjectSpace((FROM_R - ready * points.right).Unit)
	self.armDir.Left = ready:VectorToObjectSpace((FROM_L - ready * points.left).Unit)
	model.Parent = nil
	return self
end

-- the pose `u` seconds into the move from `a` to `b` (muzzle leads, arc, gentle stop)
local function between(a: Pose, b: Pose, s: number): Pose
	local tr, mv = turnAt(s), moveAt(s)
	return { pos = arcPos(a.pos, b.pos, mv), rot = a.rot:Lerp(b.rot, tr) }
end

function ViewModel.current(self: ViewModel): Pose
	local goal = self.holds[self.target]
	if not self.from then
		return goal
	end
	local s = self.t / self.dur
	if s >= 1 then
		self.from = nil
		return goal
	end
	return between(self.from :: Pose, goal, s)
end

-- every frame. state: fp (first person on), target ("safe" | "ready" | "hip" | "aim" | "sprint"), rec (recoil spring),
-- aim (0..1), speed (studs/s), phase (gait 0..1), armDown (0..1: the left hand off the gun and down, from the body)
function ViewModel.update(
	self: ViewModel,
	dt: number,
	camera: Camera,
	state: {
		fp: boolean,
		target: string,
		rec: number,
		aim: number,
		speed: number,
		phase: number,
		armDown: number?,
	}
)
	if not state.fp then
		if self.shown then
			self.model.Parent = nil
			self.shown = false
		end
		self.lastLook = nil
		return
	end
	if not self.shown then
		self.model.Parent = camera
		self.shown = true
		self.target, self.from = state.target, nil
	end
	self.clock += dt
	-- a new hold: start the move from wherever the gun is now
	if state.target ~= self.target and self.holds[state.target] then
		local now = self:current()
		self.dur = TRANS[self.target .. ">" .. state.target] or DEFAULT_T
		self.from, self.fromName, self.target, self.t = now, self.target, state.target, 0
	end
	self.t += dt
	local pose = self:current()
	-- breathing, aim x0.3
	local w = 2 * math.pi / BREATH.period
	local k = 1 - (1 - BREATH.aim) * state.aim
	local rot = pose.rot
		+ Vector3.new(
			BREATH.pitch * math.sin(w * self.clock) * k,
			BREATH.yaw * math.sin(2 * w * self.clock) * k,
			0
		)
	-- walk / sprint bounce: small on the walk, bigger on the sprint, x0.15 aiming (§4.1)
	local run = math.clamp(state.speed / 20, 0, 1)
	local bob = (0.02 + 0.05 * run * run)
		* math.clamp(state.speed / 8, 0, 1)
		* (1 - 0.85 * state.aim)
	local ph = 2 * math.pi * state.phase
	local pos = pose.pos + Vector3.new(math.sin(ph) * bob * 0.6, -math.abs(math.cos(ph)) * bob, 0)
	-- turn lag: the gun trails a turn of the view, then settles
	local look = camera.CFrame.LookVector
	if self.lastLook then
		local localLook = camera.CFrame:VectorToObjectSpace(self.lastLook :: Vector3)
		self.lagY = math.clamp(
			self.lagY + math.deg(math.atan2(-localLook.X, -localLook.Z)),
			-LAG.max,
			LAG.max
		)
		self.lagX = math.clamp(
			self.lagX + math.deg(math.asin(math.clamp(localLook.Y, -1, 1))),
			-LAG.max,
			LAG.max
		)
	end
	self.lastLook = look
	local decay = math.exp(-dt * LAG.rate)
	self.lagX *= decay
	self.lagY *= decay
	rot += Vector3.new(self.lagX, self.lagY, 0) * (1 - 0.7 * state.aim)
	local gun = camera.CFrame * cf({ pos = pos, rot = rot })
	-- recoil (the body's spring): back into the shoulder, muzzle up
	if math.abs(state.rec) > 1e-4 then
		gun *= CFrame.new(0, 0.02 * state.rec, 0.08 * state.rec) * CFrame.Angles(
			math.rad(3 * state.rec * (1 - 0.5 * state.aim)),
			0,
			0
		)
	end
	local cfs = table.create(#self.parts)
	for i, off in self.offsets do
		cfs[i] = gun * off
	end
	workspace:BulkMoveTo(self.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- arms: hands on the gun's hand points, each forearm keeping 75% of its angle to the gun
	local up = gun.UpVector
	local camCf = camera.CFrame
	local armCfs = {}
	local down = math.clamp(state.armDown or 0, 0, 1)
	down = down * down * (3 - 2 * down)
	for i, side in { "Right", "Left" } do
		local hand = gun * (if side == "Right" then self.points.right else self.points.left)
		local off = if side == "Left" then down else 0 -- the left hand on its way to the ground
		if off > 0 then
			hand = hand:Lerp(camCf * DOWN_L, off)
		end
		local root = camCf * (if side == "Right" then FROM_R else FROM_L)
		local toRoot = (root - hand).Unit
		local withGun = gun:VectorToWorldSpace(self.armDir[side])
		local follow = FOLLOW * (1 - off)
		local dir = (toRoot * (1 - follow) + withGun * follow).Unit -- hand -> elbow
		local x = dir:Cross(up)
		x = if x.Magnitude < 1e-4 then camCf.RightVector else x.Unit
		local z = x:Cross(dir).Unit -- nearest gun up
		local yAxis = dir -- an R6 arm's hand is its -Y end
		local xx = yAxis:Cross(z).Unit
		local centre = hand + dir * (ARM_L / 2)
		if side == "Left" then
			centre -= z * (ARM_W / 2 * (1 - off)) -- top face flat under the handguard
		end
		armCfs[i] = CFrame.fromMatrix(centre, xx, yAxis, z)
	end
	workspace:BulkMoveTo(
		{ self.arms.Right, self.arms.Left },
		armCfs,
		Enum.BulkMoveMode.FireCFrameChanged
	)
end

function ViewModel.destroy(self: ViewModel)
	self.model:Destroy()
end

return ViewModel
