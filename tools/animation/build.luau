--!strict
-- Builds R6 animations from keyframe data into KeyframeSequence .rbxm files.
-- Ported from Runenkrieg (tools/animation/build.luau, 2026-11-22) for the Strays M2 movement clips; conventions unchanged.
-- usage: lune run tools/animation/build.luau <out .rbxm> <data module> [<data module> ...]
--   e.g. lune run tools/animation/build.luau assets/Animations.rbxm tools/animation/movement.luau tools/animation/rifle.luau
-- The style test plays them unuploaded (KeyframeSequenceProvider:RegisterKeyframeSequence, Studio only); M5 uploads.
--
-- Pose values are body-relative and in degrees, so the data reads like an animator's notes:
--   root (Torso on HumanoidRootPart): lean (+ forward), tilt (+ toward the right), twist (+ turn left),
--                                     x / y / z offset in studs (y up, -z forward)
--   head (Neck):                      lean, tilt, twist
--   leftArm/rightArm/leftLeg/rightLeg: swing (+ forward), spread (+ out to its own side), twist (+ turn left),
--                                     x / y / z offset of the shoulder or hip in the torso's axes (the sprint pedal),
--                                     fold = 1: offset first, then turn about the joint (crouched legs)
-- A joint left out of a key stays at rest. Each key: { t = seconds, pose = {...}, marker = {name, value}? }
-- `footsteps = true` on an animation places "Footstep" markers where each foot lands (forward kinematics);
-- `planted = true` sets the root height every frame so the lower foot stays on the ground (natural bob).
--
-- Weapon layers (`weapon = "<Config/Weapons name>"`): an upper-body layer played over the movement cycles. Each key
-- has `gun = { x, y, z, yaw, pitch, roll }` in the character's upright frame (root space: origin at the torso
-- centre at rest, +X right, +Y up, -Z forward; degrees, yaw + muzzle left, pitch + muzzle up, roll + top to the left):
-- x/y/z place the gun's grip (the right hand), or the attachment the animation names in `at` (e.g. "Aim", the eye). The gun is a
-- "Gun" pose under the torso (src/server/Armory joins the weapon to the Torso with a Motor6D). `under` is the root
-- pose of the cycle it plays over (the sprint's forward lean), so the gun sits where the data says in the world.
-- The arms aren't keyed: each one is pointed at its hand point on the gun (`hands`: right on the grip unless given,
-- left on the forend; modelled gun space) and slid along its own line when the point is out of reach (R6 arms are straight).
-- An arm with no hand point (`hands` without `left`: the staff) isn't posed at all, so the cycle underneath keeps it.
-- `from = { leftArm = {x, y, z} }` (root space) makes an arm come from that point instead of its shoulder: the
-- first-person holds only show forearms, so they rise from below the screen like a shooter's viewmodel.
-- Only the arms, the gun and a keyed head are written; the root and torso poses are weight 0 so the cycle's show.
-- A weapon layer whose keys give `root` (e.g. { twist = -30 }) turns the body itself: its torso pose is written and
-- the gun and arms are placed on the turned body (the gun still where `gun` says in the upright frame).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Instance = roblox.Instance
local Enum = roblox.Enum :: any

-- R6 joint C0 rotations (measured from a stock R6 rig, 2026-10-11) and the part each joint moves.
local JOINTS = {
	root = { part = "Torso", c0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	head = { part = "Head", c0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	rightArm = {
		part = "Right Arm",
		c0 = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		side = 1,
	},
	leftArm = { part = "Left Arm", c0 = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), side = -1 },
	rightLeg = {
		part = "Right Leg",
		c0 = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		side = 1,
	},
	leftLeg = { part = "Left Leg", c0 = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), side = -1 },
}
local LIMBS = { "head", "rightArm", "leftArm", "rightLeg", "leftLeg" }

