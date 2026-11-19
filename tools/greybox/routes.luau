--!strict
-- Offline route check over the built ground: length along the slopes, steepest grade,
-- foot and truck times at the plan's speeds. Run: lune run tools/greybox/routes
local Data = require("../../src/shared/Map/Data")
local Geo = require("../../src/shared/Map/Geo")(Data)
local Metrics = require("../../src/shared/Map/Metrics")

local function mmss(s: number): string
	local r = math.floor(s + 0.5)
	return string.format("%d:%02d", r // 60, r % 60)
end

local function check(from: string, to: string)
	local planLen, pts = Geo.route(from, to)
	local len3, maxGrade, steep = 0, 0, 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.ceil(d / 16))
		local px, py = a[1], a[2]
		local ph = Geo.roadHeight(px, py)
		for k = 1, n do
			local x, y = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
			local h = Geo.roadHeight(x, y)
			local run = d / n
			local grade = math.deg(math.atan(math.abs(h - ph) / run))
			maxGrade = math.max(maxGrade, grade)
			if grade > Metrics.Vehicle.maxSlope then
				steep += run
			end
			len3 += math.sqrt(run * run + (h - ph) ^ 2)
			px, py, ph = x, y, h
		end
	end
	print(
		string.format(
			"%-10s plan %5d  built %5d  foot %s (plan %s)  truck %s (plan %s)  max grade %4.1f deg  over %d deg: %d studs",
			`{from}-{to}`,
			planLen,
			len3,
			mmss(len3 / Data.Speed.foot),
			mmss(planLen / Data.Speed.foot),
			mmss(len3 / Data.Speed.truck),
			mmss(planLen / Data.Speed.truck),
			maxGrade,
			Metrics.Vehicle.maxSlope,
			steep
		)
	)
end

for _, id in Data.Routes do
	check("HQ1", id)
end
check("HQ2", "S3")
