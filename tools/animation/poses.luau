--!strict
-- Shared poses and numbers for the M2 movement clips (movement.luau: body cycles; rifle.luau: the rifle layers and the
-- whole-body one-shots). Pose conventions: tools/animation/build.luau. Numbers: jarvis
-- notes/ideas/korea-pve/ANIMATION-GUIDE.md §3 (approved 2026-11-22).
-- Root space: origin at the torso centre standing, +X right, +Y up, -Z forward; the ground is at y = -3.
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

local P = {}

-- cycle lengths at the guide's speeds (the client scales playback with the real speed)
P.IDLE_LEN = 4.0
P.WALK_LEN = 0.70 -- at 12
P.SPRINT_LEN = 0.52 -- at 20
P.CROUCH_LEN = 0.90 -- at 7
P.CRAWL_LEN = 1.2 -- at 3
P.LIMP1_LEN = 0.85 -- at 8
P.LIMP2_LEN = 1.0 -- at 5
P.SWIM_LEN = 1.2
P.TREAD_LEN = 1.6

P.IDLE_LEAN = 4
P.WALK_LEAN = 3
P.SPRINT_LEAN = 18
P.CROUCH_LEAN = 20
P.CROUCH_HIP = 0.8 -- the torso's bottom above the ground, crouched (head top ~3.8)
P.SIDE_SPREAD = 3

local SWAP =
	{ leftArm = "rightArm", rightArm = "leftArm", leftLeg = "rightLeg", rightLeg = "leftLeg" }

-- the same pose on the other side: left and right limbs swap, turns and tilts flip
function P.mirror(pose: { [string]: any }): { [string]: any }
	local out = {}
	for joint, v in pose do
		local m = table.clone(v)
		for _, k in { "twist", "tilt", "x", "yaw", "roll" } do
			if m[k] then
				m[k] = -m[k]
			end
		end
		out[SWAP[joint] or joint] = m
	end
	return out
end

