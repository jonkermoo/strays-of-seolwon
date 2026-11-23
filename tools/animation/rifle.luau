--!strict
-- M2 rifle layers for the movement test (block-out rifle; built by tools/animation/build.luau, conventions there).
-- Holds (priority Action): the gun and both arms over each movement cycle; the body stays the cycle's.
-- Whole-body one-shots (priority Action3): stance changes, vault hop, mantle; and swim / tread (rifle slung on the
-- back, priority Action3 loops). These key the root, legs and gun, so they own the whole body while they play.
-- Timing (user 2026-11-22, ANIMATION-GUIDE.md §1.1 / §3): anticipation 2-3 frames, action 4-6, settle 4-6 with a small
-- overshoot. The full gun-hold families (aim, per-gun holds) are later M2 rounds; these are just the movement carries.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local P = luau.load(fs.readFile("tools/animation/poses.luau"), { debugName = "poses" })()

local W = "blockout"
-- third person: both hands under the gun, the gun resting on them (Runenkrieg holds.luau H.UNDER / `touch`):
-- the right hand at the pistol grip, the left under the handguard
local HANDS = { right = { 0, -0.12, 0.08 }, left = { 0, -0.02, -0.95 } }
local UNDER = { left = { -0.7071, -0.7071, 0 }, right = { 0.7071, -0.7071, 0 } }

local function g(base: any, d: { [string]: number }?): any
	local out = table.clone(base)
	for k, v in d or {} do
		out[k] = (out[k] or 0) + v
	end
	return out
end

local function merge(a: any, b: any): any
	local out = table.clone(a)
	for k, v in b do
		out[k] = v
	end
	return out
end

local function hold(name: string, gun: any, under: any, breath: boolean): any
	local keys
	if breath then
		keys = {
			{ t = 0, pose = { gun = gun } },
			{ t = 2, pose = { gun = g(gun, { y = -0.035, pitch = -1.2, roll = 0.6 }) } },
			{ t = 4, pose = { gun = gun } },
		}
	else
		keys = { { t = 0, pose = { gun = gun } }, { t = 1, pose = { gun = gun } } }
	end
	return {
		name = name,
		loop = true,
		priority = "Action",
		weapon = W,
		hands = HANDS,
		touch = UNDER,
		under = under,
		keys = keys,
	}
end

-- the gun swings with the legs: contact offsets (mirrored for the other foot) and passing offsets
local function moving(
	name: string,
	base: any,
	length: number,
	under: any,
	contact: any,
	passing: any
): any
	local function at(o: any, flip: boolean): any
		local out = table.clone(base)
		for k, d in o do
			local m = flip and (k == "x" or k == "yaw" or k == "roll")
			out[k] = (out[k] or 0) + (if m then -d else d)
		end
		return { gun = out }
	end
	local q = length / 4
	return {
		name = name,
		loop = true,
		priority = "Action",
		weapon = W,
		hands = HANDS,
		touch = UNDER,
		under = under,
		keys = {
			{ t = 0, pose = at(contact, false) },
			{ t = q, pose = at(passing, false) },
			{ t = 2 * q, pose = at(contact, true) },
			{ t = 3 * q, pose = at(passing, true) },
			{ t = length, pose = at(contact, false) },
		},
	}
end

local CROUCH_ROOT = P.crouchRoot(P.CROUCH_LEAN)
-- the glide walk's torso: the rifle rides on it nearly still (user 2026-11-22: the upper body stays steady)
local WALK_ROOT = { lean = P.WALK_LEAN, y = -0.2, twist = P.TWIST }
local holds = {
	hold("HoldIdle", P.GUN_READY, { lean = P.IDLE_LEAN, twist = P.TWIST }, true),
	moving(
		"HoldWalk",
		P.carry(WALK_ROOT),
		P.WALK_LEN,
		WALK_ROOT,
		{ y = -0.015, pitch = -0.6, x = 0.01, yaw = 0.8 },
		{ y = 0.01, pitch = 0.3 }
	),
	moving(
		"HoldSprint",
		P.GUN_SPRINT,
		P.SPRINT_LEN,
		{ lean = P.SPRINT_LEAN },
		{ y = -0.06, pitch = -4, x = 0.06, yaw = 6, roll = 6 },
		{ y = 0.05, pitch = 3 }
	),
	hold("HoldCrouch", P.GUN_CROUCH, CROUCH_ROOT, true),
	moving(
		"HoldCrouchWalk",
		P.GUN_CROUCH,
		P.CROUCH_LEN,
		CROUCH_ROOT,
		{ y = -0.015, pitch = -0.6, x = 0.01, yaw = 0.8 },
		{ y = 0.01, pitch = 0.3 }
	),
	hold("HoldProne", P.GUN_PRONE, P.PRONE_ROOT, false),
	moving(
		"HoldCrawl",
		P.GUN_CRAWL,
		P.CRAWL_LEN,
		P.PRONE_ROOT,
		{ z = 0.12, x = 0.04, yaw = 3 },
		{ z = -0.1 }
	),
}

