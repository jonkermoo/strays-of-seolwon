--!strict
-- M1 style test: Grey Front light and weather presets (STYLE-BIBLE.md §9 in jarvis), applied to
-- Lighting. Starting values, tuned in the test scene; write the tuned numbers back to the bible.
-- Sightlines use classic distance fog, not Atmosphere: Atmosphere is dropped at low graphics
-- quality (and in an unfocused Studio window), and sight distance is gameplay, so it must hold on
-- every device (M1 finding 2026-11-20). The atmo values stay for a later look pass.
-- Works in Edit mode (screenshots) and at run time (the StyleToggle client panel).
local Lighting = game:GetService("Lighting")

export type Preset = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	atmo: {
		density: number,
		offset: number,
		color: Color3,
		decay: Color3,
		haze: number,
		glare: number,
	},
	cc: { saturation: number, contrast: number, brightness: number, tint: Color3 },
	exposure: number,
	weather: string?, -- "rain" | "snow" | "blizzard"
	nvg: boolean?,
	fog: { start: number, finish: number, color: Color3 },
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local Light = {}

Light.Order = { "Day", "Dusk", "Fog", "Rain", "Snow", "NightMoon", "NightDark", "NVG", "Blizzard" }

Light.Presets = {
	Day = {
		fog = { start = 40, finish = 250, color = hex("#a5abad") },
		clock = 11,
		brightness = 1.6,
		ambient = hex("#4a4f53"),
		outdoor = hex("#80878b"),
		atmo = {
			density = 0.42,
			offset = 0.1,
			color = hex("#a5abad"),
			decay = hex("#6d7377"),
			haze = 2.2,
			glare = 0,
		},
		cc = { saturation = -0.35, contrast = 0.08, brightness = 0, tint = hex("#eef1f2") },
		exposure = 0,
	},
	Dusk = {
		fog = { start = 30, finish = 180, color = hex("#6f7178") },
		clock = 17.7,
		brightness = 0.6,
		ambient = hex("#3a3d44"),
		outdoor = hex("#5a5f6b"),
		atmo = {
			density = 0.45,
			offset = 0.1,
			color = hex("#8d8f99"),
			decay = hex("#5a4e4a"),
			haze = 2.0,
			glare = 0.2,
		},
		cc = { saturation = -0.5, contrast = 0.1, brightness = 0, tint = hex("#f2ece6") },
		exposure = 0,
	},
	Fog = {
		fog = { start = 10, finish = 120, color = hex("#b0b5b6") },
		clock = 9,
		brightness = 1.2,
		ambient = hex("#4a4f53"),
		outdoor = hex("#7a8185"),
		atmo = {
			density = 0.62,
			offset = 0,
			color = hex("#b0b5b6"),
			decay = hex("#8a9093"),
			haze = 3.0,
			glare = 0,
		},
		cc = { saturation = -0.45, contrast = 0.04, brightness = 0, tint = hex("#ffffff") },
		exposure = 0,
	},
	Rain = {
		fog = { start = 25, finish = 180, color = hex("#8d9395") },
		clock = 12,
		brightness = 1.1,
		ambient = hex("#43484c"),
		outdoor = hex("#6f767a"),
		atmo = {
			density = 0.52,
			offset = 0.05,
			color = hex("#9aa0a2"),
			decay = hex("#5f6569"),
			haze = 2.6,
			glare = 0,
		},
		cc = { saturation = -0.4, contrast = 0.06, brightness = 0, tint = hex("#ffffff") },
		exposure = 0,
		weather = "rain",
	},
	Snow = {
		fog = { start = 30, finish = 200, color = hex("#c3cad0") },
		clock = 12,
		brightness = 1.5,
		ambient = hex("#525860"),
		outdoor = hex("#8a9198"),
		atmo = {
			density = 0.48,
			offset = 0.05,
			color = hex("#c3cad0"),
			decay = hex("#8d969e"),
			haze = 2.0,
			glare = 0,
		},
		cc = { saturation = -0.4, contrast = 0.04, brightness = 0, tint = hex("#f1f5ff") },
		exposure = 0,
		weather = "snow",
	},
	NightMoon = {
		fog = { start = 8, finish = 70, color = hex("#1b212b") },
		clock = 0,
		brightness = 0.6,
		ambient = hex("#262e3a"),
		outdoor = hex("#55627a"),
		atmo = {
			density = 0.4,
			offset = 0,
			color = hex("#1a2027"),
			decay = hex("#0a0c10"),
			haze = 1.0,
			glare = 0,
		},
		cc = { saturation = -0.6, contrast = 0.05, brightness = 0, tint = hex("#cdd8ff") },
		exposure = 1.1,
	},
	NightDark = {
		fog = { start = 2, finish = 22, color = hex("#07080a") },
		clock = 0,
		brightness = 0,
		ambient = hex("#06070a"),
		outdoor = hex("#0b0d10"),
		atmo = {
			density = 0.45,
			offset = 0,
			color = hex("#0b0d10"),
			decay = hex("#050607"),
			haze = 1.0,
			glare = 0,
		},
		cc = { saturation = -0.7, contrast = 0.05, brightness = 0, tint = hex("#ffffff") },
		exposure = 0,
	},
	NVG = { -- over a moonless night: green phosphor, grain and dual-tube vignette (the overlay is client UI)
		fog = { start = 20, finish = 150, color = hex("#1c2a1f") },
		clock = 0,
		brightness = 0.8,
		ambient = hex("#4a524c"),
		outdoor = hex("#8a948c"),
		atmo = {
			density = 0.3,
			offset = 0,
			color = hex("#0b0d10"),
			decay = hex("#050607"),
			haze = 0.5,
			glare = 0,
		},
		cc = { saturation = -1, contrast = 0.2, brightness = 0.12, tint = hex("#9dffaa") },
		exposure = 2.2,
		nvg = true,
	},
	Blizzard = {
		fog = { start = 5, finish = 120, color = hex("#c9d2d8") },
		clock = 12,
		brightness = 1.3,
		ambient = hex("#5a6168"),
		outdoor = hex("#949ba2"),
		atmo = {
			density = 0.66,
			offset = 0,
			color = hex("#c9d2d8"),
			decay = hex("#a3acb3"),
			haze = 1.6,
			glare = 0,
		},
		cc = { saturation = -0.45, contrast = 0, brightness = 0, tint = hex("#ffffff") },
		exposure = 0,
		weather = "blizzard",
	},
} :: { [string]: Preset }

