--!strict
-- M2 movement body clips for Strays of Seolwon (built by tools/animation/build.luau; conventions there).
-- Style (user 2026-11-22, jarvis ANIMATION-GUIDE.md §3): "combat-ready" gait from Runenkrieg's serious set, snappy
-- with weight (anticipation 2-3 frames, action 4-6, settle 4-6 with a small overshoot, 30 fps). Rifle layers and the
-- whole-body one-shots (stance changes, vault, mantle, swim) are in tools/animation/rifle.luau.
-- The arms are keyed here too (hanging, swinging) for when nothing is in the hands; the rifle layers cover them.
-- Lean is not a clip: src/client/MoveTest tilts the root joint live (it has to sit on any cycle).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local P = luau.load(fs.readFile("tools/animation/poses.luau"), { debugName = "poses" })()

local mirror = P.mirror
local kLeg = P.kLeg
local SIDE = P.SIDE_SPREAD

-- a two-step loop: contact (left foot ahead), passing, then their mirror
local function cycle(name: string, length: number, bob: number, contact: any, passing: any): any
	local q = length / 4
	return {
		name = name,
		loop = true,
		priority = "Movement",
		footsteps = true,
		planted = bob,
		keys = {
			{ t = 0, pose = contact },
			{ t = q, pose = passing },
			{ t = 2 * q, pose = mirror(contact) },
			{ t = 3 * q, pose = mirror(passing) },
			{ t = length, pose = contact },
		},
	}
end

-- Idle: breathing only (user: no fidgets), 4 s
local idle = {
	name = "Idle",
	loop = true,
	priority = "Idle",
	planted = true,
	keys = {
		{ t = 0, pose = P.idlePose(0) },
		{ t = P.IDLE_LEN / 2, pose = P.idlePose(1) },
		{ t = P.IDLE_LEN, pose = P.idlePose(0) },
	},
}

-- Walk: lean 3, soft knees, small bob, steady head, no shoulder roll
local WL = P.WALK_LEAN
local walk = cycle("Walk", P.WALK_LEN, 0.5, {
	root = { lean = WL },
	head = { lean = -1 },
	leftLeg = { swing = 20 },
	rightLeg = { swing = -24 },
	leftArm = { swing = WL - 14, spread = SIDE },
	rightArm = { swing = WL + 14, spread = SIDE },
}, {
	root = { lean = WL },
	head = { lean = -1 },
	leftLeg = { swing = -4 },
	rightLeg = { swing = 6, y = 0.24 },
	leftArm = { swing = WL, spread = SIDE },
	rightArm = { swing = WL, spread = SIDE },
})

-- Sprint: lean 18, long strides; the head counters part of the lean to look ahead
local SL = P.SPRINT_LEAN
local function sl(world: number): number
	return world + SL
end
local sprint = cycle("Sprint", P.SPRINT_LEN, 0.6, {
	root = { lean = SL },
	head = { lean = -12 },
	leftLeg = { swing = sl(30), z = -0.15 },
	rightLeg = { swing = sl(-52), y = 0.1, z = 0.15 },
	leftArm = { swing = sl(-30), spread = SIDE + 2 },
	rightArm = { swing = sl(32), spread = SIDE + 2 },
}, {
	root = { lean = SL },
	head = { lean = -12 },
	leftLeg = { swing = sl(-12) },
	rightLeg = { swing = sl(2), y = 0.4 },
	leftArm = { swing = sl(-2), spread = SIDE + 2 },
	rightArm = { swing = sl(4), spread = SIDE + 2 },
})

