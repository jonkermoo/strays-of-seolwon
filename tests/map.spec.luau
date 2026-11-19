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
		assert(Geo.waterLevel(8250, 8250) == Data.LakeLevel, "lake")
		assert(Geo.waterLevel(8850, 8025) == nil, "G2 isle is dry")
		assert(Geo.waterLevel(16250, 11750) == 0, "Sawmill channel is sea")
	end,
	["HQ 1 is autumn, North City is winter"] = function()
		local x, y = node("HQ1")
		assert(Geo.zone(x, y) == "autumn", "HQ1")
		x, y = node("NC")
		assert(Geo.zone(x, y) == "winter", "NC")
	end,
	["mountains stand above the lowlands; off the frame is sea"] = function()
		assert(Geo.height(14000, -500) < 0, "sea")
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
}