local function child(className: string, name: string): any
	local found = Lighting:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	if found then
		found:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

-- Weather particles live on a large invisible part that follows a focus point (the camera at run
-- time, the shot position in Edit mode).
local WEATHER = {
	rain = {
		rate = 900,
		speed = NumberRange.new(70, 90),
		size = 0.08,
		length = 2.2,
		color = hex("#c6ccd0"),
		alpha = 0.55,
		drift = Vector3.new(4, 0, 2),
	},
	snow = {
		rate = 260,
		speed = NumberRange.new(5, 8),
		size = 0.18,
		length = 0,
		color = hex("#eef2f6"),
		alpha = 0.2,
		drift = Vector3.new(2, 0, 1),
	},
	blizzard = {
		rate = 1400,
		speed = NumberRange.new(18, 26),
		size = 0.22,
		length = 0,
		color = hex("#f2f5f8"),
		alpha = 0.1,
		drift = Vector3.new(30, 0, 8),
	},
}

function Light.weather(kind: string?, focus: Vector3, parent: Instance)
	local old = parent:FindFirstChild("StyleWeather")
	if old then
		old:Destroy()
	end
	if not kind then
		return
	end
	local w = WEATHER[kind]
	local p = Instance.new("Part")
	p.Name = "StyleWeather"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(160, 1, 160)
	p.CFrame = CFrame.new(focus + Vector3.new(0, 40, 0))
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = w.rate
	e.Lifetime = NumberRange.new(2.5, 3.5)
	e.Speed = w.speed
	e.Acceleration = w.drift
	e.SpreadAngle = Vector2.new(6, 6)
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Color = ColorSequence.new(w.color)
	e.Transparency = NumberSequence.new(w.alpha)
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	if w.length > 0 then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Size = NumberSequence.new(w.size)
		e.Squash = NumberSequence.new(-w.length * 3)
	else
		e.Size = NumberSequence.new(w.size)
	end
	e.Parent = p
	p.Parent = parent
end

function Light.apply(name: string)
	local pr = Light.Presets[name]
	assert(pr, "no preset " .. name)
	Lighting.ClockTime = pr.clock
	Lighting.Brightness = pr.brightness
	Lighting.Ambient = pr.ambient
	Lighting.OutdoorAmbient = pr.outdoor
	Lighting.ExposureCompensation = pr.exposure
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.2
	for _, other in Lighting:GetChildren() do -- fog only works without an Atmosphere
		if other:IsA("Atmosphere") then
			other:Destroy()
		end
	end
	Lighting.FogStart = pr.fog.start
	Lighting.FogEnd = pr.fog.finish
	Lighting.FogColor = pr.fog.color
	-- classic fog doesn't reach the skybox: a full cloud deck in the fog colour closes the sky
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover, clouds.Density, clouds.Color = 1, 1, pr.fog.color
	clouds.Parent = workspace.Terrain
	local cc = child("ColorCorrectionEffect", "StyleGrade")
	cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor =
		pr.cc.saturation, pr.cc.contrast, pr.cc.brightness, pr.cc.tint
	local bloom = child("BloomEffect", "StyleBloom")
	bloom.Intensity, bloom.Threshold, bloom.Size =
		if pr.nvg then 0.8 else 0.25, if pr.nvg then 1.0 else 1.6, 24
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.CelestialBodiesShown = name == "Day" or name == "Dusk"
	end
	return pr
end

return Light
