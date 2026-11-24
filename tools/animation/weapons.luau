--!strict
-- Held items for tools/animation/build.luau (M2 style test). Modelled gun space: origin at the right hand's grip,
-- -Z toward the muzzle, +Y up, studs at game size. M5 moves this into Config/Weapons.
-- blockout: the block-out rifle (src/shared/StyleTest/Blockout.luau builds the same shape), H2 size as the M1 scene's
-- H2 model (3.4 studs long: muzzle z -2.3, butt z +1.1).
return {
	blockout = {
		grip = { 0, 0, 0 },
		scale = { 1, 1, 1 },
		attachments = {
			Aim = { 0, 0.36, 0.5 }, -- the eye on the sight line
		},
		shouldered = { 0.4, 1.45, -0.6 },
	},
	-- test_rifle: the rigged test rifle (assets/TestRifle.rbxm, 1 stud = 0.28 m, 3.3 studs long: muzzle z -2.06, butt
	-- z +1.26 with the stock out). Origin on the top of the pistol grip (rifle space -112, 0, 22 mm), as blockout's.
	-- Points measured by rays on the model (jarvis rifle_import/rig/test_rifle.gun.json): Aim is the eye on the iron
	-- sights' line; RightHand the middle of the pistol grip; LeftHand the handguard underside, 3/4 of the way forward.
	-- The holds are still keyed with blockout's hand points (rifle.luau HANDS), not these.
	test_rifle = {
		grip = { 0, 0, 0 },
		scale = { 1, 1, 1 },
		attachments = {
			Aim = { 0, 0.3781, 0.3252 },
			RightHand = { 0, -0.2571, 0.1464 },
			LeftHand = { 0, 0, -1.2393 },
		},
	},
}
