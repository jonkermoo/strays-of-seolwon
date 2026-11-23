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
}
