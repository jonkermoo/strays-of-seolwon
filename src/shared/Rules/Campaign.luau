--!strict
-- A campaign = one server's endless world. Pure state rules; the host is
-- src/server/CampaignHost.luau.  local Campaign = require(Rules.Campaign)(Config.Servers)
--
-- Lifecycle (user): live while anyone is in it; frozen the moment the last player leaves
-- (time and the world stop); a public campaign frozen for 24 h ends for good. A private
-- campaign freezes but never ends (user, 2026-11-17); its owner can reset it.
-- The day counter starts at 0 and ticks at dawn; one day = 40 real minutes of live time.

export type State = "live" | "frozen" | "ended"

export type Record = {
	v: number,
	id: string, -- the reserved server's PrivateServerId
	code: string?, -- reserved server access code (server-only, never sent to clients)
	private: boolean,
	owner: number?, -- private server owner
	state: State,
	day: number,
	clock: number, -- live seconds since the last dawn
	createdAt: number,
	frozenAt: number?,
	endedAt: number?,
	resets: number,
	world: { [string]: any }, -- per-server saved state (sites, stocks...); filled by later systems
}

return function(servers: any)
	local Campaign = {}

	function Campaign.new(
		id: string,
		now: number,
		private: boolean?,
		code: string?,
		owner: number?
	): Record
		return {
			v = 1,
			id = id,
			code = code,
			private = private == true,
			owner = owner,
			state = "live",
			day = 0,
			clock = 0,
			createdAt = now,
			frozenAt = nil,
			endedAt = nil,
			resets = 0,
			world = {},
		}
	end

	-- Has this campaign ended (or should it have, by now)?
	function Campaign.isEnded(rec: Record, now: number): boolean
		if rec.state == "ended" then
			return true
		end
		if rec.state ~= "frozen" or rec.frozenAt == nil then
			return false
		end
		if rec.private and servers.PrivateNeverEnds then
			return false
		end
		return now - rec.frozenAt >= servers.FreezeEndSeconds
	end

	-- Seconds left before a frozen public campaign ends (nil = never / not frozen).
	function Campaign.endsIn(rec: Record, now: number): number?
		if rec.state ~= "frozen" or rec.frozenAt == nil then
			return nil
		end
		if rec.private and servers.PrivateNeverEnds then
			return nil
		end
		return math.max(0, servers.FreezeEndSeconds - (now - rec.frozenAt))
	end

	-- Mark it ended if its time ran out. Returns true if it is ended.
	function Campaign.settle(rec: Record, now: number): boolean
		if rec.state ~= "ended" and Campaign.isEnded(rec, now) then
			rec.state = "ended"
			rec.endedAt = (rec.frozenAt or now) + servers.FreezeEndSeconds
		end
		return rec.state == "ended"
	end

	-- A player arrives. Returns false if the campaign has ended (send them back to match).
	function Campaign.wake(rec: Record, now: number): boolean
		if Campaign.settle(rec, now) then
			return false
		end
		rec.state = "live"
		rec.frozenAt = nil
		return true
	end

	-- The last player left: stop time.
	function Campaign.freeze(rec: Record, now: number)
		if rec.state == "live" then
			rec.state = "frozen"
			rec.frozenAt = now
		end
	end

	-- Advance live time. Returns how many dawns passed (usually 0 or 1).
	function Campaign.tick(rec: Record, dt: number): number
		if rec.state ~= "live" or dt <= 0 then
			return 0
		end
		rec.clock += dt
		local dawns = 0
		while rec.clock >= servers.DayLengthSeconds do
			rec.clock -= servers.DayLengthSeconds
			rec.day += 1
			dawns += 1
		end
		return dawns
	end

	-- Time of day 0..1 (0 = dawn), for lighting later.
	function Campaign.dayFraction(rec: Record): number
		return rec.clock / servers.DayLengthSeconds
	end

	-- Private owner's reset: a fresh Day 0 in the same server.
	function Campaign.reset(rec: Record, now: number)
		rec.state = "live"
		rec.day = 0
		rec.clock = 0
		rec.frozenAt = nil
		rec.endedAt = nil
		rec.createdAt = now
		rec.resets += 1
		rec.world = {}
	end

	return Campaign
end
