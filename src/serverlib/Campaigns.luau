--!strict
-- Shared server-side access to campaigns, used by the entry place and the campaign place:
--   - the public server list (MemoryStore sorted map, key = campaign id), read by auto-match
--     and the in-game list, written by each campaign server's heartbeat;
--   - campaign records (DataStore, key = campaign id), the saved world of each server;
--   - private campaigns (DataStore, key = Roblox private server id -> campaign id);
--   - reserving servers and teleporting into them.
-- Access codes stay on servers; clients only ever see list rows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Servers = require(Shared.Config.Servers)
local Campaign = require(Shared.Rules.Campaign)(Servers)
local Matchmaker = require(Shared.Rules.Matchmaker)(Servers)
local Stores = require(script.Parent.Stores)

local Campaigns = {}

local list = Stores.sortedMap(Servers.Stores.ServerList)
local records = Stores.data(Servers.Stores.Campaigns)
local privates = Stores.data(Servers.Stores.PrivateCampaigns)

Campaigns.Campaign = Campaign
Campaigns.Matchmaker = Matchmaker

function Campaigns.now(): number
	return os.time()
end

-- Every listed public campaign (live and frozen).
function Campaigns.entries(): { Matchmaker.Entry }
	local ok, items = list.range(Servers.ListMax)
	local out = {}
	if ok then
		for _, item in items do
			table.insert(out, item.value)
		end
	end
	return out
end

function Campaigns.entry(id: string): Matchmaker.Entry?
	local ok, e = list.get(id)
	return if ok then e else nil
end

-- A campaign server's heartbeat: it is live with this many players.
function Campaigns.reportLive(rec: Campaign.Record, players: number, job: string)
	local now = Campaigns.now()
	list.update(rec.id, function(old: any)
		local e = old or {}
		e.id = rec.id
		e.job = job
		e.state = "live"
		e.players = players
		e.day = rec.day
		e.frozenAt = nil
		e.updated = now
		Matchmaker.prune(e, now)
		return e
	end, Servers.ListEntryTtlSeconds)
end

-- Last player left: listed as frozen until it ends (the entry expires with it).
function Campaigns.reportFrozen(rec: Campaign.Record)
	local now = Campaigns.now()
	list.set(rec.id, {
		id = rec.id,
		state = "frozen",
		players = 0,
		day = rec.day,
		frozenAt = rec.frozenAt or now,
		updated = now,
		promised = {},
	}, Servers.FreezeEndSeconds)
end

function Campaigns.unlist(id: string)
	list.remove(id)
end

-- Count a seat for a player who is about to teleport in.
function Campaigns.promise(id: string, ttl: number)
	local now = Campaigns.now()
	list.update(id, function(old: any)
		if old == nil then
			return nil
		end
		Matchmaker.prune(old, now)
		table.insert(old.promised, now)
		return old
	end, ttl)
end

function Campaigns.loadRecord(id: string): (boolean, Campaign.Record?)
	return records.get(id)
end

function Campaigns.updateRecord(
	id: string,
	fn: (Campaign.Record?) -> Campaign.Record?
): (boolean, any)
	return records.update(id, fn :: any)
end

-- Reserve a new campaign server. Returns the new record (with its access code).
function Campaigns.create(private: boolean, owner: number?): Campaign.Record?
	local ok, code, psid
	if Stores.mock then
		-- Studio can't reserve servers: a fake id, listed like a real one
		ok, code, psid = true, "studio", "studio_" .. tostring(math.random(1e6))
	else
		ok, code, psid = pcall(function()
			return TeleportService:ReserveServer(Servers.CampaignPlaceId)
		end)
	end
	if not ok then
		warn("[Campaigns] ReserveServer failed: " .. tostring(code))
		return nil
	end
	local rec = Campaign.new(psid, Campaigns.now(), private, code, owner)
	if not records.set(rec.id, rec) then
		return nil
	end
	if not private then
		-- listed straight away with a seat promised, so the next joiners fill it
		list.set(rec.id, {
			id = rec.id,
			state = "live",
			players = 0,
			day = 0,
			promised = { Campaigns.now() },
			updated = Campaigns.now(),
		}, Servers.ListEntryTtlSeconds + Servers.JoinWindowSeconds)
	end
	return rec
end

