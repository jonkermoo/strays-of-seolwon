--!strict
-- M2 block-out rifle: plain blocks at H2 size (3.4 studs, as the M1 scene's H2 model), for animation tests only.
-- Gun space as tools/animation/weapons.luau "blockout": origin at the right hand's grip, -Z to the muzzle, +Y up.
-- The root part is named "Gun" and sits on that origin, so a Motor6D Torso -> Gun with C0 = C1 = identity takes the
-- clips' "Gun" pose directly.
local Blockout = {}

local METAL = Color3.fromHex("2b2d2f") -- dark phosphate (STYLE-BIBLE gun tones)
local POLY = Color3.fromHex("1b1c1d") -- near-black polymer

-- { name, size, position, pitch (deg), colour }
local PIECES = {
	{ "Receiver", Vector3.new(0.2, 0.3, 1.25), Vector3.new(0, 0.12, -0.28), 0, METAL },
	{ "RearSight", Vector3.new(0.08, 0.12, 0.22), Vector3.new(0, 0.33, 0.22), 0, METAL },
	{ "Handguard", Vector3.new(0.22, 0.24, 0.75), Vector3.new(0, 0.12, -1.28), 0, POLY },
	{ "FrontSight", Vector3.new(0.05, 0.2, 0.06), Vector3.new(0, 0.32, -1.6), 0, METAL },
	{ "Barrel", Vector3.new(0.08, 0.08, 0.65), Vector3.new(0, 0.14, -1.975), 0, METAL },
	{ "Muzzle", Vector3.new(0.11, 0.11, 0.12), Vector3.new(0, 0.14, -2.24), 0, METAL },
	{ "Mag", Vector3.new(0.15, 0.55, 0.24), Vector3.new(0, -0.27, -0.52), 12, POLY },
	{ "Grip", Vector3.new(0.15, 0.4, 0.2), Vector3.new(0, -0.15, 0.06), -18, POLY },
	{ "Stock", Vector3.new(0.16, 0.32, 0.75), Vector3.new(0, 0.06, 0.72), 0, POLY },
	{ "Butt", Vector3.new(0.18, 0.42, 0.06), Vector3.new(0, 0.03, 1.08), 0, POLY },
}

local function prep(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- A model "BlockoutRifle" whose PrimaryPart "Gun" (invisible) is at `origin`.
function Blockout.build(origin: CFrame?): Model
	local at = origin or CFrame.new()
	local model = Instance.new("Model")
	model.Name = "BlockoutRifle"
	local root = Instance.new("Part")
	root.Name = "Gun"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.CFrame = at
	prep(root)
	root.Parent = model
	model.PrimaryPart = root
	for _, piece in PIECES do
		local p = Instance.new("Part")
		p.Name = piece[1]
		p.Size = piece[2]
		p.Color = piece[5]
		p.Material = if piece[5] == METAL then Enum.Material.Metal else Enum.Material.SmoothPlastic
		p.CFrame = at * CFrame.new(piece[3]) * CFrame.Angles(math.rad(piece[4]), 0, 0)
		prep(p)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	return model
end

return Blockout
