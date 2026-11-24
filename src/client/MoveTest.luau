--!strict
-- M2 movement test (style-test branch only; M6 builds the real Locomotion). Plays the movement clips
-- (ReplicatedStorage.Animations, built by tools/animation/build.luau) on the player's Strays rifleman with the
-- block-out rifle, to the approved ANIMATION-GUIDE.md §2-4 (jarvis, 2026-11-22):
--   WASD walk 12 · Shift sprint 20 · C crouch 7 · Z prone, crawl 3 · Space jump (low hop) / vault / mantle
--   Q / E lean (live, any cycle) · L limp: none / one leg 8 / both legs 5 · T first / third person
--   F or right mouse aim (walk 8) · left click or X fire (hip fire unless aiming)
-- The cycles, holds, stance changes and vaults are baked from the jarvis motion study (v11, approved 2026-11-23;
-- tools/animation/baked.luau). Carry (study): with nothing happening the rifle rests in the safe carry; firing or
-- aiming brings it up (0.3 s from safe to the first shot), hip fire holds 0.6 s after the last shot, then low ready,
-- and after 4 s of rest the safe carry again. Leaning and going prone / getting up count as alert.
-- The clips aren't uploaded: KeyframeSequenceProvider:RegisterKeyframeSequence (works in Studio only).
-- Test hooks (Studio MCP, no key mapping): player attribute "M2Cmd" = "crouch" | "prone" | "jump" | "limp" | "camera"
-- | "sprintOn" | "sprintOff" | "leanL" | "leanR" | "leanOff" | "fire" | "aimOn" | "aimOff"; "M2Move" (Vector3,
-- world) moves like the stick.
-- Each frame the character carries "M2State" (JSON: stance, speed, clips, camera offset) for checks by numbers.
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MotionPaths = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StyleTest"):WaitForChild("MotionPaths")
)

local MoveTest = {}

local player = Players.LocalPlayer

-- ANIMATION-GUIDE §2 speeds (studs/s)
local SPEED =
	{ walk = 12, sprint = 20, crouch = 7, prone = 3, lean = 7, limp1 = 8, limp2 = 5, aim = 8 }