-- The campaign for a Roblox private server (created on first use).
function Campaigns.forPrivate(vipId: string, owner: number): Campaign.Record?
	local ok, id = privates.get(vipId)
	if ok and id then
		local okRec, rec = records.get(id)
		if okRec and rec then
			return rec
		end
	end
	if not ok then
		return nil
	end
	local rec = Campaigns.create(true, owner)
	if rec and privates.set(vipId, rec.id) then
		return rec
	end
	return nil
end

-- Send players into a campaign. Returns false if it could not start the teleport.
function Campaigns.teleport(rec: Campaign.Record, players: { Player }, note: string?): boolean
	if Stores.mock or rec.code == nil then
		print(
			`[Campaigns] (Studio) would teleport {#players} player(s) to campaign {rec.id} {note or ""}`
		)
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = rec.code
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Servers.CampaignPlaceId, players, options)
	end)
	if not ok then
		warn("[Campaigns] teleport failed: " .. tostring(err))
	end
	return ok
end

-- Back to the entry place (campaign ended, or a public server of the campaign place).
function Campaigns.toEntry(players: { Player }): boolean
	if Stores.mock or Servers.EntryPlaceId == 0 then
		print(`[Campaigns] (Studio) would send {#players} player(s) to the entry place`)
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Servers.EntryPlaceId, players)
	end)
	if not ok then
		warn("[Campaigns] teleport to entry failed: " .. tostring(err))
	end
	return ok
end

-- Job ids of this player's friends who are online in a campaign (for friends-first match).
local friendCache: { [number]: { at: number, jobs: { [string]: boolean } } } = {}
function Campaigns.friendJobs(player: Player): { [string]: boolean }
	local cached = friendCache[player.UserId]
	if cached and Campaigns.now() - cached.at < 30 then
		return cached.jobs
	end
	local jobs = {}
	local ok, friends = pcall(function()
		return player:GetFriendsOnline(200)
	end)
	if ok then
		for _, f in friends do
			if f.PlaceId == Servers.CampaignPlaceId and f.GameId then
				jobs[f.GameId] = true
			end
		end
	end
	friendCache[player.UserId] = { at = Campaigns.now(), jobs = jobs }
	return jobs
end

Players.PlayerRemoving:Connect(function(p)
	friendCache[p.UserId] = nil
end)

-- Auto-match one player: pick, then join / wake / create, then teleport.
-- Returns a short status for the debug UI.
function Campaigns.autoMatch(player: Player): string
	local now = Campaigns.now()
	local decision = Matchmaker.pick(Campaigns.entries(), Campaigns.friendJobs(player), now)
	local rec: Campaign.Record?
	if decision.kind == "new" then
		rec = Campaigns.create(false)
	else
		local id = decision.id :: string
		local ok, loaded = Campaigns.loadRecord(id)
		if ok and loaded and not Campaign.isEnded(loaded, now) then
			rec = loaded
			local ttl = if decision.kind == "wake"
				then math.max(60, Servers.FreezeEndSeconds - (now - (loaded.frozenAt or now)))
				else Servers.ListEntryTtlSeconds + Servers.JoinWindowSeconds
			Campaigns.promise(id, ttl)
		elseif ok then
			Campaigns.unlist(id) -- ended or missing: drop it and try again next press
		end
	end
	if rec == nil then
		return `{decision.kind}: failed, try again`
	end
	local sent = Campaigns.teleport(rec, { player }, decision.kind)
	return `{decision.kind} {rec.id}{if sent then "" else " (not sent: Studio)"}`
end

-- Join one row of the server list (validated against the live list).
function Campaigns.joinById(player: Player, id: string): string
	local now = Campaigns.now()
	local e = Campaigns.entry(id)
	if not Matchmaker.canJoin(e, now) then
		return "That server is full or gone."
	end
	local ok, rec = Campaigns.loadRecord(id)
	if not ok or rec == nil or Campaign.isEnded(rec, now) then
		return "That campaign has ended."
	end
	local ttl = if e and e.state == "frozen"
		then math.max(60, Servers.FreezeEndSeconds - (now - (e.frozenAt or now)))
		else Servers.ListEntryTtlSeconds + Servers.JoinWindowSeconds
	Campaigns.promise(id, ttl)
	local sent = Campaigns.teleport(rec, { player }, "list")
	return if sent then "Joining..." else `Would join {id} (Studio)`
end

function Campaigns.rows(player: Player)
	return Matchmaker.rows(Campaigns.entries(), Campaigns.friendJobs(player), Campaigns.now())
end

return Campaigns
