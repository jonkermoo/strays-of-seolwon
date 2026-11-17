--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Progression = require("../src/shared/Config/Progression")
local Servers = require("../src/shared/Config/Servers")
local PlayerSave = require("../src/shared/Rules/PlayerSave")(Progression, Servers)
local SessionLock = require("../src/shared/Rules/SessionLock")(Servers)
local MemoryBackend = require("../src/shared/Rules/MemoryBackend")

local KEY = "p_1"

return {
	["a new save starts at 0 marks, Rifleman, guide not done"] = function()
		local s = PlayerSave.new(10)
		assert(
			s.marks == 0
				and not s.guideDone
				and s.lastClass == "rifleman"
				and s.v == Servers.SchemaVersion
		)
	end,
	["finishing the guide grants the release code once"] = function()
		local s = PlayerSave.new(0)
		assert(PlayerSave.finishGuide(s, 1) == 100 and s.marks == 100)
		assert(PlayerSave.finishGuide(s, 2) == 0 and s.marks == 100)
		assert(s.sources.release_code == 100)
	end,
	["awards use the source table; unknown sources and negative admin amounts pay nothing"] = function()
		local s = PlayerSave.new(0)
		assert(PlayerSave.award(s, "revive", nil, 1) == 5)
		assert(PlayerSave.award(s, "revive", 999, 1) == 5) -- amount ignored for fixed sources
		assert(PlayerSave.award(s, "crafting", nil, 1) == 0)
		assert(PlayerSave.award(s, "admin", -50, 1) == 0)
		assert(PlayerSave.award(s, "admin", 40, 1) == 40)
		assert(s.marks == 50)
	end,
	["the marks log keeps the newest entries only"] = function()
		local s = PlayerSave.new(0)
		for i = 1, Servers.MarksLogLength + 5 do
			PlayerSave.award(s, "kill", nil, i)
		end
		assert(#s.log == Servers.MarksLogLength and s.log[#s.log].at == Servers.MarksLogLength + 5)
	end,
	["migrate fills missing fields and never lowers marks"] = function()
		local s = PlayerSave.migrate({ marks = 321.7, lore = { a = true }, cosmetics = {} }, 5)
		assert(
			s.marks == 321
				and s.lore.a
				and s.guideDone == false
				and type(s.cosmetics.robux) == "table"
		)
		assert(PlayerSave.migrate(nil, 5).marks == 0)
		assert(PlayerSave.migrate("garbage", 5).marks == 0)
	end,
	["merge keeps the higher marks and unions found things"] = function()
		local a = PlayerSave.new(0)
		a.marks = 500
		a.lore.x = true
		local b = PlayerSave.new(0)
		b.marks = 300
		b.blueprints.y = true
		b.cosmetics.selected.vest = "v2"
		local m = PlayerSave.merge(a, b)
		assert(m.marks == 500 and m.lore.x and m.blueprints.y and m.cosmetics.selected.vest == "v2")
	end,
	["the highest-marks backup restores a lowered save"] = function()
		local s = PlayerSave.new(0)
		s.marks = 100
		PlayerSave.applyHighest(s, 750)
		assert(s.marks == 750 and s.sources.restored == 650)
		PlayerSave.applyHighest(s, 10)
		assert(s.marks == 750)
	end,
	["session lock: a second server can't load while the first holds the lock"] = function()
		local store = MemoryBackend.store()
		local r1 = SessionLock.acquire(store, KEY, "jobA", 100)
		assert(r1 == "ok")
		local r2 = SessionLock.acquire(store, KEY, "jobB", 110)
		assert(r2 == "locked")
	end,
	["session lock: release on leave lets the next server in with the saved marks"] = function()
		local store = MemoryBackend.store()
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "ok")
		local s = PlayerSave.new(0)
		PlayerSave.finishGuide(s, 1)
		assert(SessionLock.save(store, KEY, "jobA", s, 5, true, PlayerSave.merge) == "ok")
		local r, data = SessionLock.acquire(store, KEY, "jobB", 6)
		assert(r == "ok" and data.marks == 100)
	end,
	["session lock: a crashed server's lock goes stale and can be taken"] = function()
		local store = MemoryBackend.store()
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "ok")
		assert(SessionLock.acquire(store, KEY, "jobB", Servers.LockStaleSeconds - 1) == "locked")
		assert(SessionLock.acquire(store, KEY, "jobB", Servers.LockStaleSeconds) == "ok")
		-- the old server must not overwrite now
		assert(SessionLock.save(store, KEY, "jobA", PlayerSave.new(0), 200, false) == "lost")
	end,
	["session lock: autosave refreshes the lock so it never goes stale while alive"] = function()
		local store = MemoryBackend.store()
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "ok")
		local t = 0
		for _ = 1, 10 do
			t += Servers.AutosaveSeconds
			assert(SessionLock.save(store, KEY, "jobA", PlayerSave.new(0), t, false) == "ok")
		end
		assert(
			SessionLock.acquire(store, KEY, "jobB", t + Servers.LockStaleSeconds - 1) == "locked"
		)
	end,
	["session lock: a store error is reported, not treated as success"] = function()
		local store = MemoryBackend.store()
		store.failNext(1)
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "error")
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "ok")
		store.failNext(1)
		assert(SessionLock.save(store, KEY, "jobA", PlayerSave.new(0), 1, false) == "error")
	end,
	["saving with merge never lowers stored marks"] = function()
		local store = MemoryBackend.store()
		assert(SessionLock.acquire(store, KEY, "jobA", 0) == "ok")
		local hi = PlayerSave.new(0)
		hi.marks = 900
		assert(SessionLock.save(store, KEY, "jobA", hi, 1, false, PlayerSave.merge) == "ok")
		assert(
			SessionLock.save(store, KEY, "jobA", PlayerSave.new(0), 2, false, PlayerSave.merge)
				== "ok"
		)
		local _, rec = store.get(KEY)
		assert(rec.data.marks == 900)
	end,
	["a player earns marks, unlocks Medic and Engineer, and keeps them on another server"] = function()
		local Unlocks = require("../src/shared/Rules/Unlocks")(Progression)
		local store = MemoryBackend.store()
		local _, data = SessionLock.acquire(store, KEY, "serverA", 0)
		local s = PlayerSave.migrate(data, 0)
		PlayerSave.award(s, "revive", nil, 1)
		PlayerSave.finishGuide(s, 2)
		assert(
			Unlocks.classUnlocked(s.marks, "medic") and Unlocks.classUnlocked(s.marks, "engineer")
		)
		PlayerSave.addLore(s, "note_01")
		assert(SessionLock.save(store, KEY, "serverA", s, 3, true, PlayerSave.merge) == "ok")
		local r, data2 = SessionLock.acquire(store, KEY, "serverB", 4)
		local s2 = PlayerSave.migrate(data2, 4)
		assert(r == "ok" and s2.marks == 105 and s2.lore.note_01 and s2.guideDone)
	end,
}
