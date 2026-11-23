--!strict
-- Baked clips from the jarvis motion study (Seolwon rifleman, v11, approved by the user 2026-11-23): the study's
-- solver sampled at 30 fps into R6 joint Transforms (tools/animation/baked/motion-study.json). Built last, so each
-- replaces the hand-keyed clip of the same name (build.luau). Cycles carry the study's footfall bounce; the noise
-- (stride, cadence, trunk drift, head glance) is left out so they loop, and MoveTest adds the live parts.
--   bodies (root, legs, head; arms and gun too, under the holds): Idle, Walk, Sprint, CrouchIdle, CrouchWalk,
--     ProneIdle, Crawl, AimIdle, AimWalk, AimCrouchIdle, AimCrouchWalk, AimProneIdle
--   holds (arms + gun, priority Action) per cycle and carry: Hold* (low ready; HoldSprint is port arms), Safe* (safe
--     carry, muzzle down across the body), Hip* (hip fire), AimHold*
--   one-shots (whole body, Action3): the six stance changes, VaultHop, Mantle, MantleWindow (with the root's path)
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local data = serde.decode("json", fs.readFile("tools/animation/baked/motion-study.json"))
local out = {}
for _, c in data.clips do
	table.insert(
		out,
		{ name = c.name, raw = true, loop = c.loop, priority = c.priority, frames = c.frames }
	)
end
return out
