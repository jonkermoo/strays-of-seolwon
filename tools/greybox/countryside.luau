--!strict
-- Generates the countryside into src/shared/Map/Data.luau (the block between the BEGIN / END
-- countryside markers): dirt roads and trails (Data.Dirt) and soft buildings with stray loot
-- spots (Data.Buildings). Deterministic. Run from the repo root:
--   lune run tools/greybox/countryside
-- 0. dirt roads up to the garrisons that sit off the road (M1, M2, s1)
-- 1. back-country loops: dirt roads between road nodes whose road trip is a long way round
-- 2. trails up to the radio sites and into the deep forests (logging trails)
-- 3. farm / cabin / hut clusters along all roads; off-road ones get a dirt spur or a trail
-- Paths are least-cost walks over a 32-stud grid: gentle slopes cheap, steep ones dear, no
-- water, sea, gorge or enemy / gated sites, and running beside a main road is discouraged.
local fs = require("@lune/fs")

local Data = require("../../src/shared/Map/Data")
local GeoMod = require("../../src/shared/Map/Geo")

type Pt = { number }

local PATH = "src/shared/Map/Data.luau"
local BEGIN = "-- BEGIN countryside"
local END = "-- END countryside"
local TARGET_BUILDINGS = 120
local MAX_LOOPS = 8

local seed = 4242
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

Data.Dirt = {}
Data.Buildings = {}
local Geo = GeoMod(Data)
local W, H = Data.Frame.width, Data.Frame.height

local function dist(a: Pt, b: Pt): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

-------------------------------------------------------------------- the cost grid
local G = 32
local NX, NY = W // G, H // G
local blocked: { boolean } = {}
local solid: { boolean } = {} -- item markers and water: never crossed, even near the ends
local penalty: { number } = {}
local height: { number } = {}
local hard = {} -- sites a path may not cross
for _, p in Data.Places do
	if not p.site and (p.kind == "enemy" or p.kind == "gated" or p.kind == "hq") then
		table.insert(hard, { x = p.pos[1], y = p.pos[2], r = (p.r or 120) + 30 })
	end
end

local items: { Pt } = {}
for _, p in Data.Places do
	if p.site then
		table.insert(items, p.pos)
	end
end

local function cellOf(x: number, y: number): number
	local i = math.clamp(math.floor(x / G), 0, NX - 1)
	local j = math.clamp(math.floor(y / G), 0, NY - 1)
	return j * NX + i + 1
end
local function centre(k: number): (number, number)
	local i, j = (k - 1) % NX, (k - 1) // NX
	return i * G + G / 2, j * G + G / 2
end

local function buildGrid()
	for k = 1, NX * NY do
		local x, y = centre(k)
		local bad = Geo.coastDist(x, y) < 40 or Geo.waterLevel(x, y) ~= nil
		if not bad and (Geo.lineDist(Data.Gorge, x, y, false)) < Data.GorgeWidth / 2 + 30 then
			bad = true
		end
		if not bad then
			for _, s in hard do
				if (x - s.x) ^ 2 + (y - s.y) ^ 2 < s.r * s.r then
					bad = true
					break
				end
			end
		end
		blocked[k] = bad
		local hit = false
		for _, it in items do
			if (x - it[1]) ^ 2 + (y - it[2]) ^ 2 < 30 * 30 then
				hit = true
				break
			end
		end
		solid[k] = hit or Geo.waterLevel(x, y) ~= nil -- water too: never crossed, even at the ends
		height[k] = Geo.height(x, y)
		local d, _, kind = Geo.nearestRoad(x, y)
		-- don't run alongside an existing road (crossing or joining it is fine)
		penalty[k] = if kind and d < 70 then 3 else 0
	end
end

