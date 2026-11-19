--!strict
-- Rank steps for analytics. Pure; the caller passes the progression config:
--   local RankTrack = require(Rules.RankTrack)(Config.Progression)
--
-- Steps = 0 (joined) + Progression.RankLadder + Progression.RankLadderBeyond, in marks.
-- Step index 1 is "joined" (0 marks), so funnel and progression levels start at 1.

export type Step = { index: number, at: number, name: string }

return function(cfg: any)
	local RankTrack = {}

	local steps: { Step } = {}
	local function add(at: number)
		-- Zero-padded so dashboard breakdowns sort in ladder order ("m00100" < "m01200").
		table.insert(steps, { index = #steps + 1, at = at, name = string.format("m%05d", at) })
	end
	add(0)
	local last = 0
	for _, list in { cfg.RankLadder, cfg.RankLadderBeyond } do
		for _, at in list do
			assert(at > last, "rank ladder must be strictly increasing")
			add(at)
			last = at
		end
	end
	RankTrack.steps = table.freeze(steps)

	-- The highest step at or below these marks.
	function RankTrack.stepFor(marks: number): Step
		local best = steps[1]
		for _, s in steps do
			if marks >= s.at then
				best = s
			else
				break
			end
		end
		return best
	end

	-- Steps reached above `logged` marks, up to `marks` (lowest first). `logged` is the
	-- highest step threshold already reported for this player.
	function RankTrack.crossed(logged: number, marks: number): { Step }
		local out = {}
		for _, s in steps do
			if s.at > logged and s.at <= marks then
				table.insert(out, s)
			end
		end
		return out
	end

	return RankTrack
end
