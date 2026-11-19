--!strict
-- Builds the Seolwon greybox from src/shared/Map/Data.luau into assets/Greybox.rbxm.
-- Plain anchored SmoothPlastic parts only, coloured by purpose (no art, textures or props).
-- Run from the repo root: lune run tools/greybox/build
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Data = require("../../src/shared/Map/Data")
local Geo = require("../../src/shared/Map/Geo")(Data)
local Metrics = require("../../src/shared/Map/Metrics")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

type Pt = { number }

local TOP = Metrics.LandTop
local MAXPART = 2048

local C = {
	autumn = Color3.fromRGB(178, 150, 102),
	frost = Color3.fromRGB(196, 210, 222),
	winter = Color3.fromRGB(236, 240, 245),
	rock = Color3.fromRGB(140, 142, 146),
	water = Color3.fromRGB(70, 120, 170),
	lakebed = Color3.fromRGB(96, 104, 112),
	road = Color3.fromRGB(70, 70, 74),
	track = Color3.fromRGB(112, 106, 98),
	rail = Color3.fromRGB(92, 82, 76),
	building = Color3.fromRGB(176, 176, 176),
	enemy = Color3.fromRGB(190, 62, 56),
	player = Color3.fromRGB(56, 106, 200),
	pickup = Color3.fromRGB(232, 190, 40),
	gated = Color3.fromRGB(132, 82, 182),
	orange = Color3.fromRGB(232, 132, 40),
}

local partCount = 0

