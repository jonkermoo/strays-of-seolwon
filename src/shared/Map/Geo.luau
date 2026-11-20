--!strict
-- Map maths over the layout data: land test, terrain height and surface, season zone, road
-- routes. Pure Luau (no Roblox objects), so Lune and Studio compute the same ground.
-- Use: local Geo = require(Geo)(Data). Heights are Y (sea level 0). Coordinates are map x, y.

type Pt = { number }

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- distance from (px, py) to segment ab, and the 0..1 position along it
local function segDist(px: number, py: number, a: Pt, b: Pt): (number, number)
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dy * dy
	local t = if len2 > 0 then math.clamp(((px - a[1]) * dx + (py - a[2]) * dy) / len2, 0, 1) else 0
	local cx, cy = a[1] + t * dx, a[2] + t * dy
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), t
end

local function fbm(x: number, y: number, oct: number): number
	local s, amp, f, norm = 0, 1, 1, 0
	for o = 1, oct do
		s += amp * math.noise(x * f + o * 17.31, y * f - o * 9.17, 0.5)
		norm += amp
		amp *= 0.5
		f *= 2.03
	end
	return s / norm -- about -0.5..0.5
end

local function ridged(x: number, y: number): number
	local s, amp, f = 0, 0.6, 1
	for o = 1, 3 do
		s += amp * (1 - math.abs(math.noise(x * f + 41.7 * o, y * f + 13.3 * o, 2.5)) * 2)
		amp *= 0.5
		f *= 2.1
	end
	return s -- about 0..1
end

