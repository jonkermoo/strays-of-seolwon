--!strict
-- M2 movement test (style-test branch only; M6 builds the real Locomotion). Plays the movement clips
-- (ReplicatedStorage.Animations, built by tools/animation/build.luau) on the player's Strays rifleman with the
-- block-out rifle, to the approved ANIMATION-GUIDE.md §2-4 (jarvis, 2026-11-22):
--   WASD walk 12 · Shift sprint 20 · C crouch 7 · Z prone, crawl 3 · Space jump (low hop) / vault / mantle
--   Q / E lean (live, any cycle) · L limp: none / one leg 8 / both legs 5 · T first / third person
-- The clips aren't uploaded: KeyframeSequenceProvider:RegisterKeyframeSequence (works in Studio only).
-- Test hooks (Studio MCP, no key mapping): player attribute "M2Cmd" = "crouch" | "prone" | "jump" | "limp" | "camera"
-- | "sprintOn" | "sprintOff" | "leanL" | "leanR" | "leanOff"; "M2Move" (Vector3, world) moves like the stick.
-- Each frame the character carries "M2State" (JSON: stance, speed, clips, camera offset) for checks by numbers.
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MoveTest = {}

local player = Players.LocalPlayer

-- ANIMATION-GUIDE §2 speeds (studs/s)
local SPEED = { walk = 12, sprint = 20, crouch = 7, prone = 3, lean = 7, limp1 = 8, limp2 = 5 }
-- each body loop's speed at its keyed length (the playback rate scales with the real speed)
local NOMINAL =
	{ Walk = 12, Sprint = 20, CrouchWalk = 7, Crawl = 3, LimpOne = 8, LimpBoth = 5, Swim = 12 }