-- Crouch: low ready, head top ~3.8; idle breathes, the walk is Runenkrieg's "J" creep at 0.9 s
local CL = P.CROUCH_LEAN
local crouchIdle = {
	name = "CrouchIdle",
	loop = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = P.crouchPose(CL) },
		{ t = 2, pose = P.crouchPose(CL + 1) },
		{ t = 4, pose = P.crouchPose(CL) },
	},
}
local J = {
	{ 25, 1.01, -0.75 },
	{ 5, 1.19, -0.88 },
	{ -30, 1.03, -1.15 },
	{ -60, 0.6, -1.0 },
	{ -95, -0.25, -0.25 },
	{ -60, 0.85, -0.35 },
	{ 0, 1.85, -0.6 },
	{ 35, 1.6, -0.8 },
}
local J_ARM = { 18, 12, 0, -12, -18, -12, 0, 12 }
local J_BOB = { 0, 0.5, 1, 0.5, 0, 0.5, 1, 0.5 }
local J_PLANTED = { [1] = true, [2] = true, [3] = true }
local crouchKeys = {}
for k = 0, 8 do
	local i = k % 8 + 1
	local l, r = i, (k + 4) % 8 + 1
	local bob = 0.07 * J_BOB[i]
	local function leg(pose: number): any
		local j = J[pose]
		return kLeg(j[1], j[2] - (if J_PLANTED[pose] then bob else 0), j[3])
	end
	table.insert(crouchKeys, {
		t = k / 8 * P.CROUCH_LEN,
		pose = {
			root = P.crouchRoot(CL, bob),
			leftLeg = leg(l),
			rightLeg = leg(r),
			leftArm = { swing = CL + 4 + J_ARM[r], spread = SIDE + 1 },
			rightArm = { swing = CL + 4 + J_ARM[l], spread = SIDE + 1 },
		},
	})
end
local crouchWalk =
	{ name = "CrouchWalk", loop = true, priority = "Movement", footsteps = true, keys = crouchKeys }

-- Prone: breathing on the ground
local proneIdle = {
	name = "ProneIdle",
	loop = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = P.pronePose(0) },
		{ t = 2, pose = P.pronePose(1) },
		{ t = 4, pose = P.pronePose(0) },
	},
}

-- Low crawl (elbows and knees), 1.2 s: one knee draws up out to its side while the hips shift and the torso rolls a
-- little toward it, then pushes back straight; the other side follows. The arms are the rifle layer's (forearms).
local function crawlPose(side: number, draw: number): any
	-- side 1: the right knee drawn up by `draw` (0..1)
	local base = P.pronePose(0)
	local pose = {
		root = {
			lean = P.PRONE_ROOT.lean,
			y = P.PRONE_ROOT.y + 0.06 * draw,
			z = P.PRONE_ROOT.z,
			twist = 4 * side * draw,
			tilt = 3 * side * draw,
		},
		head = { lean = -72, twist = -3 * side * draw },
		leftArm = base.leftArm,
		rightArm = base.rightArm,
	}
	local drawn = { swing = 10 + 4 * draw, spread = 9 + 38 * draw, twist = 12 * draw } -- the knee draws out along the ground
	local straight = { swing = 10 - 4 * draw, spread = 7 }
	if side > 0 then
		pose.rightLeg, pose.leftLeg = drawn, straight
	else
		pose.leftLeg, pose.rightLeg = drawn, straight
	end
	return pose
end
local CR = P.CRAWL_LEN
local crawl = {
	name = "Crawl",
	loop = true,
	priority = "Movement",
	keys = {
		{ t = 0, pose = crawlPose(1, 0) },
		{ t = CR * 0.25, pose = crawlPose(1, 1) },
		{ t = CR * 0.5, pose = crawlPose(-1, 0) },
		{ t = CR * 0.75, pose = crawlPose(-1, 1) },
		{ t = CR, pose = crawlPose(1, 0) },
	},
}

-- Jump: a 2-frame dip, push, then a tucked hop (legs drawn up); the fall keeps the tuck loosely
local function arms(swing: number, spread: number?): any
	return { swing = swing, spread = spread or SIDE }