return function(Data: any)
	local Geo = {}
	local W, H = Data.Frame.width, Data.Frame.height

	function Geo.world(x: number, y: number): (number, number)
		return x - W / 2, y - H / 2
	end
	function Geo.map(X: number, Z: number): (number, number)
		return X + W / 2, Z + H / 2
	end

	function Geo.inside(poly: { Pt }, x: number, y: number): boolean
		local n, c = #poly, false
		local j = n
		for i = 1, n do
			local a, b = poly[i], poly[j]
			if
				(a[2] > y) ~= (b[2] > y)
				and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1]
			then
				c = not c
			end
			j = i
		end
		return c
	end

	-- Distance to a polyline (closed = polygon edge), and (for open lines) how far along (0..1).
	function Geo.lineDist(pts: { Pt }, x: number, y: number, closed: boolean?): (number, number)
		local best, along, total, acc = math.huge, 0, 0, 0
		local lens = {}
		for i = 1, #pts - 1 do
			lens[i] = math.sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2)
			total += lens[i]
		end
		for i = 1, #pts - 1 do
			local d, t = segDist(x, y, pts[i], pts[i + 1])
			if d < best then
				best, along = d, (acc + t * lens[i]) / math.max(total, 1)
			end
			acc += lens[i]
		end
		if closed and #pts > 2 then
			best = math.min(best, (segDist(x, y, pts[#pts], pts[1])))
		end
		return best, along
	end

	local function bbox(poly: { Pt }, pad: number): { number }
		local a, b, c, d = math.huge, -math.huge, math.huge, -math.huge
		for _, p in poly do
			a, b = math.min(a, p[1]), math.max(b, p[1])
			c, d = math.min(c, p[2]), math.max(d, p[2])
		end
		return { a - pad, b + pad, c - pad, d + pad }
	end
	local function inBox(bb: { number }, x: number, y: number): boolean
		return x >= bb[1] and x <= bb[2] and y >= bb[3] and y <= bb[4]
	end
	local lakeBox = bbox(Data.Land.Lake, 170)

	-- Sorted x where row y crosses the island coastlines (land between pairs).
	function Geo.crossings(y: number): { number }
		local xs = {}
		for _, name in Data.Islands do
			local poly = Data.Land[name]
			local j = #poly
			for i = 1, #poly do
				local a, b = poly[i], poly[j]
				if (a[2] > y) ~= (b[2] > y) then
					table.insert(xs, (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1])
				end
				j = i
			end
		end
		table.sort(xs)
		return xs
	end

	---------------------------------------------------------------- precomputed fields
	local G = 32 -- field grid (studs)
	local NX, NY = W // G + 1, H // G + 1
	local coast: { number }? = nil -- signed distance to the coast (+ inland, - offshore)
	local mtn: { number }? = nil -- mountain height (before ridge detail)
	local roadPts: { any }? = nil -- smoothed road profiles
	local buckets: { [number]: { any } }? = nil
	local siteBuckets: { [number]: { any } } = {}
	local BK = 256
	local MAX_GRADE = math.tan(math.rad(14)) -- steepest road a loaded truck takes
	local PAD_BLEND = 220
	local FOREST_AT = -0.055 -- lower = more forest (2026-11-20: +50%)

	local function idx(i: number, j: number): number
		return j * NX + i + 1
	end

	local function prepare()
		if coast then
			return
		end
		-- land mask by scanlines, then a two-pass chamfer distance transform
		local land = table.create(NX * NY, false)
		for j = 0, NY - 1 do
			local xs = Geo.crossings(j * G)
			for k = 1, #xs - 1, 2 do
				for i = math.max(0, math.ceil(xs[k] / G)), math.min(NX - 1, math.floor(xs[k + 1] / G)) do
					land[idx(i, j)] = true
				end
			end
		end
		local function chamfer(target: boolean): { number }
			local INF = 1e9
			local dist = table.create(NX * NY, INF)
			for k = 1, NX * NY do
				if land[k] ~= target then
					dist[k] = 0
				end
			end
			local d1, d2 = G, G * 1.4142
			for j = 0, NY - 1 do
				for i = 0, NX - 1 do
					local k = idx(i, j)
					local v = dist[k]
					if i > 0 then
						v = math.min(v, dist[k - 1] + d1)
					end
					if j > 0 then
						v = math.min(v, dist[k - NX] + d1)
						if i > 0 then
							v = math.min(v, dist[k - NX - 1] + d2)
						end
						if i < NX - 1 then
							v = math.min(v, dist[k - NX + 1] + d2)
						end
					end
					dist[k] = v
				end
			end
			for j = NY - 1, 0, -1 do
				for i = NX - 1, 0, -1 do
					local k = idx(i, j)
					local v = dist[k]
					if i < NX - 1 then
						v = math.min(v, dist[k + 1] + d1)
					end
					if j < NY - 1 then
						v = math.min(v, dist[k + NX] + d1)
						if i < NX - 1 then
							v = math.min(v, dist[k + NX + 1] + d2)
						end
						if i > 0 then
							v = math.min(v, dist[k + NX - 1] + d2)
						end
					end
					dist[k] = v
				end
			end
			return dist
		end
		local inland = chamfer(true) -- for land cells: distance to sea
		local offshore = chamfer(false) -- for sea cells: distance to land
		local c = table.create(NX * NY, 0)
		for k = 1, NX * NY do
			c[k] = if land[k] then inland[k] else -offshore[k]
		end
		coast = c

		-- mountain field: a ranged core inside the outline plus foothills up to HALO outside it
		local HALO = 900
		local m = table.create(NX * NY, 0)
		for _, mt in Data.Mountains do
			local bb = bbox(mt.poly, HALO)
			local fall = math.min(mt.falloff, 650)
			for j = math.max(0, math.floor(bb[3] / G)), math.min(NY - 1, math.ceil(bb[4] / G)) do
				for i = math.max(0, math.floor(bb[1] / G)), math.min(NX - 1, math.ceil(bb[2] / G)) do
					local x, y = i * G, j * G
					local d = Geo.lineDist(mt.poly, x, y, true)
					local t
					if Geo.inside(mt.poly, x, y) then
						t = 0.22 + 0.78 * smoothstep(d / fall)
					elseif d < HALO then
						t = 0.22 * (1 - smoothstep(d / HALO))
					else
						t = 0
					end
					local k = idx(i, j)
					m[k] = math.max(m[k], mt.peak * t)
				end
			end
		end
		mtn = m

		-- sites: flat pads for towns, bases and HQs
		local s = {}
		for _, p in Data.Places do
			local r = if p.kind == "aoi"
					or p.kind == "enemy"
					or p.kind == "gated"
				then p.r or 120
				elseif p.kind == "hq" then (p.r or 100) + 10
				else nil
			if r then
				table.insert(s, { x = p.pos[1], y = p.pos[2], r = r })
			end
		end
		siteBuckets = {}
		for _, st in s do
			local R = st.r + PAD_BLEND
			for bx = math.floor((st.x - R) / BK), math.floor((st.x + R) / BK) do
				for by = math.floor((st.y - R) / BK), math.floor((st.y + R) / BK) do
					local key = by * 1000 + bx
					siteBuckets[key] = siteBuckets[key] or {}
					table.insert(siteBuckets[key], st)
				end
			end
		end
	end

	local function field(f: { number }, x: number, y: number): number
		local fx, fy = math.clamp(x / G, 0, NX - 1.001), math.clamp(y / G, 0, NY - 1.001)
		local i, j = math.floor(fx), math.floor(fy)
		local tx, ty = fx - i, fy - j
		local k = idx(i, j)
		return lerp(lerp(f[k], f[k + 1], tx), lerp(f[k + NX], f[k + NX + 1], tx), ty)
	end

	function Geo.coastDist(x: number, y: number): number
		prepare()
		return field(coast :: { number }, x, y)
	end

	function Geo.isLand(x: number, y: number): boolean
		return Geo.coastDist(x, y) > 0
	end

	-- Natural ground before sites, water and roads.
	local function natural(x: number, y: number): number
		local c = Geo.coastDist(x, y)
		if c < 0 then
			return -3 - 45 * smoothstep(-c / 700) + 3 * fbm(x / 300, y / 300, 2)
		end
		local inland = smoothstep(c / 1200)
		local base = 2 + 14 * smoothstep(c / 500)
		-- rolling country: broad swells, with hillier and flatter regions
		local region = smoothstep((fbm(x / 4200, y / 4200, 2) + 0.25) / 0.5)
		local roll = (fbm(x / 1700, y / 1700, 5) + 0.5) ^ 2 * (60 + 120 * region) * inland
		local small = 14 * fbm(x / 420, y / 420, 3) * inland
		local m = field(mtn :: { number }, x, y)
		if m > 0 then
			m *= 0.5 + 0.8 * ridged(x / 950, y / 950)
		end
		return base + roll + small + m + 2 * fbm(x / 80, y / 80, 2)
	end

	local siteCache: { [any]: number } = {}
	local function siteLevel(s: any): number
		local v = siteCache[s]
		if v == nil then
			v = math.max(natural(s.x, s.y), 4)
			siteCache[s] = v
		end
		return v :: number
	end

	-- Ground with site pads, lake, river and gorge carved; `noCarve` leaves the valleys uncut.
	local function shaped(x: number, y: number, noCarve: boolean?): number
		prepare()
		local h = natural(x, y)
		for _, s in siteBuckets[math.floor(y / BK) * 1000 + math.floor(x / BK)] or {} do
			local d = math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2)
			if d < s.r + PAD_BLEND then
				-- towns keep a little of the land's roll (90% flat)
				h = lerp(lerp(siteLevel(s), h, 0.1), h, smoothstep((d - s.r) / PAD_BLEND))
			end
		end
		if noCarve then
			return h
		end
		local lake = Data.Land.Lake
		if inBox(lakeBox, x, y) then
			if Geo.inside(Data.Land.G2Isle, x, y) then
				local d = Geo.lineDist(Data.Land.G2Isle, x, y, true)
				h = Data.LakeLevel + 3 + 12 * smoothstep(d / 120)
			else
				local d = Geo.lineDist(lake, x, y, true)
				if Geo.inside(lake, x, y) then
					h = Data.LakeLevel - 3 - 32 * smoothstep(d / 400)
				elseif d < 160 then
					h = lerp(
						Data.LakeLevel + 1.5,
						math.max(h, Data.LakeLevel + 1.5),
						smoothstep(d / 160)
					)
				end
			end
		end
		local rd, along = Geo.lineDist(Data.River, x, y, false)
		local half = Data.RiverWidth / 2
		if rd < half + 140 then
			local level = lerp(Data.LakeLevel, 0.5, along)
			local bed = level - 6
			if rd < half then
				h = math.min(h, lerp(bed, level - 1, smoothstep(rd / half)))
			else
				h = lerp(level + 1, math.max(h, level + 1), smoothstep((rd - half) / 140))
			end
		end
		local gd = Geo.lineDist(Data.Gorge, x, y, false)
		local gh = Data.GorgeWidth / 2
		if gd < gh then
			local floor = 18
			h = math.min(h, lerp(floor, h, smoothstep(gd / gh) ^ 1.5))
		end
		return h
	end

	-- water surface over a point, if any (sea 0, lake, river)
	function Geo.waterLevel(x: number, y: number): number?
		if not Geo.isLand(x, y) then
			return 0
		end
		if
			inBox(lakeBox, x, y)
			and Geo.inside(Data.Land.Lake, x, y)
			and not Geo.inside(Data.Land.G2Isle, x, y)
		then
			return Data.LakeLevel
		end
		local rd, along = Geo.lineDist(Data.River, x, y, false)
		if rd < Data.RiverWidth / 2 then
			return lerp(Data.LakeLevel, 0.5, along)
		end
		return nil
	end

	---------------------------------------------------------------- roads
	function Geo.edgePoints(e: any): { Pt }
		local pts = { Data.Nodes[e.a] }
		for _, p in e.via do
			table.insert(pts, p)
		end
		table.insert(pts, Data.Nodes[e.b])
		return pts
	end

	local function prepareRoads()
		if roadPts then
			return
		end
		prepare()
		local all, b = {}, {}
		local STEP = 16
		local rise = MAX_GRADE * STEP

		-- 1. sample each line and smooth the uncut ground along it (bridges keep the deck high)
		local function profile(pts: { Pt }): ({ any }, { number })
			local samples = {}
			for i = 1, #pts - 1 do
				local a, c = pts[i], pts[i + 1]
				local len = math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
				local n = math.max(1, math.ceil(len / STEP))
				for k = 0, n - (if i == #pts - 1 then 0 else 1) do
					local x, y = lerp(a[1], c[1], k / n), lerp(a[2], c[2], k / n)
					table.insert(samples, { x = x, y = y, h = math.max(shaped(x, y, true), 2.5) })
				end
			end
			local R = 6 -- +-96 studs moving average
			local sm = {}
			for i = 1, #samples do
				local s, n = 0, 0
				for k = math.max(1, i - R), math.min(#samples, i + R) do
					s += samples[k].h
					n += 1
				end
				sm[i] = s / n
			end
			-- cap the grade by cutting into the slope (these passes only ever lower the road)
			for i = 2, #sm do
				sm[i] = math.min(sm[i], sm[i - 1] + rise)
			end
			for i = #sm - 1, 1, -1 do
				sm[i] = math.min(sm[i], sm[i + 1] + rise)
			end
			return samples, sm
		end

		local lines = {}
		for _, e in Data.Edges do
			if e.kind ~= "tunnel" then
				local samples, sm = profile(Geo.edgePoints(e))
				table.insert(lines, {
					a = e.a,
					b = e.b,
					kind = e.kind,
					width = Data.RoadWidth[e.kind],
					samples = samples,
					sm = sm,
				})
			end
		end
		do
			local samples, sm = profile(Data.Rail)
			table.insert(lines, { kind = "rail", width = 8, samples = samples, sm = sm })
		end

		-- 2. every road meeting at a junction takes the same height there (the lowest of them)
		local nodeH: { [string]: number } = {}
		for _, l in lines do
			if l.a then
				nodeH[l.a] = math.min(nodeH[l.a] or math.huge, l.sm[1])
				nodeH[l.b] = math.min(nodeH[l.b] or math.huge, l.sm[#l.sm])
			end
		end

		-- re-cap the grade both ways (cut or fill) between pinned ends
		local function recap(sm: { number })
			for _ = 1, 2 do
				for i = 2, #sm - 1 do
					sm[i] = math.clamp(sm[i], sm[i - 1] - rise, sm[i - 1] + rise)
				end
				for i = #sm - 1, 2, -1 do
					sm[i] = math.clamp(sm[i], sm[i + 1] - rise, sm[i + 1] + rise)
				end
			end
		end

		local function addLine(l: any)
			local sm = l.sm
			local samples = l.samples
			for i = 1, #samples - 1 do
				local seg = {
					a = { samples[i].x, samples[i].y },
					b = { samples[i + 1].x, samples[i + 1].y },
					ha = sm[i],
					hb = sm[i + 1],
					kind = l.kind,
					half = l.width / 2,
				}
				table.insert(all, seg)
				local x0 = math.floor((math.min(seg.a[1], seg.b[1]) - 60) / BK)
				local x1 = math.floor((math.max(seg.a[1], seg.b[1]) + 60) / BK)
				local y0 = math.floor((math.min(seg.a[2], seg.b[2]) - 60) / BK)
				local y1 = math.floor((math.max(seg.a[2], seg.b[2]) + 60) / BK)
				for bx = x0, x1 do
					for by = y0, y1 do
						local key = by * 1000 + bx
						b[key] = b[key] or {}
						table.insert(b[key], seg)
					end
				end
			end
		end

		-- 3. pin the ends at the shared junction heights and join them smoothly
		for _, l in lines do
			if l.a then
				l.sm[1], l.sm[#l.sm] = nodeH[l.a], nodeH[l.b]
				recap(l.sm)
			end
			addLine(l)
		end

		-- 4. dirt roads and trails (Data.Dirt) join whatever road they start or end on at that
		-- road's height; they are not part of the planned route graph
		local function deckAt(x: number, y: number): (number, number)
			local best, bh = math.huge, 0
			for _, sg in b[math.floor(y / BK) * 1000 + math.floor(x / BK)] or {} do
				local d, t = segDist(x, y, sg.a, sg.b)
				if d - sg.half < best then
					best, bh = d - sg.half, lerp(sg.ha, sg.hb, t)
				end
			end
			return best, bh
		end
		for _, d in Data.Dirt or {} do
			local samples, sm = profile(d.pts)
			for _, i in { 1, #sm } do
				local gap, h = deckAt(samples[i].x, samples[i].y)
				if gap < 6 then
					sm[i] = h
				end
			end
			recap(sm)
			addLine({ kind = d.kind, width = Data.RoadWidth[d.kind], samples = samples, sm = sm })
		end
		roadPts = all
		buckets = b
	end

	-- Nearest road piece: distance, its deck height there, kind, half width.
	function Geo.nearestRoad(x: number, y: number): (number, number, string?, number)
		prepareRoads()
		local list = (buckets :: any)[math.floor(y / BK) * 1000 + math.floor(x / BK)]
		local best, bh, bk, bhalf = math.huge, 0, nil, 0
		if list then
			for _, s in list do
				local d, t = segDist(x, y, s.a, s.b)
				if d - s.half < best - bhalf then
					best, bh, bk, bhalf = d, lerp(s.ha, s.hb, t), s.kind, s.half
				end
			end
		end
		return best, bh, bk, bhalf
	end

	---------------------------------------------------------------- final ground
	local SHOULDER = 18

	-- Terrain surface height and what is on it:
	-- surface: "road" / "track" / "rail" / "shoulder" / nil;  bridge = true where a deck spans a cut.
	function Geo.sample(x: number, y: number): (number, string?, boolean)
		local h = shaped(x, y)
		local d, rh, kind, half = Geo.nearestRoad(x, y)
		if kind and d < half + SHOULDER then
			local cut = rh - h
			if
				cut > 4
				and d < half + 4
				and (
					Geo.waterLevel(x, y) ~= nil
					or (Geo.lineDist(Data.Gorge, x, y, false)) < Data.GorgeWidth / 2
				)
			then
				return h, nil, true -- a bridge deck spans water or the gorge; the ground stays cut
			end
			if h < 0 then
				return h, nil, false -- tracks that run out to sea (docks)
			end
			local w = 1 - smoothstep((d - half) / SHOULDER)
			h = lerp(h, rh, w)
			if d < half then
				return h,
					if kind == "track"
							or kind == "dirt"
							or kind == "trail"
						then "track"
						elseif kind == "rail" then "rail"
						else "road",
					false
			end
			return h, "shoulder", false
		end
		return h, nil, false
	end

	function Geo.height(x: number, y: number): number
		return (Geo.sample(x, y))
	end

	-- Road deck height (the surface a walker or truck uses on a road, bridges included).
	function Geo.roadHeight(x: number, y: number): number
		for _, e in Data.Edges do
			if e.kind == "tunnel" then
				-- the tunnel deck runs straight between its portals
				local a, c = Data.Nodes[e.a], Data.Nodes[e.b]
				local td, t = segDist(x, y, a, c)
				if td < Data.RoadWidth.tunnel / 2 and t > 0 and t < 1 then
					return lerp(
						Geo.roadHeight(a[1] - (c[1] - a[1]) * 0.01, a[2] - (c[2] - a[2]) * 0.01),
						Geo.roadHeight(c[1] + (c[1] - a[1]) * 0.01, c[2] + (c[2] - a[2]) * 0.01),
						t
					)
				end
			end
		end
		local d, rh, kind, half = Geo.nearestRoad(x, y)
		if kind and d < half + 2 then
			return rh
		end
		return Geo.height(x, y)
	end

	function Geo.zone(x: number, y: number): string
		if Geo.inside(Data.Autumn, x, y) then
			return "autumn"
		elseif (Geo.lineDist(Data.Autumn, x, y, true)) <= Data.FrostBand then
			return "frost"
		end
		return "winter"
	end

	-- Forest cover 0..1 (placeholder trees for now): broad noise patches with ragged edges; none
	-- on beaches, water, sites or above the tree line.
	function Geo.forest(x: number, y: number): number
		prepare()
		local c = Geo.coastDist(x, y)
		if c < 50 or Geo.waterLevel(x, y) then
			return 0
		end
		local n = fbm(x / 1300 + 3.7, y / 1300 - 8.1, 3) + 0.35 * fbm(x / 260, y / 260, 2)
		local f = smoothstep((n - FOREST_AT) / 0.22)
		-- named forests (Data.Forests): dense inside a ragged edge, with clearings
		for _, fo in Data.Forests or {} do
			fo.box = fo.box or bbox(fo.poly, 0)
			if inBox(fo.box, x, y) and Geo.inside(fo.poly, x, y) then
				local d = Geo.lineDist(fo.poly, x, y, true)
				local edge = smoothstep((d + 70 * fbm(x / 150, y / 150, 2)) / 220)
				local clear = smoothstep((fbm(x / 450 + 11.3, y / 450 - 4.1, 2) - 0.2) / 0.08)
				f = lerp(f, fo.density * (1 - clear), edge)
			end
		end
		f *= smoothstep((c - 50) / 150)
		f *= 1 - smoothstep((natural(x, y) - 230) / 70)
		for _, st in siteBuckets[math.floor(y / BK) * 1000 + math.floor(x / BK)] or {} do
			local d = math.sqrt((x - st.x) ^ 2 + (y - st.y) ^ 2)
			f *= smoothstep((d - st.r) / 80)
		end
		return f
	end

	function Geo.cell(x: number, y: number): string
		local c = Data.Frame.cell
		return string.format("c%02d r%02d", math.floor(x / c) + 1, math.floor(y / c) + 1)
	end

	function Geo.length(pts: { Pt }): number
		local s = 0
		for i = 2, #pts do
			s += math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		end
		return s
	end

	-- Shortest road path from node a to node b: length and the points along it.
	function Geo.route(a: string, b: string): (number, { Pt })
		local adj: { [string]: { any } } = {}
		for _, e in Data.Edges do
			local pts = Geo.edgePoints(e)
			local len = Geo.length(pts)
			local rev = table.clone(pts)
			for i = 1, #rev // 2 do
				rev[i], rev[#rev - i + 1] = rev[#rev - i + 1], rev[i]
			end
			adj[e.a] = adj[e.a] or {}
			adj[e.b] = adj[e.b] or {}
			table.insert(adj[e.a], { to = e.b, len = len, pts = pts })
			table.insert(adj[e.b], { to = e.a, len = len, pts = rev })
		end
		local dist: { [string]: number } = { [a] = 0 }
		local prev: { [string]: any } = {}
		local done: { [string]: boolean } = {}
		while true do
			local u: string? = nil
			for k, v in dist do
				if not done[k] and (u == nil or v < dist[u :: string]) then
					u = k
				end
			end
			if u == nil then
				return math.huge, {}
			end
			if u == b then
				break
			end
			done[u] = true
			for _, ed in adj[u] or {} do
				local nd = dist[u] + ed.len
				if dist[ed.to] == nil or nd < dist[ed.to] then
					dist[ed.to] = nd
					prev[ed.to] = { from = u, pts = ed.pts }
				end
			end
		end
		local chain = {}
		local at = b
		while prev[at] do
			table.insert(chain, 1, prev[at].pts)
			at = prev[at].from
		end
		local pts: { Pt } = { Data.Nodes[a] }
		for _, seg in chain do
			for i = 2, #seg do
				table.insert(pts, seg[i])
			end
		end
		return dist[b], pts
	end

	return Geo
end
