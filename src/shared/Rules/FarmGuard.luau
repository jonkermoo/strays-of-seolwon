--!strict
-- Anti-farm for kill marks: kills at one spot pay nothing after `limit` within `windowSeconds`.
-- A "spot" is a grid cell `spotStuds` wide. Pure; one guard per player.
--   local guard = FarmGuard.new(Config.Progression.KillFarm)
--   if guard.allow(x, z, now) then award kill marks end

local FarmGuard = {}

function FarmGuard.new(cfg: { limit: number, windowSeconds: number, spotStuds: number })
	local hits: { [string]: { number } } = {}
	local self = {}
	function self.allow(x: number, z: number, now: number): boolean
		local key = math.floor(x / cfg.spotStuds) .. ":" .. math.floor(z / cfg.spotStuds)
		local list = hits[key] or {}
		local keep = {}
		for _, at in list do
			if now - at < cfg.windowSeconds then
				table.insert(keep, at)
			end
		end
		local ok = #keep < cfg.limit
		table.insert(keep, now)
		hits[key] = keep
		return ok
	end
	return self
end

return FarmGuard