end
local air = {
	root = { lean = 6 },
	leftLeg = { swing = 34, y = 0.25 },
	rightLeg = { swing = 18, y = 0.15 },
	leftArm = arms(10, 9),
	rightArm = arms(10, 9),
}
local air2 = {
	root = { lean = 7 },
	leftLeg = { swing = 26, y = 0.15 },
	rightLeg = { swing = 14, y = 0.1 },
	leftArm = arms(12, 10),
	rightArm = arms(12, 10),
}
local jump = {
	name = "Jump",
	priority = "Movement",
	keys = {
		{
			t = 0,
			pose = {
				root = { lean = 9, y = -0.15 },
				leftLeg = { swing = 12 },
				rightLeg = { swing = -6 },
			},
		},
		{
			t = 0.067,
			pose = {
				root = { lean = 4, y = 0.05 },
				leftLeg = { swing = 2 },
				rightLeg = { swing = -10 },
			},
		},
		{ t = 0.2, pose = air },
	},
}
local fall = {
	name = "Fall",
	loop = true,
	priority = "Movement",
	keys = { { t = 0, pose = air }, { t = 0.4, pose = air2 }, { t = 0.8, pose = air } },
}

-- Landing accents (only the body and legs: the rifle layer keeps the arms). Short fall: a 0.15 s dip. Long fall
-- (> 10 studs): knees deep, 0.35 s, a small overshoot up before settling.
local BODY = { "root", "head", "leftLeg", "rightLeg" }
local landShort = {
	name = "LandShort",
	priority = "Action2",
	only = BODY,
	keys = {
		{
			t = 0,
			pose = {
				root = { lean = 8, y = -0.05 },
				leftLeg = { swing = 14 },
				rightLeg = { swing = -8 },
			},
		},
		{
			t = 0.05,
			pose = {
				root = { lean = 11, y = -0.28 },
				leftLeg = { swing = 20, y = 0.15 },
				rightLeg = { swing = -10, y = 0.1 },
			},
		},
		{
			t = 0.1,
			pose = {
				root = { lean = 5, y = 0.02 },
				leftLeg = { swing = 3 },
				rightLeg = { swing = -2 },
			},
		},
		{ t = 0.15, pose = P.idlePose(0) },
	},
}
local deep = P.crouchPose(18)
deep.root.y += 0.15 -- knees deep, the rifle still clear of the ground
local landLong = {
	name = "LandLong",
	priority = "Action2",
	only = BODY,
	keys = {
		{
			t = 0,
			pose = {
				root = { lean = 10, y = -0.1 },
				leftLeg = { swing = 16 },
				rightLeg = { swing = -10 },
			},
		},
		{ t = 0.08, pose = deep },
		{ t = 0.2, pose = P.crouchPose(14) },
		{
			t = 0.29,
			pose = {
				root = { lean = 2, y = 0.04 },
				leftLeg = { spread = 4 },
				rightLeg = { spread = 4 },
			},
		},
		{ t = 0.35, pose = P.idlePose(0) },
	},
}

-- Sprint accents. Start: the body tips into the run (0.15 s, a small overshoot past the sprint lean). Stop: a 0.2 s
-- settle: the lead foot plants ahead, the body rocks back past upright, then comes to the idle lean.
local sprintStart = {
	name = "SprintStart",
	priority = "Action2",
	only = { "root", "head" },
	keys = {
		{ t = 0, pose = { root = { lean = WL } } },
		{ t = 0.067, pose = { root = { lean = WL - 2 } } }, -- anticipation: a hair back
		{ t = 0.12, pose = { root = { lean = SL + 4 }, head = { lean = -14 } } },
		{ t = 0.15, pose = { root = { lean = SL }, head = { lean = -12 } } },
	},
}
local sprintStop = {
	name = "SprintStop",
	priority = "Action2",
	only = BODY,
	keys = {
		{
			t = 0,
			pose = {
				root = { lean = SL },
				head = { lean = -12 },
				leftLeg = { swing = sl(26) },
				rightLeg = { swing = sl(-30) },
			},
		},
		{
			t = 0.07,
			pose = {
				root = { lean = -5, y = -0.12 },
				head = { lean = 3 },
				leftLeg = { swing = 26 },
				rightLeg = { swing = -14 },
			},
		},
		{
			t = 0.14,
			pose = {
				root = { lean = 6, y = -0.04 },
				leftLeg = { swing = 8, spread = 4 },
				rightLeg = { swing = -4, spread = 4 },
			},
		},
		{ t = 0.2, pose = P.idlePose(0) },
	},
}

