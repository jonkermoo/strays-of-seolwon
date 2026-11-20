-- Sets Lighting.Technology (not writable from Studio's command bar / MCP) in a place file.
-- lune run tools/styletest/lighting <place.rbxl> [Future|ShadowMap]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local path = process.args[1]
local tech = process.args[2] or "Future"
local place = roblox.deserializePlace(fs.readFile(path))
local lighting = place:GetService("Lighting")
print("before", lighting.Technology)
lighting.Technology = (roblox.Enum :: any).Technology[tech]
fs.writeFile(path, roblox.serializePlace(place))
print("after", lighting.Technology)