-- a folded leg whose knee is at (kneeY, kneeZ) above/ahead of the ground point under the hip, shin at `world`
-- degrees from vertical (+ forward), under a torso leaning `lean` (Runenkrieg's crouch legs)
function P.kLeg(world: number, kneeY: number, kneeZ: number, lean: number?): any
	local l0 = lean or P.CROUCH_LEAN
	local w, l = math.rad(world), math.rad(l0)
	local footY, footZ = kneeY - 2 * math.cos(w), kneeZ - 2 * math.sin(w)
	local ty, tz =
		footY * math.cos(l) - footZ * math.sin(l), footY * math.sin(l) + footZ * math.cos(l)
	local a = w + l
	return {
		swing = world + l0,
		spread = 4,
		y = 2 + ty * math.cos(a) + tz * math.sin(a),
		z = -ty * math.sin(a) + tz * math.cos(a),
		fold = 1,
	}
end

function P.idlePose(breath: number): any
	return {
		root = { lean = P.IDLE_LEAN + 0.6 * breath },
		leftLeg = { spread = 4 },
		rightLeg = { spread = 4 },
		leftArm = { swing = P.IDLE_LEAN + 2 + breath, spread = P.SIDE_SPREAD + breath },
		rightArm = { swing = P.IDLE_LEAN + 2 + breath, spread = P.SIDE_SPREAD + breath },
	}
end

function P.crouchRoot(lean: number, bob: number?): any
	return { lean = lean, y = P.CROUCH_HIP + math.cos(math.rad(lean)) - 3 + (bob or 0) }
end

function P.crouchPose(lean: number?): any
	local l = lean or P.CROUCH_LEAN
	return {
		root = P.crouchRoot(l),
		leftLeg = P.kLeg(5, 2 * math.cos(math.rad(5)) - P.CROUCH_HIP, -0.55, l),
		rightLeg = P.kLeg(-100, 0.5 - P.CROUCH_HIP, -0.2, l),
		leftArm = { swing = l + 4, spread = P.SIDE_SPREAD + 1 },
		rightArm = { swing = l + 4, spread = P.SIDE_SPREAD + 1 },
	}
end

-- Prone: chest down, the torso nearly flat (its centre 0.85 above the ground: the carrier's front just clear),
-- shifted back so the body lies over the root; the head tipped back to look ahead, legs straight back, feet apart.
P.PRONE_ROOT = { lean = 88, y = -2.15, z = 0.9 }
function P.pronePose(breath: number?): any
	local b = breath or 0
	return {
		root = { lean = P.PRONE_ROOT.lean, y = P.PRONE_ROOT.y + 0.02 * b, z = P.PRONE_ROOT.z },
		head = { lean = -72 },
		leftLeg = { swing = 10, spread = 7 },
		rightLeg = { swing = 10, spread = 9, twist = 10 },
		leftArm = { swing = 150, spread = 10 },
		rightArm = { swing = 150, spread = 10 },
	}
end

-- Rifle poses in root space (the gun placed by its grip; yaw + muzzle left, pitch + muzzle up, roll + top left)
-- standing ready: low in front of the stomach, the butt near the right hip, muzzle ahead a little up and in
P.GUN_READY = { x = 0.7, y = -0.75, z = -0.8, yaw = 18, pitch = 6 }
-- sprint (user: "rifle carried across the chest"): port arms, muzzle up past the left shoulder
P.GUN_SPRINT = { x = 0.55, y = -0.5, z = -0.5, yaw = 42, pitch = 12 }
-- crouched: the same carry, lower with the body
P.GUN_CROUCH = { x = 0.65, y = -1.55, z = -1.15, yaw = 14, pitch = 4 }
-- prone: butt in the right shoulder, the gun flat on the ground ahead
P.GUN_PRONE = { x = 0.55, y = -1.9, z = -0.85, yaw = 3, pitch = 2 }
-- crawling: across the forearms in front of the head
P.GUN_CRAWL = { x = 0.6, y = -1.9, z = -1.0, yaw = 40, pitch = 2 }

-- the torso's frame in root space for a root pose (rotation about the torso centre, as build.luau's root transform:
-- offset first, then lean / tilt / twist)
function P.torsoFrame(root: any): any
	local r = math.rad
	return CFrame.new(root.x or 0, root.y or 0, root.z or 0)
		* CFrame.Angles(0, r(root.twist or 0), 0)
		* CFrame.Angles(-r(root.lean or 0), 0, 0)
		* CFrame.Angles(0, 0, -r(root.tilt or 0))
end

-- a gun pose (root space) for a grip placed in the torso's own frame: at (x, y, z) torso space, turned by yaw / pitch
-- / roll in the torso's axes. For slung guns that ride with the body (swim, mantle).
function P.onTorso(
	root: any,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	roll: number
): any
	local r = math.rad
	local cf = P.torsoFrame(root)
		* CFrame.new(x, y, z)
		* CFrame.Angles(0, r(yaw), 0)
		* CFrame.Angles(r(pitch), 0, 0)
		* CFrame.Angles(0, 0, r(roll))
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	local p = cf.Position
	return {
		x = p.X,
		y = p.Y,
		z = p.Z,
		yaw = math.deg(ry),
		pitch = math.deg(rx),
		roll = math.deg(rz),
	}
end

-- the same, the gun given by where its grip is and which way its muzzle and its top point (torso space)
function P.onTorsoLook(root: any, at: { number }, muzzle: { number }, up: { number }): any
	local V = roblox.Vector3.new
	local pos = V(at[1], at[2], at[3])
	local cf = P.torsoFrame(root)
		* CFrame.lookAt(pos, pos + V(muzzle[1], muzzle[2], muzzle[3]), V(up[1], up[2], up[3]))
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	local p = cf.Position
	return {
		x = p.X,
		y = p.Y,
		z = p.Z,
		yaw = math.deg(ry),
		pitch = math.deg(rx),
		roll = math.deg(rz),
	}
end

-- a point in the torso's frame, in root space (hand targets that ride with the body)
function P.torsoPoint(root: any, x: number, y: number, z: number): any
	local p = P.torsoFrame(root) * roblox.Vector3.new(x, y, z)
	return { x = p.X, y = p.Y, z = p.Z }
end

return P