-- Limp, one leg at 0 (the right): the hurt step takes 35% of the cycle. The good leg steps long; the stiff hurt leg
-- swings short and the body drops and tilts onto it, then hurries off it.
local L1 = P.LIMP1_LEN
local limpOne = {
	name = "LimpOne",
	loop = true,
	priority = "Movement",
	planted = 0.6,
	footsteps = true,
	keys = {
		{
			t = 0,
			pose = {
				root = { lean = 5 },
				leftLeg = { swing = 22 },
				rightLeg = { swing = -16 },
				leftArm = arms(-8),
				rightArm = arms(16),
			},
		},
		{
			t = L1 * 0.32,
			pose = {
				root = { lean = 5, tilt = -2 },
				leftLeg = { swing = -6 },
				rightLeg = { swing = 2, y = 0.08 },
				leftArm = arms(4),
				rightArm = arms(4),
			},
		},
		{
			t = L1 * 0.65,
			pose = {
				root = { lean = 7, tilt = 6, y = -0.12 },
				head = { tilt = -3 },
				leftLeg = { swing = -18 },
				rightLeg = { swing = 12 },
				leftArm = arms(12, 6),
				rightArm = arms(-4),
			},
		},
		{
			t = L1 * 0.82,
			pose = {
				root = { lean = 6, tilt = 3, y = -0.06 },
				leftLeg = { swing = 2, y = 0.22 },
				rightLeg = { swing = -6 },
				leftArm = arms(4),
				rightArm = arms(6),
			},
		},
		{
			t = L1,
			pose = {
				root = { lean = 5 },
				leftLeg = { swing = 22 },
				rightLeg = { swing = -16 },
				leftArm = arms(-8),
				rightArm = arms(16),
			},
		},
	},
}
-- Both legs at 0: a short, bent shuffle, swaying side to side
local limpBoth = cycle("LimpBoth", P.LIMP2_LEN, 0.4, {
	root = { lean = 9, tilt = -3, y = -0.08 },
	leftLeg = { swing = 9 },
	rightLeg = { swing = -9 },
	leftArm = arms(4, 6),
	rightArm = arms(10, 6),
}, {
	root = { lean = 9, tilt = 0, y = -0.08 },
	leftLeg = { swing = 0 },
	rightLeg = { swing = 2, y = 0.12 },
	leftArm = arms(7, 6),
	rightArm = arms(7, 6),
})

-- Turning in place past 45 degrees: two small steps (legs only), 0.3 s
local turnShuffle = {
	name = "TurnShuffle",
	priority = "Action2",
	only = { "leftLeg", "rightLeg" },
	keys = {
		{ t = 0, pose = { leftLeg = { spread = 4 }, rightLeg = { spread = 4 } } },
		{
			t = 0.08,
			pose = {
				leftLeg = { spread = 4, swing = 6, y = 0.2, twist = 15 },
				rightLeg = { spread = 4 },
			},
		},
		{ t = 0.15, pose = { leftLeg = { spread = 4, twist = 8 }, rightLeg = { spread = 4 } } },
		{
			t = 0.23,
			pose = {
				leftLeg = { spread = 4 },
				rightLeg = { spread = 4, swing = 6, y = 0.2, twist = 12 },
			},
		},
		{ t = 0.3, pose = { leftLeg = { spread = 4 }, rightLeg = { spread = 4 } } },
	},
}

return {
	idle,
	walk,
	sprint,
	crouchIdle,
	crouchWalk,
	proneIdle,
	crawl,
	jump,
	fall,
	landShort,
	landLong,
	sprintStart,
	sprintStop,
	limpOne,
	limpBoth,
	turnShuffle,
}
