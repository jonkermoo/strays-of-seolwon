--!strict
-- Studio-only greybox check: one R6 dummy per planned route walks the built roads at sprint
-- speed and the real times are printed. Runs when the Workspace attribute RouteTest = true.
-- Output: one "ROUTETEST <json>" line per route, then "ROUTETEST DONE".
-- Times are game time (DistributedGameTime): a background Studio window pauses the game.
local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = ReplicatedStorage.Shared.Map
local Data = require(Map.Data)
local Geo = require(Map.Geo)(Data)
local Metrics = require(Map.Metrics)

local RouteTest = {}

local function now(): number
	return workspace.DistributedGameTime
end

local STEP = 40 -- studs between waypoints
local STUCK_AFTER = 6 -- seconds without reaching a waypoint

local function waypoints(pts: { { number } }): { Vector3 }
	local out = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.ceil(len / STEP))
		for k = 1, n do
			local x = a[1] + (b[1] - a[1]) * k / n
			local y = a[2] + (b[2] - a[2]) * k / n
			local X, Z = Geo.world(x, y)
			table.insert(out, Vector3.new(X, Geo.roadHeight(x, y), Z))
		end
	end
	return out
end

local function walk(from: string, to: string, results: { any })
	local planLen, pts = Geo.route(from, to)
	local wps = waypoints(pts)
	local dummy = Players:CreateHumanoidModelFromDescription(
		Instance.new("HumanoidDescription"),
		Enum.HumanoidRigType.R6
	)
	dummy.Name = `RouteDummy_{from}_{to}`
	for _, d in dummy:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "RouteDummy"
		end
	end
	local hum = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart
	hum.WalkSpeed = Metrics.Player.sprint
	local s = Data.Nodes[from]
	local sX, sZ = Geo.world(s[1], s[2])
	dummy:PivotTo(CFrame.new(sX, Geo.roadHeight(s[1], s[2]) + 4, sZ))
	dummy.Parent = workspace
	root:SetNetworkOwner(nil)
	task.wait(1)

	local t0 = now()
	local stuck = {}
	for i, wp in wps do
		local started = now()
		hum:MoveTo(wp)
		while true do
			local pos = root.Position
			if Vector3.new(pos.X - wp.X, 0, pos.Z - wp.Z).Magnitude < 4 then
				break
			end
			if now() - started > STUCK_AFTER then
				-- Note where it got stuck, then put it on the waypoint and go on.
				local mx, my = Geo.map(wp.X, wp.Z)
				table.insert(stuck, { i = i, x = math.floor(mx), y = math.floor(my) })
				dummy:PivotTo(CFrame.new(wp + Vector3.new(0, 4, 0)))
				break
			end
			if hum.FloorMaterial == Enum.Material.Air and root.Position.Y < -20 then
				table.insert(
					stuck,
					{ i = i, x = math.floor(wp.X), z = math.floor(wp.Z), fell = true }
				)
				dummy:PivotTo(CFrame.new(wp + Vector3.new(0, 4, 0)))
				break
			end
			task.wait(0.1)
		end
	end
	local secs = now() - t0
	local row = {
		route = `{from}-{to}`,
		planLength = math.floor(planLen),
		planFoot = math.floor(planLen / Data.Speed.foot),
		walked = math.floor(secs),
		stuck = stuck,
	}
	table.insert(results, row)
	print("ROUTETEST " .. HttpService:JSONEncode(row))
	dummy:Destroy()
end

function RouteTest.run()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("RouteDummy")
	end)
	PhysicsService:CollisionGroupSetCollidable("RouteDummy", "RouteDummy", false)
	local results = {}
	local pairs_ = {}
	-- Optional Workspace attribute RouteTestOnly = "RT,S1" walks just those routes.
	local only = workspace:GetAttribute("RouteTestOnly")
	for _, id in Data.Routes do
		if type(only) ~= "string" or table.find(string.split(only, ","), id) then
			table.insert(pairs_, { "HQ1", id })
		end
	end
	if type(only) ~= "string" then
		table.insert(pairs_, { "HQ2", "S3" })
	end
	local left = #pairs_
	for _, p in pairs_ do
		task.spawn(function()
			local ok, err = pcall(walk, p[1], p[2], results)
			if not ok then
				print(`ROUTETEST ERROR {p[1]}-{p[2]} {err}`)
			end
			left -= 1
		end)
	end
	while left > 0 do
		task.wait(1)
	end
	workspace:SetAttribute("RouteTestResult", HttpService:JSONEncode(results))
	print("ROUTETEST DONE")
end

return RouteTest
