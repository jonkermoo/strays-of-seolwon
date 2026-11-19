--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Data = require("../src/shared/Map/Data")
local Geo = require("../src/shared/Map/Geo")(Data)

return {
	["every planned route has the plan's road length"] = function()
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
	["HQs and towns are on land, the lake is not, G2 isle is"] = function()
		for _, id in { "HQ1", "HQ2", "PORT", "NC", "RT", "SW" } do
			local p = Data.Nodes[id]
			assert(Geo.isLand(p[1], p[2]), id)
		end
		assert(not Geo.isLand(3300, 3300), "lake")
		assert(Geo.isLand(3540, 3210), "G2 isle")
		assert(not Geo.isLand(6500, 4700), "channel")
	end,
	["HQ 1 is autumn, North City is winter"] = function()
		assert(Geo.zone(2050, 6300) == "autumn", "HQ1")
		assert(Geo.zone(3650, 1750) == "winter", "NC")
	end,
	["HQ 1 sits on its hill; lowlands are flat"] = function()
		assert(Geo.height(2050, 6300) > 10, "HQ1 hill")
		assert(Geo.height(3700, 5250) == 0, "River Town")
	end,
	["every place has a unique id and is on the frame"] = function()
		local seen = {}
		for _, p in Data.Places do
			assert(not seen[p.id], p.id)
			seen[p.id] = true
			assert(p.pos[1] >= 0 and p.pos[1] <= 8192 and p.pos[2] >= 0 and p.pos[2] <= 7168, p.id)
		end
	end,
}
