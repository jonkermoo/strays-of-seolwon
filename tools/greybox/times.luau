--!strict
-- Travel-time estimates from each HQ to every site on the map, walking and driving, over all
-- roads, dirt roads and trails (shortest time, so a truck prefers fast roads and a walker the
-- shortest way), plus an off-road leg from the nearest road to the spot.
-- Run from the repo root: lune run tools/greybox/times   (prints a Markdown table)
-- Estimates, not driven: no slope, traffic, enemies or stops. The Citadel (X1) counts its
-- bridge as repaired. Speeds: Data.Speed. Optional argument: a speed multiplier to try.
local Data = require("../../src/shared/Map/Data")
local Geo = require("../../src/shared/Map/Geo")(Data)

type Pt = { number }

local WALK = Data.Speed.foot -- studs/s, sprinting
local process = require("@lune/process")
local S = Data.Speed.drive -- studs/s by surface for a truck
local scale = tonumber(process.args[1]) or 1 -- try faster / slower trucks: lune run ... 1.5
local DRIVE = {
	artery = S.paved * scale,
	road = S.paved * scale,
	tunnel = S.paved * scale,
	track = S.track * scale,
	dirt = S.dirt * scale,
	trail = S.trail * scale,
}
local OFFROAD_DRIVE = S.offroad * scale -- across open ground from the nearest road

-- graph: vertices every <= 40 studs along every line; shared points merge
local verts: { Pt } = {}
local key: { [string]: number } = {}
local adj: { [number]: { { number } } } = {} -- {to, length, driveSpeed}
local function vert(p: Pt): number
	local k = string.format("%d,%d", math.floor(p[1] / 8 + 0.5), math.floor(p[2] / 8 + 0.5))
	local v = key[k]
	if not v then
		table.insert(verts, p)
		v = #verts
		key[k] = v
		adj[v] = {}
	end
	return v
end
local function link(a: number, b: number, len: number, speed: number)
	table.insert(adj[a], { b, len, speed })
	table.insert(adj[b], { a, len, speed })
end
local function addLine(pts: { Pt }, speed: number)
	local prev = vert(pts[1])
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.ceil(len / 40))
		for k = 1, n do
			local v = vert({ a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n })
			if v ~= prev then
				link(prev, v, len / n, speed)
			end
			prev = v
		end
	end
end
for _, e in Data.Edges do
	addLine(Geo.edgePoints(e), DRIVE[e.kind])
end
-- the Citadel bridge is down at the start; times assume it has been repaired (or bridged)
for _, p in Data.Places do
	if p.id == "X1" then
		addLine({ Data.Nodes.CB, p.pos }, DRIVE.road)
	end
end
local own: { [number]: { [number]: boolean } } = {} -- each dirt line's own vertices
for i, d in Data.Dirt or {} do
	local before = #verts
	addLine(d.pts, DRIVE[d.kind])
	own[i] = {}
	for v = before + 1, #verts do
		own[i][v] = true
	end
	own[i][vert(d.pts[1])] = true
	own[i][vert(d.pts[#d.pts])] = true
end
-- dirt roads start / end on another line: join each end to the nearest vertex
local function nearest(p: Pt, upto: number?): (number, number)
	local best, bd = 1, math.huge
	for i = 1, upto or #verts do
		local q = verts[i]
		local d = (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2
		if d < bd then
			best, bd = i, d
		end
	end
	return best, math.sqrt(bd)
end
for li, d in Data.Dirt or {} do
	for _, p in { d.pts[1], d.pts[#d.pts] } do
		local v = vert(p)
		local best, bd = math.huge, math.huge
		for i = 1, #verts do
			if not own[li][i] then
				local q = verts[i]
				local dd = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
				if dd < bd then
					best, bd = i, dd
				end
			end
		end
		if bd < 40 and bd > 0 then
			link(v, best, bd, DRIVE[d.kind])
		end
	end
end

-- Dijkstra by time; `speedOf(edgeSpeed)` picks walk or drive
local function times(from: number, walk: boolean): { number }
	local t: { number } = table.create(#verts, math.huge)
	t[from] = 0
	local heap: { { number } } = { { 0, from } }
	while #heap > 0 do
		-- small graph: a simple binary heap
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
		local c, u = top[1], top[2]
		if c <= t[u] then
			for _, e in adj[u] do
				local nc = c + e[2] / (if walk then WALK else e[3])
				if nc < t[e[1]] then
					t[e[1]] = nc
					table.insert(heap, { nc, e[1] })
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
			end
		end
	end
	return t
end

local function mmss(s: number): string
	s = math.floor(s + 0.5)
	return string.format("%d:%02d", s // 60, s % 60)
end

local hq = {}
for _, id in { "HQ1", "HQ2" } do
	local p = Data.Nodes[id]
	local v = nearest(p)
	hq[id] = { walk = times(v, true), drive = times(v, false) }
end

local worst, worstName = 0, ""
print("| Spot | Cell | HQ 1 walk | HQ 1 drive | HQ 2 walk | HQ 2 drive |")
print("|---|---|---|---|---|---|")
for _, p in Data.Places do
	if not p.site then
		local v, off = nearest(p.pos)
		local row = { p.name, Geo.cell(p.pos[1], p.pos[2]) }
		for _, id in { "HQ1", "HQ2" } do
			local w = hq[id].walk[v] + off / WALK
			local d = hq[id].drive[v] + off / OFFROAD_DRIVE
			table.insert(row, mmss(w))
			table.insert(row, mmss(d))
			if d > worst then
				worst, worstName = d, `{id} to {p.name}`
			end
		end
		print("| " .. table.concat(row, " | ") .. " |")
	end
end
print("")
print(`Longest drive: {mmss(worst)} ({worstName})`)