-- Full R6 C0 / C1 of the joints the feet hang from, for forward kinematics (footstep timing).
local RIG = {
	root = {
		c0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		c1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	},
	rightLeg = {
		c0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		c1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	leftLeg = {
		c0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		c1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}
-- Shoulder pivots in the torso's axes (R6 Right/Left Shoulder C0 positions).
local SHOULDER =
	{ rightArm = roblox.Vector3.new(1, 0.5, 0), leftArm = roblox.Vector3.new(-1, 0.5, 0) }
local HAND = { rightArm = "rightHand", leftArm = "leftHand" } -- key fields that place a hand (no weapon)
local FIST = 0.8 -- the hand point: this far below the arm's centre, inside the bottom of the block
-- a `touch` hand (armGoal): the gun's surface this far off the arm's axis (half the 1-stud arm) or past the hand point
-- (to the block's end), a hair inside so it reads as held
local TOUCH_SIDE, TOUCH_END = 0.47, 0.17
local REST_FOOT = -3 -- foot bottom below the root at rest
local GROUND = 0.02 -- a foot this close to the ground counts as touching

-- The joint Transform (Pose.CFrame) for a body-relative rotation / offset in the parent part's axes:
-- rotating about the joint pivot by R in parent space is C0rot^-1 * R * C0rot in the joint's own frame.
local function transform(name: string, v: { [string]: number }?): any
	local j = JOINTS[name]
	if not v then
		return CFrame.new()
	end
	local r = math.rad
	local pitch, roll
	if j.side then
		pitch = r(v.swing or 0) -- + about X swings a hanging limb forward (-Z)
		roll = r(v.spread or 0) * j.side -- + about Z swings a hanging limb toward +X
	else
		pitch = -r(v.lean or 0) -- + about X tips the top backward, so lean forward is negative
		roll = -r(v.tilt or 0) -- + about Z tips the top toward -X
	end
	local rot = CFrame.Angles(0, r(v.twist or 0), 0)
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.Angles(0, 0, roll)
	-- `fold = 1` on a limb: move it by x/y/z first, then turn it about the joint. A leg pushed up into the torso then
	-- swings its visible part from the torso's bottom (a knee), instead of from a pivot high inside the torso, which
	-- swung the leg out through the torso's front (the crouch walk, 2026-10-11).
	local offset = CFrame.new(v.x or 0, v.y or 0, v.z or 0)
	local body = if (v.fold or 0) > 0.5 then rot * offset else offset * rot
	return j.c0:Inverse() * body * j.c0
end

local function pose(name: string, cf: any, ease: string): any
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	p.Weight = 1
	p.EasingStyle = Enum.PoseEasingStyle[ease]
	p.EasingDirection = Enum.PoseEasingDirection.InOut
	return p
end

-- Smooth motion: a cubic Hermite curve runs through the keys (tangents from the neighbouring keys, wrapping
-- round on loops; a one-shot starts and ends at rest), sampled at FPS with linear steps in between. Easing each
-- key separately (Cubic InOut) stops every limb at every key, which reads as a pause between steps.
local FPS = 30

local function flatten(p: { [string]: any }?): { [string]: number }
	local out = {}
	for joint, v in p or {} do
		for field, n in v do
			out[joint .. "." .. field] = n
		end
	end
	return out
end

local function unflatten(f: { [string]: number }): { [string]: any }
	local out = {}
	for k, n in f do
		local joint, field = string.match(k, "^(.-)%.(.+)$")
		out[joint] = out[joint] or {}
		out[joint][field] = n
	end
	return out
end

local function sample(anim: any): { any }
	local keys = anim.keys
	local n = #keys
	local fields, poses = {}, {}
	for i, key in keys do
		poses[i] = flatten(key.pose)
		for k in poses[i] do
			fields[k] = true
		end
	end
	local function value(i: number, k: string): number
		return poses[i][k] or 0
	end
	-- tangent (units per second) at key i
	local function tangent(i: number, k: string): number
		if anim.loop then
			-- the last key repeats the first: neighbours wrap round through it
			local prev = if i == 1 then n - 1 else i - 1
			local nxt = if i == n then 2 else i + 1
			local dt = (if i == 1 then keys[n].t - keys[n - 1].t else keys[i].t - keys[i - 1].t)
				+ (if i == n then keys[2].t - keys[1].t else keys[i + 1].t - keys[i].t)
			return (value(nxt, k) - value(prev, k)) / dt
		end
		if i == 1 or i == n then
			return 0
		end
		return (value(i + 1, k) - value(i - 1, k)) / (keys[i + 1].t - keys[i - 1].t)
	end
	local out = {}
	for i = 1, n - 1 do
		local t0, t1 = keys[i].t, keys[i + 1].t
		local h = t1 - t0
		local steps = math.max(1, math.floor(h * FPS + 0.5))
		for s = 0, steps - 1 do
			local u = s / steps
			local h00, h10 = 2 * u ^ 3 - 3 * u ^ 2 + 1, u ^ 3 - 2 * u ^ 2 + u
			local h01, h11 = -2 * u ^ 3 + 3 * u ^ 2, u ^ 3 - u ^ 2
			local f = {}
			for k in fields do
				f[k] = h00 * value(i, k)
					+ h10 * h * tangent(i, k)
					+ h01 * value(i + 1, k)
					+ h11 * h * tangent(i + 1, k)
			end
			table.insert(
				out,
				{
					t = t0 + u * h,
					pose = unflatten(f),
					marker = if s == 0 then keys[i].marker else nil,
				}
			)
		end
	end
	table.insert(out, { t = keys[n].t, pose = keys[n].pose, marker = keys[n].marker })
	return out
end

-- Height above the ground (the rest foot level) of a foot's sole centre for a pose. The centre, not the lowest
-- corner: a swung block always dips one corner (0.5 sin A), which reads as the foot rolling heel to toe.
local function footHeight(p: { [string]: any }, leg: string): number
	local torso = RIG.root.c0 * transform("root", p.root) * RIG.root.c1:Inverse()
	local j = RIG[leg]
	local part = torso * j.c0 * transform(leg, p[leg]) * j.c1:Inverse()
	return (part * roblox.Vector3.new(0, -1, 0)).Y - REST_FOOT
end

-- `planted = true` (or a strength 0..1): the body rides on its legs. Each frame the root is raised or lowered so the
-- lower foot stands on the ground, which gives the natural walking bob: lowest when the legs are spread at a step,
-- highest passing over the planted leg (an inverted pendulum). A strength under 1 scales the bob down; the planted
-- foot then drifts by (1 - strength) of the bob, split evenly between floating at the dip and sinking at the top.
-- Data root `y` adds on top.
local function plant(frames: { any }, strength: number)
	local drops = {}
	local dmin, dmax = math.huge, -math.huge
	for i, f in frames do
		local p = f.pose or {}
		drops[i] = math.min(footHeight(p, "leftLeg"), footHeight(p, "rightLeg"))
		dmin, dmax = math.min(dmin, drops[i]), math.max(dmax, drops[i])
	end
	local centre = -(1 - strength) * (dmin + dmax) / 2
	local lo, hi = math.huge, -math.huge
	for i, f in frames do
		local p = table.clone(f.pose or {})
		p.root = table.clone(p.root or {})
		p.root.y = (p.root.y or 0) - strength * drops[i] + centre
		f.pose = p
		lo, hi = math.min(lo, p.root.y), math.max(hi, p.root.y)
	end
	print(
		string.format(
			"  body bob %.3f studs (strength %.2f, planted foot drift +-%.3f)",
			hi - lo,
			strength,
			(1 - strength) * (dmax - dmin) / 2
		)
	)
end

-- Footstep markers where each foot actually lands: one per foot, the first frame after the top of its swing where
-- it is down level with the other foot (looping round the cycle). Keyed markers can't be trusted: smoothing and the root drop move the touchdown.
local function placeFootsteps(frames: { any }, loop: boolean)
	for _, f in frames do
		if f.marker and f.marker[1] == "Footstep" then
			f.marker = nil
		end
	end
	local n = if loop then #frames - 1 else #frames -- a loop's last frame repeats the first
	for _, leg in { "leftLeg", "rightLeg" } do
		local other = if leg == "leftLeg" then "rightLeg" else "leftLeg"
		local h, o = {}, {}
		for i = 1, n do
			h[i] = footHeight(frames[i].pose or {}, leg)
			o[i] = footHeight(frames[i].pose or {}, other)
		end
		-- the landing that ends the swing: from the foot's highest frame, the first one where it is back down to the
		-- other foot's height, i.e. it takes the weight (a trailing toe brushing the ground earlier isn't a step)
		local top = 1
		for i = 2, n do
			if h[i] > h[top] then
				top = i
			end
		end
		for k = 1, n - 1 do
			local i = (top + k - 1) % n + 1
			if not loop and i < top then
				break
			end
			if h[i] <= o[i] + GROUND then
				assert(not frames[i].marker, `{leg} lands on a frame that already has a marker`)
				frames[i].marker = { "Footstep", if leg == "leftLeg" then "Left" else "Right" }
				print(string.format("  %s lands at %.3f s", leg, frames[i].t))
				break
			end
		end
	end
end

local function v3(t: { number }): any
	return roblox.Vector3.new(t[1], t[2], t[3])
end

-- Config/Weapons and Config/Firing, read from the source (data only).
-- Strays (M2): the held items' grips and sights come from tools/animation/weapons.luau until Config/Weapons exists
-- (M5 moves them there). No firing data yet.
local WEAPONS = luau.load(fs.readFile("tools/animation/weapons.luau"), { debugName = "weapons" })()
local FIRING = {}
-- the pieces every held item's holds share (tools/animation/holds.luau)
local HOLDS = nil -- Runenkrieg's shared hold pieces aren't ported yet (M5)

-- The gun origin in root space for a key's `gun` pose.
local function gunFrame(g: { [string]: any }, w: any, at: string?): any
	local r = math.rad
	local scale = v3(w.scale)
	local anchor = if at then v3(w.attachments[at]) else v3(w.grip)
	local rot = CFrame.Angles(0, r(g.yaw or 0), 0)
		* CFrame.Angles(r(g.pitch or 0), 0, 0)
		* CFrame.Angles(0, 0, r(g.roll or 0))
	return CFrame.new(g.x or 0, g.y or 0, g.z or 0) * rot * CFrame.new(-(anchor * scale))
end

-- Points an arm's hand at `target` (torso space): the shortest turn from hanging down so the arm lies along the line
-- from its shoulder (or from `from`, a point it should seem to come from) to the target, then moved along so the hand
-- lands on it. Returns the joint Transform and how far the arm moved off its shoulder.
local function reach(limb: string, target: any, from: any?, prev: any?): (any, number, any)
	local side = JOINTS[limb].side
	local rest = roblox.Vector3.new(0.5 * side, -0.5 - FIST, 0) -- pivot -> hand point, hanging
	local pivot = SHOULDER[limb]
	local want = target - (from or pivot)
	-- the smallest turn from `a` to `b`
	local function arc(a: any, b: any): any
		local axis = a:Cross(b)
		local angle = math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
		return if axis.Magnitude > 1e-6
			then CFrame.fromAxisAngle(axis.Unit, angle)
			else CFrame.new()
	end
	-- frame to frame the arm turns only as far as its direction moved (carried on from the last frame's turn). The
	-- smallest turn from hanging each frame flips round the arm's own axis when the arm points up (straight up is
	-- the opposite of hanging down): the hand spun during the equip.
	-- (`pinned`, from `fresh = "ends"`: this frame's turn, solved over the whole animation by pinTurns)
	local rot = if prev and prev.pinned
		then prev.pinned
		elseif prev then arc(prev.want, want) * prev.rot
		else arc(rest, want)
	local offset = target - pivot - rot * rest
	local body = CFrame.new(offset) * rot
	local c0 = JOINTS[limb].c0
	return c0:Inverse() * body * c0, offset.Magnitude, { want = want, rot = rot }
end

-- `fresh = "ends"`: the arm's turn carried frame to frame (no flip about its own axis, which a turn solved from hanging
-- makes as the arm swings up: the reload's right arm spun up to 242 deg in a frame), yet starting and ending exactly
-- on the holds' arms (solved from hanging, as the holds are). `pinAt` times pin more frames: a stretch src/client/GunFx
-- plays again (the single load's round) must start and end on the same turn. A pinned frame keeps the turn carried
-- into it, or the turn of an earlier pinned frame with the same arm line. Between two pinned frames the turn is
-- carried forward from the one and backward from the other: both point the arm the same way every frame and differ
-- only by a twist about it, handed over smoothly. `wants`: per frame, the line from the arm's origin to its hand.
local function pinTurns(
	limb: string,
	wants: { any },
	times: { number },
	pinAt: { number }?
): { any }
	local side = JOINTS[limb].side
	local rest = roblox.Vector3.new(0.5 * side, -0.5 - FIST, 0)
	local function arc(a: any, b: any): any
		local axis = a:Cross(b)
		local angle = math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
		return if axis.Magnitude > 1e-6
			then CFrame.fromAxisAngle(axis.Unit, angle)
			else CFrame.new()
	end
	local n = #wants
	-- the pinned frames: the first, the last and the frame at each `pinAt` time
	local pinned = { [1] = true, [n] = true }
	for _, at in pinAt or {} do
		local best = 1
		for i = 1, n do
			if math.abs(times[i] - at) < math.abs(times[best] - at) then
				best = i
			end
		end
		pinned[best] = true
	end
	-- their turns, in order
	local turn = { [1] = arc(rest, wants[1]), [n] = arc(rest, wants[n]) }
	local carried, prev = turn[1], 1
	for i = 2, n - 1 do
		carried = arc(wants[i - 1], wants[i]) * carried
		if pinned[i] then
			for j = 1, i - 1 do
				if pinned[j] and turn[j] and (wants[j] - wants[i]).Magnitude < 1e-4 then
					carried = turn[j] -- the same pose as before: the same turn
					break
				end
			end
			turn[i], prev = carried, i
		end
	end
	local out = {}
	local a = 1
	while a < n do
		local b = a + 1
		while not pinned[b] do
			b += 1
		end
		local fwd, back = { [a] = turn[a] }, { [b] = turn[b] }
		for i = a + 1, b do
			fwd[i] = arc(wants[i - 1], wants[i]) * fwd[i - 1]
		end
		for i = b - 1, a, -1 do
			back[i] = arc(wants[i + 1], wants[i]) * back[i + 1]
		end
		local last = nil
		for i = a, b do
			local dir = wants[i].Unit
			local axis, angle = (back[i] * fwd[i]:Inverse()):ToAxisAngle()
			local twist = if axis:Dot(dir) < 0 then -angle else angle
			if last then -- the twist moves continuously: take the turn nearest the last frame's
				twist += 2 * math.pi * math.floor((last - twist) / (2 * math.pi) + 0.5)
			end
			last = twist
			local u = (times[i] - times[a]) / (times[b] - times[a])
			out[i] = CFrame.fromAxisAngle(dir, u * u * (3 - 2 * u) * twist) * fwd[i]
		end
		a = b
	end
	return out
end

-- A key's gun pose may place another point than the animation's `at` (`gun.at = "grip"` or an attachment name): it is
-- moved onto the animation's point before smoothing, so keys placed by different points blend (the ADS from the
-- ready hold, placed by the grip, into the aim, placed by the sights).
local function reanchor(anim: any, w: any): any
	local keys = {}
	for i, key in anim.keys do
		local g = key.pose and key.pose.gun
		if g and g.at then
			local origin = gunFrame(g, w, if g.at == "grip" then nil else g.at)
			local anchor = if anim.at then v3(w.attachments[anim.at]) else v3(w.grip)
			local p = origin * (anchor * v3(w.scale))
			local gun = table.clone(g)
			gun.at, gun.x, gun.y, gun.z = nil, p.X, p.Y, p.Z
			local pose = table.clone(key.pose)
			pose.gun = gun
			key = table.clone(key)
			key.pose = pose
		end
		keys[i] = key
	end
	local out = table.clone(anim)
	out.keys = keys
	return out
end

local function build(anim: any): (any, number)
	local seq = Instance.new("KeyframeSequence")
	seq.Name = anim.name
	seq.Loop = anim.loop == true
	seq.Priority = Enum.AnimationPriority[anim.priority or "Movement"]
	local w = anim.weapon and WEAPONS[anim.weapon]
	assert(not anim.weapon or w, `unknown weapon {anim.weapon}`)
	if w then
		anim = reanchor(anim, w)
	end
	local keys = sample(anim)
	if anim.planted then
		plant(keys, if anim.planted == true then 1 else anim.planted)
	end
	if anim.footsteps then
		placeFootsteps(keys, anim.loop == true)
	end
	local under = RIG.root.c0 * transform("root", anim.under) * RIG.root.c1:Inverse() -- torso in root space
	local slides = { rightArm = { math.huge, -math.huge }, leftArm = { math.huge, -math.huge } }
	local carried = {} -- per arm: last frame's direction and turn (reach)
	-- weapon layers: the torso (root space) and the gun (torso space) for a key's pose
	local function layerAt(p: any): (any, any)
		local u = if p.root
			then RIG.root.c0 * transform("root", p.root) * RIG.root.c1:Inverse()
			else under
		return u, u:Inverse() * gunFrame(p.gun, w, anim.at)
	end
	-- the arms a weapon layer poses, each with its hand point on the gun (modelled gun space)
	local arms = if w
		then { rightArm = anim.hands.right or w.grip, leftArm = anim.hands.left }
		else {}
	-- where an arm's hand goes and where the arm comes from, torso space
	local function armGoal(p: any, limb: string, u: any, gun: any): (any, any?)
		local point = arms[limb]
		local from = anim.from and anim.from[limb]
		-- a key may give its own hand point (`rightGrip` / `leftGrip`, gun space) and arm origin (`rightFrom` /
		-- `leftFrom`, root space; the shoulder is { 1, 0.5, 0 }), each { x, y, z } and smoothed between keys, so
		-- a one shot between two holds can blend their hands too (the aim-in from the ready hold's arms into the
		-- aim hold's: the right arm jumped at the start)
		local side = if limb == "rightArm" then "right" else "left"
		local grip, origin = p[side .. "Grip"], p[side .. "From"]
		if grip then
			point = { grip.x, grip.y, grip.z }
		end
		if origin then
			from = { origin.x, origin.y, origin.z }
		end
		local target = gun * (v3(point) * v3(w.scale))
		-- `touch` (user 2026-10-19: the rifles clipped through the hands; "it looks held"): the hand point is on the
		-- gun's surface and the hand sits off it along `touch` (gun space; `anim.touch.right` / `.left`, or per key
		-- `rightTouch` / `leftTouch` { x, y, z }, smoothed), pushed out until the surface point is on the hand block's face:
		-- its side (half the arm's width off its axis) or its end (0.2 past the hand point), whichever the arm's angle
		-- meets first, a hair inside so it touches
		local touch = p[side .. "Touch"] or (anim.touch and anim.touch[side])
		if touch then
			local n = gun:VectorToWorldSpace(
				v3(if touch.x then { touch.x, touch.y, touch.z } else touch)
			).Unit
			local origin = if from then u:Inverse() * v3(from) else SHOULDER[limb]
			local surface = target
			for _ = 1, 5 do
				local d = (target - origin).Unit
				local along = -n:Dot(d)
				local perp = (n - d * n:Dot(d)).Magnitude
				local k = if perp > 1e-3 then TOUCH_SIDE / perp else math.huge
				if along > 1e-3 then
					k = math.min(k, TOUCH_END / along)
				end
				target = surface + n * (if k == math.huge then 0 else k)
			end
		end
		-- `rightBody` / `leftBody` (root space { x, y, z }) with `rightMix` / `leftMix` ({ w = 0..1 }): the hand leaves
		-- the gun for a point on the body by that much (a reload's hand to the ammo pouch and back); keys give all
		-- three so the smoothing blends them
		local body, mix = p[side .. "Body"], p[side .. "Mix"]
		if body and mix then
			target = target:Lerp(
				u:Inverse() * roblox.Vector3.new(body.x, body.y, body.z),
				math.clamp(mix.w, 0, 1)
			)
		end
		return target, from and (u:Inverse() * v3(from))
	end
	local pins = {} -- `fresh = "ends"`: per arm, each frame's turn
	if w and anim.fresh == "ends" then
		for limb in arms do
			local wants, times = {}, {}
			for i, key in keys do
				local p = key.pose or {}
				local u, gun = layerAt(p)
				local target, from = armGoal(p, limb, u, gun)
				wants[i], times[i] = target - (from or SHOULDER[limb]), key.t
			end
			pins[limb] = pinTurns(limb, wants, times, anim.pinAt)
		end
	end
	for i, key in keys do
		local kf = Instance.new("Keyframe")
		kf.Name = "Keyframe"
		kf.Time = key.t
		local ease = "Linear"
		local p = key.pose or {}
		local hrp = pose("HumanoidRootPart", CFrame.new(), ease)
		local torso = pose("Torso", transform("root", p.root), ease)
		if w then
			-- weapon layer: the gun and the arms reaching for it; the movement cycle keeps the root and the torso, unless
			-- the keys turn the body themselves (`root` in a key: the staff's charge twisting right; then this layer
			-- writes the torso, and the gun stays where the data puts it in the upright frame while the body turns)
			assert(
				not (p.root and anim.under),
				`{anim.name}: a weapon layer keys root or has under, not both`
			)
			local under, gun = layerAt(p)
			hrp.Weight, torso.Weight = 0, if p.root then 1 else 0
			pose("Gun", gun, ease).Parent = torso
			for limb in arms do
				local target, from = armGoal(p, limb, under, gun)
				local prev = carried[limb]
				if pins[limb] then
					prev = { pinned = pins[limb][i] }
				end
				local t, slide, state = reach(limb, target, from, prev)
				-- `fresh = true`: each frame solved from hanging, as the holds are, so a short one shot between two holds
				-- starts and ends on their exact arm poses (carried, the arms ended twisted about themselves; `fresh =
				-- "ends"`: carried but pinned to them, pinTurns)
				carried[limb] = if anim.fresh then nil else state
				-- `grab = { rightArm = 0..1, leftArm = 0..1 }` on a key: how far the hand is on the gun (0 = the arm
				-- hangs at rest), so a hand can take hold partway through (the equip)
				local hold = p.grab and p.grab[limb]
				if hold then
					t = CFrame.new():Lerp(t, math.clamp(hold, 0, 1))
				end
				pose(JOINTS[limb].part, t, ease).Parent = torso
				slides[limb] =
					{ math.min(slides[limb][1], slide), math.max(slides[limb][2], slide) }
			end
			if p.head then
				pose("Head", transform("head", p.head), ease).Parent = torso
			end
			-- legs keyed in a weapon layer (the staff's air charge: legs hanging straight down under a leaning body)
			for _, limb in { "leftLeg", "rightLeg" } do
				if p[limb] then
					pose(JOINTS[limb].part, transform(limb, p[limb]), ease).Parent = torso
				end
			end
		else
			-- `only = { "rightArm", "leftArm", "head" }`: an upper-body layer with nothing in the hands (healing someone):
			-- only those joints are written, the root and torso poses weigh 0, so the cycle underneath (the crouch) keeps
			-- the body and legs
			if anim.only then
				hrp.Weight, torso.Weight = 0, if table.find(anim.only, "root") then 1 else 0
			end
			for _, limb in LIMBS do
				if anim.only and not table.find(anim.only, limb) then
					continue
				end
				local target = p[HAND[limb] or ""]
				if target and SHOULDER[limb] then
					-- a key's `leftHand` / `rightHand = { x, y, z }` puts that hand there (root space), the arm coming
					-- from `from` if given (first-person arms with nothing in the hands)
					-- (a key that poses the root bends and turns the body under the hands: its own torso, not `under`)
					local from = anim.from and anim.from[limb]
					local u = if p.root
						then RIG.root.c0 * transform("root", p.root) * RIG.root.c1:Inverse()
						else under
					local t, _, state = reach(
						limb,
						u:Inverse() * roblox.Vector3.new(target.x, target.y, target.z),
						from and (u:Inverse() * v3(from)),
						carried[limb]
					)
					carried[limb] = state
					pose(JOINTS[limb].part, t, ease).Parent = torso
				else
					pose(JOINTS[limb].part, transform(limb, p[limb]), ease).Parent = torso
				end
			end
		end
		torso.Parent = hrp
		hrp.Parent = kf
		if key.marker then
			local m = Instance.new("KeyframeMarker")
			m.Name = key.marker[1]
			m.Value = key.marker[2] or ""
			m.Parent = kf
		end
		kf.Parent = seq
	end
	if w then
		for _, limb in { "rightArm", "leftArm" } do
			if slides[limb][1] == math.huge then
				continue -- not posed: a one-handed item leaves this arm to the cycle underneath
			end
			print(
				string.format(
					"  %s slides %.2f .. %.2f studs along itself to reach",
					limb,
					slides[limb][1],
					slides[limb][2]
				)
			)
		end
	end
	return seq, #keys
end

-- The first frame's joint Transforms as Luau source ({ [part name] = CFrame components }), for posing a dummy in
-- Studio before uploading (C0 = C0 * Transform; the gun's Motor6D has C0 = C1 = identity).
local function preview(seq: any): string
	local lines = {}
	local function walk(p: any)
		for _, c in p:GetChildren() do
			if c:IsA("Pose") then
				if c.Weight > 0 and c.Name ~= "HumanoidRootPart" then
					local parts = { c.CFrame:GetComponents() }
					for i, n in parts do
						parts[i] = string.format("%.5f", n)
					end
					table.insert(
						lines,
						string.format('	["%s"] = { %s },', c.Name, table.concat(parts, ", "))
					)
				end
				walk(c)
			end
		end
	end
	walk(seq:GetChildren()[1])
	return "return {\n" .. table.concat(lines, "\n") .. "\n}\n"
end

local args = process.args
assert(
	#args >= 2,
	"usage: lune run tools/animation/build.luau <out .rbxm> <data module> [<data module> ...]"
)
-- every sequence from every data module goes into one Folder "Animations" (names must be unique)
local folder = Instance.new("Folder")
folder.Name = "Animations"
local seen = {}
for i = 2, #args do
	local data = luau.load(fs.readFile(args[i]), { debugName = args[i] })()
	if type(data) == "function" then
		-- a data module may read the weapons (grips, sights), firing data and the shared hold pieces
		data = data(WEAPONS, FIRING, HOLDS)
	end
	for _, anim in data do
		assert(not seen[anim.name], `two animations named {anim.name}`)
		seen[anim.name] = true
		print(`{anim.name}`)
		local seq, frames = build(anim)
		seq.Parent = folder
		print(
			`  {#anim.keys} keys -> {frames} frames  {anim.keys[#anim.keys].t}s  loop={anim.loop == true}`
		)
	end
end
fs.writeFile(args[1], roblox.serializeModel({ folder }))
print(`wrote {args[1]}`)