-- least-cost path from `from` to the nearest cell where `goal(k)` holds; points from start
local NB = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local function search(from: Pt, goal: (number) -> boolean, free: Pt?, maxCost: number?): { Pt }?
	local start = cellOf(from[1], from[2])
	local cost: { [number]: number } = { [start] = 0 }
	local prev: { [number]: number } = {}
	local heap: { { number } } = { { 0, start } }
	local function push(c: number, k: number)
		table.insert(heap, { c, k })
		local i = #heap
		while i > 1 do
			local p = i // 2
			if heap[p][1] <= heap[i][1] then
				break
			end
			heap[p], heap[i] = heap[i], heap[p]
			i = p
		end
	end
	local function pop(): { number }
		local top = heap[1]
		local last = table.remove(heap) :: { number }
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, m = i * 2, i * 2 + 1, i
				if l <= #heap and heap[l][1] < heap[m][1] then
					m = l
				end
				if r <= #heap and heap[r][1] < heap[m][1] then
					m = r
				end
				if m == i then
					break
				end
				heap[m], heap[i] = heap[i], heap[m]
				i = m
			end
		end
		return top
	end
	local function near(k: number, p: Pt?): boolean
		if not p then
			return false
		end
		local x, y = centre(k)
		return (x - p[1]) ^ 2 + (y - p[2]) ^ 2 < 320 * 320
	end
	while #heap > 0 do
		local top = pop()
		local c, k = top[1], top[2]
		if c <= cost[k] then
			if k ~= start and goal(k) then
				local cells = { k }
				while prev[cells[1]] do
					table.insert(cells, 1, prev[cells[1]])
				end
				local pts = { from }
				for n = 2, #cells do
					local x, y = centre(cells[n])
					table.insert(pts, { x, y })
				end
				return pts
			end
			if maxCost and c > maxCost then
				return nil
			end
			local i, j = (k - 1) % NX, (k - 1) // NX
			for _, o in NB do
				local ni, nj = i + o[1], j + o[2]
				if ni >= 0 and nj >= 0 and ni < NX and nj < NY then
					local nk = nj * NX + ni + 1
					if not solid[nk] and (not blocked[nk] or near(nk, from) or near(nk, free)) then
						local len = if o[1] ~= 0 and o[2] ~= 0 then G * 1.4142 else G
						local grade = math.abs(height[nk] - height[k]) / len
						local step = len * (1 + 8 * (grade / 0.25) ^ 2 + penalty[nk])
						if grade > 0.3 then
							step *= 5
						end
						local nc = c + step
						if cost[nk] == nil or nc < cost[nk] then
							cost[nk] = nc
							prev[nk] = k
							push(nc, nk)
						end
					end
				end
			end
		end
	end
	return nil
end

