--!strict
-- Session locking for player saves: only one server may write a player's save at a time.
-- Pure; works on any Store from MemoryBackend or src/serverlib/Stores.luau.
--   local SessionLock = require(Rules.SessionLock)(Config.Servers)
--
-- Record shape in the store: { lock = { job = string, at = number } | nil, data = Save }
--   acquire: take the lock if free, ours, or stale (not refreshed for LockStaleSeconds).
--   save:    write data and refresh the lock, only while we still hold it.
--   release: save one last time and clear the lock.
-- A server that finds its lock taken by another server must stop writing ("lost").

export type Result = "ok" | "locked" | "lost" | "error"

return function(servers: any)
	local SessionLock = {}

	function SessionLock.acquire(store: any, key: string, job: string, now: number): (Result, any)
		local result: Result = "ok"
		local ok, record = store.update(key, function(old: any)
			result = "ok" -- the real UpdateAsync may run this more than once
			old = old or {}
			local lock = old.lock
			if lock and lock.job ~= job and now - lock.at < servers.LockStaleSeconds then
				result = "locked"
				return nil
			end
			old.lock = { job = job, at = now }
			return old
		end)
		if not ok then
			return "error", nil
		end
		if result ~= "ok" then
			return result, nil
		end
		return "ok", record.data
	end

	-- `merge(stored, ours)` combines the stored save with ours (PlayerSave.merge) so a racing
	-- write can never lower marks.
	function SessionLock.save(
		store: any,
		key: string,
		job: string,
		data: any,
		now: number,
		release: boolean,
		merge: ((any, any) -> any)?
	): Result
		local result: Result = "ok"
		local ok = store.update(key, function(old: any)
			result = "ok"
			old = old or {}
			if old.lock == nil or old.lock.job ~= job then
				result = "lost"
				return nil
			end
			old.data = if merge then merge(old.data, data) else data
			old.lock = if release then nil else { job = job, at = now }
			return old
		end)
		if not ok then
			return "error"
		end
		return result
	end

	return SessionLock
end
