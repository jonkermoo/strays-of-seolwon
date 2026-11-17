--!strict
-- Auto-match and the in-game server list, on the shared list of public campaigns
-- (a MemoryStore sorted map; see src/serverlib/ServerList.luau). Pure.
--   local Matchmaker = require(Rules.Matchmaker)(Config.Servers)
--
-- Auto-match order (user, 2026-11-17: friends first; no server should feel empty):
--   1. a live campaign a friend is in, with a free seat;
--   2. the fullest live campaign still under MatchTarget (~20);
--   3. when all are at the target, the emptiest live campaign under MatchSoftCap (~45);
--   4. otherwise wake the most recently frozen campaign (always continue frozen ones);
--   5. only when nothing is frozen, start a new Day 0.
-- Seats promised to players still teleporting count for JoinWindowSeconds, so a burst of
-- joiners doesn't overfill one server.

export type Entry = {
	id: string,
	job: string?, -- JobId of the running server (live only)
	state: string, -- "live" | "frozen"
	players: number,
	day: number,
	frozenAt: number?,
	promised: { number }?, -- times seats were promised to teleporting players
	updated: number?,
}

export type Decision = { kind: "join" | "wake" | "new", id: string? }

export type Row = {
	id: string,
	state: string,
	day: number,
	players: number,
	max: number,
	friend: boolean,
	endsIn: number?,
	full: boolean,
}

return function(servers: any)
	local Matchmaker = {}

	function Matchmaker.seats(e: Entry, now: number): number
		local n = e.players
		for _, at in e.promised or {} do
			if now - at < servers.JoinWindowSeconds then
				n += 1
			end
		end
		return n
	end

	-- Drop promises older than the join window (call inside the list's update).
	function Matchmaker.prune(e: Entry, now: number)
		local keep = {}
		for _, at in e.promised or {} do
			if now - at < servers.JoinWindowSeconds then
				table.insert(keep, at)
			end
		end
		e.promised = keep
	end

	local function frozenLive(e: Entry, now: number): boolean
		return e.state == "frozen"
			and e.frozenAt ~= nil
			and now - e.frozenAt < servers.FreezeEndSeconds
	end

	-- Live, or frozen with players on their way (being woken). A woken entry stays "frozen"
	-- in the list until its server boots, so a failed teleport never drops it from the list.
	function Matchmaker.isLive(e: Entry, now: number): boolean
		if e.state == "live" then
			return true
		end
		return frozenLive(e, now) and Matchmaker.seats(e, now) > 0
	end

	function Matchmaker.pick(
		entries: { Entry },
		friendJobs: { [string]: boolean },
		now: number
	): Decision
		local live = {}
		for _, e in entries do
			if Matchmaker.isLive(e, now) then
				table.insert(live, e)
			end
		end
		-- 1. friends
		local best: Entry?, bestSeats = nil, -1
		for _, e in live do
			local s = Matchmaker.seats(e, now)
			if e.job and friendJobs[e.job] and s < servers.MaxPlayers and s > bestSeats then
				best, bestSeats = e, s
			end
		end
		if best then
			return { kind = "join", id = best.id }
		end
		-- 2. fullest under the target
		for _, e in live do
			local s = Matchmaker.seats(e, now)
			if
				s < servers.MatchTarget
				and (s > bestSeats or (s == bestSeats and best and e.id < best.id))
			then
				best, bestSeats = e, s
			end
		end
		if best then
			return { kind = "join", id = best.id }
		end
		-- 3. emptiest under the soft cap
		bestSeats = math.huge
		for _, e in live do
			local s = Matchmaker.seats(e, now)
			if
				s < servers.MatchSoftCap
				and (s < bestSeats or (s == bestSeats and best and e.id < best.id))
			then
				best, bestSeats = e, s
			end
		end
		if best then
			return { kind = "join", id = best.id }
		end
		-- 4. most recently frozen
		local newest = -math.huge
		for _, e in entries do
			if
				frozenLive(e, now)
				and not Matchmaker.isLive(e, now)
				and (e.frozenAt :: number) > newest
			then
				best, newest = e, e.frozenAt :: number
			end
		end
		if best then
			return { kind = "wake", id = best.id }
		end
		return { kind = "new" }
	end

	-- May a player pick this row from the server list?
	function Matchmaker.canJoin(e: Entry?, now: number): boolean
		if e == nil then
			return false
		end
		if Matchmaker.isLive(e, now) then
			return Matchmaker.seats(e, now) < servers.MaxPlayers
		end
		return frozenLive(e, now)
	end

	-- Rows for the server list: friends first, then live by players, then frozen newest first.
	function Matchmaker.rows(
		entries: { Entry },
		friendJobs: { [string]: boolean },
		now: number
	): { Row }
		local rows: { Row } = {}
		for _, e in entries do
			if e.state == "live" or frozenLive(e, now) then
				local waking = e.state == "frozen" and Matchmaker.isLive(e, now)
				local seats = Matchmaker.seats(e, now)
				table.insert(rows, {
					id = e.id,
					state = if waking then "live" else e.state,
					day = e.day,
					players = e.players,
					max = servers.MaxPlayers,
					friend = e.job ~= nil and friendJobs[e.job] == true,
					endsIn = if e.state == "frozen" and not waking
						then servers.FreezeEndSeconds - (now - (e.frozenAt :: number))
						else nil,
					full = seats >= servers.MaxPlayers,
				})
			end
		end
		table.sort(rows, function(a, b)
			if a.friend ~= b.friend then
				return a.friend
			end
			if a.state ~= b.state then
				return a.state == "live"
			end
			if a.state == "live" and a.players ~= b.players then
				return a.players > b.players
			end
			if a.state == "frozen" and a.endsIn ~= b.endsIn then
				return (a.endsIn or 0) > (b.endsIn or 0)
			end
			return a.id < b.id
		end)
		return rows
	end

	return Matchmaker
end
