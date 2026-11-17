--!strict
-- A player's saved data and the rules that change it. Pure; the caller passes the configs:
--   local PlayerSave = require(Rules.PlayerSave)(Config.Progression, Config.Servers)
--
-- Only marks (and what follows from them), lore, loadout blueprints, cosmetics and settings
-- are saved. Nothing a player carried is ever saved.
--
-- Marks rules (user, 2026-11-17):
--   - only go up, never spent, never lost;
--   - "never go below highest seen": every merge or restore keeps the larger value, and the
--     server keeps a separate highest-marks backup (Config.Servers.Stores.MarksHigh);
--   - a per-source lifetime total and a short log of the last awards, for audits and restores.

export type LogEntry = { source: string, amount: number, at: number }

export type Save = {
	v: number,
	marks: number,
	sources: { [string]: number }, -- lifetime marks per source
	log: { LogEntry }, -- newest last, capped
	guideDone: boolean, -- release code granted
	lore: { [string]: boolean },
	blueprints: { [string]: boolean }, -- loadout blueprints (per player, forever)
	cosmetics: {
		selected: { [string]: string }, -- marks-track slot -> cosmetic id
		robux: { [string]: boolean }, -- owned Robux cosmetics
	},
	settings: { [string]: any },
	lastClass: string,
	firstJoin: number,
	lastJoin: number,
}

return function(progression: any, servers: any)
	local PlayerSave = {}

	function PlayerSave.new(now: number): Save
		return {
			v = servers.SchemaVersion,
			marks = 0,
			sources = {},
			log = {},
			guideDone = false,
			lore = {},
			blueprints = {},
			cosmetics = { selected = {}, robux = {} },
			settings = {},
			lastClass = "rifleman",
			firstJoin = now,
			lastJoin = now,
		}
	end

	-- Fill any missing field and upgrade old versions. Never lowers marks.
	function PlayerSave.migrate(raw: any, now: number): Save
		local base = PlayerSave.new(now)
		if type(raw) ~= "table" then
			return base
		end
		for k, v in base :: any do
			if raw[k] == nil or type(raw[k]) ~= type(v) then
				raw[k] = v
			end
		end
		if type(raw.cosmetics.selected) ~= "table" then
			raw.cosmetics.selected = {}
		end
		if type(raw.cosmetics.robux) ~= "table" then
			raw.cosmetics.robux = {}
		end
		raw.marks = math.max(0, math.floor(raw.marks))
		raw.v = servers.SchemaVersion
		return raw :: Save
	end

	-- Add marks for one action. Returns the amount actually added (0 if rejected).
	function PlayerSave.award(save: Save, source: string, amount: number?, now: number): number
		local fixed = progression.Sources[source]
		if fixed == nil then
			return 0
		end
		local add = if source == "admin" then (amount or 0) else fixed
		add = math.floor(add)
		if add <= 0 then
			return 0
		end
		save.marks += add
		save.sources[source] = (save.sources[source] or 0) + add
		table.insert(save.log, { source = source, amount = add, at = now })
		while #save.log > servers.MarksLogLength do
			table.remove(save.log, 1)
		end
		return add
	end

	-- The release code: +100 once, when the guide is finished.
	function PlayerSave.finishGuide(save: Save, now: number): number
		if save.guideDone then
			return 0
		end
		save.guideDone = true
		return PlayerSave.award(save, progression.ReleaseCode.source, nil, now)
	end

	-- Combine what is stored with what this server holds: never lose marks or found things.
	-- `ours` wins for choices (selected cosmetics, settings, class); sets are unioned.
	function PlayerSave.merge(stored: Save?, ours: Save): Save
		if stored == nil then
			return ours
		end
		local out = table.clone(ours)
		out.marks = math.max(stored.marks, ours.marks)
		out.guideDone = stored.guideDone or ours.guideDone
		local function union(a: { [string]: boolean }, b: { [string]: boolean })
			local u = table.clone(a)
			for k, v in b do
				u[k] = u[k] or v
			end
			return u
		end
		out.lore = union(stored.lore, ours.lore)
		out.blueprints = union(stored.blueprints, ours.blueprints)
		out.cosmetics = {
			selected = ours.cosmetics.selected,
			robux = union(stored.cosmetics.robux, ours.cosmetics.robux),
		}
		local sources = table.clone(stored.sources)
		for k, v in ours.sources do
			sources[k] = math.max(sources[k] or 0, v)
		end
		out.sources = sources
		out.firstJoin = math.min(stored.firstJoin, ours.firstJoin)
		return out
	end

	-- Apply the highest-marks backup on load (restore after corruption or a rollback).
	function PlayerSave.applyHighest(save: Save, highest: number?): Save
		if type(highest) == "number" and highest > save.marks then
			local missing = math.floor(highest) - save.marks
			save.marks += missing
			save.sources.restored = (save.sources.restored or 0) + missing
		end
		return save
	end

	function PlayerSave.addLore(save: Save, id: string): boolean
		if save.lore[id] then
			return false
		end
		save.lore[id] = true
		return true
	end

	function PlayerSave.addBlueprint(save: Save, id: string): boolean
		if save.blueprints[id] then
			return false
		end
		save.blueprints[id] = true
		return true
	end

	return PlayerSave
end