-- straighten a grid path: drop points within `tol` of the line, then round the corners
local function simplify(pts: { Pt }, tol: number): { Pt }
	local keep = { [1] = true, [#pts] = true }
	local function dp(a: number, b: number)
		local best, bi = 0, nil
		for i = a + 1, b - 1 do
			local d = Geo.lineDist({ pts[a], pts[b] }, pts[i][1], pts[i][2], false)
			if d > best then
				best, bi = d, i
			end
		end
		if bi and best > tol then
			keep[bi] = true
			dp(a, bi)
			dp(bi, b)
		end
	end
	dp(1, #pts)
	local out = {}
	for i = 1, #pts do
		if keep[i] then
			table.insert(out, pts[i])
		end
	end
	for _ = 1, 2 do
		local sm = { out[1] }
		for i = 1, #out - 1 do
			local a, b = out[i], out[i + 1]
			if i > 1 then
				table.insert(sm, { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 })
			end
			if i < #out - 1 then
				table.insert(sm, { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 })
			end
		end
		table.insert(sm, out[#out])
		out = sm
	end
	return out
end

local function onRoad(k: number): boolean
	local x, y = centre(k)
	local d, _, kind, half = Geo.nearestRoad(x, y)
	return kind ~= nil and kind ~= "rail" and d < half + 2 -- the old railway is not a road
end

-- loop goal: node B itself, or any dry road cell close to it (town centres can sit on a bridge)
local function reaches(B: Pt): (number) -> boolean
	local bk = cellOf(B[1], B[2])
	return function(k: number): boolean
		if k == bk then
			return true
		end
		local x, y = centre(k)
		return (x - B[1]) ^ 2 + (y - B[2]) ^ 2 < 250 * 250 and onRoad(k)
	end
end

local function rebuild()
	Geo = GeoMod(Data)
	buildGrid()
end

local function overlap(pts: { Pt }): number
	local n = 0
	for _, p in pts do
		for _, d in Data.Dirt do
			if (Geo.lineDist(d.pts, p[1], p[2], false)) < 200 then
				n += 1
				break
			end
		end
	end
	return n / #pts
end

-------------------------------------------------------------------- 1. back-country loops
buildGrid()
local loopMids: { Pt } = {}
-- garrisons out in open country (M1, M2, s1) are reached by a dirt road from the nearest road
local OFFROAD = { M1 = true, M2 = true, S1 = true }
for _, p in Data.Places do
	if OFFROAD[p.id] then
		local pts = search(p.pos, onRoad, p.pos)
		if pts then
			pts = simplify(pts, 16)
			local rev = {}
			for i = #pts, 1, -1 do
				table.insert(rev, pts[i])
			end
			table.insert(Data.Dirt, { kind = "dirt", use = `garrison {p.id}`, pts = rev })
			print(`garrison road {p.id}: {math.floor(Geo.length(rev))} studs`)
		else
			error("no road to " .. p.id)
		end
	end
end
rebuild()

-- hand-picked loops through country the road graph leaves empty (a waypoint keeps them there)
local EXTRA = {
	{ a = "M1", via = { 7842, 5975 }, b = "M2" }, -- the eastern interior
}
for _, x in EXTRA do
	local A, V, B = Data.Nodes[x.a], x.via, Data.Nodes[x.b]
	local vk, bk = cellOf(V[1], V[2]), cellOf(B[1], B[2])
	local p1 = search(A, function(k)
		return k == vk
	end, V)
	local p2 = p1 and search(V, reaches(B), B)
	if p1 and p2 then
		for i = 2, #p2 do
			table.insert(p1, p2[i])
		end
		if cellOf(p1[#p1][1], p1[#p1][2]) == bk then
			p1[#p1] = B
		end
		local pts = simplify(p1, 24)
		table.insert(Data.Dirt, { kind = "dirt", use = `loop {x.a}-{x.b}`, pts = pts })
		print(`loop {x.a}-{x.b} (via): {math.floor(Geo.length(pts))} studs`)
		table.insert(loopMids, V)
	end
end

local SKIP = { DOCK1 = true, DOCK2 = true, CB = true, TS = true, LH = true, RB = true } -- RB: on the bridge
local ids = {}
for id in Data.Nodes do
	if not SKIP[id] then
		table.insert(ids, id)
	end
end
table.sort(ids)
local cands = {}
for i = 1, #ids do
	for j = i + 1, #ids do
		local a, b = Data.Nodes[ids[i]], Data.Nodes[ids[j]]
		local d = dist(a, b)
		if d > 1500 and d < 4500 then
			local road = Geo.route(ids[i], ids[j])
			if road / d > 1.6 then
				table.insert(cands, { a = ids[i], b = ids[j], ratio = road / d, road = road })
			end
		end
	end
end
table.sort(cands, function(p, q)
	return p.ratio > q.ratio
end)
local loops = 0
for _, c in cands do
	if loops >= MAX_LOOPS then
		break
	end
	local A, B = Data.Nodes[c.a], Data.Nodes[c.b]
	-- spread the loops over the island: skip pairs centred near a loop already taken
	local mid = { (A[1] + B[1]) / 2, (A[2] + B[2]) / 2 }
	local spread = true
	for _, m in loopMids do
		if dist(m, mid) < 1800 then
			spread = false
		end
	end
	local bk = cellOf(B[1], B[2])
	local pts = search(A, reaches(B), B)
	if pts and spread then
		if cellOf(pts[#pts][1], pts[#pts][2]) == bk then
			pts[#pts] = B
		end
		pts = simplify(pts, 24)
		if Geo.length(pts) < c.road * 0.8 and overlap(pts) < 0.3 then
			table.insert(Data.Dirt, { kind = "dirt", use = `loop {c.a}-{c.b}`, pts = pts })
			loops += 1
			table.insert(loopMids, mid)
			print(
				`loop {c.a}-{c.b}: {math.floor(Geo.length(pts))} studs (road {math.floor(c.road)})`
			)
		end
	end
end

-------------------------------------------------------------------- 2. trails
rebuild()
local trailEnds = {}
for _, p in Data.Places do
	if p.kind == "radio" then
		local d = Geo.nearestRoad(p.pos[1], p.pos[2])
		if d > 60 then
			table.insert(trailEnds, { p.pos, `radio {p.id}` })
		end
	end
end
-- logging: the deepest forest far from any road, spread out
local deep = {}
for k = 1, NX * NY, 3 do
	local x, y = centre(k)
	if not blocked[k] and Geo.forest(x, y) > 0.85 then
		local d = Geo.nearestRoad(x, y)
		if d > 450 then
			table.insert(deep, { x, y, d })
		end
	end
end
table.sort(deep, function(p, q)
	return p[3] > q[3]
end)
local logging = 0
for _, p in deep do
	if logging >= 5 then
		break
	end
	local ok = true
	for _, e in trailEnds do
		if dist(e[1], p) < 1800 then
			ok = false
		end
	end
	if ok then
		table.insert(trailEnds, { { p[1], p[2] }, "logging" })
		logging += 1
	end
end
for _, e in trailEnds do
	local pts = search(e[1], onRoad, nil, 40000)
	if pts then
		pts = simplify(pts, 16)
		-- trails run from the road out to the end
		local rev = {}
		for i = #pts, 1, -1 do
			table.insert(rev, pts[i])
		end
		table.insert(Data.Dirt, { kind = "trail", use = `trail {e[2]}`, pts = rev })
		print(`trail {e[2]}: {math.floor(Geo.length(rev))} studs`)
	end
end

-------------------------------------------------------------------- 3. farms, cabins, huts
rebuild()
local KINDS = {
	farm = {
		{ "farmhouse", 0, 0, 16, 12, 10 },
		{ "barn", 30, 4, 24, 16, 14 },
		{ "shed", -4, 22, 9, 8, 7 },
		{ "shed", 26, 28, 8, 8, 6, 0.5 }, -- last field = chance
	},
	cabin = { { "cabin", 0, 0, 12, 10, 8 }, { "woodshed", 14, 6, 6, 5, 5, 0.4 } },
	hut = { { "hut", 0, 0, 8, 7, 6 } },
	stop = { { "garage", 0, 0, 14, 10, 7 }, { "shed", 14, 2, 6, 6, 5, 0.5 } },
}
local avoid = {} -- sites the countryside keeps clear of
for _, p in Data.Places do
	if not p.site then
		table.insert(avoid, { x = p.pos[1], y = p.pos[2], r = (p.r or 60) + 160 })
	end
end
local itemSpots = {}
for _, p in Data.Places do
	if p.site or p.kind == "hum" or p.kind == "veh" or p.kind == "bp" then
		table.insert(itemSpots, p.pos)
	end
end

local function footprintOk(x: number, y: number, w: number, d: number, rot: number): boolean
	local c, s = math.cos(rot), math.sin(rot)
	local lo, hi = math.huge, -math.huge
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } } do
		local ox, oz = o[1] * w / 2, o[2] * d / 2
		local px, py = x + ox * c - oz * s, y + ox * s + oz * c
		if Geo.waterLevel(px, py) or Geo.coastDist(px, py) < 30 then
			return false
		end
		local rd, _, kind, half = Geo.nearestRoad(px, py)
		if kind and rd < half + 6 then
			return false
		end
		local h = Geo.height(px, py)
		lo, hi = math.min(lo, h), math.max(hi, h)
	end
	if hi - lo > 8 then
		return false
	end
	for _, sp in itemSpots do
		if math.abs(sp[1] - x) < w / 2 + 16 and math.abs(sp[2] - y) < d / 2 + 16 then
			return false
		end
	end
	return true
end

-- candidate spots: along every road line, both sides, near (roadside) or far (needs a spur)
local lines = {}
for _, e in Data.Edges do
	if e.kind ~= "tunnel" then
		table.insert(lines, Geo.edgePoints(e))
	end
end
for _, d in Data.Dirt do
	table.insert(lines, d.pts)
end
local spots = {}
for _, pts in lines do
	local along = rnd() * 300
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = dist(a, b)
		while along < len do
			local t = along / len
			local x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
			local dx, dy = (b[1] - a[1]) / len, (b[2] - a[2]) / len
			local side = if rnd() < 0.5 then 1 else -1
			local far = rnd() < 0.4
			local off = if far then 160 + rnd() * 220 else 45 + rnd() * 35
			table.insert(spots, {
				x = x - dy * side * off,
				y = y + dx * side * off,
				-- local -z (the door side, (sin r, -cos r) on the map) faces the road
				face = math.atan2(dy * side, dx * side),
				road = { x, y },
				far = far,
				order = rnd(),
			})
			along += 200 + rnd() * 300
		end
		along -= len
	end
end
table.sort(spots, function(p, q)
	return p.order < q.order
end)

local clusters = {}
local count = 0
for _, sp in spots do
	if count >= TARGET_BUILDINGS then
		break
	end
	local ok = Geo.isLand(sp.x, sp.y) and not Geo.waterLevel(sp.x, sp.y)
	if ok then
		for _, a in avoid do
			if (sp.x - a.x) ^ 2 + (sp.y - a.y) ^ 2 < a.r * a.r then
				ok = false
				break
			end
		end
	end
	if ok then
		for _, c in clusters do
			if (sp.x - c.x) ^ 2 + (sp.y - c.y) ^ 2 < 320 * 320 then
				ok = false
				break
			end
		end
	end
	if ok then
		local zone = Geo.zone(sp.x, sp.y)
		local r = rnd()
		local kind = if zone == "autumn"
			then (if r < 0.65 then "farm" elseif r < 0.85 then "cabin" else "stop")
			elseif zone == "frost" then (if r < 0.4
				then "farm"
				elseif r < 0.8 then "cabin"
				else "hut")
			else (if r < 0.15
				then "farm"
				elseif r < 0.55 then "cabin"
				elseif r < 0.85 then "hut"
				else "stop")
		if not sp.far and Geo.forest(sp.x, sp.y) > 0.6 and kind == "farm" then
			kind = "cabin"
		end
		local rot = sp.face
		local c, s = math.cos(rot), math.sin(rot)
		local list = {}
		for _, b in KINDS[kind] do
			if b[7] == nil or rnd() < b[7] then
				local bx, by = sp.x + b[2] * c - b[3] * s, sp.y + b[2] * s + b[3] * c
				local brot = rot + (rnd() - 0.5) * 0.12
				if footprintOk(bx, by, b[4], b[5], brot) then
					table.insert(
						list,
						{ kind = b[1], x = bx, y = by, w = b[4], d = b[5], h = b[6], rot = brot }
					)
				end
			end
		end
		if #list > 0 and (kind ~= "farm" or #list >= 2) then
			local cl = {
				x = sp.x,
				y = sp.y,
				kind = kind,
				list = list,
				far = sp.far,
				road = sp.road,
				rot = rot,
			}
			if sp.far then
				-- a spur from the yard in front of the main building to the nearest road
				local front = { sp.x + s * 18, sp.y - c * 18 } -- local -z, towards the road
				local pts = search(front, onRoad, front, 30000)
				if pts and Geo.length(pts) < 700 then
					pts = simplify(pts, 12)
					local rev = {}
					for i = #pts, 1, -1 do
						table.insert(rev, pts[i])
					end
					cl.spur = {
						kind = if kind == "farm" or kind == "stop" then "dirt" else "trail",
						use = `spur {kind}`,
						pts = rev,
					}
				else
					cl = nil :: any
				end
			end
			if cl then
				table.insert(clusters, cl)
				count += #list
			end
		end
	end
end

-- add the spurs, then drop buildings the spurs now run through
for _, cl in clusters do
	if cl.spur then
		table.insert(Data.Dirt, cl.spur)
	end
end
rebuild()
local loot = 0
for _, cl in clusters do
	for _, b in cl.list do
		if footprintOk(b.x, b.y, b.w, b.d, b.rot) then
			local spotsOut = {}
			if rnd() < 0.34 then
				local c, s = math.cos(b.rot), math.sin(b.rot)
				for _ = 1, 1 + math.floor(rnd() * 3) do
					-- in front of the door side (local -z faces the road)
					local lx, lz = (rnd() - 0.5) * b.w * 0.6, -(b.d / 2 + 3)
					table.insert(spotsOut, { b.x + lx * c - lz * s, b.y + lx * s + lz * c })
					loot += 1
				end
			end
			table.insert(Data.Buildings, {
				kind = b.kind,
				pos = { b.x, b.y },
				size = { b.w, b.d, b.h },
				rot = b.rot,
				loot = spotsOut,
			})
		end
	end
end
print(
	`{#Data.Dirt} dirt roads / trails, {#clusters} clusters, {#Data.Buildings} buildings, {loot} loot spots`
)

-------------------------------------------------------------------- write the data block
local function pt(p: Pt): string
	return string.format("{ %d, %d }", math.floor(p[1] + 0.5), math.floor(p[2] + 0.5))
end
local out = {
	BEGIN .. " (generated by tools/greybox/countryside; do not edit by hand)",
	"-- Dirt roads (dirt) and trails: loops, radio / logging trails, spurs to farms and cabins.",
	"-- Not part of the planned route graph. Buildings: soft countryside buildings (solid",
	"-- placeholders); loot = stray common loot spots by the door.",
	"Data.Dirt = {",
}
for _, d in Data.Dirt do
	local ps = {}
	for _, p in d.pts do
		table.insert(ps, pt(p))
	end
	table.insert(
		out,
		`\t\{ kind = "{d.kind}", use = "{d.use}", pts = \{ {table.concat(ps, ", ")} } },`
	)
end
table.insert(out, "}")
table.insert(out, "Data.Buildings = {")
for _, b in Data.Buildings do
	local ls = {}
	for _, p in b.loot do
		table.insert(ls, pt(p))
	end
	table.insert(
		out,
		string.format(
			'\t{ kind = "%s", pos = %s, size = { %d, %d, %d }, rot = %.3f, loot = { %s } },',
			b.kind,
			pt(b.pos),
			b.size[1],
			b.size[2],
			b.size[3],
			b.rot,
			table.concat(ls, ", ")
		)
	)
end
table.insert(out, "}")
table.insert(out, END)

local src = fs.readFile(PATH)
local i0 = string.find(src, BEGIN, 1, true)
local block = table.concat(out, "\n")
if i0 then
	local _, i1 = string.find(src, END, i0, true)
	src = string.sub(src, 1, i0 - 1) .. block .. string.sub(src, (i1 :: number) + 1)
else
	local r = string.find(src, "\nreturn Data", 1, true) :: number
	src = string.sub(src, 1, r) .. block .. "\n" .. string.sub(src, r)
end
fs.writeFile(PATH, src)
print("wrote " .. PATH)
