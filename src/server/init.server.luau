--!strict
-- Campaign place server. Placeholder world only (no art yet).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Lib = game:GetService("ServerScriptService").Lib
local Campaigns = require(Lib.Campaigns)
local PlayerData = require(script.PlayerData)
local CampaignHost = require(script.CampaignHost)

for name in Net.Messages do
	Net.remote(name :: any)
end

PlayerData.start()
CampaignHost.start()

local status = Net.remote("Status")
local listRows = Net.remote("ListRows")

-- In-game server list
Net.remote("ListRequest").OnServerEvent:Connect(function(p)
	local rec = CampaignHost.record()
	local rows = {}
	for _, row in Campaigns.rows(p) do
		if not (rec and row.id == rec.id) then -- not this server
			table.insert(rows, row)
		end
	end
	listRows:FireClient(p, rows)
end)
Net.remote("JoinRequest").OnServerEvent:Connect(function(p, id)
	local rec = CampaignHost.record()
	if type(id) ~= "string" or (rec and rec.id == id) then
		return
	end
	status:FireClient(p, Campaigns.joinById(p, id))
end)

-- Studio-only test hook: set the attribute FreezeForSeconds on this script to pretend the
-- server sat empty that long (try 3600, then 90000 for a public campaign ending).
if RunService:IsStudio() then
	script:SetAttribute("FreezeForSeconds", 0)
	script:GetAttributeChangedSignal("FreezeForSeconds"):Connect(function()
		local s = script:GetAttribute("FreezeForSeconds")
		if type(s) == "number" and s > 0 then
			local msg = CampaignHost.debugFreezeFor(s)
			print("[Debug] " .. msg)
			status:FireAllClients(msg)
		end
	end)
end

-- A plain grey baseplate to stand on until the map exists (the greybox replaces it).
if
	not workspace:FindFirstChild("PlaceholderGround") and not workspace:FindFirstChild("Greybox")
then
	local ground = Instance.new("Part")
	ground.Name = "PlaceholderGround"
	ground.Anchored = true
	ground.Size = Vector3.new(512, 4, 512)
	ground.Position = Vector3.new(0, -2, 0)
	ground.Parent = workspace
end

-- Studio-only greybox walk test (see RouteTest.luau).
if RunService:IsStudio() and workspace:GetAttribute("RouteTest") == true then
	task.spawn(require(script.RouteTest).run)
end