local function part(parent: any, name: string, size: any, cf: any, color: any, class: string?): any
	local p = Instance.new(class or "Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	partCount += 1
	return p
end

local function folder(parent: any, name: string): any
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function groundY(x: number, y: number): number
	return TOP + Geo.height(x, y)
end

local root = Instance.new("Model")
root.Name = "Greybox"

-------------------------------------------------------------------- sea
local sea = folder(root, "Sea")
do
	local W, H = Data.Frame.width + 2048, Data.Frame.height + 2048
	local x0, y0 = -1024, -1024
	local x = x0
	while x < x0 + W do
		local y = y0
		while y < y0 + H do
			local p = part(
				sea,
				"Water",
				Vector3.new(MAXPART, 1, MAXPART),
				CFrame.new(x + MAXPART / 2, Metrics.SeaLevel - 0.5, y + MAXPART / 2),
				C.water
			)
			p.Transparency = 0.35
			p.CanCollide = false
			p.CastShadow = false
			y += MAXPART
		end
		x += MAXPART
	end
end

-------------------------------------------------------------------- land (scanline slabs by zone)
local land = folder(root, "Land")
local ROW = 32
do
	local y = ROW / 2
	while y < Data.Frame.height do
		local xs = Geo.crossings(y)
		for i = 1, #xs - 1, 2 do
			local a, b = xs[i], xs[i + 1]
			-- split the run where the season zone changes, and at the max part size
			local runStart = a
			local zone = Geo.zone(a + 1, y)
			local x = a
			while x < b do
				local nx = math.min(x + ROW, b)
				local z = Geo.zone((x + nx) / 2, y)
				if z ~= zone or nx - runStart > MAXPART then
					part(
						land,
						zone,
						Vector3.new(x - runStart, TOP, ROW),
						CFrame.new((runStart + x) / 2, TOP / 2, y),
						C[zone]
					)
					runStart, zone = x, z
				end
				x = nx
			end
			if b - runStart > 0.5 then
				part(
					land,
					zone,
					Vector3.new(b - runStart, TOP, ROW),
					CFrame.new((runStart + b) / 2, TOP / 2, y),
					C[zone]
				)
			end
		end
		y += ROW
	end
	-- lake bed (the lake is a hole in the land; players can climb out)
	local lake = Data.Land.Lake
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in lake do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
	end
	local bed = part(
		land,
		"LakeBed",
		Vector3.new(maxX - minX + 64, 1, maxY - minY + 64),
		CFrame.new((minX + maxX) / 2, -0.5, (minY + maxY) / 2),
		C.lakebed
	)
	bed.Name = "LakeBed"
end

-------------------------------------------------------------------- hills (wedge triangles)
local hills = folder(root, "Hills")
local GRID = Data.HillGrid

local function triangle(parent: any, a: any, b: any, c: any, color: any)
	-- Two wedges make one triangle; surface on the triangle plane, 2 studs thick below it.
	local thick = 2
	local n = (b - a):Cross(c - a).Unit
	if n.Y < 0 then
		n = -n
	end
	a, b, c = a - n * (thick / 2), b - n * (thick / 2), c - n * (thick / 2)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then
		return
	end
	local w1 = math.abs(ab:Dot(back))
	local w2 = math.abs(ac:Dot(back))
	if w1 > 0.05 then
		part(
			parent,
			"Slope",
			Vector3.new(thick, height, w1),
			CFrame.fromMatrix((a + b) / 2, right, up, back),
			color,
			"WedgePart"
		)
	end
	if w2 > 0.05 then
		part(
			parent,
			"Slope",
			Vector3.new(thick, height, w2),
			CFrame.fromMatrix((a + c) / 2, -right, up, -back),
			color,
			"WedgePart"
		)
	end
end

do
	local hcache: { [number]: number } = {}
	local function hAt(i: number, j: number): number
		local k = i * 100000 + j
		local v = hcache[k]
		if v == nil then
			v = Geo.height(i * GRID, j * GRID)
			hcache[k] = v
		end
		return v
	end
	local done: { [number]: boolean } = {}
	for _, m in Data.Mountains do
		local mf = folder(hills, m.name)
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, p in m.poly do
			minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
			minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
		end
		for i = math.floor(minX / GRID), math.ceil(maxX / GRID) do
			for j = math.floor(minY / GRID), math.ceil(maxY / GRID) do
				local key = i * 100000 + j
				local h00, h10, h01, h11 =
					hAt(i, j), hAt(i + 1, j), hAt(i, j + 1), hAt(i + 1, j + 1)
				local cx, cy = (i + 0.5) * GRID, (j + 0.5) * GRID
				if not done[key] and (h00 + h10 + h01 + h11) > 0.1 and Geo.isLand(cx, cy) then
					done[key] = true
					local function v(ii: number, jj: number, h: number): any
						return Vector3.new(ii * GRID, TOP + h, jj * GRID)
					end
					local avg = (h00 + h10 + h01 + h11) / 4
					local col = if avg > 45 then C.rock else C[Geo.zone(cx, cy)]
					triangle(mf, v(i, j, h00), v(i + 1, j, h10), v(i + 1, j + 1, h11), col)
					triangle(mf, v(i, j, h00), v(i + 1, j + 1, h11), v(i, j + 1, h01), col)
				end
			end
		end
	end
end

-------------------------------------------------------------------- water strips (river)
local water = folder(root, "Inland water")
local function strip(
	parent: any,
	name: string,
	pts: { Pt },
	width: number,
	color: any,
	lift: number,
	step: number?
)
	local out = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		local n = math.max(1, math.ceil(len / (step or 48)))
		for k = 0, n - 1 do
			local x1, y1 = a[1] + dx * k / n, a[2] + dy * k / n
			local x2, y2 = a[1] + dx * (k + 1) / n, a[2] + dy * (k + 1) / n
			local p1 = Vector3.new(x1, TOP + Geo.roadHeight(x1, y1) + lift, y1)
			local p2 = Vector3.new(x2, TOP + Geo.roadHeight(x2, y2) + lift, y2)
			-- Overlap pieces at inner joints only: an overhang at a junction node would stick up
			-- out of the other roads on a slope (a lip the walk test snagged on at s1).
			local dir = (p2 - p1).Unit
			local ext = width * 0.15
			local first = i == 1 and k == 0
			local last = i == #pts - 1 and k == n - 1
			local q1 = if first then p1 else p1 - dir * ext
			local q2 = if last then p2 else p2 + dir * ext
			local p = part(
				parent,
				name,
				Vector3.new(width, 1, (q2 - q1).Magnitude),
				CFrame.lookAt((q1 + q2) / 2, q2) * CFrame.new(0, -0.5, 0),
				color
			)
			table.insert(out, p)
		end
	end
	return out
end
for _, p in strip(water, "River", Data.River, Data.RiverWidth, C.water, 0.1, 96) do
	p.Transparency = 0.35
	p.CanCollide = false
end
do
	local lake = Data.Land.Lake
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, p in lake do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
	end
	-- water surface rows inside the lake, skipping the G2 isle
	local y = math.floor(minY / ROW) * ROW + ROW / 2
	while y < maxY do
		local x = minX
		local runStart: number? = nil
		while x <= maxX + 8 do
			local wet = Geo.inside(lake, x, y) and not Geo.inside(Data.Land.G2Isle, x, y)
			if wet and not runStart then
				runStart = x
			elseif not wet and runStart then
				local p = part(
					water,
					"Lake",
					Vector3.new(x - runStart, 1, ROW),
					CFrame.new((runStart + x) / 2, TOP - 1.5, y),
					C.water
				)
				p.Transparency = 0.35
				p.CanCollide = false
				runStart = nil
			end
			x += 8
		end
		y += ROW
	end
end

-------------------------------------------------------------------- roads, rail, tunnel, bridges
local roads = folder(root, "Roads")
for _, e in Data.Edges do
	local pts = Geo.edgePoints(e)
	local name = `{e.a}-{e.b}`
	if e.kind == "tunnel" then
		local tf = folder(roads, "Tunnel " .. name)
		local a, b = pts[1], pts[#pts]
		local W, Hh = Metrics.Road.tunnelWidth, Metrics.Road.tunnelHeight
		local p1 = Vector3.new(a[1], TOP, a[2])
		local p2 = Vector3.new(b[1], TOP, b[2])
		local len = (p2 - p1).Magnitude
		local cf = CFrame.lookAt((p1 + p2) / 2, p2)
		part(tf, "Floor", Vector3.new(W, 2, len), cf * CFrame.new(0, -1, 0), C.road)
		part(tf, "Roof", Vector3.new(W + 4, 2, len), cf * CFrame.new(0, Hh + 1, 0), C.road)
		part(tf, "WallL", Vector3.new(2, Hh, len), cf * CFrame.new(-W / 2 - 1, Hh / 2, 0), C.road)
		part(tf, "WallR", Vector3.new(2, Hh, len), cf * CFrame.new(W / 2 + 1, Hh / 2, 0), C.road)
	else
		local f = folder(roads, name)
		f:SetAttribute("Kind", e.kind)
		strip(
			f,
			e.kind,
			pts,
			Data.RoadWidth[e.kind],
			if e.kind == "track" then C.track else C.road,
			0.3
		)
	end
end
strip(folder(roads, "Rail"), "rail", Data.Rail, 8, C.rail, 0.2)

-- Citadel bridge: down at the start, so two stubs with a gap over the strait.
do
	local cb = Data.Nodes.CB
	local x, y = cb[1], cb[2]
	local shore = y
	while Geo.isLand(x, shore) do
		shore -= 8
	end
	local far = shore
	while not Geo.isLand(x, far) and far > 0 do
		far -= 8
	end
	local gap = shore - far
	local bf = folder(roads, "Citadel bridge (down)")
	local stub = gap * 0.35
	part(
		bf,
		"Stub main",
		Vector3.new(20, 2, stub + 40),
		CFrame.new(x, TOP - 1, shore - stub / 2 + 20),
		C.road
	)
	part(
		bf,
		"Stub citadel",
		Vector3.new(20, 2, stub + 40),
		CFrame.new(x, TOP - 1, far + stub / 2 - 20),
		C.road
	)
end

-------------------------------------------------------------------- places
local KIND = {
	aoi = { color = C.building, shape = "disc", h = 0.6, pole = 140 },
	enemy = { color = C.enemy, shape = "disc", h = 0.8, r = 60, pole = 100 },
	gated = { color = C.gated, shape = "disc", h = 0.8, r = 120, pole = 100 },
	hq = { color = C.player, size = { 160, 1, 160 }, pole = 120 },
	dock = { color = C.player, size = { 30, 1, 60 }, pole = 60 },
	fb = { color = C.player, size = { 120, 1, 120 }, pole = 80 },
	radio = { color = C.orange, size = { 4, 40, 4 }, pole = 0 },
	power = { color = C.orange, size = { 40, 6, 40 }, pole = 60 },
	cut = { color = C.orange, size = { 30, 2, 30 }, pole = 40 },
	misc = { color = C.orange, size = { 20, 8, 20 }, pole = 40 },
	veh = { color = C.pickup, size = { 5, 4, 8 }, pole = 20 },
	truck = { color = C.pickup, size = { 8, 8, 20 }, pole = 25 },
	hum = { color = C.pickup, size = { 7, 6, 14 }, pole = 25 },
	gun = { color = C.pickup, size = { 7, 7, 14 }, pole = 25 },
	apc = { color = C.pickup, size = { 9, 8, 20 }, pole = 25 },
	apcg = { color = C.pickup, size = { 9, 9, 20 }, pole = 25 },
	tank = { color = C.pickup, size = { 12, 8, 24 }, pole = 25 },
	key = { color = C.pickup, size = { 1.5, 1.5, 1.5 }, raise = 3, pole = 15 },
	bp = { color = C.pickup, size = { 3, 0.4, 2 }, raise = 3, pole = 15 },
	manual = { color = C.pickup, size = { 2, 0.6, 3 }, raise = 3, pole = 15 },
	rare = { color = C.pickup, size = { 4, 3, 4 }, pole = 15 },
	kp = { color = C.gated, size = { 4, 7.5, 1 }, pole = 15 },
}

local function label(adornee: any, text: string, color: any, dist: number, height: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(220, 36)
	bb.StudsOffset = Vector3.new(0, height, 0)
	bb.MaxDistance = dist
	bb.LightInfluence = 0
	bb.Parent = adornee
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.FontFace = roblox.Font.fromEnum(Enum.Font.GothamBold)
	t.Parent = bb
end

local places = folder(root, "Places")
for _, pl in Data.Places do
	local k = KIND[pl.kind]
	assert(k, "no greybox style for kind " .. pl.kind)
	local x, y = pl.pos[1], pl.pos[2]
	local gy = groundY(x, y)
	local m = Instance.new("Model")
	m.Name = pl.id
	m:SetAttribute("Kind", pl.kind)
	m:SetAttribute("Label", pl.name)
	m:SetAttribute("Cell", Geo.cell(x, y))
	m:SetAttribute("MapX", x)
	m:SetAttribute("MapY", y)
	m.Parent = places
	local body
	if k.shape == "disc" then
		local r = pl.r or k.r
		body = part(
			m,
			"Footprint",
			Vector3.new(k.h, r * 2, r * 2),
			CFrame.new(x, gy + k.h / 2, y) * CFrame.Angles(0, 0, math.rad(90)),
			k.color,
			"Part"
		)
		body.Shape = Enum.PartType.Cylinder
		body.CanCollide = false
		body.Transparency = 0.25
	else
		local s = k.size
		local raise = k.raise or 0
		if raise > 0 then
			part(m, "Stand", Vector3.new(2, raise, 2), CFrame.new(x, gy + raise / 2, y), C.building)
		end
		body = part(
			m,
			"Block",
			Vector3.new(s[1], s[2], s[3]),
			CFrame.new(x, gy + raise + s[2] / 2, y),
			k.color
		)
	end
	m.PrimaryPart = body
	local poleH = k.pole
	local top = body
	if poleH > 0 then
		top = part(m, "Pole", Vector3.new(1, poleH, 1), CFrame.new(x, gy + poleH / 2, y), k.color)
		top.CanCollide = false
	end
	local big = pl.kind == "aoi" or pl.kind == "enemy" or pl.kind == "gated" or pl.kind == "hq"
	label(
		top,
		pl.name,
		k.color,
		if big then 4000 else 700,
		(if poleH > 0 then poleH / 2 else 20) + 4
	)
end

-------------------------------------------------------------------- spawn and legend at HQ 1
do
	local hq = Data.Nodes.HQ1
	local gy = groundY(hq[1], hq[2])
	local sp = Instance.new("SpawnLocation")
	sp.Name = "HQ1Spawn"
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(hq[1], gy + 1.5, hq[2])
	sp.Color = C.player
	sp.Material = Enum.Material.SmoothPlastic
	sp.Parent = root
	partCount += 1

	local board = part(
		root,
		"Legend",
		Vector3.new(36, 22, 1),
		CFrame.new(hq[1], gy + 12, hq[2] - 70),
		Color3.fromRGB(40, 40, 44)
	)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(720, 440)
	sg.LightInfluence = 0
	sg.Parent = board
	local rows = {
		{ C.building, "Light grey: buildings, area footprints" },
		{ C.road, "Dark grey: roads, rail, tunnel" },
		{ C.enemy, "Red: enemy sites" },
		{ C.player, "Blue: player bases, docks, firebase" },
		{ C.pickup, "Yellow: vehicles, keys, blueprints, caches" },
		{ C.gated, "Purple: gated zones, keypad rooms" },
		{ C.orange, "Orange: radio, power, cut points" },
		{ C.autumn, "Tan / pale blue / white: autumn / frost / winter" },
	}
	for i, r in rows do
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromOffset(40, 40)
		sw.Position = UDim2.fromOffset(20, 20 + (i - 1) * 52)
		sw.BackgroundColor3 = r[1]
		sw.BorderSizePixel = 0
		sw.Parent = sg
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromOffset(640, 40)
		t.Position = UDim2.fromOffset(74, 20 + (i - 1) * 52)
		t.BackgroundTransparency = 1
		t.Text = r[2]
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextSize = 28
		t.TextColor3 = Color3.new(1, 1, 1)
		t.FontFace = roblox.Font.fromEnum(Enum.Font.GothamBold)
		t.Parent = sg
	end
end

root:SetAttribute("PartCount", partCount)
fs.writeDir("assets")
fs.writeFile("assets/Greybox.rbxm", roblox.serializeModel({ root }))
print(`greybox: {partCount} parts -> assets/Greybox.rbxm`)
