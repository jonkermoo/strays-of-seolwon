--!strict
-- Builds the Seolwon greybox parts from src/shared/Map/Data.luau into assets/Greybox.rbxm:
-- place markers, solid placeholder buildings, bridge decks, the tunnel, spawn and legend.
-- The ground itself is Roblox terrain (tools/terrain). Plain anchored SmoothPlastic parts only,
-- coloured by purpose (no art). Run from the repo root: lune run tools/greybox/build
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Data = require("../../src/shared/Map/Data")
local Geo = require("../../src/shared/Map/Geo")(Data)
local Metrics = require("../../src/shared/Map/Metrics")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2

type Pt = { number }

local C = {
	road = Color3.fromRGB(70, 70, 74),
	building = Color3.fromRGB(176, 176, 176),
	roof = Color3.fromRGB(128, 128, 132),
	enemy = Color3.fromRGB(190, 62, 56),
	enemyWall = Color3.fromRGB(120, 60, 56),
	player = Color3.fromRGB(56, 106, 200),
	playerWall = Color3.fromRGB(60, 80, 120),
	pickup = Color3.fromRGB(232, 190, 40),
	gated = Color3.fromRGB(132, 82, 182),
	orange = Color3.fromRGB(232, 132, 40),
	autumn = Color3.fromRGB(178, 150, 102),
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

-- world position of a map point at height Y
local function at(x: number, y: number, Y: number): any
	local X, Z = Geo.world(x, y)
	return Vector3.new(X, Y, Z)
end

-- deterministic random (same build every time)
local seed = 12345
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local root = Instance.new("Model")
root.Name = "Greybox"

-------------------------------------------------------------------- bridges and tunnel
local roads = folder(root, "Roads")
do
	-- decks wherever a road crosses a cut (river, gorge, lake inlet): runs of "bridge" samples
	local bf = folder(roads, "Bridges")
	for _, e in Data.Edges do
		if e.kind ~= "tunnel" then
			local pts = Geo.edgePoints(e)
			local run: { any }? = nil
			local function flush()
				if run and #run >= 1 then
					local a, b = run[1], run[#run]
					local dx, dy = b.x - a.x, b.y - a.y
					local len = math.sqrt(dx * dx + dy * dy)
					local ux, uy = if len > 0 then dx / len else 1, if len > 0 then dy / len else 0
					local pa = at(a.x - ux * 12, a.y - uy * 12, a.h)
					local pb = at(b.x + ux * 12, b.y + uy * 12, b.h)
					local w = Data.RoadWidth[e.kind] + 2
					part(
						bf,
						`{e.a}-{e.b}`,
						Vector3.new(w, 2, (pb - pa).Magnitude),
						CFrame.lookAt((pa + pb) / 2, pb) * CFrame.new(0, -1, 0),
						C.road
					)
				end
				run = nil
			end
			for i = 1, #pts - 1 do
				local a, c = pts[i], pts[i + 1]
				local len = math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
				local n = math.max(1, math.ceil(len / 8))
				for k = 0, n - 1 do
					local x, y = a[1] + (c[1] - a[1]) * k / n, a[2] + (c[2] - a[2]) * k / n
					local _, _, bridge = Geo.sample(x, y)
					if bridge then
						run = run or {}
						table.insert(run :: { any }, { x = x, y = y, h = Geo.roadHeight(x, y) })
					else
						flush()
					end
				end
			end
			flush()
		end
	end

	-- the tunnel under the Sawmill channel: a covered box from portal to portal
	for _, e in Data.Edges do
		if e.kind == "tunnel" then
			local tf = folder(roads, `Tunnel {e.a}-{e.b}`)
			local a, b = Data.Nodes[e.a], Data.Nodes[e.b]
			local Wd, Hh = Metrics.Road.tunnelWidth, Metrics.Road.tunnelHeight
			local p1 = at(a[1], a[2], Geo.roadHeight(a[1], a[2]))
			local p2 = at(b[1], b[2], Geo.roadHeight(b[1], b[2]))
			local len = (p2 - p1).Magnitude
			local cf = CFrame.lookAt((p1 + p2) / 2, p2)
			part(tf, "Floor", Vector3.new(Wd, 2, len), cf * CFrame.new(0, -1, 0), C.road)
			part(tf, "Roof", Vector3.new(Wd + 4, 2, len), cf * CFrame.new(0, Hh + 1, 0), C.road)
			part(
				tf,
				"WallL",
				Vector3.new(2, Hh, len),
				cf * CFrame.new(-Wd / 2 - 1, Hh / 2, 0),
				C.road
			)
			part(
				tf,
				"WallR",
				Vector3.new(2, Hh, len),
				cf * CFrame.new(Wd / 2 + 1, Hh / 2, 0),
				C.road
			)
		end
	end

	-- Citadel bridge: down at the start, so two stubs with a gap over the strait
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
	local cf = folder(roads, "Citadel bridge (down)")
	local stub = gap * 0.35
	local deck = 8
	part(
		cf,
		"Stub main",
		Vector3.new(20, 2, stub + 40),
		CFrame.new(at(x, shore - stub / 2 + 20, deck)),
		C.road
	)
	part(
		cf,
		"Stub citadel",
		Vector3.new(20, 2, stub + 40),
		CFrame.new(at(x, far + stub / 2 - 20, deck)),
		C.road
	)
end

-------------------------------------------------------------------- placeholder buildings
local buildings = folder(root, "Buildings")
local itemSpots: { { number } } = {}
for _, pl in Data.Places do
	if pl.site then
		table.insert(itemSpots, pl.pos)
	end
end

-- a solid block standing on the ground (bottom sunk below the lowest corner); false if unsuitable
local function block(
	parent: any,
	x: number,
	y: number,
	sx: number,
	sz: number,
	tall: number,
	rot: number,
	color: any
): boolean
	local hs = {}
	local c, s = math.cos(rot), math.sin(rot)
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } } do
		local ox, oz = o[1] * sx / 2, o[2] * sz / 2
		local px, py = x + ox * c - oz * s, y + ox * s + oz * c
		if Geo.waterLevel(px, py) then
			return false
		end
		local d, _, kind, half = Geo.nearestRoad(px, py)
		if kind and d < half + 5 then
			return false
		end
		table.insert(hs, Geo.height(px, py))
	end
	local lo, hi = math.min(table.unpack(hs)), math.max(table.unpack(hs))
	if hi - lo > 14 then
		return false
	end
	for _, sp in itemSpots do
		if math.abs(sp[1] - x) < sx / 2 + 14 and math.abs(sp[2] - y) < sz / 2 + 14 then
			return false
		end
	end
	local bottom = lo - 3
	local top = hi + tall
	local p = part(
		parent,
		"Block",
		Vector3.new(sx, top - bottom, sz),
		CFrame.new(at(x, y, (bottom + top) / 2)) * CFrame.Angles(0, -rot, 0),
		color
	)
	p:SetAttribute("Storeys", math.max(1, math.floor(tall / Metrics.Building.storey)))
	return true