local SPRINT_CONE = math.cos(math.rad(50)) -- sprint only within 50 deg of the camera look
local BLEND = 0.13 -- §3.11 0.12-0.15
local LEAN = { tilt = 20, inTime = 0.15, outTime = 0.12, roll = 8 } -- §3.8 (+ 1P camera roll, approved proposal)
local BOB = { walk = 0.03, sprint = 0.08 } -- §4.1 1P camera bob
local LAG = { max = 3, settle = 0.15 } -- §4.1 1P gun turn lag (deg, s)
local VAULT = { hop = 3.5, mantle = 5.5, reach = 2.2, hopTime = 0.45, mantleTime = 0.8 } -- §3.7
local LONG_FALL = 10 -- §3.6
local VIEW_LIFT = Vector3.new(0, 1.2, -0.8) -- 1P: the body rides up and forward (root space) so the rifle shows
local VIEW_LIFT_CROUCH = Vector3.new(0, 0.7, -0.8)
-- stance changes (§3.4 / §3.5): clip and seconds
local CHANGE = {
	stand_crouch = { "StandToCrouch", 0.2 },
	crouch_stand = { "CrouchToStand", 0.2 },
	stand_prone = { "StandToProne", 0.45 },
	prone_stand = { "ProneToStand", 0.55 },
	crouch_prone = { "CrouchToProne", 0.35 },
	prone_crouch = { "ProneToCrouch", 0.35 },
}
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
	local wasSprinting = false
	local sprintStopAt = 0
	local dip = { t0 = 0, len = 0, depth = 0 }
	local camOffset = Vector3.zero
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
		local old = slots[slot] and track(slots[slot] :: string)
		if old then
			old:Stop(fade or BLEND)
		end
		slots[slot] = name
		local new = name and track(name)
		if new then
			new:Play(fade or BLEND)
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
			play(change[1])
			busyUntil = os.clock() + change[2] * 0.6 -- the settle can be cut (approved proposal)
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
		if not top then
			return false
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
		local len = if hop then VAULT.hopTime else VAULT.mantleTime
		local topY = top.Position.Y
		-- the root's height over the top while crossing: standing height, or as low as a window allows
		local cross = math.min(3, math.max(1.8, headroom - 2.1))
		vaulting = true
		busyUntil = os.clock() + len
		r.Anchored = true
		play(if hop then "VaultHop" else "Mantle")
		local rot = p0 - p0.Position
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			local u = math.clamp((os.clock() - t0) / len, 0, 1)
			local pos: Vector3
			if hop then
				-- one arc over the wall, its top with the root 2.0 over the wall (the tucked legs clear it)
				local apex = topY + 2.0
				local mid = p0.Position:Lerp(land, 0.5)
				local c = Vector3.new(mid.X, 2 * apex - 0.5 * (p0.Position.Y + land.Y), mid.Z)
				pos = p0.Position:Lerp(c, u):Lerp(c:Lerp(land, u), u)
			else
				-- up first (0.08-0.55), then forward onto / through (0.55-0.75)
				local up = math.clamp((u - 0.08) / 0.47, 0, 1)
				local fwd = math.clamp((u - 0.5) / 0.25, 0, 1)
				up = up * up * (3 - 2 * up)
				fwd = fwd * fwd * (3 - 2 * fwd)
				local peak = if onto then land.Y else topY + cross
				local down = math.clamp((u - 0.75) / 0.25, 0, 1) -- through a window: drop to the landing at the end
				local y = p0.Position.Y
					+ (peak - p0.Position.Y) * up
					+ (land.Y - peak) * down * down
				local xz = p0.Position:Lerp(land, fwd * 0.999)
				pos = Vector3.new(xz.X, y, xz.Z)
			end
			r.CFrame = rot + pos
			if u >= 1 then
				conn:Disconnect()
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
			if not rig or vaulting or os.clock() < busyUntil then
				return
			end
			if stance == "crouch" then
				setStance("stand")
			elseif stance == "prone" then
				setStance("crouch")
			elseif not tryVault() then
				local st = rig.hum:GetState()
				if
					st ~= Enum.HumanoidStateType.Freefall
					and st ~= Enum.HumanoidStateType.Jumping
				then
					rig.hum.Jump = true
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
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local k = input.KeyCode
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
				play(if long then "LandLong" else "LandShort")
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
		local sprinting = sprintHeld
			and moving
			and forward
			and limp == 0
			and not air
			and not swimming
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

		-- loops
		local body, hold
		local walkingNow = moving and speed > 0.5
		if swimming then
			body, hold = if walkingNow then "Swim" else "Tread", nil
		elseif air then
			body, hold = "Fall", "HoldIdle"
		elseif stance == "prone" then
			body, hold =
				if walkingNow then "Crawl" else "ProneIdle",
				if walkingNow then "HoldCrawl" else "HoldProne"
		elseif stance == "crouch" then
			body, hold =
				if walkingNow then "CrouchWalk" else "CrouchIdle",
				if walkingNow then "HoldCrouchWalk" else "HoldCrouch"
		elseif walkingNow then
			if sprinting then
				body, hold = "Sprint", "HoldSprint"
			else
				body = if limp == 1 then "LimpOne" elseif limp == 2 then "LimpBoth" else "Walk"
				hold = "HoldWalk"
			end
		else
			body, hold = "Idle", "HoldIdle"
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
		setSlot("hold", hold)
		-- playback rate follows the real speed; moving holds stay in phase with the body
		local bt = slots.body and track(slots.body :: string)
		if bt and NOMINAL[slots.body :: string] then
			bt:AdjustSpeed(math.clamp(speed / NOMINAL[slots.body :: string], 0.4, 1.6))
		end
		local ht = slots.hold and track(slots.hold :: string)
		if bt and ht and bt.Length > 0 and ht.Length > 0 and bt.Looped and ht.Looped then
			ht.TimePosition = (bt.TimePosition / bt.Length) * ht.Length
		end
		if oneShot and not oneShot.IsPlaying then
			oneShot, oneShotName = nil, ""
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
			" WASD move · Shift sprint · C crouch · Z prone · Space jump/vault · Q/E lean · L limp · T camera\n %s %s | %s + %s %s | %.1f studs/s | limp %s | %s",
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
