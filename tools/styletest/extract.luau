--!strict
-- M1 style test: takes the hand-built test scene out of a Studio-saved place into repo assets.
--   assets/StyleTest.rbxm  Workspace.StyleTest (bunker, Strays rifleman, Seori soldier, H2 prop)
--   assets/StyleSky.rbxm   the overcast Sky (plain grey faces) for Lighting
--   assets/Greybox.rbxm    Workspace.Greybox with the 6 placeholder parts that sat inside the bunker
--                          hill removed (style-test branch only)
-- Terrain (bunker berm) goes through tools/terrain/extract as usual.
-- Run: lune run tools/styletest/extract <saved.rbxl>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local src = process.args[1]
assert(src, "usage: lune run tools/styletest/extract <saved.rbxl>")
local place = roblox.deserializePlace(fs.readFile(src))
local ws = place:GetService("Workspace")

local function strip(root)
	for _, d in root:GetDescendants() do
		-- no scripts from public models, no package links (they would pull creator updates)
		if d:IsA("LuaSourceContainer") or d.ClassName == "PackageLink" then
			d:Destroy()
		end
	end
end

local scene = ws:FindFirstChild("StyleTest")
assert(scene, "no Workspace.StyleTest")
local weather = scene:FindFirstChild("StyleWeather")
if weather then
	weather:Destroy()
end
strip(scene)
fs.writeFile("assets/StyleTest.rbxm", roblox.serializeModel({ scene }))

local sky = place:GetService("Lighting"):FindFirstChildOfClass("Sky")
assert(sky, "no Sky in Lighting")
sky.Name = "OvercastSky"
fs.writeFile("assets/StyleSky.rbxm", roblox.serializeModel({ sky }))

local greybox = ws:FindFirstChild("Greybox")
assert(greybox, "no Workspace.Greybox")
fs.writeFile("assets/Greybox.rbxm", roblox.serializeModel({ greybox }))
print("wrote assets/StyleTest.rbxm, assets/StyleSky.rbxm, assets/Greybox.rbxm")