end

-- a wall ring of segments round a site, with gaps where roads come in
local function wallRing(parent: any, cx: number, cy: number, r: number, color: any, tall: number)
	local n = math.max(12, math.floor(2 * math.pi * r / 24))
	for i = 0, n - 1 do
		local a1, a2 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
		local x1, y1 = cx + math.cos(a1) * r, cy + math.sin(a1) * r
		local x2, y2 = cx + math.cos(a2) * r, cy + math.sin(a2) * r
		local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
		local d, _, kind, half = Geo.nearestRoad(mx, my)
		if not (kind and d < half + 8) and not Geo.waterLevel(mx, my) then
			local h = Geo.height(mx, my)
			local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + 1
			local pa, pb = at(x1, y1, h + tall / 2 - 2), at(x2, y2, h + tall / 2 - 2)
			part(
				parent,
				"Wall",
				Vector3.new(2, tall + 4, len),
				CFrame.lookAt((pa + pb) / 2, pb),
				color
			)
		end
	end
end

-- town: lots on a rough street grid; denser and taller towards the middle of a city
local function town(f: any, cx: number, cy: number, r: number, city: boolean)
	local LOT = 38
	local rot = rnd() * math.pi
	local c, s = math.cos(rot), math.sin(rot)
	local n = math.floor(r / LOT)
	for gi = -n, n do
		for gj = -n, n do
			if gi % 5 ~= 0 and gj % 4 ~= 0 then -- every 5th / 4th lot line is a street
				local lx, ly = gi * LOT, gj * LOT
				local x, y = cx + lx * c - ly * s, cy + lx * s + ly * c
				local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / r
				if d < 0.97 and rnd() < 0.95 - d * 0.3 then
					local sx, sz = 16 + rnd() * 16, 14 + rnd() * 14
					local storeys = if city
						then 1 + math.floor((1 - d) ^ 2 * 6 * rnd() + rnd() * 2)
						else 1 + (if rnd() < 0.25 then 1 else 0)
					block(f, x, y, sx, sz, storeys * Metrics.Building.storey, rot, C.building)
				end
			end
		end
	end
