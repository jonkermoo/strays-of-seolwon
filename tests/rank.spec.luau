--!strict
--# selene: allow(incorrect_standard_library_use) -- bare asserts are fine in tests
local Progression = require("../src/shared/Config/Progression")
local Servers = require("../src/shared/Config/Servers")
local RankTrack = require("../src/shared/Rules/RankTrack")(Progression)
local PlayerSave = require("../src/shared/Rules/PlayerSave")(Progression, Servers)

return {
	["rank steps start at joined (0) and follow the ladder, then the beyond steps"] = function()
		local steps = RankTrack.steps
		assert(steps[1].at == 0 and steps[1].index == 1 and steps[1].name == "m00000")
		assert(steps[2].at == Progression.RankLadder[1])
		assert(#steps == 1 + #Progression.RankLadder + #Progression.RankLadderBeyond)
		assert(steps[#steps].name == "m10000")
	end,
	["the ladder has the 2026-11-19 steps up to a 5,000 patch"] = function()
		local want = { 100, 500, 600, 1000, 1200, 2000, 2500, 3000, 4000, 5000 }
		for _, at in want do
			assert(table.find(Progression.RankLadder, at), at)
		end
		assert(Progression.RankLadder[#Progression.RankLadder] == 5000)
	end,
	["stepFor picks the highest step at or below the marks"] = function()
		assert(RankTrack.stepFor(0).at == 0)
		assert(RankTrack.stepFor(99).at == 0)
		assert(RankTrack.stepFor(100).at == 100)
		assert(RankTrack.stepFor(1199).at == 1000)
		assert(RankTrack.stepFor(4999).at == 4000)
		assert(RankTrack.stepFor(7000).at == 6000)
		assert(RankTrack.stepFor(999999).at == 10000)
	end,
	["crossed lists each new step once, lowest first"] = function()
		local c = RankTrack.crossed(0, 350)
		assert(#c == 3 and c[1].at == 100 and c[3].at == 300)
		assert(#RankTrack.crossed(300, 350) == 0)
		local big = RankTrack.crossed(900, 2600)
		assert(big[1].at == 1000 and big[#big].at == 2500)
	end,
	["analytics save fields start at 0, survive migrate and merge keeps the larger"] = function()
		local s = PlayerSave.new(0)
		assert(s.playSeconds == 0 and s.sessions == 0 and s.rankLogged == 0)
		local old = PlayerSave.new(0) :: any
		old.playSeconds, old.sessions, old.rankLogged = nil, nil, nil
		local m = PlayerSave.migrate(old, 1)
		assert(m.playSeconds == 0 and m.sessions == 0 and m.rankLogged == 0)
		local stored = PlayerSave.new(0)
		stored.sessions, stored.playSeconds, stored.rankLogged = 5, 900, 300
		local ours = PlayerSave.new(0)
		ours.sessions, ours.playSeconds, ours.rankLogged = 4, 1000, 200
		local out = PlayerSave.merge(stored, ours)
		assert(out.sessions == 5 and out.playSeconds == 1000 and out.rankLogged == 300)
	end,
}
