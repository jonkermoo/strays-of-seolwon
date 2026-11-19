--!strict
-- Map maths over the layout data: land test, ground height, season zone, road routes.
-- Pure Luau (no Roblox objects), so Lune can run it. Use: local Geo = require(Geo)(Data)

type Pt = { number }

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function segDist(px: number, py: number, a: Pt, b: Pt): number
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dy * dy
	local t = if len2 > 0 then math.clamp(((px - a[1]) * dx + (py - a[2]) * dy) / len2, 0, 1) else 0
	local cx, cy = a[1] + t * dx, a[2] + t * dy
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

return function(Data: any)
	local Geo = {}

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

	-- Distance to a polyline (closed = polygon edge).
	function Geo.lineDist(pts: { Pt }, x: number, y: number, closed: boolean?): number
		local best = math.huge
		for i = 1, #pts - 1 do
			best = math.min(best, segDist(x, y, pts[i], pts[i + 1]))
		end
		if closed and #pts > 2 then
			best = math.min(best, segDist(x, y, pts[#pts], pts[1]))
		end
		return best
	end

	function Geo.isLand(x: number, y: number): boolean
		local c = false
		for _, name in Data.LandOrder do
			if Geo.inside(Data.Land[name], x, y) then
				c = not c
			end
		end
		return c
	end

	-- Sorted x where the row y crosses a coastline; land is between pairs (even-odd).
	function Geo.crossings(y: number): { number }
		local xs = {}
		for _, name in Data.LandOrder do
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

	-- Ground height above the land top (studs). 0 on the lowlands. `noGorge` gives the ridge as if
	-- uncut: roads use it, so the artery crosses the gorge on a bridge at ridge height.
	function Geo.height(x: number, y: number, noGorge: boolean?): number
		local h = 0
		for _, m in Data.Mountains do
			if Geo.inside(m.poly, x, y) then
				local d = Geo.lineDist(m.poly, x, y, true)
				h = math.max(h, m.peak * smoothstep(d / (m.falloff or Data.Falloff)))
			end
		end
		if h > 0 and not noGorge then
			-- The gorge cuts through the ridge under the artery.
			local g = Geo.lineDist(Data.Gorge, x, y, false)
			local half = Data.GorgeWidth / 2
			h *= smoothstep((g - half * 0.5) / (half * 1.5))
		end
		return h
	end

	-- Height of the drawn hill surface: triangles on the HillGrid (cell split corner 00 to 11).
	-- Chords sit a little above the true curve in places, so roads take the higher of the two.
	function Geo.surfaceHeight(x: number, y: number): number
		local G = Data.HillGrid
		local i, j = math.floor(x / G), math.floor(y / G)
		local fx, fy = x / G - i, y / G - j
		local h00, h10 = Geo.height(i * G, j * G), Geo.height((i + 1) * G, j * G)
		local h01, h11 = Geo.height(i * G, (j + 1) * G), Geo.height((i + 1) * G, (j + 1) * G)
		if fx >= fy then
			return h00 + fx * (h10 - h00) + fy * (h11 - h10)
		end
		return h00 + fy * (h01 - h00) + fx * (h11 - h01)
	end

	-- Road surface: the uncut ridge (so the artery bridges the gorge), never under the hill mesh.
	function Geo.roadHeight(x: number, y: number): number
		return math.max(Geo.height(x, y, true), Geo.surfaceHeight(x, y))
	end

	function Geo.zone(x: number, y: number): string
		if Geo.inside(Data.Autumn, x, y) then
			return "autumn"
		elseif Geo.lineDist(Data.Autumn, x, y, true) <= Data.FrostBand then
			return "frost"
		end
		return "winter"
	end

	function Geo.cell(x: number, y: number): string
		local c = Data.Frame.cell
		return string.format("c%02d r%02d", math.floor(x / c) + 1, math.floor(y / c) + 1)
	end

	function Geo.edgePoints(e: any): { Pt }
		local pts = { Data.Nodes[e.a] }
		for _, p in e.via do
			table.insert(pts, p)
		end
		table.insert(pts, Data.Nodes[e.b])
		return pts
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