end

-- military site: wall ring, barracks, sheds, a tower or two
local function base(f: any, cx: number, cy: number, r: number, wallColor: any, count: number)
	wallRing(f, cx, cy, r, wallColor, 10)
	for _ = 1, count do
		local a, d = rnd() * 2 * math.pi, (0.15 + rnd() * 0.6) * r
		local x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
		if rnd() < 0.2 then
			block(f, x, y, 8, 8, 24, a, wallColor) -- tower
		else
			block(f, x, y, 26 + rnd() * 16, 12 + rnd() * 6, Metrics.Building.storey, a, C.building)
		end
	end
end

for _, pl in Data.Places do
	local x, y = pl.pos[1], pl.pos[2]
	if pl.kind == "aoi" then
		town(folder(buildings, pl.id), x, y, pl.r, pl.r >= 500)
	elseif pl.kind == "enemy" then
		base(folder(buildings, pl.id), x, y, pl.r, C.enemyWall, math.floor(pl.r / 18))
	elseif pl.kind == "gated" then
		base(folder(buildings, pl.id), x, y, pl.r or 120, C.gated, 5)
	elseif pl.kind == "hq" then
		base(folder(buildings, pl.id), x, y, pl.r or 100, C.playerWall, 12)
	elseif pl.kind == "fb" then
		base(folder(buildings, pl.id), x, y, 60, C.playerWall, 2)
	elseif pl.kind == "veh" then
		block(folder(buildings, pl.id), x + 14, y, 14, 12, 9, 0, C.building) -- farm shed
	end
end

-------------------------------------------------------------------- countryside buildings + loot
-- Soft buildings from Data.Buildings (tools/greybox/countryside): solid placeholders; a third
-- have 1-3 stray common loot spots by the door (yellow pads).
local country = folder(root, "Countryside")
local lootCount, built = 0, 0
for i, b in Data.Buildings or {} do
	local f = folder(country, `{b.kind}_{i}`)
	f:SetAttribute("Kind", b.kind)
	if block(f, b.pos[1], b.pos[2], b.size[1], b.size[2], b.size[3], b.rot, C.building) then
		built += 1
	end
	for _, l in b.loot do
		local pad = part(
			f,
			"LootSpot",
			Vector3.new(2, 0.4, 2),
			CFrame.new(at(l[1], l[2], Geo.height(l[1], l[2]) + 0.2)),
			C.pickup
		)
		pad.Material = Enum.Material.Neon
		pad.CanCollide = false
		pad:SetAttribute("Tier", "common")
		lootCount += 1
	end
