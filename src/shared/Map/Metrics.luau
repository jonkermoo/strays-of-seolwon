--!strict
-- Player metrics: every block is built to these (studs). Change the design sheet first.

return table.freeze({
	Player = table.freeze({ height = 5, walk = 16, sprint = 20, stepUp = 2, vault = 3 }),
	Cover = table.freeze({ prone = 1.5, crouch = 3.5, standing = 6, windowSill = 3.5 }),
	Door = table.freeze({
		width = 4,
		height = 7.5,
		double = 8,
		garageWidth = 14,
		garageHeight = 10,
	}),
	Window = table.freeze({ size = 3, sill = 3.5 }),
	Building = table.freeze({ storey = 10, wall = 1, bunkerWall = 2, corridor = 6 }),
	Stairs = table.freeze({ angle = 35, riser = 1, tread = 1.4, publicWidth = 8, houseWidth = 5 }),
	Road = table.freeze({ track = 10, road = 20, artery = 28, tunnelWidth = 24, tunnelHeight = 16 }),
	Vehicle = table.freeze({ maxSlope = 30, garageBay = { 14, 24 } }),
	-- Greybox heights
	LandTop = 4, -- land surface above sea level (Y)
	SeaLevel = 0,
})
