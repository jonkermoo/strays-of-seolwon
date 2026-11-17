--!strict
-- Runs this server's campaign: which campaign it is, waking it, the day clock (only while
-- someone is here), freezing when the last player leaves, ending a public campaign frozen for
-- 24 h, the heartbeat into the public server list, and saving the record.
--
-- Who am I?
--   reserved server (PrivateServerId set, no owner): the campaign with that id
--   Studio (mock stores): campaign "studio"
--   a public server of the campaign place: not a campaign; send players to the entry place

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Servers = require(Shared.Config.Servers)
local Net = require(Shared.Net)
local Lib = game:GetService("ServerScriptService").Lib
local Stores = require(Lib.Stores)
local Campaigns = require(Lib.Campaigns)
local Campaign = Campaigns.Campaign

local CampaignHost = {}

local JOB = if game.JobId ~= "" then game.JobId else "studio"
local rec: Campaign.Record? = nil
local campaignState = Net.remote("CampaignState")
local status = Net.remote("Status")

local dawnEvent = Instance.new("BindableEvent")
CampaignHost.Dawn = dawnEvent.Event -- (day)

function CampaignHost.record(): Campaign.Record?
	return rec
end

local function snapshot()
	if not rec then
		return nil
	end
	return {
		id = rec.id,
		day = rec.day,
		state = rec.state,
		fraction = Campaign.dayFraction(rec),
		players = #Players:GetPlayers(),
		private = rec.private,
		owner = rec.owner,
		mock = Stores.mock,
	}
end

local function broadcast()
	campaignState:FireAllClients(snapshot())
end

local function saveRecord()
	local r = rec
	if not r then
		return
	end
	Campaigns.updateRecord(r.id, function(old: any)
		if old and old.state == "ended" then
			return nil -- never revive an ended campaign
		end
		return r
	end)
end

local function report()
	local r = rec
	if not r or r.private then
		return
	end
	if r.state == "live" then
		Campaigns.reportLive(r, #Players:GetPlayers(), JOB)
	elseif r.state == "frozen" then
		Campaigns.reportFrozen(r)
	end
end

local function freeze()
	local r = rec
	if not r or r.state ~= "live" then
		return
	end
	Campaign.freeze(r, Campaigns.now())
	saveRecord()
	report()
	broadcast()
end

local function wake(): boolean
	local r = rec
	if not r then
		return false
	end
	if r.state == "live" then
		return true
	end
	if not Campaign.wake(r, Campaigns.now()) then
		saveRecord()
		Campaigns.unlist(r.id)
		return false
	end
	saveRecord()
	report()
	broadcast()
	return true
end

local function identify(): (string?, boolean)
	if Stores.mock then
		return "studio", false
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return game.PrivateServerId, false
	end
	if game.PrivateServerId ~= "" then
		return "vip_" .. game.PrivateServerId, true -- a VIP server of this place (unexpected)
	end
	return nil, false
end

local function load(): boolean
	local id, vip = identify()
	if id == nil then
		return false
	end
	local ok, stored = Campaigns.loadRecord(id)
	while not ok do
		task.wait(5)
		ok, stored = Campaigns.loadRecord(id)
	end
	if stored == nil then
		stored = Campaign.new(
			id,
			Campaigns.now(),
			vip,
			nil,
			if vip then game.PrivateServerOwnerId else nil
		)
	end
	rec = stored
	return true
end

function CampaignHost.start()
	if not load() then
		-- public server of the campaign place: nobody plays here
		local function send(p: Player)
			status:FireClient(p, "This is not a campaign server. Sending you to the menu...")
			Campaigns.toEntry({ p })
		end
		Players.PlayerAdded:Connect(send)
		for _, p in Players:GetPlayers() do
			send(p)
		end
		return
	end

	local function arrive(p: Player)
		if not wake() then
			status:FireClient(p, "This campaign has ended. Sending you to the menu...")
			Campaigns.toEntry({ p })
			return
		end
		campaignState:FireClient(p, snapshot())
		report()
	end
	Players.PlayerAdded:Connect(arrive)
	for _, p in Players:GetPlayers() do
		task.spawn(arrive, p)
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if #Players:GetPlayers() == 0 then
				freeze()
			else
				report()
			end
		end)
	end)

	-- the day clock: only while someone is here
	RunService.Heartbeat:Connect(function(dt)
		local r = rec
		if r and r.state == "live" and #Players:GetPlayers() > 0 then
			local dawns = Campaign.tick(r, dt)
			if dawns > 0 then
				dawnEvent:Fire(r.day)
				broadcast()
			end
		end
	end)

	task.spawn(function()
		local sinceSave = 0
		while true do
			task.wait(Servers.HeartbeatSeconds)
			report()
			broadcast()
			sinceSave += Servers.HeartbeatSeconds
			if sinceSave >= Servers.RecordSaveSeconds then
				sinceSave = 0
				saveRecord()
			end
		end
	end)

	game:BindToClose(function()
		if Stores.mock then
			return
		end
		-- shutting down (empty, or an update): the world waits frozen
		local r = rec
		if r and r.state == "live" then
			Campaign.freeze(r, Campaigns.now())
			report()
		end
		saveRecord()
	end)

	Net.remote("ResetCampaign").OnServerEvent:Connect(function(p)
		local r = rec
		if r and r.private and (r.owner == p.UserId or RunService:IsStudio()) then
			Campaign.reset(r, Campaigns.now())
			saveRecord()
			broadcast()
			status:FireAllClients("The owner reset this campaign to Day 0.")
		end
	end)
end

-- Studio debug: pretend the server emptied (freeze) and came back after `seconds`.
function CampaignHost.debugFreezeFor(seconds: number): string
	local r = rec
	if not r then
		return "no campaign"
	end
	Campaign.freeze(r, Campaigns.now() - seconds)
	local woke = wake()
	return if woke then `woke after {seconds}s frozen` else "ended (frozen too long)"
end

return CampaignHost