end

-------------------------------------------------------------------- placeholder trees
-- Where forests will be (Geo.forest), plus scattered single trees. Trunk + canopy (a sphere
-- mesh); only trunks collide. Conifers in the snow, mixed in the frost band, mostly broadleaf
-- autumn colours in sector B. One folder per map cell.
local trees = folder(root, "Trees")
local cellFolders: { [string]: any } = {}
local clear: { { number } } = {} -- {x, y, r}: keep trees off sites and buildings
for _, pl in Data.Places do
	if not pl.site then
		table.insert(clear, { pl.pos[1], pl.pos[2], (pl.r or 30) + 20 })
	else
		table.insert(clear, { pl.pos[1], pl.pos[2], 14 })
	end
end
for _, b in Data.Buildings or {} do
	table.insert(clear, { b.pos[1], b.pos[2], math.max(b.size[1], b.size[2]) / 2 + 8 })
end
local CON = {
	Color3.fromRGB(46, 64, 50),
	Color3.fromRGB(56, 74, 58),
	Color3.fromRGB(40, 56, 46),
}
local SNOWY = Color3.fromRGB(196, 204, 202)
local AUT = {
	Color3.fromRGB(176, 104, 48),
	Color3.fromRGB(150, 118, 52),
	Color3.fromRGB(124, 72, 42),
	Color3.fromRGB(160, 132, 70),
}
local TRUNK = Color3.fromRGB(78, 62, 50)
local treeCount = 0
local SP = 30
for gy = SP / 2, Data.Frame.height, SP do
	for gx = SP / 2, Data.Frame.width, SP do
		local x, y = gx + (rnd() - 0.5) * SP * 0.8, gy + (rnd() - 0.5) * SP * 0.8
		local f = Geo.forest(x, y)
		local p = if f > 0.1 then f ^ 1.3 * 0.8 else 0.012
		if rnd() < p and Geo.coastDist(x, y) > 40 and not Geo.waterLevel(x, y) then
			local ok = true
			local d, _, kind, half = Geo.nearestRoad(x, y)
			if kind and d < half + 8 then
				ok = false
			end
			if ok then
				for _, c in clear do
					if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < c[3] * c[3] then
						ok = false
						break
					end
				end
			end
			local h = Geo.height(x, y)
			if
				ok
				and math.abs(Geo.height(x + 4, y) - h) + math.abs(Geo.height(x, y + 4) - h) > 7
			then
				ok = false -- cliffs and rock faces
			end
			if ok then
				local zone = Geo.zone(x, y)
				local broad = if zone == "autumn"
					then rnd() < 0.65
					elseif zone == "frost" then rnd() < 0.25
					else rnd() < 0.04
				local tall = 18 + rnd() * 16
				local cell = Geo.cell(x, y)
				local cf = cellFolders[cell]
				if not cf then
					cf = folder(trees, cell)
					cellFolders[cell] = cf
				end
				local m = Instance.new("Model")
				m.Name = if broad then "Broadleaf" else "Conifer"
				m.Parent = cf
				local trunkH = if broad then tall * 0.55 else tall * 0.4
				part(
					m,
					"Trunk",
					Vector3.new(1.6, trunkH + 2, 1.6),
					CFrame.new(at(x, y, h + trunkH / 2 - 1)),
					TRUNK
				)
				local w = if broad then 10 + rnd() * 6 else 7 + rnd() * 4
				local ch = if broad then w * 0.9 else tall * 0.8
				local col = if broad
					then AUT[1 + math.floor(rnd() * #AUT)]
					elseif zone == "winter" and rnd() < 0.3 then SNOWY
					else CON[1 + math.floor(rnd() * #CON)]
				local canopy = part(
					m,
					"Canopy",
					Vector3.new(w, ch, w),
					CFrame.new(at(x, y, h + tall - ch / 2)),
					col
				)
				canopy.CanCollide = false
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = canopy
				treeCount += 1
			end
		end
	end
end
print(
	`countryside: {built}/{#(Data.Buildings or {})} buildings, {lootCount} loot spots, {treeCount} trees`
)

-------------------------------------------------------------------- places (markers)
local KIND = {
	aoi = { color = C.building, pole = 160 },
	enemy = { color = C.enemy, pole = 120 },
	gated = { color = C.gated, pole = 120 },
	hq = { color = C.player, pole = 140 },
	dock = { color = C.player, size = { 30, 1, 60 }, pole = 60 },
	fb = { color = C.player, pole = 90 },
	radio = { color = C.orange, size = { 4, 40, 4 }, pole = 0 },
	power = { color = C.orange, size = { 40, 12, 40 }, pole = 60 },
	cut = { color = C.orange, size = { 6, 6, 6 }, pole = 40 },
	misc = { color = C.orange, size = { 20, 14, 20 }, pole = 40 },
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
	local gy = math.max(Geo.height(x, y), Geo.waterLevel(x, y) or -math.huge)
	local m = Instance.new("Model")
	m.Name = pl.id
	m:SetAttribute("Kind", pl.kind)
	m:SetAttribute("Label", pl.name)
	m:SetAttribute("Cell", Geo.cell(x, y))
	m:SetAttribute("MapX", x)
	m:SetAttribute("MapY", y)
	m.Parent = places
	local body
	if k.size then
		local s = k.size
		local raise = k.raise or 0
		if raise > 0 then
			part(
				m,
				"Stand",
				Vector3.new(2, raise + 2, 2),
				CFrame.new(at(x, y, gy + raise / 2 - 1)),
				C.building
			)
		end
		body = part(
			m,
			"Block",
			Vector3.new(s[1], s[2], s[3]),
			CFrame.new(at(x, y, gy + raise + s[2] / 2)),
			k.color
		)
	end
	local top = body
	if k.pole > 0 then
		top = part(
			m,
			"Pole",
			Vector3.new(1, k.pole, 1),
			CFrame.new(at(x, y, gy + k.pole / 2)),
			k.color
		)
		top.CanCollide = false
	end
	m.PrimaryPart = body or top
	local big = pl.kind == "aoi" or pl.kind == "enemy" or pl.kind == "gated" or pl.kind == "hq"
	label(
		top,
		pl.name,
		k.color,
		if big then 6000 else 700,
		(if k.pole > 0 then k.pole / 2 else 20) + 4
	)
end

-------------------------------------------------------------------- spawn and legend at HQ 1
do
	local hq = Data.Nodes.HQ1
	local gy = Geo.height(hq[1], hq[2])
	local sp = Instance.new("SpawnLocation")
	sp.Name = "HQ1Spawn"
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(at(hq[1], hq[2], gy + 0.5))
	sp.Color = C.player
	sp.Material = Enum.Material.SmoothPlastic
	sp.Parent = root
	partCount += 1

	local board = part(
		root,
		"Legend",
		Vector3.new(36, 22, 1),
		CFrame.new(at(hq[1], hq[2] - 40, gy + 12)),
		Color3.fromRGB(40, 40, 44)
	)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(720, 440)
	sg.LightInfluence = 0
	sg.Parent = board
	local rows = {
		{ C.building, "Light grey: placeholder buildings" },
		{ C.road, "Dark grey: bridges, tunnel" },
		{ C.enemy, "Red: enemy sites (dark red walls)" },
		{ C.player, "Blue: player bases, docks, firebase" },
		{ C.pickup, "Yellow: vehicles, keys, blueprints, caches" },
		{ C.gated, "Purple: gated zones, keypad rooms" },
		{ C.orange, "Orange: radio, power, cut points" },
		{ C.autumn, "Ground is terrain: autumn B, frost band, winter" },
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
