--!strict
-- Graphics quality profiles (client only, cosmetic). "Low" is the default on phones and
-- tablets (Settings "Auto"); players can switch in the Settings window.

export type Profile = {
	name: string,
	props: number, -- trees/rocks/etc. scattered around the arena
	mountains: number, -- distant mountains or dunes
	particleRate: number, -- multiplier on the ambient area particles (snow, fireflies...)
	shadows: boolean, -- Lighting.GlobalShadows
	unitScale: number, -- multiplier on how many troop models are shown per type
	debris: number, -- multiplier on pieces flying off defeated enemies (0 = none)
	trails: boolean, -- glowing trails behind arrows
	damageNumbers: number, -- max floating damage numbers at once
}

local GraphicsConfig = {
	PROFILES = {
		High = {
			name = "High",
			props = 110,
			mountains = 14,
			particleRate = 1,
			shadows = true,
			unitScale = 1,
			debris = 1,
			trails = true,
			damageNumbers = 12,
		},
		Low = {
			name = "Low",
			props = 35,
			mountains = 8,
			particleRate = 0.35,
			shadows = false,
			unitScale = 0.5,
			debris = 0,
			trails = false,
			damageNumbers = 6,
		},
	} :: { [string]: Profile },
}

return table.freeze(GraphicsConfig)
