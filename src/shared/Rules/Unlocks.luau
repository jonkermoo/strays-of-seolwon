--!strict
-- What a player's marks unlock. Pure; used by the server (authority) and the client (menus).
--   local Unlocks = require(Rules.Unlocks)(Config.Progression)
--
-- Rule (user, 2026-11-17): if it is unlocked/equippable, it is craftable. An item has one
-- marks gate; crafting it also needs the right bench, class and any per-server condition.

export type Ctx = {
	carrierArrived: boolean?,
	serverBlueprints: { [string]: boolean }?, -- carried to a full bench on this server
	docked: { [string]: boolean }?, -- vehicle types docked at an HQ on this server
	blueprints: { [string]: boolean }?, -- the player's loadout blueprints
}

return function(cfg: any)
	local Unlocks = {}
	local ALL = cfg.AllClasses

	local classById: { [string]: any } = {}
	for _, c in cfg.Classes do
		classById[c.id] = c
	end

	local function allows(list: { string }?, classId: string?): boolean
		if list == nil then
			return true
		end
		for _, c in list do
			if c == ALL or c == classId then
				return true
			end
		end
		return false
	end
	Unlocks.allows = allows

	local function condition(needs: string?, ctx: Ctx?): boolean
		if needs == nil then
			return true
		end
		local c: Ctx = ctx or {}
		if needs == "carrierArrived" then
			return c.carrierArrived == true
		end
		local kind, id = string.match(needs, "^(%w+):(.+)$")
		if kind == "serverBlueprint" then
			return (c.serverBlueprints or {})[id] == true
		elseif kind == "docked" then
			return (c.docked or {})[id] == true
		end
		return false
	end

	function Unlocks.classGate(classId: string): number?
		local c = classById[classId]
		return c and c.marks
	end

	-- `ignoreNeeds` = marks alone (the loadout screen shows "arrives with the carrier").
	function Unlocks.classUnlocked(
		marks: number,
		classId: string,
		ctx: Ctx?,
		ignoreNeeds: boolean?
	): boolean
		local c = classById[classId]
		if c == nil or marks < c.marks then
			return false
		end
		return ignoreNeeds == true or condition(c.needs, ctx)
	end

	function Unlocks.classes(
		marks: number,
		ctx: Ctx?
	): { { id: string, marks: number, open: boolean } }
		local out = {}
		for _, c in cfg.Classes do
			table.insert(
				out,
				{ id = c.id, marks = c.marks, open = Unlocks.classUnlocked(marks, c.id, ctx) }
			)
		end
		return out
	end

	-- Can this class take this gun into its loadout?
	function Unlocks.gunEquippable(
		marks: number,
		gunId: string,
		classId: string,
		ctx: Ctx?
	): boolean
		local g = cfg.Guns[gunId]
		if g == nil or not Unlocks.classUnlocked(marks, classId, ctx) then
			return false
		end
		if g.blueprint and not (ctx and ctx.blueprints or {})[gunId] then
			return false
		end
		return marks >= g.marks and allows(g.classes, classId)
	end

	function Unlocks.guns(marks: number, classId: string, ctx: Ctx?): { string }
		local out = {}
		for id in cfg.Guns do
			if Unlocks.gunEquippable(marks, id, classId, ctx) then
				table.insert(out, id)
			end
		end
		table.sort(out, function(a, b)
			local ga, gb = cfg.Guns[a].marks, cfg.Guns[b].marks
			return if ga == gb then a < b else ga < gb
		end)
		return out
	end

	-- Unlocked = equippable (for its classes). Marks only, class optional.
	function Unlocks.itemUnlocked(marks: number, itemId: string, classId: string?): boolean
		local it = cfg.Items[itemId]
		if it == nil or marks < it.marks then
			return false
		end
		return classId == nil or allows(it.classes, classId)
	end

	-- Craftable = unlocked + has a recipe + bench is good enough + per-server condition.
	function Unlocks.canCraft(
		marks: number,
		itemId: string,
		classId: string,
		bench: string,
		ctx: Ctx?
	): boolean
		local it = cfg.Items[itemId]
		if it == nil or it.cost == nil then
			return false
		end
		if not Unlocks.itemUnlocked(marks, itemId, classId) then
			return false
		end
		if it.bench == "full" and bench ~= "full" then
			return false
		end
		return condition(it.needs, ctx)
	end

	-- Engine for a wreck: Engineer, full bench, vehicle docked on this server, its drive marks.
	function Unlocks.canCraftEngine(
		marks: number,
		vehicleId: string,
		classId: string,
		bench: string,
		ctx: Ctx?
	): boolean
		local v = cfg.Vehicles[vehicleId]
		if v == nil or v.engine == nil or bench ~= cfg.EngineBench then
			return false
		end
		if not allows(cfg.EngineClasses, classId) or marks < v.marks then
			return false
		end
		return condition("docked:" .. vehicleId, ctx)
	end

	function Unlocks.canDrive(marks: number, vehicleId: string, classId: string): boolean
		local v = cfg.Vehicles[vehicleId]
		return v ~= nil and marks >= v.marks and allows(v.classes, classId)
	end

	function Unlocks.canStartBuild(marks: number, buildId: string, classId: string): boolean
		local b = cfg.Builds[buildId]
		return b ~= nil and marks >= b.marks and allows(cfg.BuildClasses, classId)
	end

	-- Items this class spawns with at these marks (the shared kit is not listed).
	function Unlocks.spawnItems(marks: number, classId: string): { string }
		local out = {}
		for _, s in cfg.SpawnItems do
			if marks >= s.marks and allows(s.classes, classId) then
				table.insert(out, s.item)
			end
		end
		return out
	end

	function Unlocks.rankPatch(marks: number): { at: number, family: string, count: number }
		local best = cfg.RankPatch[1]
		for _, step in cfg.RankPatch do
			if marks >= step.at then
				best = step
			end
		end
		return best
	end

	-- Everything whose marks gate lies in (before, after]: for "unlocked!" messages.
	function Unlocks.newBetween(
		before: number,
		after: number
	): { { kind: string, id: string, marks: number } }
		local out = {}
		local function add(kind: string, id: string, m: number)
			if m > before and m <= after then
				table.insert(out, { kind = kind, id = id, marks = m })
			end
		end
		for _, c in cfg.Classes do
			add("class", c.id, c.marks)
		end
		for id, g in cfg.Guns do
			add("gun", id, g.marks)
		end
		for id, it in cfg.Items do
			add("item", id, it.marks)
		end
		for id, v in cfg.Vehicles do
			add("vehicle", id, v.marks)
		end
		table.sort(out, function(a, b)
			return if a.marks == b.marks then a.kind .. a.id < b.kind .. b.id else a.marks < b.marks
		end)
		return out
	end

	-- Table problems (empty list = fine). Run by the tests.
	function Unlocks.problems(): { string }
		local out = {}
		local function bad(msg: string)
			table.insert(out, msg)
		end
		local last = -1
		for _, c in cfg.Classes do
			if c.marks < last then
				bad("class ladder out of order at " .. c.id)
			end
			last = c.marks
		end
		local function checkClasses(where: string, list: { string }?)
			for _, c in list or {} do
				if c ~= ALL and classById[c] == nil then
					bad(where .. " names unknown class " .. c)
				end
			end
		end
		for id, g in cfg.Guns do
			checkClasses("gun " .. id, g.classes)
			-- a gun nobody can ever reach is a mistake
			local reachable = false
			for _, c in cfg.Classes do
				if allows(g.classes, c.id) then
					reachable = true
				end
			end
			if not reachable then
				bad("gun " .. id .. " has no class")
			end
		end
		for id, it in cfg.Items do
			checkClasses("item " .. id, it.classes)
			if it.cost and it.bench ~= "field" and it.bench ~= "full" then
				bad("item " .. id .. " has a recipe but no bench")
			end
		end
		for _, s in cfg.SpawnItems do
			checkClasses("spawn item " .. s.item, s.classes)
			local it = cfg.Items[s.item]
			if it == nil then
				bad("spawn item " .. s.item .. " is not an item")
			elseif s.marks < it.marks then
				-- a spawn item before its own gate is fine only for a class's own kit
				if s.marks ~= 0 or allows(s.classes, "rifleman") then
					bad("spawn item " .. s.item .. " comes before its unlock")
				end
			end
		end
		checkClasses("builds", cfg.BuildClasses)
		checkClasses("engines", cfg.EngineClasses)
		return out
	end

	return Unlocks
end