-- each body loop's speed at its keyed length (the playback rate scales with the real speed)
local NOMINAL = {
	Walk = 12,
	Sprint = 20,
	CrouchWalk = 7,
	Crawl = 3,
	LimpOne = 8,
	LimpBoth = 5,
	Swim = 12,
	AimWalk = 8,
	AimCrouchWalk = 7,
}
-- carry (motion study): rest delay, raise / lower smoothing, hip-fire hold, aim tween, recoil
local CARRY = {
	rest = 4,
	raise = 0.1,
	lower = 0.32,
	hipIn = 0.05,
	hipOut = 0.14,
	hipHold = 0.6,
	aimUp = 0.2,
	aimDown = 0.18,
}
local FIRE = { gap = 0.1, kick = 9, flash = 0.05 }
local SPRINT_CONE = math.cos(math.rad(50)) -- sprint only within 50 deg of the camera look
local BLEND = 0.13 -- §3.11 0.12-0.15
local LEAN = { tilt = 20, inTime = 0.15, outTime = 0.12, roll = 8 } -- §3.8 (+ 1P camera roll, approved proposal)
local BOB = { walk = 0.03, sprint = 0.08 } -- §4.1 1P camera bob
local LAG = { max = 3, settle = 0.15 } -- §4.1 1P gun turn lag (deg, s)
-- §3.7; faceSlope: the face must be near vertical (|normal.Y| under this); standable: a top / landing floor no steeper
-- than ~37 deg (normal.Y over this); maxDrop: the farthest floor below the top a vault lands on
local VAULT = {
	hop = 3.5,
	mantle = 5.5,
	reach = 2.2,
	hopTime = 0.45,
	mantleTime = 0.8,
	faceSlope = 0.5,
	standable = 0.8,
	maxDrop = 8,
}
local LONG_FALL = 10 -- §3.6
local VIEW_LIFT = Vector3.new(0, 0.6, -0.6) -- 1P: the body rides up and forward (root space) so the rifle shows
local VIEW_LIFT_CROUCH = Vector3.new(0, 1.1, -0.6)
-- stance changes (§3.4 / §3.5; timing from the motion study, the clip's own length): clip
local CHANGE = {
	stand_crouch = "StandToCrouch",
	crouch_stand = "CrouchToStand",
	stand_prone = "StandToProne",
	prone_stand = "ProneToStand",
	crouch_prone = "CrouchToProne",
	prone_crouch = "ProneToCrouch",
}
-- a critically damped follow (the study's damp): x, velocity -> new x, new velocity
local function damp(x: number, v: number, target: number, T: number, dt: number): (number, number)
	local w = 2 / T
	local k = w * dt
	local e = 1 / (1 + k + 0.48 * k * k + 0.235 * k * k * k)
	local ch = x - target
	local tmp = (v + w * ch) * dt
	return target + (ch + tmp) * e, (v - w * tmp) * e
end
-- slow multi-sine noise (-1..1), as the study's life layer
local function noise(t: number, k: number): number
	return (
		math.sin(t * 1.13 + k)
		+ 0.7 * math.sin(t * 0.71 + 2.1 * k)
		+ 0.4 * math.sin(t * 2.37 + 0.6 * k)
	) / 2.1
end
-- the R6 joints' C0 rotations (tools/animation/build.luau JOINTS)
local C0 = {
	root = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	rightLeg = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	leftLeg = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}
local function inJoint(c0: CFrame, body: CFrame): CFrame
	return c0:Inverse() * body * c0
end

local ids: { [string]: string } = {}
local function registerAll()
	local folder = ReplicatedStorage:WaitForChild("Animations")
	for _, seq in folder:GetChildren() do
		if seq:IsA("KeyframeSequence") and not ids[seq.Name] then
			ids[seq.Name] = KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
		end
	end
end
MoveTest.ids = ids
function MoveTest.register()
	registerAll()
	return ids
end

-- the lean / gun-lag pass and its state, per character
type Rig = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	head: BasePart,
	rootJoint: Motor6D,
	rightHip: Motor6D,
	leftHip: Motor6D,
	neck: Motor6D?,
	gun: Motor6D?,
	tracks: { [string]: AnimationTrack },
}

local function loadRig(char: Model): Rig?
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return nil
	end
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local torso = char:WaitForChild("Torso") :: BasePart
	-- Roblox's Animate would play its own idle / walk on the joints this test owns (notes/traps/animation.md)
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	local animator = hum:WaitForChild("Animator") :: Animator
	for _, t in animator:GetPlayingAnimationTracks() do
		t:Stop(0)
	end
	local tracks = {}
	for name, id in ids do
		local a = Instance.new("Animation")
		a.AnimationId = id
		tracks[name] = animator:LoadAnimation(a)
	end
	return {
		char = char,
		hum = hum,
		root = root,
		head = char:WaitForChild("Head") :: BasePart,
		rootJoint = root:WaitForChild("RootJoint") :: Motor6D,
		rightHip = torso:WaitForChild("Right Hip") :: Motor6D,
		leftHip = torso:WaitForChild("Left Hip") :: Motor6D,
		neck = torso:FindFirstChild("Neck") :: Motor6D?,
		gun = torso:WaitForChild("Gun", 5) :: Motor6D?,
		tracks = tracks,
	}
end

-- Lean (live, on top of any cycle): the torso tilts about its centre and shifts so the hips stay put, the legs turn
-- back so they stay upright. `a` -1 (left) .. 1 (right). Also used by the gallery.
function MoveTest.applyLean(rig: any, a: number)
	if math.abs(a) < 1e-3 then
		return
	end
	local t = math.rad(LEAN.tilt * a)
	local body = CFrame.new(math.sin(t), -(1 - math.cos(t)), 0) * CFrame.Angles(0, 0, -t)
	rig.rootJoint.Transform = inJoint(C0.root, body) * rig.rootJoint.Transform
	local legs = CFrame.Angles(0, 0, t)
	rig.rightHip.Transform = inJoint(C0.rightLeg, legs) * rig.rightHip.Transform
	rig.leftHip.Transform = inJoint(C0.leftLeg, legs) * rig.leftHip.Transform
end
MoveTest.loadRig = loadRig

function MoveTest.start()
	registerAll()
	local camera = workspace.CurrentCamera

	-- HUD: the keys and what is playing
	local gui = Instance.new("ScreenGui")
	gui.Name = "M2MoveTest"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -8)
	label.Size = UDim2.fromOffset(760, 44)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.TextColor3 = Color3.fromRGB(210, 214, 210)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = label

	local rig: Rig? = nil
	local stance = "stand" -- stand | crouch | prone
	local sprintHeld = false
	local leanIn = 0 -- held keys: -1, 0, 1
	local leanA = 0 -- current lean -1..1
	local limp = 0 -- 0 none, 1 one leg, 2 both
	local firstPerson = false
	local hookMove: Vector3? = nil
	local busyUntil = 0 -- a stance change / vault in its action phase
	local vaulting = false
	local slots: { [string]: string? } = { body = nil, hold = nil }
	local oneShot: AnimationTrack? = nil
	local oneShotName = ""
	local lastPlay = "" -- the last one-shot started (any priority), for checks
	local airPeak = 0
	local lastWalkT = 0
	local wasSprinting = false
	local sprintStopAt = 0
	local dip = { t0 = 0, len = 0, depth = 0 }
	local camOffset = Vector3.zero
	-- carry state (motion study): ready 0 safe .. 1 up, hip, aim; shots queued; recoil spring
	local carry = {
		alertT = 99,
		ready = 0,
		readyV = 0,
		hip = 0,
		hipV = 0,
		hipT = 99,
		aimIn = false,
		aimLin = 0,
		aim = 0,
		shots = 0,
		shotT = 0,
		rec = 0,
		recV = 0,
		flash = 0,
		fired = 0,
	}
	local holdW: { [string]: number } = {} -- the hold layers playing and their weights
	local life = 0
	local stanceY = { stand = 0, crouch = -1.25, prone = -2.55 }
	local bobPhase = 0
	local lagYaw, lagPitch = 0, 0
	local vmBlend = 0
	local liftNow = VIEW_LIFT
	-- crouched the carry sits higher on the body (measured: muzzle 4 deg under the view centre at the standing lift)
	local function viewLift(): Vector3
		local want = if stance == "crouch" then VIEW_LIFT_CROUCH else VIEW_LIFT
		liftNow = liftNow:Lerp(want, 0.15)
		return liftNow
	end
	local lastLook: Vector3? = nil
	local turnAcc, lastYaw = 0, 0

	local function track(name: string): AnimationTrack?
		return rig and rig.tracks[name]
	end
	local function setSlot(slot: string, name: string?, fade: number?)
		if slots[slot] == name then
			return
		end
		local oldName = slots[slot]
		local old = oldName and track(oldName :: string)
		if old then
			old:Stop(fade or BLEND)
		end
		slots[slot] = name
		local new = name and track(name)
		if new then
			new:Play(fade or BLEND)
			-- cycle to cycle (walk / aim walk / crouch walk / sprint ...) the new loop picks up the old one's phase, so
			-- the feet don't restart from the first contact
			if
				old
				and NOMINAL[oldName :: string]
				and NOMINAL[name :: string]
				and old.Length > 0
				and new.Length > 0
			then
				new.TimePosition = (old.TimePosition / old.Length) * new.Length
			end
		end
	end
	local function play(name: string, fade: number?)
		local t = track(name)
		if not t then
			return
		end
		if oneShot and oneShot ~= t and oneShot.Priority == t.Priority then
			oneShot:Stop(0.05)
		end
		t:Play(fade or 0.05)
		lastPlay = name
		if t.Priority == Enum.AnimationPriority.Action3 then
			oneShot, oneShotName = t, name
		end
	end

	local function setStance(to: string)
		if not rig or to == stance or vaulting then
			return
		end
		local st = rig.hum:GetState()
		if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Swimming then
			return
		end
		local change = CHANGE[stance .. "_" .. to]
		stance = to
		if change then
			play(change)
			local t = track(change)
			busyUntil = os.clock() + (if t then t.Length else 0.3) * 0.6 -- the settle can be cut (approved proposal)
		end
	end

	-- Vault / mantle (§3.7): find a ledge ahead, its top and depth; carry the root over on a path while the clip plays.
	local function ray(from: Vector3, dir: Vector3): RaycastResult?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rig and rig.char :: any }
		params.IgnoreWater = true
		return workspace:Raycast(from, dir, params)
	end
	local function tryVault(): boolean
		if not rig or stance ~= "stand" then
			return false
		end
		local r = rig.root
		local look = r.CFrame.LookVector
		local dir = Vector3.new(look.X, 0, look.Z).Unit
		local g = r.Position.Y - 3
		local face: Vector3? = nil
		for h = 0.6, 5.4, 0.4 do
			local hit = ray(Vector3.new(r.Position.X, g + h, r.Position.Z), dir * VAULT.reach)
			if hit then
				if math.abs(hit.Normal.Y) > VAULT.faceSlope then
					return false -- a slope or a roof edge, not a wall to go over (walk up it or jump)
				end
				face = hit.Position
				break
			end
		end
		if not face then
			return false
		end
		if ray(Vector3.new(r.Position.X, g + 5.8, r.Position.Z), dir * VAULT.reach) then
			return false -- too tall (a window's opening is clear at 5.8)
		end
		local top =
			ray(face + dir * 0.25 + Vector3.new(0, g + 5.6 - face.Y, 0), Vector3.new(0, -5.4, 0))
		if not top or top.Normal.Y < VAULT.standable then
			return false -- nothing flat to put the hands and feet on (a steep or pointed top)
		end
		local h = top.Position.Y - g
		if h < 0.8 or h > VAULT.mantle then
			return false
		end
		-- depth: march along the top until it drops away
		local depth = 3
		for k = 0.5, 3, 0.25 do
			local d =
				ray(face + dir * k + Vector3.new(0, g + 5.6 - face.Y, 0), Vector3.new(0, -8, 0))
			if not d or d.Position.Y < top.Position.Y - 0.5 then
				depth = k
				break
			end
		end
		local p0 = r.CFrame
		-- a wall reads about 0.25 deeper than it is (the march step): 1-stud walls give 1.25, so 1.6 is a ledge
		local onto = depth >= 1.6
		-- a window: something over the sill within 4 studs. Always the mantle (§3.7), the root kept low through it
		local roof = ray(
			face + dir * 0.5 + Vector3.new(0, top.Position.Y + 0.1 - face.Y, 0),
			Vector3.new(0, 4, 0)
		)
		local headroom = if roof then roof.Position.Y - top.Position.Y else math.huge
		local land: Vector3
		if onto then
			local at = face + dir * math.min(depth - 0.4, 1.2)
			land = Vector3.new(at.X, top.Position.Y + 3, at.Z)
		else
			local at = face + dir * (depth + 1.3)
			local below = ray(Vector3.new(at.X, top.Position.Y + 1, at.Z), Vector3.new(0, -12, 0))
			land = Vector3.new(at.X, (if below then below.Position.Y else g) + 3, at.Z)
		end
		if onto and headroom < 5.2 then
			return false -- no room to stand up there
		end
		local hop = h <= VAULT.hop and headroom > 4
		-- the baked clip and its root path (motion study): the lift scaled to this ledge's height, the forward path as
		-- baked (the body clears the top as in the study), the difference between this face distance and the baked one
		-- taken up over the first 40%, and the landing floor found where the path ends
		local clip = if hop then "VaultHop" elseif onto then "Mantle" else "MantleWindow"
		local bake = MotionPaths[clip]
		local path = bake.path
		local n = #path
		local len = (n - 1) / bake.fps
		local ky = h / bake.height
		local shift = (face - p0.Position):Dot(dir) - bake.trigger
		local endPos = p0.Position + dir * (path[n][2] + shift)
		local floorY = land.Y
		if not onto then
			local below = ray(
				Vector3.new(endPos.X, top.Position.Y + 1, endPos.Z),
				Vector3.new(0, -(VAULT.maxDrop + h + 1), 0)
			)
			if not below or below.Normal.Y < VAULT.standable then
				return false -- no floor to land on past it (a map edge, a drop, a steep bank)
			end
			floorY = below.Position.Y + 3
		end
		-- the way over and the landing must be clear: a straight line just over the top to the end, and a body-sized
		-- box where it stands at the end (no vaulting into or through walls)
		local over = top.Position.Y + (if headroom < 5 then 1.2 else 2)
		local from = Vector3.new(p0.Position.X, over, p0.Position.Z)
		local to = Vector3.new(endPos.X, if onto then floorY else over, endPos.Z)
		if ray(from, to - from) then
			return false
		end
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { rig and rig.char :: any }
		overlap.RespectCanCollide = true
		local room = workspace:GetPartBoundsInBox(
			CFrame.new(endPos.X, floorY - 0.2, endPos.Z) * (p0 - p0.Position),
			Vector3.new(1.8, 4.2, 1.2),
			overlap
		)
		if #room > 0 then
			return false
		end
		local dropY = floorY - (p0.Position.Y + path[n][1] * ky) -- a lower or higher floor past the obstacle
		vaulting = true
		busyUntil = os.clock() + len
		r.Anchored = true
		play(clip, 0.05)
		local rot = p0 - p0.Position
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			local f = math.clamp(t * bake.fps, 0, n - 1)
			local a = math.floor(f)
			local b = math.min(a + 1, n - 1)
			local u = f - a
			local lift = path[a + 1][1] + (path[b + 1][1] - path[a + 1][1]) * u
			local fwd = path[a + 1][2] + (path[b + 1][2] - path[a + 1][2]) * u
			local s0 = math.clamp(t / (0.4 * len), 0, 1)
			local e0 = math.clamp((t / len - 0.6) / 0.4, 0, 1)
			-- the hop clears the wall with a little margin (the Studio body stands ~0.1 lower than the study's, and
			-- ground isn't flat): +0.4 over the middle of the clip
			local margin = if hop
				then 0.4 * math.sin(math.pi * math.clamp(t / (0.8 * len), 0, 1))
				else 0
			local pos = p0.Position
				+ dir * (fwd + shift * s0 * s0 * (3 - 2 * s0))
				+ Vector3.new(0, lift * ky + dropY * e0 * e0 + margin, 0)
			r.CFrame = rot + pos
			if t >= len then
				conn:Disconnect()
				r.CFrame = rot + Vector3.new(endPos.X, floorY, endPos.Z)
				r.Anchored = false
				r.AssemblyLinearVelocity = dir * (if hop then SPEED.walk else 0)
				vaulting = false
			end
		end)
		return true
	end

	-- input
	local function cmd(name: string)
		if name == "crouch" then
			setStance(if stance == "crouch" then "stand" else "crouch")
		elseif name == "prone" then
			setStance(if stance == "prone" then "stand" else "prone")
		elseif name == "jump" then
			-- (user 2026-11-23) a plain jump whenever: standing, crouched (stands and hops) or mid stance change; a
			-- vault only where tryVault finds something to stand on. Prone is too low to hop: Space gets up a step.
			if not rig or vaulting then
				return
			end
			if stance == "prone" then
				if os.clock() >= busyUntil then
					setStance("crouch")
				end
				return
			end
			if stance == "crouch" then
				setStance("stand")
			end
			if not tryVault() then
				local st = rig.hum:GetState()
				if
					st ~= Enum.HumanoidStateType.Freefall
					and st ~= Enum.HumanoidStateType.Jumping
				then
					if oneShot and string.find(oneShotName, "To") then
						oneShot:Stop(0.08) -- the jump takes over from a stance change
					end
					busyUntil = 0
					-- (not hum.Jump = true: Space is sunk here, so the default ControlModule writes Jump = false every
					-- frame and the flag never reached the simulation; no jump happened at all)
					rig.hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end
		elseif name == "limp" then
			limp = (limp + 1) % 3
		elseif name == "camera" then
			firstPerson = not firstPerson
			if firstPerson then
				player.CameraMode = Enum.CameraMode.LockFirstPerson
			else
				player.CameraMode = Enum.CameraMode.Classic
				player.CameraMinZoomDistance = 12
				task.delay(0.1, function()
					player.CameraMinZoomDistance = 0.5
				end)
			end
		elseif name == "sprintOn" then
			sprintHeld = true
		elseif name == "sprintOff" then
			sprintHeld = false
		elseif name == "leanL" then
			leanIn = -1
		elseif name == "leanR" then
			leanIn = 1
		elseif name == "leanOff" then
			leanIn = 0
		elseif name == "fire" then
			if not rig or vaulting then
				return
			end
			carry.shots += 1
			carry.alertT = 0
		elseif name == "aimOn" then
			carry.aimIn = true
		elseif name == "aimOff" then
			carry.aimIn = false
		elseif name == "aimToggle" then
			carry.aimIn = not carry.aimIn
		end
	end
	ContextActionService:BindActionAtPriority("M2Jump", function(_, state)
		if state == Enum.UserInputState.Begin then
			cmd("jump")
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.LeftShift then
			cmd("sprintOn")
		elseif k == Enum.KeyCode.C then
			cmd("crouch")
		elseif k == Enum.KeyCode.Z then
			cmd("prone")
		elseif k == Enum.KeyCode.Q then
			cmd("leanL")
		elseif k == Enum.KeyCode.E then
			cmd("leanR")
		elseif k == Enum.KeyCode.L then
			cmd("limp")
		elseif k == Enum.KeyCode.T then
			cmd("camera")
		elseif k == Enum.KeyCode.F then
			cmd("aimToggle")
		elseif k == Enum.KeyCode.X or input.UserInputType == Enum.UserInputType.MouseButton1 then
			cmd("fire")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			cmd("aimOn")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local k = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			cmd("aimOff")
		end
		if k == Enum.KeyCode.LeftShift then
			cmd("sprintOff")
		elseif (k == Enum.KeyCode.Q and leanIn < 0) or (k == Enum.KeyCode.E and leanIn > 0) then
			cmd("leanOff")
		end
	end)
	player:GetAttributeChangedSignal("M2Cmd"):Connect(function()
		local c = player:GetAttribute("M2Cmd")
		if type(c) == "string" and c ~= "" then
			cmd(c)
			player:SetAttribute("M2Cmd", "")
		end
	end)
	player:GetAttributeChangedSignal("M2Move"):Connect(function()
		local v = player:GetAttribute("M2Move")
		hookMove = if typeof(v) == "Vector3" and v.Magnitude > 0 then v else nil
	end)

	local function onCharacter(char: Model)
		rig = nil
		slots = { body = nil, hold = nil }
		stance, limp, leanA, vaulting = "stand", 0, 0, false
		local r = loadRig(char)
		if not r then
			return
		end
		rig = r
		r.hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				airPeak = r.root.Position.Y
			elseif new == Enum.HumanoidStateType.Freefall then
				airPeak = math.max(airPeak, r.root.Position.Y)
			elseif new == Enum.HumanoidStateType.Landed then
				local fallen = airPeak - r.root.Position.Y
				local long = fallen > LONG_FALL
				-- landing on the move, the cycle carries on (the clip froze the legs): only the camera dip, below
				if long or r.hum.MoveDirection.Magnitude < 0.1 then
					play(if long then "LandLong" else "LandShort")
				end
				dip = {
					t0 = os.clock(),
					len = if long then 0.35 else 0.15,
					depth = if long then 0.6 else 0.18,
				}
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- state -> loops, speeds (every frame)
	RunService.Heartbeat:Connect(function(dt)
		local r = rig
		if not r or not r.char.Parent then
			return
		end
		local hum = r.hum
		local st = hum:GetState()
		local vel = r.root.AssemblyLinearVelocity
		local planar = Vector3.new(vel.X, 0, vel.Z)
		local moving = hum.MoveDirection.Magnitude > 0.1
		local speed = planar.Magnitude
		local air = st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping
		local swimming = st == Enum.HumanoidStateType.Swimming
		if air then
			airPeak = math.max(airPeak, r.root.Position.Y)
		end
		-- §3.10 head above water: Roblox lets a swimmer sink a few studs; hold the root ~1.2 under the surface
		if swimming then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { r.char }
			params.IgnoreWater = false
			local hit = workspace:Raycast(
				r.root.Position + Vector3.new(0, 8, 0),
				Vector3.new(0, -8, 0),
				params
			)
			-- not over a floor in reach (wading out up a ramp or a bank: let the legs climb)
			params.IgnoreWater = true
			local floor = workspace:Raycast(r.root.Position, Vector3.new(0, -3.6, 0), params)
			if hit and hit.Material == Enum.Material.Water and not floor then
				local want = hit.Position.Y - 1.2
				local v = r.root.AssemblyLinearVelocity
				r.root.AssemblyLinearVelocity =
					Vector3.new(v.X, math.clamp((want - r.root.Position.Y) * 6, -8, 8), v.Z)
			end
		end
		local camLook = camera.CFrame.LookVector
		local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
		local forward = moving
			and flatLook.Magnitude > 0
			and hum.MoveDirection:Dot(flatLook.Unit) > SPRINT_CONE
		local aimOn = carry.aimIn and not swimming and not vaulting
		local sprinting = sprintHeld
			and moving
			and forward
			and limp == 0
			and not air
			and not swimming
			and not aimOn
			and carry.shots == 0
		if sprinting and stance == "crouch" then
			setStance("stand")
		end
		sprinting = sprinting and stance == "stand"
		-- lean: standing or crouched, not sprinting, not in the air (§3.8)
		local leanWant = if (
				stance ~= "prone"
				and not sprinting
				and not air
				and not swimming
				and not vaulting
			)
			then leanIn
			else 0
		local rate = 1
			/ (if math.abs(leanWant) > math.abs(leanA) then LEAN.inTime else LEAN.outTime)
		leanA += math.clamp(leanWant - leanA, -rate * dt, rate * dt)

		-- speed
		local ws = SPEED.walk
		if stance == "crouch" then
			ws = SPEED.crouch
		elseif stance == "prone" then
			ws = SPEED.prone
		elseif sprinting then
			ws = SPEED.sprint
		end
		if limp == 1 then
			ws = math.min(ws, SPEED.limp1)
		elseif limp == 2 then
			ws = math.min(ws, SPEED.limp2)
		end
		if math.abs(leanA) > 0.3 then
			ws = math.min(ws, SPEED.lean)
		end
		if aimOn and stance == "stand" then
			ws = math.min(ws, SPEED.aim)
		end

		-- carry (motion study): alert while aiming, firing, peeking or going prone / getting up; ready rises in ~0.3 s
		-- from the safe carry, lowers after CARRY.rest s of rest; hip fire holds after the last shot
		life += dt
		if
			aimOn
			or leanIn ~= 0
			or stance == "prone"
			or (oneShot and string.find(oneShotName, "Prone"))
		then
			carry.alertT = 0
		else
			carry.alertT += dt
		end
		local alert = carry.alertT < CARRY.rest or carry.shots > 0
		carry.ready, carry.readyV = damp(
			carry.ready,
			carry.readyV,
			if alert then 1 else 0,
			if alert then CARRY.raise else CARRY.lower,
			dt
		)
		carry.aimLin = math.clamp(
			carry.aimLin + (if aimOn then dt / CARRY.aimUp else -dt / CARRY.aimDown),
			0,
			1
		)
		local a = carry.aimLin
		carry.aim = a * a * a * (a * (a * 6 - 15) + 10)
		carry.hipT += dt
		local hipOn = not aimOn and (carry.shots > 0 or carry.hipT < CARRY.hipHold)
		carry.hip, carry.hipV = damp(
			carry.hip,
			carry.hipV,
			if hipOn then 1 else 0,
			if hipOn then CARRY.hipIn else CARRY.hipOut,
			dt
		)
		carry.shotT -= dt
		local upNow = carry.ready > 0.97
			and (carry.aim > 0.9 or carry.hip > 0.97 or stance == "prone")
		if carry.shots > 0 and upNow and carry.shotT <= 0 and not vaulting then
			carry.shots -= 1
			carry.shotT = FIRE.gap
			carry.recV += FIRE.kick
			carry.flash = FIRE.flash
			carry.fired += 1
			carry.alertT = 0
			if not aimOn then
				carry.hipT = 0
			end
		end
		if vaulting or swimming then
			carry.shots = 0
		end
		if oneShot and string.find(oneShotName, "Prone") then
			ws = math.min(ws, SPEED.prone) -- going down or getting up: no sliding at a run under it
		end
		hum.WalkSpeed = ws

		-- sprint accents (§3.3)
		if sprinting and not wasSprinting then
			play("SprintStart")
		end
		if wasSprinting and not sprinting then
			sprintStopAt = os.clock()
		end
		if sprintStopAt > 0 and not moving and os.clock() - sprintStopAt < 0.25 then
			play("SprintStop")
			sprintStopAt = 0
		elseif sprintStopAt > 0 and os.clock() - sprintStopAt >= 0.25 then
			sprintStopAt = 0
		end
		wasSprinting = sprinting

		-- loops: the body cycle, and its hold family (low ready / safe / hip / aim, weighted by the carry)
		local body, hold
		local family: string? = nil -- "Idle" | "Walk" | "Crouch" | "CrouchWalk"
		-- (a one-frame drop in MoveDirection flipped the body to its idle and back, restarting the cycle from its first
		-- frame: the walk looked paused; seen at 15 flips/s crouch-walking) the cycle holds through gaps under 0.15 s
		if moving and speed > 0.5 then
			lastWalkT = os.clock()
		end
		local walkingNow = speed > 0.5 and os.clock() - lastWalkT < 0.15
		local aimBody = carry.aim > 0.5
		if swimming then
			body, hold = if walkingNow then "Swim" else "Tread", nil
		elseif air then
			body, hold, family = "Fall", "HoldIdle", "Idle"
		elseif stance == "prone" then
			if walkingNow then
				body, hold = "Crawl", "HoldCrawl"
			else
				body = if aimBody then "AimProneIdle" else "ProneIdle"
				hold = if aimBody then "AimHoldProne" else "HoldProne"
			end
		elseif stance == "crouch" then
			body = if walkingNow
				then (if aimBody then "AimCrouchWalk" else "CrouchWalk")
				else (if aimBody then "AimCrouchIdle" else "CrouchIdle")
			hold = if walkingNow then "HoldCrouchWalk" else "HoldCrouch"
			family = if walkingNow then "CrouchWalk" else "Crouch"
		elseif walkingNow then
			if sprinting then
				body, hold = "Sprint", "HoldSprint"
			else
				body = if limp == 1
					then "LimpOne"
					elseif limp == 2 then "LimpBoth"
					elseif aimBody then "AimWalk"
					else "Walk"
				hold, family = "HoldWalk", "Walk"
			end
		else
			body, hold, family = if aimBody then "AimIdle" else "Idle", "HoldIdle", "Idle"
		end
		if st == Enum.HumanoidStateType.Jumping and slots.body ~= "Jump" then
			setSlot("body", "Jump", 0.05)
		end
		if slots.body == "Jump" then
			local jt = track("Jump")
			if jt and jt.IsPlaying and air then
				body = "Jump"
			end
		end
		setSlot("body", body)
		-- holds: the family's carries blended by weight (same priority), each kept in phase with the body
		local want: { [string]: number } = {}
		if family then
			local aimW = carry.aim
			local up = carry.ready * (1 - aimW)
			local holdName = ({
				Idle = "HoldIdle",
				Walk = "HoldWalk",
				Crouch = "HoldCrouch",
				CrouchWalk = "HoldCrouchWalk",
			})[family]
			want[holdName] = up * (1 - carry.hip)
			want["Safe" .. family] = (1 - carry.ready) * (1 - aimW)
			want["Hip" .. family] = up * carry.hip
			want["AimHold" .. family] = aimW
			hold = if aimW > 0.5
				then "AimHold" .. family
				elseif carry.ready < 0.5 then "Safe" .. family
				elseif carry.hip > 0.5 then "Hip" .. family
				else holdName
		elseif hold then
			want[hold] = 1
			if stance == "prone" and not walkingNow then
				want.HoldProne, want.AimHoldProne = 1 - carry.aim, carry.aim
			end
		end
		slots.hold = hold
		local bt = slots.body and track(slots.body :: string)
		if bt and NOMINAL[slots.body :: string] then
			bt:AdjustSpeed(math.clamp(speed / NOMINAL[slots.body :: string], 0.4, 1.6))
		end
		for name, w in want do
			local t = track(name)
			if t then
				if not t.IsPlaying and w > 0.01 then
					t:Play(BLEND, math.max(w, 0.01))
				end
				if t.IsPlaying then
					t:AdjustWeight(math.max(w, 0.001), 0.05)
				end
				if bt and bt.Length > 0 and t.Length > 0 and bt.Looped and t.Looped then
					t.TimePosition = (bt.TimePosition / bt.Length) * t.Length
				end
			end
		end
		for name in holdW do
			if not want[name] then
				local t = track(name)
				if t then
					t:Stop(BLEND)
				end
			end
		end
		holdW = want
		if oneShot and not oneShot.IsPlaying then
			oneShot, oneShotName = nil, ""
		end
		-- (user 2026-11-23: "between animations there is a pause") a full-body one-shot froze the leg cycle: the
		-- crouch / stand changes held the legs for 0.5 s while the body slid on at full speed. Moving, a crouch or
		-- stand change hands over to the new stance's cycle at once (the height still eases across the fade), and
		-- every one-shot fades out into the loop over its last BLEND s instead of snapping off at its end.
		if oneShot and oneShot.IsPlaying and not vaulting then
			local change = string.find(oneShotName, "To") ~= nil
			local toProne = string.find(oneShotName, "Prone") ~= nil
			if change and walkingNow and not toProne then
				oneShot:Stop(0.2)
				oneShot, oneShotName = nil, ""
				busyUntil = 0
			elseif oneShot.Length > 0 and oneShot.TimePosition > oneShot.Length - BLEND then
				oneShot:Stop(BLEND)
				oneShot, oneShotName = nil, ""
			end
		end

		-- turn in place past 45 deg: a foot shuffle (§3.11)
		local _, yaw = r.root.CFrame:ToOrientation()
		local dy = math.deg(yaw - lastYaw)
		dy = (dy + 180) % 360 - 180
		lastYaw = yaw
		if body == "Idle" and not oneShot then
			turnAcc += math.abs(dy)
			if turnAcc > 45 then
				turnAcc = 0
				play("TurnShuffle")
			end
		else
			turnAcc = 0
		end

		r.char:SetAttribute(
			"M2State",
			HttpService:JSONEncode({
				stance = stance,
				body = slots.body,
				hold = slots.hold,
				carry = {
					ready = math.floor(carry.ready * 100 + 0.5) / 100,
					hip = math.floor(carry.hip * 100 + 0.5) / 100,
					aim = math.floor(carry.aim * 100 + 0.5) / 100,
					shots = carry.shots,
					fired = carry.fired,
				},
				oneShot = oneShotName,
				last = lastPlay,
				speed = math.floor(speed * 10 + 0.5) / 10,
				walkSpeed = ws,
				lean = math.floor(leanA * 100 + 0.5) / 100,
				limp = limp,
				fp = firstPerson,
				state = st.Name,
				cam = { camOffset.X, camOffset.Y, camOffset.Z },
			})
		)
		label.Text = string.format(
			" WASD move · Shift sprint · C crouch · Z prone · Space jump/vault · Q/E lean · F/RMB aim · click fire · L limp · T camera\n %s %s | %s + %s %s | %.1f studs/s | limp %s | %s",
			stance,
			if sprinting then "(sprint)" else "",
			tostring(slots.body),
			tostring(slots.hold),
			if oneShotName ~= "" then "| " .. oneShotName else "",
			speed,
			({ "none", "one leg", "both legs" })[limp + 1],
			if firstPerson then "1P" else "3P"
		)
	end)

	-- after the Animator: lean, 1P gun lag (on the root joint: in 1P only the arms and rifle show, so the whole view
	-- model lags together; Transform isn't replicated)
	RunService.PreSimulation:Connect(function(dt)
		local r = rig
		if not r then
			return
		end
		-- the test hook's move, here: after the ControlModule's RenderStepped Move, before the simulation
		if hookMove then
			r.hum:Move(hookMove :: Vector3, false)
		end
		MoveTest.applyLean(r, leanA)
		-- live layer (the study's noise, left out of the baked loops): a slow trunk drift and a head glance when not
		-- aiming, so no two cycles look the same
		local calm = 1 - 0.65 * carry.aim
		local drift = CFrame.Angles(
			math.rad(1.2 * noise(life, 4.2) * calm),
			math.rad(2 * noise(life, 5.3) * calm),
			0
		)
		r.rootJoint.Transform = inJoint(C0.root, drift) * r.rootJoint.Transform
		if r.neck and stance ~= "prone" then
			local glance = (4 * noise(life, 8.8) + 1.5 * noise(life, 12.1)) * (1 - carry.aim)
			r.neck.Transform = r.neck.Transform * CFrame.Angles(0, 0, math.rad(glance))
		end
		-- recoil: a spring kicked by each shot; the rifle goes back into the shoulder and the muzzle climbs, the
		-- upper body rocks back a little with it
		carry.recV += (-2 * 0.5 * (2 * math.pi * 6) * carry.recV - (2 * math.pi * 6) ^ 2 * carry.rec) * dt
		carry.rec += carry.recV * dt
		carry.flash = math.max(0, carry.flash - dt)
		if math.abs(carry.rec) > 1e-4 then
			if r.gun then
				r.gun.Transform = r.gun.Transform
					* CFrame.new(0, 0.02 * carry.rec, 0.08 * carry.rec)
					* CFrame.Angles(math.rad(3 * carry.rec * (1 - 0.5 * carry.aim)), 0, 0)
			end
			r.rootJoint.Transform = inJoint(
				C0.root,
				CFrame.Angles(math.rad(-1.2 * carry.rec), 0, 0)
			) * r.rootJoint.Transform
		end
		local muzzle = r.char:FindFirstChild("BlockoutRifle") -- the test rifle has no Muzzle part (no flash yet)
		local flashPart = muzzle and muzzle:FindFirstChild("Muzzle")
		if flashPart and flashPart:IsA("BasePart") then
			flashPart.Color = if carry.flash > 0
				then Color3.fromRGB(255, 210, 122)
				else Color3.fromHex("2b2d2f")
			flashPart.Material = if carry.flash > 0
				then Enum.Material.Neon
				else Enum.Material.SmoothPlastic
		end
		local look = camera.CFrame.LookVector
		if firstPerson and lastLook then
			local _, y1 = CFrame.lookAt(Vector3.zero, look):ToOrientation()
			local p1, y0 = CFrame.lookAt(Vector3.zero, lastLook):ToOrientation()
			local x1 = math.asin(math.clamp(look.Y, -1, 1))
			local dyaw = ((math.deg(y1 - y0) + 180) % 360 - 180) / math.max(dt, 1e-3)
			local dpitch = math.deg(x1 - math.asin(math.clamp(lastLook.Y, -1, 1)))
				/ math.max(dt, 1e-3)
			local _ = p1
			local k = 1 - math.exp(-dt * 3 / LAG.settle)
			lagYaw += (math.clamp(-dyaw * 0.03, -LAG.max, LAG.max) - lagYaw) * k
			lagPitch += (math.clamp(-dpitch * 0.03, -LAG.max, LAG.max) - lagPitch) * k
			local eye = Vector3.new(0, 1.5, 0)
			local lag = CFrame.new(eye)
				* CFrame.Angles(math.rad(lagPitch), math.rad(lagYaw), 0)
				* CFrame.new(-eye)
			r.rootJoint.Transform = inJoint(C0.root, lag) * r.rootJoint.Transform
		else
			lagYaw, lagPitch = 0, 0
		end
		-- 1P stopgap until the viewmodel rules (guide §5.3): only the arms and rifle show, and the low carry sits
		-- below the view, so standing and crouched the whole (hidden) body rides up and forward to bring the rifle
		-- into the lower right of the screen. Prone and swimming the view already shows it.
		local want = if firstPerson
				and stance ~= "prone"
				and r.hum:GetState() ~= Enum.HumanoidStateType.Swimming
			then 1
			else 0
		vmBlend += (want - vmBlend) * (1 - math.exp(-dt * 12))
		if vmBlend > 1e-3 then
			r.rootJoint.Transform = inJoint(C0.root, CFrame.new(viewLift() * vmBlend))
				* r.rootJoint.Transform
		end
		lastLook = look
	end)

	-- camera: follows the head (stance changes, lean, vault) on a fast spring; in 1P a light bob instead of the
	-- cycle's own bob, the landing dip, and the lean roll (§4.1)
	RunService:BindToRenderStep("M2CameraOffset", Enum.RenderPriority.Camera.Value - 1, function(dt)
		local r = rig
		if not r then
			return
		end
		-- (minus the 1P view lift: the camera stays at the real eye while the shown arms ride up)
		local rel = r.root.CFrame:PointToObjectSpace(r.head.Position)
			- Vector3.new(0, 1.5, 0)
			- viewLift() * vmBlend
		local follow = oneShot ~= nil or vaulting or math.abs(leanA) > 0.01
		local base = stanceY[stance]
		local cycleBody = slots.body
		if
			not oneShot
			and (cycleBody == "Idle" or cycleBody == "CrouchIdle" or cycleBody == "ProneIdle")
		then
			stanceY[stance] += (rel.Y - stanceY[stance]) * (1 - math.exp(-dt * 2)) -- learn the stance's eye height
		end
		local y = if follow then rel.Y else base
		-- 1P bob: one dip per step (two per cycle)
		local bt = cycleBody and track(cycleBody)
		local amp = if cycleBody == "Sprint"
			then BOB.sprint
			elseif
				cycleBody == "Walk"
				or cycleBody == "CrouchWalk"
				or cycleBody == "LimpOne"
				or cycleBody == "LimpBoth"
			then BOB.walk
			else 0
		if bt and bt.Length > 0 and amp > 0 then
			bobPhase = bt.TimePosition / bt.Length
			y += -amp * 0.5 * (1 - math.cos(4 * math.pi * bobPhase))
		end
		if dip.len > 0 then
			local u = (os.clock() - dip.t0) / dip.len
			if u >= 1 then
				dip.len = 0
			else
				y -= dip.depth * math.sin(math.pi * u)
			end
		end
		local target = Vector3.new(rel.X, y, if firstPerson then rel.Z else 0)
		local k = 1 - math.exp(-dt * 25)
		camOffset = camOffset:Lerp(target, k)
		r.hum.CameraOffset = camOffset
	end)
	RunService:BindToRenderStep("M2CameraAfter", Enum.RenderPriority.Camera.Value + 2, function()
		local r = rig
		if not r then
			return
		end
		local fp = (camera.CFrame.Position - r.head.Position).Magnitude < 2.5
		if fp and math.abs(leanA) > 0.01 then
			camera.CFrame *= CFrame.Angles(0, 0, -math.rad(LEAN.roll) * leanA)
		end
		-- 1P: show the arms and the rifle (Roblox hides the whole body)
		if fp then
			for _, n in { "Left Arm", "Right Arm" } do
				local p = r.char:FindFirstChild(n)
				if p and p:IsA("BasePart") then
					p.LocalTransparencyModifier = 0
				end
			end
			local rifle = r.char:FindFirstChild("BlockoutRifle")
				or r.char:FindFirstChild("TestRifle")
			if rifle then
				for _, p in rifle:GetChildren() do
					if p:IsA("BasePart") then
						p.LocalTransparencyModifier = 0
					end
				end
			end
		end
	end)
end

return MoveTest
