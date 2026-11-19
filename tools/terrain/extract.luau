--!strict
-- Takes the terrain out of a Studio-saved place (after tools/terrain/generate.luau ran in it) and
-- writes assets/Terrain.rbxl: a place holding only that terrain. Builds copy it in with
-- tools/terrain/merge.luau. Run: lune run tools/terrain/extract <saved.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local src = process.args[1]
assert(src, "usage: lune run tools/terrain/extract <saved.rbxl>")
local place = roblox.deserializePlace(fs.readFile(src))
local terrain = place:GetService("Workspace"):FindFirstChildOfClass("Terrain")
assert(terrain, "no terrain in " .. src)

local out = roblox.Instance.new("DataModel")
local ws = out:GetService("Workspace")
local t = ws:FindFirstChildOfClass("Terrain") or roblox.Instance.new("Terrain")
for _, prop in
	{
		"SmoothGrid",
		"MaterialColors",
		"WaterColor",
		"WaterReflectance",
		"WaterTransparency",
		"WaterWaveSize",
		"WaterWaveSpeed",
		"Decoration",
	}
do
	local ok, v = pcall(function()
		return (terrain :: any)[prop]
	end)
	if ok and v ~= nil then
		(t :: any)[prop] = v
	end
end
t.Parent = ws
fs.writeDir("assets")
fs.writeFile("assets/Terrain.rbxl", roblox.serializePlace(out))
print("terrain -> assets/Terrain.rbxl", #fs.readFile("assets/Terrain.rbxl"), "bytes")
