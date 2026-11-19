--!strict
-- Player saves on the campaign server: load with a session lock, autosave, save and release on
-- leave and on shutdown, and the marks API every gameplay system calls:
--   PlayerData.award(player, "revive")    -- marks for one action (Config.Progression.Sources)
-- Marks only go up. The highest marks are also kept in an ordered backup store and re-applied
-- on load ("never go below highest seen", user 2026-11-17).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Config.Progression)
local Servers = require(Shared.Config.Servers)
local Net = require(Shared.Net)
local PlayerSave = require(Shared.Rules.PlayerSave)(Progression, Servers)
local SessionLock = require(Shared.Rules.SessionLock)(Servers)
local Unlocks = require(Shared.Rules.Unlocks)(Progression)
local Lib = game:GetService("ServerScriptService").Lib
local Stores = require(Lib.Stores)
local Analytics = require(script.Parent.Analytics)

local PlayerData = {}
PlayerData.Unlocks = Unlocks

local store = Stores.data(Servers.Stores.Players)
local high = Stores.ordered(Servers.Stores.MarksHigh)
local JOB = if game.JobId ~= "" then game.JobId else "studio"

type Session = { save: PlayerSave.Save, highWritten: number, saving: boolean }
local sessions: { [Player]: Session } = {}
local loadedEvent = Instance.new("BindableEvent")
PlayerData.Loaded = loadedEvent.Event -- (player)

-- Per-server conditions for unlocks (filled by later systems: carrier, blueprints, docks).
PlayerData.serverCtx = { carrierArrived = false, serverBlueprints = {}, docked = {} }

local dataState = Net.remote("DataState")

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function now(): number
	return os.time()
end

function PlayerData.get(player: Player): PlayerSave.Save?
	local s = sessions[player]
	return s and s.save
end

local function ctxFor(save: PlayerSave.Save)
	local c = table.clone(PlayerData.serverCtx) :: any
	c.blueprints = save.blueprints
	return c
end

function PlayerData.push(player: Player, newlyUnlocked: { any }?)
	local save = PlayerData.get(player)
	if not save then
		return
	end
	dataState:FireClient(player, {
		marks = save.marks,
		guideDone = save.guideDone,
		class = save.lastClass,
		rank = Unlocks.rankPatch(save.marks),
		classes = Unlocks.classes(save.marks, ctxFor(save)),
		guns = Unlocks.guns(save.marks, save.lastClass, ctxFor(save)),
		spawnItems = Unlocks.spawnItems(save.marks, save.lastClass),
		log = save.log,
		newlyUnlocked = newlyUnlocked or {},
	})
end

-- Marks for one action. Returns the marks added.
function PlayerData.award(player: Player, source: string, amount: number?): number
	local save = PlayerData.get(player)
	if not save then
		return 0
	end
	local before = save.marks
	local added = PlayerSave.award(save, source, amount, now())
	if added > 0 then
		Analytics.marks(player, save, source, added)
		PlayerData.push(player, Unlocks.newBetween(before, save.marks))
	end
	return added
end

function PlayerData.finishGuide(player: Player): number
	local save = PlayerData.get(player)
	if not save then
		return 0
	end
	local before = save.marks
	local added = PlayerSave.finishGuide(save, now())
	if added > 0 then
		Analytics.marks(player, save, Progression.ReleaseCode.source, added)
		PlayerData.push(player, Unlocks.newBetween(before, save.marks))
	end
	return added
end

function PlayerData.pickClass(player: Player, classId: string): boolean
	local save = PlayerData.get(player)
	if not save or not Unlocks.classUnlocked(save.marks, classId, ctxFor(save)) then
		return false
	end
	save.lastClass = classId
	PlayerData.push(player)
	return true
end

local function writeHigh(player: Player, s: Session)
	if s.save.marks > s.highWritten then
		if high.set(key(player), s.save.marks) then
			s.highWritten = s.save.marks
		end
	end
end

-- Save one player. `release` on leave/shutdown.
local function save(player: Player, release: boolean)
	local s = sessions[player]
	if not s or s.saving then
		return
	end
	s.saving = true
	s.save.lastJoin = now()
	Analytics.accrue(player, s.save)
	local result =
		SessionLock.save(store, key(player), JOB, s.save, now(), release, PlayerSave.merge)
	s.saving = false
	writeHigh(player, s)
	if result == "lost" then
		warn(`[PlayerData] lost the save lock for {player.UserId}`)
		sessions[player] = nil
		if player.Parent then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	elseif result == "error" then
		warn(`[PlayerData] save failed for {player.UserId}; will retry at the next autosave`)
	end
	if release then
		sessions[player] = nil
	end
end

local function load(player: Player)
	for _ = 1, Servers.LockRetries do
		local result, data = SessionLock.acquire(store, key(player), JOB, now())
		if not player.Parent then
			if result == "ok" then
				SessionLock.save(
					store,
					key(player),
					JOB,
					PlayerSave.migrate(data, now()),
					now(),
					true
				)
			end
			return
		end
		if result == "ok" then
			local s = PlayerSave.migrate(data, now())
			local okHigh, highest = high.get(key(player))
			if okHigh then
				PlayerSave.applyHighest(s, highest)
			end
			s.lastJoin = now()
			sessions[player] =
				{ save = s, highWritten = if okHigh then (highest or 0) else 0, saving = false }
			Analytics.join(player, s)
			PlayerData.push(player)
			loadedEvent:Fire(player)
			return
		end
		task.wait(Servers.LockRetrySeconds)
	end
	player:Kick("Your save is still closing on another server. Please rejoin in a minute.")
end

function PlayerData.start()
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		Analytics.leave(p, PlayerData.get(p))
		save(p, true)
	end)
	Analytics.start(PlayerData.get)
	task.spawn(function()
		while true do
			task.wait(Servers.AutosaveSeconds)
			for p in sessions do
				task.spawn(save, p, false)
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and Stores.mock then
			return
		end
		local pending = 0
		for p in sessions do
			pending += 1
			task.spawn(function()
				Analytics.leave(p, PlayerData.get(p))
				save(p, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do
			task.wait(0.2)
		end
	end)

	Net.remote("GuideFinish").OnServerEvent:Connect(function(p)
		PlayerData.finishGuide(p)
	end)
	Net.remote("PickClass").OnServerEvent:Connect(function(p, classId)
		if type(classId) == "string" then
			PlayerData.pickClass(p, classId)
		end
	end)
	Net.remote("DebugGrant").OnServerEvent:Connect(function(p, amount)
		local admin = RunService:IsStudio() or table.find(Servers.Admins, p.UserId) ~= nil
		if admin and type(amount) == "number" and amount > 0 and amount <= 10000 then
			PlayerData.award(p, "admin", amount)
		end
	end)
end

return PlayerData
