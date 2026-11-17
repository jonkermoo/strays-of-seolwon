--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Servers = require("../src/shared/Config/Servers")
local Campaign = require("../src/shared/Rules/Campaign")(Servers)
local Matchmaker = require("../src/shared/Rules/Matchmaker")(Servers)
local MemoryBackend = require("../src/shared/Rules/MemoryBackend")

local DAY = Servers.DayLengthSeconds
local END = Servers.FreezeEndSeconds

local function live(id: string, players: number, job: string?): any
	return { id = id, job = job or ("job_" .. id), state = "live", players = players, day = 3 }
end
local function frozen(id: string, at: number): any
	return { id = id, state = "frozen", players = 0, day = 7, frozenAt = at }
end

return {
	["a campaign starts live at day 0 and the day ticks at dawn"] = function()
		local c = Campaign.new("a", 0)
		assert(c.state == "live" and c.day == 0)
		assert(Campaign.tick(c, DAY - 1) == 0 and c.day == 0)
		assert(Campaign.tick(c, 1) == 1 and c.day == 1 and c.clock == 0)
		Campaign.tick(c, DAY * 2.5)
		assert(c.day == 3 and math.abs(Campaign.dayFraction(c) - 0.5) < 1e-9)
	end,
	["it is endless: no day cap on the counter"] = function()
		local c = Campaign.new("a", 0)
		Campaign.tick(c, DAY * 500)
		assert(c.day == 500 and c.state == "live")
	end,
	["frozen: time stops while empty"] = function()
		local c = Campaign.new("a", 0)
		Campaign.freeze(c, 100)
		assert(Campaign.tick(c, DAY * 3) == 0 and c.day == 0)
	end,
	["a public campaign empty for 24 h ends; before that it wakes"] = function()
		local c = Campaign.new("a", 0)
		Campaign.freeze(c, 1000)
		assert(Campaign.endsIn(c, 1000 + 60) == END - 60)
		assert(Campaign.wake(c, 1000 + END - 1) and c.state == "live" and c.frozenAt == nil)
		Campaign.freeze(c, 5000)
		assert(not Campaign.wake(c, 5000 + END))
		assert(c.state == "ended" and c.endedAt == 5000 + END)
		assert(not Campaign.wake(c, 5000 + END * 3)) -- stays ended
	end,
	["a private campaign freezes but never ends; the owner can reset it"] = function()
		local c = Campaign.new("vip", 0, true, nil, 42)
		Campaign.tick(c, DAY * 9)
		Campaign.freeze(c, 10)
		assert(Campaign.endsIn(c, 10 + END * 30) == nil)
		assert(Campaign.wake(c, 10 + END * 30) and c.day == 9)
		Campaign.reset(c, 99)
		assert(c.day == 0 and c.resets == 1 and c.state == "live")
	end,
	["match: a friend's server first, if it has a seat"] = function()
		local e = { live("a", 15), live("b", 30, "jobF") }
		assert(Matchmaker.pick(e, { jobF = true }, 0).id == "b")
		e[2].players = Servers.MaxPlayers
		assert(Matchmaker.pick(e, { jobF = true }, 0).id == "a")
	end,
	["match: fill the fullest server under the target"] = function()
		local e = { live("a", 5), live("b", 18), live("c", 25) }
		assert(Matchmaker.pick(e, {}, 0).id == "b")
	end,
	["match: when all are at the target, the emptiest under the soft cap"] = function()
		local e = { live("a", 40), live("b", 22), live("c", 44), live("d", 46) }
		assert(Matchmaker.pick(e, {}, 0).id == "b")
	end,
	["match: all near full: wake the newest frozen campaign before making a new one"] = function()
		local e = { live("a", 45), frozen("f1", 100), frozen("f2", 200), frozen("dead", -END) }
		local d = Matchmaker.pick(e, {}, 300)
		assert(d.kind == "wake" and d.id == "f2")
		assert(Matchmaker.pick({ live("a", 45), frozen("dead", -END) }, {}, 300).kind == "new")
		assert(Matchmaker.pick({}, {}, 0).kind == "new")
	end,
	["match: a frozen campaign is not woken while a live one has room"] = function()
		local e = { live("a", 30), frozen("f", 100) }
		assert(Matchmaker.pick(e, {}, 200).id == "a")
	end,
	["promised seats count until the join window passes"] = function()
		local e = live("a", 19)
		e.promised = { 0 }
		-- 19 + 1 promised = 20: no longer under the target, but under the soft cap
		assert(Matchmaker.seats(e, 10) == 20)
		assert(Matchmaker.seats(e, Servers.JoinWindowSeconds) == 19)
		Matchmaker.prune(e, Servers.JoinWindowSeconds)
		assert(#(e.promised :: any) == 0)
	end,
	["a burst of joiners fills one server to the target, then spreads"] = function()
		local entries = { live("a", 0), live("b", 0) }
		local counts = { a = 0, b = 0 }
		for _ = 1, 30 do
			local d = Matchmaker.pick(entries, {}, 0)
			assert(d.kind == "join")
			for _, e in entries do
				if e.id == d.id then
					e.promised = e.promised or {}
					table.insert(e.promised :: any, 0)
				end
			end
			counts[d.id :: string] += 1
		end
		assert(counts.a == 20 and counts.b == 10, `{counts.a} {counts.b}`)
	end,
	["server list rows: friends first, live by players, frozen with time left; dead ones hidden"] = function()
		local e = {
			live("a", 3),
			live("b", 30),
			live("c", 5, "jobF"),
			frozen("f", 100),
			frozen("dead", -END),
		}
		local rows = Matchmaker.rows(e, { jobF = true }, 200)
		assert(#rows == 4)
		assert(rows[1].id == "c" and rows[1].friend)
		assert(rows[2].id == "b" and rows[3].id == "a")
		assert(rows[4].id == "f" and rows[4].endsIn == END - 100)
		assert(Matchmaker.canJoin(e[4], 200) and not Matchmaker.canJoin(e[5], 200))
		local full = live("z", Servers.MaxPlayers)
		assert(not Matchmaker.canJoin(full, 0) and Matchmaker.rows({ full }, {}, 0)[1].full)
	end,
	["a woken frozen campaign fills like a live one; if nobody arrives it is frozen again"] = function()
		local f = frozen("f", 100)
		f.promised = { 200 }
		local e = { live("a", 45), f, frozen("g", 50) }
		local d = Matchmaker.pick(e, {}, 210)
		assert(d.kind == "join" and d.id == "f") -- not a second wake
		local rows = Matchmaker.rows(e, {}, 210)
		assert(rows[2].id == "f" and rows[2].state == "live")
		local later = 200 + Servers.JoinWindowSeconds
		assert(
			Matchmaker.pick(e, {}, later).kind == "wake" and Matchmaker.pick(e, {}, later).id == "f"
		)
	end,
	["the in-memory sorted map expires entries by ttl"] = function()
		local now = 0
		local map = MemoryBackend.sortedMap(function()
			return now
		end)
		map.set("b", { x = 1 }, 60)
		map.set("a", { x = 2 }, 10)
		local _, r = map.range(10)
		assert(#r == 2 and r[1].key == "a")
		now = 30
		_, r = map.range(10)
		assert(#r == 1 and r[1].key == "b")
	end,
}
