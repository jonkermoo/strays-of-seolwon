--!strict
-- Copies the generated terrain (assets/Terrain.rbxl) into a Rojo-built place, since Rojo can't
-- carry terrain. Run after rojo build: lune run tools/terrain/merge build/game.rbxl
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local target = process.args[1] or "build/game.rbxl"
if not fs.isFile("assets/Terrain.rbxl") then
	print("no assets/Terrain.rbxl; place left without terrain")
	return
end
local from = roblox.deserializePlace(fs.readFile("assets/Terrain.rbxl"))
local src = from:GetService("Workspace"):FindFirstChildOfClass("Terrain")
local place = roblox.deserializePlace(fs.readFile(target))
assert(src, "no terrain in assets/Terrain.rbxl")
local ws = place:GetService("Workspace")
local dst = ws:FindFirstChildOfClass("Terrain")
if not dst then
	dst = roblox.Instance.new("Terrain")
	dst.Parent = ws
end
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
		return (src :: any)[prop]
	end)
	if ok and v ~= nil then
		(dst :: any)[prop] = v
	end
end
fs.writeFile(target, roblox.serializePlace(place))
print("terrain merged into " .. target)