-- Whole-body one-shots ------------------------------------------------------------------------------------------
local function oneShot(name: string, keys: { any }): any
	return {
		name = name,
		priority = "Action3",
		weapon = W,
		hands = HANDS,
		touch = UNDER,
		keys = keys,
	}
end
local function key(t: number, body: any, gun: any, extra: any?): any
	local pose = {
		gun = gun,
		root = body.root,
		head = body.head,
		leftLeg = body.leftLeg,
		rightLeg = body.rightLeg,
	}
	for k, v in extra or {} do
		pose[k] = v
	end
	return { t = t, pose = pose }
end

local STAND = P.idlePose(0)
local CROUCH = P.crouchPose()
local PRONE = P.pronePose(0)
local function with(pose: any, root: any): any
	return merge(pose, { root = merge(pose.root, root) })
end
-- kneeling on the left knee, the right foot planted ahead (the way down to prone)
local function kneel(lean: number, hip: number): any
	return {
		root = { lean = lean, y = hip + math.cos(math.rad(lean)) - 3 },
		leftLeg = P.kLeg(-95, -0.2, -0.3, lean),
		rightLeg = P.kLeg(8, 2 * math.cos(math.rad(8)) - hip, -0.7, lean),
	}
end
-- hands and knees, the chest going down (shins flat behind)
local function allFours(lean: number, y: number, z: number): any
	return {
		root = { lean = lean, y = y, z = z },
		head = { lean = -lean * 0.6 },
		leftLeg = { swing = -22, spread = 6 },
		rightLeg = { swing = -20, spread = 8 },
	}
end

local stance = {
	-- 0.20 s: a hair up (anticipation), down past the crouch, settle
	oneShot("StandToCrouch", {
		key(0, STAND, P.GUN_READY),
		key(0.067, with(STAND, { y = 0.04, lean = 3 }), g(P.GUN_READY, { y = 0.03 })),
		key(
			0.15,
			with(P.crouchPose(23), { y = CROUCH.root.y - 0.08 }),
			g(P.GUN_CROUCH, { y = -0.07, pitch = -2 })
		),
		key(0.2, CROUCH, P.GUN_CROUCH),
	}),
	oneShot("CrouchToStand", {
		key(0, CROUCH, P.GUN_CROUCH),
		key(
			0.067,
			with(P.crouchPose(22), { y = CROUCH.root.y - 0.05 }),
			g(P.GUN_CROUCH, { y = -0.04 })
		),
		key(0.15, with(STAND, { y = 0.05, lean = 2 }), g(P.GUN_READY, { y = 0.04, pitch = 2 })),
		key(0.2, STAND, P.GUN_READY),
	}),
	-- 0.45 s: dip, onto the left knee, hands down, chest down (a little past), settle
	oneShot("StandToProne", {
		key(0, STAND, P.GUN_READY),
		key(0.067, with(STAND, { y = -0.15, lean = 8 }), g(P.GUN_READY, { y = 0.05, pitch = 4 })),
		key(0.17, kneel(24, 0.75), { x = 0.65, y = -1.55, z = -1.25, yaw = 12, pitch = -6 }),
		key(0.3, allFours(62, -1.9, 0.35), { x = 0.6, y = -1.95, z = -1.2, yaw = 6, pitch = -2 }),
		key(
			0.38,
			with(PRONE, { y = P.PRONE_ROOT.y - 0.06, lean = 91 }),
			g(P.GUN_PRONE, { y = -0.04 })
		),
		key(0.45, PRONE, P.GUN_PRONE),
	}),
	-- 0.55 s: push up onto the hands, knee under, rise (a hair past standing), settle
	oneShot("ProneToStand", {
		key(0, PRONE, P.GUN_PRONE),
		key(0.067, with(PRONE, { y = P.PRONE_ROOT.y - 0.04 }), g(P.GUN_PRONE, { y = -0.02 })),
		key(0.18, allFours(58, -1.85, 0.3), { x = 0.6, y = -1.9, z = -1.15, yaw = 6, pitch = -2 }),
		key(0.32, kneel(26, 0.8), { x = 0.65, y = -1.5, z = -1.2, yaw = 12, pitch = -4 }),
		key(0.46, with(STAND, { y = 0.05, lean = 2 }), g(P.GUN_READY, { y = 0.04, pitch = 2 })),
		key(0.55, STAND, P.GUN_READY),
	}),
	-- 0.35 s each way between crouch and prone
	oneShot("CrouchToProne", {
		key(0, CROUCH, P.GUN_CROUCH),
		key(
			0.067,
			with(P.crouchPose(24), { y = CROUCH.root.y - 0.05 }),
			g(P.GUN_CROUCH, { y = 0.03 })
		),
		key(0.2, allFours(62, -1.9, 0.35), { x = 0.6, y = -1.95, z = -1.2, yaw = 6, pitch = -2 }),
		key(
			0.28,
			with(PRONE, { y = P.PRONE_ROOT.y - 0.06, lean = 91 }),
			g(P.GUN_PRONE, { y = -0.04 })
		),
		key(0.35, PRONE, P.GUN_PRONE),
	}),
	oneShot("ProneToCrouch", {
		key(0, PRONE, P.GUN_PRONE),
		key(0.067, with(PRONE, { y = P.PRONE_ROOT.y - 0.04 }), g(P.GUN_PRONE, { y = -0.02 })),
		key(0.17, allFours(55, -1.8, 0.3), { x = 0.6, y = -1.85, z = -1.2, yaw = 8, pitch = -2 }),
		key(
			0.28,
			with(P.crouchPose(17), { y = CROUCH.root.y + 0.06 }),
			g(P.GUN_CROUCH, { y = 0.04 })
		),
		key(0.35, CROUCH, P.GUN_CROUCH),
	}),
}

