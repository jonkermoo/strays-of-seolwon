--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Progression = require("../src/shared/Config/Progression")
local Unlocks = require("../src/shared/Rules/Unlocks")(Progression)
local FarmGuard = require("../src/shared/Rules/FarmGuard")

local function has(list: { string }, x: string): boolean
	return table.find(list, x) ~= nil
end

return {
	["the unlock table has no problems"] = function()
		local p = Unlocks.problems()
		assert(#p == 0, table.concat(p, "; "))
	end,
	["class ladder matches the doc (U, 12)"] = function()
		local want = {
			rifleman = 0,
			medic = 50,
			engineer = 100,
			supplier = 200,
			marksman = 300,
			decon = 400,
			grenadier = 500,
			radioman = 700,
			heavy = 850,
			marine = 1000,
			ranger = 2000,
		}
		for id, m in want do
			assert(Unlocks.classGate(id) == m, id)
		end
		assert(#Progression.Classes == 11)
	end,
	["a new player has only the Rifleman; the release code opens Medic and Engineer"] = function()
		assert(Unlocks.classUnlocked(0, "rifleman") and not Unlocks.classUnlocked(0, "medic"))
		local m = Progression.ReleaseCode.marks
		assert(Unlocks.classUnlocked(m, "medic") and Unlocks.classUnlocked(m, "engineer"))
		assert(not Unlocks.classUnlocked(m, "supplier"))
	end,
	["the Marine also needs the carrier"] = function()
		assert(not Unlocks.classUnlocked(5000, "marine"))
		assert(Unlocks.classUnlocked(5000, "marine", nil, true)) -- loadout screen: shown, locked
		assert(Unlocks.classUnlocked(1000, "marine", { carrierArrived = true }))
		assert(not Unlocks.classUnlocked(999, "marine", { carrierArrived = true }))
	end,
	["a gun needs its own gate, its class list and the class gate"] = function()
		assert(Unlocks.gunEquippable(0, "H2", "rifleman"))
		assert(not Unlocks.gunEquippable(99, "H16", "rifleman"))
		assert(Unlocks.gunEquippable(100, "H16", "rifleman"))
		assert(not Unlocks.gunEquippable(5000, "H14", "rifleman")) -- Marksman only
		assert(not Unlocks.gunEquippable(250, "H1A", "marksman")) -- class gate 300
		assert(Unlocks.gunEquippable(300, "H1A", "marksman"))
		assert(Unlocks.gunEquippable(600, "H45", "medic")) -- sidearm for all
		local g = Unlocks.guns(100, "medic")
		assert(
			has(g, "H2") and has(g, "H1A") and has(g, "HP-87") and has(g, "H16") and has(g, "H5")
		)
		assert(not has(g, "H7"))
	end,
	["unlocked means craftable, at the right bench"] = function()
		assert(not Unlocks.canCraft(24, "hand_flares", "rifleman", "field"))
		assert(Unlocks.canCraft(25, "hand_flares", "rifleman", "field"))
		assert(Unlocks.canCraft(300, "c4", "medic", "field"))
		assert(not Unlocks.canCraft(300, "h72_tube", "medic", "field")) -- full bench only
		assert(Unlocks.canCraft(300, "h72_tube", "medic", "full"))
		assert(Unlocks.canCraft(1500, "nvg", "medic", "full")) -- every class crafts NVG at 1,500
		assert(not Unlocks.canCraft(300, "placed_mg", "rifleman", "full")) -- Engineer only
		assert(Unlocks.canCraft(300, "placed_mg", "engineer", "full"))
		assert(not Unlocks.canCraft(5000, "mask", "rifleman", "full")) -- no recipe
		-- every item with a recipe is craftable by someone exactly at its gate
		for id, it in Progression.Items do
			if it.cost then
				local cls = if it.classes[1] == "*" then "rifleman" else it.classes[1]
				local gate = math.max(it.marks, Unlocks.classGate(cls) :: number)
				local ctx = { serverBlueprints = { auto_mg = true } }
				assert(Unlocks.canCraft(gate, id, cls, "full", ctx), id)
				if it.marks > 0 then
					assert(not Unlocks.canCraft(it.marks - 1, id, cls, "full", ctx), id)
				end
			end
		end
	end,
	["the auto MG needs the server blueprint"] = function()
		assert(not Unlocks.canCraft(1000, "auto_mg", "engineer", "full"))
		assert(
			Unlocks.canCraft(
				1000,
				"auto_mg",
				"engineer",
				"full",
				{ serverBlueprints = { auto_mg = true } }
			)
		)
	end,
	["engines: Engineer, full bench, docked on this server, the drive marks"] = function()
		local ctx = { docked = { hv4 = true } }
		assert(not Unlocks.canCraftEngine(300, "hv4", "engineer", "full"))
		assert(Unlocks.canCraftEngine(300, "hv4", "engineer", "full", ctx))
		assert(not Unlocks.canCraftEngine(299, "hv4", "engineer", "full", ctx))
		assert(not Unlocks.canCraftEngine(300, "hv4", "rifleman", "full", ctx))
		assert(not Unlocks.canCraftEngine(300, "hv4", "engineer", "field", ctx))
	end,
	["driving gates, none over 500 except boats (Marine)"] = function()
		assert(
			not Unlocks.canDrive(49, "atv", "rifleman") and Unlocks.canDrive(50, "atv", "rifleman")
		)
		assert(Unlocks.canDrive(500, "light_tank", "medic"))
		assert(
			not Unlocks.canDrive(5000, "boat", "ranger")
				and Unlocks.canDrive(1000, "boat", "marine")
		)
		for id, v in Progression.Vehicles do
			assert(v.marks <= 500 or id == "boat", id)
		end
	end,
	["rare-part builds need 300 and an Engineer"] = function()
		assert(not Unlocks.canStartBuild(299, "mortar_pit", "engineer"))
		assert(Unlocks.canStartBuild(300, "mortar_pit", "engineer"))
		assert(not Unlocks.canStartBuild(5000, "mortar_pit", "heavy"))
		assert(Unlocks.canStartBuild(100, "aid_station", "engineer"))
	end,
	["spawn items: mask at 50, NVG at 1,500 on Rifleman/Marine/Ranger, Grenadier explosives"] = function()
		assert(
			not has(Unlocks.spawnItems(49, "medic"), "mask")
				and has(Unlocks.spawnItems(50, "medic"), "mask")
		)
		assert(
			has(Unlocks.spawnItems(1500, "rifleman"), "nvg")
				and not has(Unlocks.spawnItems(1500, "medic"), "nvg")
		)
		assert(has(Unlocks.spawnItems(2000, "ranger"), "nvg"))
		assert(
			has(Unlocks.spawnItems(500, "grenadier"), "c4")
				and has(Unlocks.spawnItems(500, "grenadier"), "h72_tube")
		)
	end,
	["rank patch steps"] = function()
		local function p(m: number): string
			local r = Unlocks.rankPatch(m)
			return r.family .. r.count
		end
		assert(p(0) == "recruit0" and p(99) == "recruit0")
		assert(p(100) == "white_bars1" and p(599) == "white_bars5")
		assert(p(600) == "white_chevrons1" and p(1199) == "white_chevrons5")
		assert(p(1200) == "white_studs1" and p(2000) == "white_studs5")
		assert(p(2200) == "gold_bars1" and p(4800) == "gold_studs4")
		assert(
			p(5000) == "black1"
				and p(9999) == "black5"
				and p(10000) == "seolwon1"
				and p(99999) == "seolwon1"
		)
	end,
	["newBetween lists what a jump in marks opens"] = function()
		local list = Unlocks.newBetween(0, 100)
		local names = {}
		for _, u in list do
			names[u.kind .. ":" .. u.id] = true
		end
		assert(
			names["class:medic"]
				and names["class:engineer"]
				and names["gun:H16"]
				and names["item:mask"]
		)
		assert(not names["class:rifleman"] and not names["class:supplier"])
	end,
	["kill farm guard: 20 at one spot in 5 min, then nothing"] = function()
		local g = FarmGuard.new(Progression.KillFarm)
		for i = 1, 20 do
			assert(g.allow(10, 10, i))
		end
		assert(not g.allow(12, 12, 21))
		assert(g.allow(500, 500, 22)) -- another spot pays
		assert(g.allow(10, 10, 21 + 300)) -- window passed
	end,
}
