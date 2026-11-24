--!strict
-- M2 movement test (style-test branch only): the player spawns as the approved Strays rifleman (M1 kit) carrying the
-- rigged test rifle (ReplicatedStorage.TestRifle, assets/TestRifle.rbxm: 14 MeshParts, a Motor6D per moving part under
-- Gun). Set the Workspace attribute StyleRifle = "blockout" before Play to carry the block-out rifle instead.
-- The scene's rifleman is copied, its kit welded to the body, the rifle joined to the Torso by a
-- Motor6D "Gun" (the clips' Gun pose). A copy also goes to ReplicatedStorage.StyleSoldier for the client's clip
-- gallery. Torso, Head and limbs go into a collision group that collides with nothing (only the root collides), so
-- the prone and crawl poses don't push the body around (notes/traps/animation.md).
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Blockout = require(ReplicatedStorage.Shared.StyleTest.Blockout)

local StyleCharacter = {}

local GROUP = "StyleBody"
-- spawn spot, set from the scene by start() (in front of the rifleman, facing the scene)
local spawnAt: CFrame? = nil

local function weldTo(part: BasePart, body: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = part
	w.Parent = part
end

-- The carried rifle, its root part "Gun" at `at`. Both share the gun space of tools/animation/weapons.luau (origin
-- on the right hand's grip, -Z to the muzzle, +Y up), so the clips' Gun pose fits either.
local function heldRifle(at: CFrame): Model
	local real = ReplicatedStorage:FindFirstChild("TestRifle")
	if
		workspace:GetAttribute("StyleRifle") == "blockout"
		or not (real and real:IsA("Model") and real.PrimaryPart)
	then
		if workspace:GetAttribute("StyleRifle") ~= "blockout" then
			warn("[StyleCharacter] no ReplicatedStorage.TestRifle; carrying the block-out rifle")
		end
		return Blockout.build(at)
	end
	local rifle = (real :: Model):Clone()
	rifle:PivotTo(at)
	return rifle
end

local function soldier(source: Model): Model
	local m = source:Clone()
	m.Name = "StarterCharacter"
	local torso = m:FindFirstChild("Torso") :: BasePart
	local head = m:FindFirstChild("Head") :: BasePart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			local isBody = d.Parent == m
			if not isBody then
				-- kit: welded where it sits (helmet to the head, the rest to the torso)
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				local kit: Instance = d
				while kit.Parent and kit.Parent ~= m do
					kit = kit.Parent
				end
				weldTo(d, if kit.Name == "Helmet" or kit.Name == "MarkerLight" then head else torso)
			elseif d.Name ~= "HumanoidRootPart" then
				d.CollisionGroup = GROUP
			end
		end
	end
	-- the rifle: Motor6D "Gun" on the Torso, C0 = C1 = identity (the clips place it)
	local rifle = heldRifle(torso.CFrame)
	for _, p in rifle:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = GROUP
		end
	end
	rifle.Parent = m
	local motor = Instance.new("Motor6D")
	motor.Name = "Gun"
	motor.Part0 = torso
	motor.Part1 = rifle.PrimaryPart
	motor.Parent = torso
	-- the root is then the only thing that collides (R6 roots don't by default: with the body in GROUP the soldier
	-- walked through walls and sank through the pool floor)
	local rootPart = m:FindFirstChild("HumanoidRootPart") :: BasePart
	rootPart.CanCollide = true
	local hum = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.UseJumpPower = false
	hum.JumpHeight = 1.5 -- ANIMATION-GUIDE §3.6 (user 2026-11-23: a low hop, weaker than a vault)
	hum.WalkSpeed = 12
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	m.PrimaryPart = m:FindFirstChild("HumanoidRootPart") :: BasePart
	return m
end

-- A small test course in front of the spawn (all relative to it; ground found by ray): a 3-stud wall (hop), a
-- 4.5-stud ledge 4 deep (mantle onto), a wall with a 3x3 window at 15-metrics sill 3.5 (mantle through), a 12-stud
-- platform with a ramp (long-fall landing, > 10 studs), and a water pool (swim, tread).
local function course(at: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "M2Course"
	local params = RaycastParams.new()
	local function ground(p: Vector3): number
		local hit = workspace:Raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -100, 0), params)
		return if hit then hit.Position.Y else p.Y - 3
	end
	local function block(name: string, local_: CFrame, size: Vector3, color: string?)
		local cf = at * local_
		local g = ground(cf.Position)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = (cf - cf.Position) + Vector3.new(cf.X, g + size.Y / 2, cf.Z)
		p.Material = Enum.Material.Concrete
		p.Color = Color3.fromHex(color or "8a8d8f")
		p.Parent = folder
		return p, g
	end
	-- lane to the spawn's left (+X world when facing +Z is the soldier's left), walls across the lane
	local lane = -16
	block("Wall3 (hop)", CFrame.new(lane, 0, -12), Vector3.new(8, 3, 1))
	block("Ledge4.5 (mantle onto)", CFrame.new(lane, 0, -22), Vector3.new(8, 4.5, 4))
	-- window wall: 10 tall, 1 thick, a 3 x 3 opening with its sill at 3.5
	local wallZ = -34
	local _, g = block("WindowSill", CFrame.new(lane, 0, wallZ), Vector3.new(12, 3.5, 1))
	local top = block("WindowTop", CFrame.new(lane, 6.5, wallZ), Vector3.new(12, 3.5, 1))
	top.CFrame = top.CFrame + Vector3.new(0, 6.5 + 3.5 / 2 - (top.Position.Y - g), 0)
	local left = block("WindowLeft", CFrame.new(lane - 3.75, 0, wallZ), Vector3.new(4.5, 3, 1))
	left.CFrame = left.CFrame + Vector3.new(0, 3.5, 0)
	local right = block("WindowRight", CFrame.new(lane + 3.75, 0, wallZ), Vector3.new(4.5, 3, 1))
	right.CFrame = right.CFrame + Vector3.new(0, 3.5, 0)
	-- 12-stud platform with a ramp, on the spawn's right
	local plat = block("Platform12 (long fall)", CFrame.new(-28, 0, -26), Vector3.new(8, 12, 8))
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.Size = Vector3.new(6, 12, 22)
	ramp.Material = Enum.Material.Concrete
	ramp.Color = Color3.fromHex("8a8d8f")
	-- a wedge is full height at its +Z face: that face against the platform's near side
	local fwd = at.LookVector
	local pos = plat.Position - fwd * (4 + 11)
	ramp.CFrame = CFrame.lookAt(pos, pos - fwd)
	ramp.Parent = folder
	-- the pool: water carved into the ground, 16 x 6 deep x 16, ahead of the spawn
	local poolAt = (at * CFrame.new(0, 0, -50)).Position
	local pg = ground(poolAt)
	-- 12 deep. Carve with Air first: a Water fill doesn't replace solid ground (only the half-empty top voxel took it)
	-- The terrain is a thin shell (~12 studs), so the pool is 8 deep on a rock floor of its own (a soldier fell
	-- through a 12-deep one).
	local T = workspace.Terrain
	T:FillBlock(CFrame.new(poolAt.X, pg - 1, poolAt.Z), Vector3.new(20, 14, 20), Enum.Material.Air)
	T:FillBlock(CFrame.new(poolAt.X, pg - 10, poolAt.Z), Vector3.new(24, 4, 24), Enum.Material.Rock)
	T:FillBlock(CFrame.new(poolAt.X, pg - 4, poolAt.Z), Vector3.new(20, 8, 20), Enum.Material.Water)
	-- a ramp out on the spawn's side (its full-height +Z face toward the spawn)
	local exit = Instance.new("WedgePart")
	exit.Name = "PoolRamp"
	exit.Anchored = true
	exit.Size = Vector3.new(6, 8, 12)
	exit.Material = Enum.Material.Concrete
	exit.Color = Color3.fromHex("8a8d8f")
	local ep = (at * CFrame.new(0, 0, -46)).Position
	ep = Vector3.new(ep.X, pg - 4, ep.Z)
	exit.CFrame = CFrame.lookAt(ep, ep + at.LookVector)
	exit.Parent = folder
	folder.Parent = workspace
end

function StyleCharacter.start()
	local scene = workspace:FindFirstChild("StyleTest")
	local source = scene and scene:FindFirstChild("StraysRifleman")
	if not source then
		warn("[StyleCharacter] no StyleTest.StraysRifleman; movement test off")
		return
	end
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

	local m = soldier(source :: Model)
	local gallery = m:Clone()
	gallery.Name = "StyleSoldier"
	gallery.Parent = ReplicatedStorage
	m.Parent = StarterPlayer

	local root = (source :: Model):GetPivot()
	spawnAt = root * CFrame.new(0, 0.2, -8) -- in front of the rifleman (it faces +Z: -8 is behind it)
	local spot = Instance.new("Part")
	spot.Name = "M2Spawn"
	spot.Anchored = true
	spot.Transparency = 1
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CFrame = spawnAt :: CFrame
	spot.Parent = workspace
	course(spawnAt :: CFrame)

	local function place(char: Model)
		task.defer(function()
			if spawnAt then
				char:PivotTo(spawnAt :: CFrame)
			end
		end)
	end
	local function hook(p: Player)
		p.CharacterAdded:Connect(place)
		if p.Character then
			p:LoadCharacter() -- respawn as the soldier
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return StyleCharacter