-- Vault hop (walls up to 3.5, 0.45 s; src/client/MoveTest carries the root over on an arc): the left hand plants on
-- the wall, the tucked legs swing over to the right, the rifle stays in the right hand.
local function run(a: number): any
	return { root = { lean = 10 }, leftLeg = { swing = a }, rightLeg = { swing = -a } }
end
local LEFT_FREE = { leftBody = { x = -0.9, y = -0.9, z = -0.6 }, leftMix = { w = 0 } }
local function leftOn(x: number, y: number, z: number, w: number): any
	return { leftBody = { x = x, y = y, z = z }, leftMix = { w = w } }
end
local vault = oneShot("VaultHop", {
	key(0, run(18), P.GUN_READY, leftOn(-0.5, -1.2, -1.2, 0)),
	key(0.07, {
		root = { lean = 30, tilt = -8, y = -0.1 },
		leftLeg = { swing = 8 },
		rightLeg = { swing = -28 },
	}, g(P.GUN_READY, { pitch = 6 }), leftOn(-0.5, -1.25, -1.2, 1)),
	key(0.2, {
		root = { lean = 20, tilt = -18 },
		leftLeg = { swing = 68, spread = -22, y = 0.3 },
		rightLeg = { swing = 62, spread = 30, y = 0.3 },
	}, g(P.GUN_READY, { y = 0.15, pitch = 14, yaw = 6 }), leftOn(-0.6, -1.6, -0.5, 1)),
	key(0.32, {
		root = { lean = 12, tilt = -6, y = -0.08 },
		leftLeg = { swing = 20 },
		rightLeg = { swing = 32, spread = 6 },
	}, g(P.GUN_READY, { y = 0.05, pitch = 4 }), leftOn(-0.9, -1.0, -0.3, 0.5)),
	key(0.45, run(15), P.GUN_READY, leftOn(-0.9, -0.9, -0.6, 0)),
})
vault.hands = HANDS -- the left hand leaves for the wall by leftMix

-- Mantle (3.5-5.5 and windows, 0.8 s; MoveTest lifts the root to the ledge, then forward): the rifle swings onto the
-- chest (slung), both hands go up on the ledge and push the body up, the right knee comes up, then the left.
local function sling(root: any): any
	return P.onTorsoLook(root, { 0.3, 0.05, -0.95 }, { -0.3, -0.95, 0 }, { 0, 0, -1 })
end
local function hands(y: number, z: number, w: number): any
	return {
		leftBody = { x = -0.6, y = y, z = z },
		leftMix = { w = w },
		rightBody = { x = 0.6, y = y, z = z },
		rightMix = { w = w },
	}
