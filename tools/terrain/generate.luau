--!strict
-- Seolwon terrain generator (Studio, Edit). Terrain can't come from Rojo, so it is generated
-- once in a Studio copy of the place, saved, and merged into builds (tools/terrain/merge.luau).
-- How to run (Studio MCP execute_luau, Edit): put this file's Source into a ModuleScript
-- ServerStorage.TerrainGen, then in a task.spawn: require(TerrainGen:Clone())(nil, nil, nil, nil, true)
-- and poll the Workspace attribute TerrainGen ("chunk n/N", then "done <seconds>"); an MCP call
-- times out after about a minute. Whole map: ~3 minutes. Arguments: chunk range (ci0, ci1,
-- cj0, cj1; nil = all) and `clear` (wipe and refill the sea first).
-- It reads Data and Geo from the synced ReplicatedStorage.Shared.Map, so Studio and Lune build
-- the same ground. Rock below a surface band of voxels; materials by slope, height, season and
-- roads; forest floors; sea / lake / river water. Map (x, y) -> world X = x - W/2, Z = y - H/2 (Geo.world).

return function(CI0: number?, CI1: number?, CJ0: number?, CJ1: number?, clear: boolean?)
	local Map = game:GetService("ReplicatedStorage").Shared.Map
	local Data = require(Map.Data:Clone()) :: any
	local Geo = require(Map.Geo:Clone())(Data)
	local Terrain = workspace.Terrain
	local M = Enum.Material
	local W, H = Data.Frame.width, Data.Frame.height
	local V = 4 -- voxel size
	local CH = 64 -- columns per chunk side (256 studs)
	local FLOOR = -64 -- bottom of the solid fill

	-- muted late-autumn / winter palette (placeholder until the style bible)
	local COLORS = {
		[M.Grass] = Color3.fromRGB(128, 118, 66),
		[M.LeafyGrass] = Color3.fromRGB(120, 108, 64),
		[M.Ground] = Color3.fromRGB(108, 92, 72),
		[M.Slate] = Color3.fromRGB(112, 110, 106),
		[M.Rock] = Color3.fromRGB(122, 120, 114),
		[M.Asphalt] = Color3.fromRGB(62, 62, 64),
		[M.Sand] = Color3.fromRGB(186, 172, 136),
		[M.Mud] = Color3.fromRGB(78, 70, 58),
	}
	for mat, col in COLORS do
		Terrain:SetMaterialColor(mat, col)
	end

	local function surfaceMaterial(
		x: number,
		y: number,
		h: number,
		slope: number,
		surf: string?,
		water: number?
	): Enum.Material
		if surf == "road" then
			return M.Asphalt
		elseif surf == "track" then
			return M.Ground
		elseif surf == "rail" then
			return M.Slate
		end
		if water and h < water - 0.5 then
			return if water == 0 and h > -14 then M.Sand else M.Mud
		end
		if slope > 42 then
			return M.Rock
		end
		if h > 420 then
			return M.Snow
		end
		if slope > 33 then
			return M.Slate
		end
		if Geo.coastDist(x, y) < 70 and h < 7 then
			return M.Sand
		end
		if surf == "shoulder" then
			return M.Ground
		end
		local z = Geo.zone(x, y)
		local n = math.noise(x / 140, y / 140, 7.7)
		if Geo.forest(x, y) > 0.55 then
			-- forest floor: leaf litter in sector B, needle-bare patches under the snow
			if z == "autumn" then
				return if n > 0.25 then M.Ground else M.LeafyGrass
			elseif n > 0.05 then
				return M.Ground
			end
		end
		if z == "autumn" then
			if n > 0.42 then
				return M.Ground -- harvested fields
			elseif n < -0.3 then
				return M.LeafyGrass
			end
			return M.Grass
		elseif z == "frost" then
			-- patchy snow, thicker away from sector B
			local d = (Geo.lineDist(Data.Autumn, x, y, true))
			if n + (d / Data.FrostBand) * 1.2 - 0.6 > 0 then
				return M.Snow
			end
			return if n < -0.35 then M.Ground else M.Grass
		end
		if slope > 26 and n > 0.2 then
			return M.Slate
		end
		return M.Snow
	end

	local t0 = os.clock()
	if clear then
		Terrain:Clear()
		-- the sea: water from the floor up to Y = 0 over the frame plus a margin (4096 tiles;
		-- one big FillBlock fails with "Extents are too large")
		local T = 4096
		for X = -W / 2 - 2048, W / 2 + 2048 - 1, T do
			for Z = -H / 2 - 2048, H / 2 + 2048 - 1, T do
				Terrain:FillBlock(
					CFrame.new(X + T / 2, FLOOR / 2, Z + T / 2),
					Vector3.new(T, -FLOOR, T),
					M.Water
				)
				Terrain:FillBlock(
					CFrame.new(X + T / 2, FLOOR - 4, Z + T / 2),
					Vector3.new(T, 8, T),
					M.Mud
				)
			end
			task.wait()
		end
	end

	local NXC, NYC = math.ceil(W / (CH * V)), math.ceil(H / (CH * V))
	local ci0, ci1, cj0, cj1 = CI0 or 0, CI1 or NXC - 1, CJ0 or 0, CJ1 or NYC - 1
	local total = (ci1 - ci0 + 1) * (cj1 - cj0 + 1)
	local done = 0
	for cj = cj0, cj1 do
		for ci = ci0, ci1 do
			local x0, y0 = ci * CH * V, cj * CH * V
			-- heights on a (CH+2)^2 grid of column centres (one ring extra for slopes)
			local hs, surfs, waters = {}, {}, {}
			local hmin, hmax, wmax = math.huge, -math.huge, -math.huge
			for k = 0, CH + 1 do
				for i = 0, CH + 1 do
					local x, y = x0 + (i - 1) * V + V / 2, y0 + (k - 1) * V + V / 2
					local h, surf = Geo.sample(x, y)
					local idx = k * (CH + 2) + i + 1
					hs[idx] = h
					if i >= 1 and i <= CH and k >= 1 and k <= CH then
						surfs[idx] = surf or false
						local wl = Geo.waterLevel(x, y)
						waters[idx] = wl or false
						hmin = math.min(hmin, h)
						hmax = math.max(hmax, h)
						if wl then
							wmax = math.max(wmax, wl)
						end
					end
				end
			end
			if hmax < -6 and wmax <= 0 then
				-- open sea: the water fill is already there; lay the sea floor only
				local X, Z = Geo.world(x0 + CH * V / 2, y0 + CH * V / 2)
				local fl = math.floor(hmin / V) * V
				if fl > FLOOR then
					Terrain:FillBlock(
						CFrame.new(X, (FLOOR + fl) / 2, Z),
						Vector3.new(CH * V, fl - FLOOR, CH * V),
						M.Mud
					)
				end
			else
				local yLo = math.max(FLOOR, math.floor((hmin - 8) / V) * V)
				local yHi = math.ceil((math.max(hmax, wmax) + V) / V) * V
				if yLo > FLOOR then
					-- solid rock below the band
					local X, Z = Geo.world(x0 + CH * V / 2, y0 + CH * V / 2)
					Terrain:FillBlock(
						CFrame.new(X, (FLOOR + yLo) / 2, Z),
						Vector3.new(CH * V, yLo - FLOOR, CH * V),
						M.Rock
					)
				end
				local ny = (yHi - yLo) // V
				local mats, occs = table.create(CH), table.create(CH)
				for i = 1, CH do
					local mi, oi = table.create(ny), table.create(ny)
					for j = 1, ny do
						mi[j] = table.create(CH, M.Air)
						oi[j] = table.create(CH, 0)
					end
					mats[i], occs[i] = mi, oi
				end
				for k = 1, CH do
					for i = 1, CH do
						local idx = k * (CH + 2) + i + 1
						local h = hs[idx]
						local dx = hs[idx + 1] - hs[idx - 1]
						local dz = hs[idx + CH + 2] - hs[idx - CH - 2]
						local slope = math.deg(math.atan(math.sqrt(dx * dx + dz * dz) / (2 * V)))
						local x, y = x0 + (i - 1) * V + V / 2, y0 + (k - 1) * V + V / 2
						local wl = waters[idx] or nil
						local surf = surfs[idx] or nil
						local top = surfaceMaterial(x, y, h, slope, surf, wl)
						local under = if slope > 33 then M.Rock else M.Ground
						for j = 1, ny do
							local yb = yLo + (j - 1) * V
							local occ = math.clamp((h - yb) / V, 0, 1)
							if occ > 0 then
								mats[i][j][k] = if h - yb < V * 2 then top else under
								occs[i][j][k] = occ
							elseif wl and yb < wl then
								mats[i][j][k] = M.Water
								occs[i][j][k] = math.clamp((wl - yb) / V, 0.05, 1)
							end
						end
					end
				end
				local X0, Z0 = Geo.world(x0, y0)
				local region = Region3.new(
					Vector3.new(X0, yLo, Z0),
					Vector3.new(X0 + CH * V, yHi, Z0 + CH * V)
				)
				Terrain:WriteVoxels(region:ExpandToGrid(V), V, mats, occs)
			end
			done += 1
			if done % 2 == 0 then
				workspace:SetAttribute(
					"TerrainGen",
					string.format("chunk %d/%d %.0fs", done, total, os.clock() - t0)
				)
				task.wait()
			end
		end
	end
	workspace:SetAttribute("TerrainGen", string.format("done %.0f", os.clock() - t0))
end
