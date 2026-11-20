--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Data = require("../src/shared/Map/Data")
local Geo = require("../src/shared/Map/Geo")(Data)

local function node(id: string): (number, number)
	local p = Data.Nodes[id]
	return p[1], p[2]
end

return {
	["every planned route has the recorded road length"] = function()
		for _, id in Data.Routes do
			local len = Geo.route("HQ1", id)
			assert(
				math.abs(len - Data.PlanRoadLength[id]) <= 1,
				`{id}: {len} vs {Data.PlanRoadLength[id]}`
			)
		end
		local len = Geo.route("HQ2", "S3")
		assert(math.abs(len - Data.PlanRoadLength.HQ2_S3) <= 1, "HQ2 to S3")
	end,
	["route points start and end at the nodes"] = function()
		local _, pts = Geo.route("HQ1", "NC")
		assert(pts[1] == Data.Nodes.HQ1 and pts[#pts] == Data.Nodes.NC, "ends")
	end,
	["towns are on dry land; the lake and the channel are water"] = function()
		for _, id in { "HQ1", "HQ2", "PORT", "NC", "SW" } do -- River Town spans the river
			local x, y = node(id)
			assert(Geo.isLand(x, y), id)
			assert(Geo.height(x, y) > 2, id .. " above the sea")
		end
		assert(Geo.waterLevel(4621, 4621) == Data.LakeLevel, "lake")
		assert(Geo.waterLevel(4957, 4495) == nil, "G2 isle is dry")
		assert(Geo.waterLevel(9103, 6582) == 0, "Sawmill channel is sea")
	end,
	["HQ 1 is autumn, North City is winter"] = function()
		local x, y = node("HQ1")
		assert(Geo.zone(x, y) == "autumn", "HQ1")
		x, y = node("NC")
		assert(Geo.zone(x, y) == "winter", "NC")
	end,
	["mountains stand above the lowlands; off the frame is sea"] = function()
		assert(Geo.height(7842, -280) < 0, "sea")
		local poly = Data.Mountains[1].poly
		local mx, my = 0, 0
		for _, p in poly do
			mx += p[1] / #poly
			my += p[2] / #poly
		end
		assert(Geo.height(mx, my) > 150, "north-west peaks are high in the middle")
	end,
	["every place has a unique id and is on the frame"] = function()
		local seen = {}
		local f = Data.Frame
		for _, p in Data.Places do
			assert(not seen[p.id], p.id)
			seen[p.id] = true
			assert(
				p.pos[1] >= 0 and p.pos[1] <= f.width and p.pos[2] >= 0 and p.pos[2] <= f.height,
				p.id
			)
		end
	end,
	["dirt roads and trails start on a road; loops join two road nodes"] = function()
		local main = table.clone(Data)
		main.Dirt = {}
		local GeoMain = require("../src/shared/Map/Geo")(main)
		for i, d in Data.Dirt do
			local p = d.pts[1]
			local dd, _, kind, half = GeoMain.nearestRoad(p[1], p[2])
			local ok = kind ~= nil and dd < half + 10
			for k = 1, i - 1 do
				ok = ok or (Geo.lineDist(Data.Dirt[k].pts, p[1], p[2], false)) < 12
			end
			assert(ok, `{d.use} starts off the roads at {p[1]}, {p[2]}`)
			assert(d.kind == "dirt" or d.kind == "trail", d.use)
		end
	end,
	["countryside buildings stay dry and off the roads; loot sits by its building"] = function()
		assert(#Data.Buildings >= 100, "about 120 buildings")
		for _, b in Data.Buildings do
			local x, y = b.pos[1], b.pos[2]
			assert(Geo.isLand(x, y) and not Geo.waterLevel(x, y), `{b.kind} at {x}, {y} is wet`)
			local d, _, kind, half = Geo.nearestRoad(x, y)
			assert(not kind or d > half + 4, `{b.kind} at {x}, {y} is on a road`)
			for _, l in b.loot do
				local r = math.sqrt((l[1] - x) ^ 2 + (l[2] - y) ^ 2)
				assert(r < math.max(b.size[1], b.size[2]) / 2 + 6, `loot by {b.kind} at {x}, {y}`)
			end
		end
	end,
	["forests grow on land, not in the lake or on town pads"] = function()
		assert(Geo.forest(4621, 4621) == 0, "lake")
		local nc = Data.Nodes.NC
		assert(Geo.forest(nc[1], nc[2]) == 0, "North City")
		local any = 0
		for y = 500, Data.Frame.height, 500 do
			for x = 500, Data.Frame.width, 500 do
				any += if Geo.forest(x, y) > 0.5 then 1 else 0
			end
		end
		assert(any > 40, "some forest")
	end,
	["the map frame centres on the 4-stud terrain voxel grid"] = function()
		-- terrain is written in 4-stud voxels from world X = x - width / 2: an off-grid half
		-- width makes WriteVoxels fail ("65-element array expected")
		assert(
			Data.Frame.width / 2 % 4 == 0 and Data.Frame.height / 2 % 4 == 0,
			"frame / 2 on the grid"
		)
	end,
}