end
local M = {
	{ root = { lean = 6 } },
	{ root = { lean = 10, y = -0.15 }, leftLeg = { swing = 10 }, rightLeg = { swing = 4 } },
	{ root = { lean = 16 }, leftLeg = { swing = -6 }, rightLeg = { swing = 24 } },
	{
		root = { lean = 34 },
		head = { lean = -20 },
		leftLeg = { swing = -22 },
		rightLeg = { swing = 86, y = 0.5 },
	},
	{
		root = { lean = 24 },
		head = { lean = -10 },
		leftLeg = { swing = 44, y = 0.3 },
		rightLeg = { swing = 32 },
	},
	{
		root = { lean = 1, y = 0.05 },
		leftLeg = { swing = 4, spread = 4 },
		rightLeg = { swing = -3, spread = 4 },
	},
	STAND,
}
local mantle = oneShot("Mantle", {
	key(0, M[1], P.GUN_READY, hands(1.2, -1.0, 0)),
	key(0.08, M[2], sling(M[2].root), hands(1.4, -1.0, 0.6)),
	key(0.2, M[3], sling(M[3].root), hands(1.15, -1.0, 1)),
	key(0.4, M[4], sling(M[4].root), hands(-0.3, -0.9, 1)),
	key(0.55, M[5], sling(M[5].root), hands(-1.2, -0.5, 1)),
	key(0.68, M[6], g(P.GUN_READY, { y = 0.06 }), hands(-0.9, -0.6, 0.4)),
	key(0.8, M[7], P.GUN_READY, hands(-0.9, -0.6, 0)),
})
mantle.hands = HANDS

-- Swim (breaststroke, 1.2 s) and tread water (1.6 s): the rifle slung across the back, both hands free (their points
-- given in the torso's frame and carried into root space).
local function backSling(root: any): any
	return P.onTorsoLook(root, { 0.3, -0.25, 1.7 }, { -0.55, 0.83, 0 }, { 0, 0, 1 })
end
local function swimKey(t: number, root: any, head: any, l: any, r: any, hand: { number }): any
	local lh = P.torsoPoint(root, -hand[1], hand[2], hand[3])
	local rh = P.torsoPoint(root, hand[1], hand[2], hand[3])
	return {
		t = t,
		pose = {
			root = root,
			head = head,
			leftLeg = l,
			rightLeg = r,
			gun = backSling(root),
			leftBody = lh,
			leftMix = { w = 1 },
			rightBody = rh,
			rightMix = { w = 1 },
		},
	}
end
local SR = { lean = 72, y = 0.3 }
local SH = { lean = -62 }
local SW = P.SWIM_LEN
local swim = {
	name = "Swim",
	loop = true,
	priority = "Action3",
	weapon = W,
	hands = HANDS,
	keys = {
		swimKey(
			0,
			SR,
			SH,
			{ swing = 2, spread = 4 },
			{ swing = 2, spread = 4 },
			{ 0.5, 1.8, -0.3 }
		), -- glide
		swimKey(
			SW * 0.3,
			{ lean = 70, y = 0.32 },
			SH,
			{ swing = 4, spread = 6 },
			{ swing = 4, spread = 6 },
			{ 2.2, 0.9, -0.4 }
		), -- sweep out
		swimKey(
			SW * 0.5,
			{ lean = 66, y = 0.4 },
			{ lean = -58 },
			{ swing = 48, spread = 26, y = 0.3 },
			{ swing = 48, spread = 26, y = 0.3 },
			{ 0.8, -0.1, -1.2 }
		), -- pull, knees in
		swimKey(
			SW * 0.7,
			{ lean = 70, y = 0.34 },
			SH,
			{ swing = 6, spread = 36 },
			{ swing = 6, spread = 36 },
			{ 0.6, 0.6, -1.35 }
		), -- kick, hands forward
		swimKey(
			SW,
			SR,
			SH,
			{ swing = 2, spread = 4 },
			{ swing = 2, spread = 4 },
			{ 0.5, 1.8, -0.3 }
		),
	},
}
local TR = { lean = 12 }
local TW = P.TREAD_LEN
local tread = {
	name = "Tread",
	loop = true,
	priority = "Action3",
	weapon = W,
	hands = HANDS,
	keys = {
		swimKey(
			0,
			TR,
			{ lean = -8 },
			{ swing = 22, y = 0.2 },
			{ swing = -12 },
			{ 1.25, -0.2, -1.0 }
		),
		swimKey(
			TW * 0.25,
			{ lean = 12, y = 0.05 },
			{ lean = -8 },
			{ swing = 4 },
			{ swing = 4 },
			{ 0.7, -0.3, -1.2 }
		),
		swimKey(
			TW * 0.5,
			TR,
			{ lean = -8 },
			{ swing = -12 },
			{ swing = 22, y = 0.2 },
			{ 1.25, -0.2, -1.0 }
		),
		swimKey(
			TW * 0.75,
			{ lean = 12, y = 0.05 },
			{ lean = -8 },
			{ swing = 4 },
			{ swing = 4 },
			{ 0.7, -0.3, -1.2 }
		),
		swimKey(
			TW,
			TR,
			{ lean = -8 },
			{ swing = 22, y = 0.2 },
			{ swing = -12 },
			{ 1.25, -0.2, -1.0 }
		),
	},
}

local out = {}
for _, list in { holds, stance, { vault, mantle, swim, tread } } do
	for _, a in list do
		table.insert(out, a)
	end
end
return out
