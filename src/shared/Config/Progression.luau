--!strict
-- Marks and everything they unlock. Pure data, no Roblox objects (Lune tests read it).
-- Marks: one number per player, only goes up, never spent, saved across servers.
-- Rules that read this table: src/shared/Rules/Unlocks.luau.

local ALL = "*" -- any class

-- Rank patch: a cosmetic step every 100 or 200 marks up to 10,000.
local function rankSteps()
	local steps = { { at = 0, family = "recruit", count = 0 } }
	local function run(family: string, first: number, step: number, n: number)
		for i = 1, n do
			table.insert(steps, { at = first + (i - 1) * step, family = family, count = i })
		end
	end
	run("white_bars", 100, 100, 5)
	run("white_chevrons", 600, 100, 5)
	run("white_studs", 1200, 200, 5)
	run("gold_bars", 2200, 200, 5)
	run("gold_chevrons", 3200, 200, 5)
	run("gold_studs", 4200, 200, 4)
	for i, at in { 5000, 6000, 7000, 8000, 9000 } do
		table.insert(steps, { at = at, family = "black", count = i })
	end
	table.insert(steps, { at = 10000, family = "seolwon", count = 1 })
	return steps
end

return table.freeze({
	AllClasses = ALL,

	-- Granted once, when the player finishes the menu guide.
	ReleaseCode = table.freeze({ marks = 100, source = "release_code" }),

	-- Class ladder. `needs` names a server condition that must also hold.
	Classes = table.freeze({
		{ id = "rifleman", marks = 0 },
		{ id = "medic", marks = 50 },
		{ id = "engineer", marks = 100 },
		{ id = "supplier", marks = 200 },
		{ id = "marksman", marks = 300 },
		{ id = "decon", marks = 400 },
		{ id = "grenadier", marks = 500 },
		{ id = "radioman", marks = 700 },
		{ id = "heavy", marks = 850 },
		{ id = "marine", marks = 1000, needs = "carrierArrived" },
		{ id = "ranger", marks = 2000 },
	}),

	-- Each gun has its own gate; the class gate applies too. `classes` = who may take it.
	-- `craftOnly` guns are never in a loadout; they are crafted items (see Items).
	Guns = table.freeze({
		H5 = { marks = 0, classes = { ALL } },
		H45 = { marks = 600, classes = { ALL } },
		H2 = {
			marks = 0,
			classes = { "rifleman", "medic", "engineer", "supplier", "decon", "radioman" },
		},
		H1A = {
			marks = 50,
			classes = {
				"medic",
				"engineer",
				"supplier",
				"marksman",
				"decon",
				"grenadier",
				"radioman",
			},
		},
		["HP-87"] = { marks = 50, classes = { "medic", "engineer", "supplier", "decon" } },
		H16 = { marks = 100, classes = { "rifleman", "medic", "supplier", "radioman" } },
		["HS-12"] = { marks = 150, classes = { "engineer", "decon", "heavy", "marine" } },
		H7 = { marks = 250, classes = { "medic", "engineer", "decon", "radioman", "ranger" } },
		H2C = { marks = 300, classes = { "rifleman", "radioman" } },
		H2M = { marks = 300, classes = { "rifleman", "marksman", "marine" } },
		H14 = { marks = 400, classes = { "marksman" } },
		H3 = { marks = 450, classes = { "rifleman", "supplier", "heavy" } },
		["H2+H201"] = { marks = 500, classes = { "grenadier" } },
		H11 = { marks = 600, classes = { "grenadier" } },
		H40 = { marks = 700, classes = { "grenadier" } },
		H67 = { marks = 800, classes = { "grenadier" } },
		H12 = { marks = 850, classes = { "heavy" } },
		H60 = { marks = 850, classes = { "heavy", "marine" } },
		H15 = { marks = 900, classes = { "heavy", "ranger" } },
		H16A2 = { marks = 1000, classes = { "marine" } },
		["H2C-M"] = { marks = 1000, classes = { "marine", "ranger" } },
		H14S = { marks = 1200, classes = { "marksman" } },
		H107 = { marks = 1500, classes = { "marksman", "ranger" } },
		["HS-16"] = { marks = 2000, classes = { "ranger" } },
	}),

	-- Items and kit. Rule (user, 2026-11-17): if it is unlocked/equippable, it is craftable.
	-- So an item has ONE marks gate; at that gate it is both equippable and (with a recipe) craftable.
	--   classes: who may use/craft it.   bench: "field" or "full" (full can make field items).
	--   cost: crates (S Stores, M Materials, E Electronics, G Engine parts, W Weapon parts).
	--   needs: a per-server condition ("serverBlueprint:<id>", "docked:<vehicle>").
	Items = table.freeze({
		toolkit = { marks = 0, classes = { ALL } },
		hand_flares = { marks = 25, classes = { ALL }, bench = "field", cost = { S = 1 } },
		headlamp = { marks = 25, classes = { ALL }, bench = "field", cost = { M = 1 } },
		mask = { marks = 50, classes = { ALL } },
		lockpick = { marks = 50, classes = { ALL }, bench = "field", cost = { M = 1 } },
		binoculars = { marks = 50, classes = { ALL }, bench = "field", cost = { M = 1 } },
		backpack = { marks = 125, classes = { ALL }, bench = "field", cost = { M = 3 } },
		blowtorch = { marks = 125, classes = { ALL }, bench = "field", cost = { M = 2 } },
		c4 = { marks = 300, classes = { ALL }, bench = "field", cost = { S = 2 } },
		h72_tube = { marks = 300, classes = { ALL }, bench = "full", cost = { S = 2, W = 1 } },
		suppressor = { marks = 500, classes = { ALL }, bench = "full", cost = { W = 1 } },
		nvg = { marks = 1500, classes = { ALL }, bench = "full", cost = { E = 2, M = 1 } },
		nvg_batteries = { marks = 1500, classes = { ALL }, bench = "field", cost = { S = 1 } },
		heavy_rig = { marks = 1500, classes = { "heavy" } },
		placed_mg = {
			marks = 300,
			classes = { "engineer" },
			bench = "full",
			cost = { W = 1, M = 2 },
		},
		auto_mg = {
			marks = 1000,
			classes = { "engineer" },
			bench = "full",
			cost = { W = 2, E = 1, M = 4 },
			needs = "serverBlueprint:auto_mg",
		},
		radioman_drop = { marks = 1500, classes = { "radioman" } },
	}),

	-- What a class spawns with (beyond its gun and the shared kit). `marks` = from this many marks.
	SpawnItems = table.freeze({
		{ item = "toolkit", classes = { ALL }, marks = 0 },
		{ item = "mask", classes = { ALL }, marks = 50 },
		{ item = "nvg", classes = { "rifleman", "marine", "ranger" }, marks = 1500 },
		{ item = "c4", classes = { "grenadier" }, marks = 0 },
		{ item = "h72_tube", classes = { "grenadier" }, marks = 0 },
		{ item = "heavy_rig", classes = { "heavy" }, marks = 1500 },
	}),

	-- Driver seat (none over 500). Crafting a vehicle's engine needs the same marks as driving it.
	Vehicles = table.freeze({
		atv = { marks = 50, engine = { G = 1 } },
		light_truck = { marks = 100, engine = { G = 1 } },
		supply_truck = { marks = 150, engine = { G = 1 } },
		hauler = { marks = 150, engine = { G = 1 } },
		med_truck = { marks = 200, engine = { G = 1 } },
		hv4 = { marks = 300, engine = { G = 2 } },
		hav9 = { marks = 400, engine = { G = 2 } },
		light_tank = { marks = 500, engine = { G = 3 } },
		boat = { marks = 1000, classes = { "marine" } },
	}),
	EngineBench = "full",
	EngineClasses = { "engineer" },

	-- HQ 1 build station: Engineer only; builds that use rare parts need 300+ marks to start.
	Builds = table.freeze({
		truck_role_swap = { marks = 0, cost = { M = 5 } },
		hardened_mast = { marks = 300, cost = { M = 2, E = 2 } },
		wall_alarm = { marks = 300, cost = { M = 1, E = 1 } },
		relay_link = { marks = 300, cost = { M = 4, E = 3 } },
		mortar_pit = { marks = 300, cost = { M = 6, W = 3 } },
		at_post = { marks = 300, cost = { M = 4, W = 3 } },
		aid_station = { marks = 0, cost = { M = 6, S = 2 } },
		surgery = { marks = 0, cost = { M = 8, S = 3 } },
	}),
	BuildClasses = { "engineer" },

	RankPatch = table.freeze(rankSteps()),

	-- Marks-track cosmetic slots (work on every class). Thresholds are set later (art not ready).
	CosmeticSlots = table.freeze({ "vest", "uniform", "bag" }),
	MarksTrackCosmetics = table.freeze({} :: { [string]: { slot: string, marks: number } }),

	-- Marks pay for specific actions, never broad outcomes. Paid to the player who did it.
	Sources = table.freeze({
		kill = 1,
		kill_special = 3, -- radioman, officer or heavy
		destroy_truck = 10,
		destroy_armour = 15,
		destroy_post = 10, -- MG nest, radio set or depot
		destroy_base = 25,
		breach_gate = 10, -- gated-zone blast door or rubble with C4
		heal = 1,
		revive = 5,
		deliver_crate = 2,
		move_crate = 1,
		deliver_rare = 10,
		deliver_blueprint = 10,
		support_drop = 10,
		hand_crate = 2,
		install_project = 4,
		fortify = 2,
		repair_station = 5,
		repair_wall = 2,
		repair_gate = 3,
		repair_vehicle = 2,
		claim_switch = 15,
		retake_command = 30,
		deliver_documents = 10,
		release_code = 100,
		admin = 0, -- amount given by the admin command
	}),

	-- Anti-farm: kills at one spot pay nothing after this many in the window.
	KillFarm = table.freeze({ limit = 20, windowSeconds = 300, spotStuds = 60 }),
})
