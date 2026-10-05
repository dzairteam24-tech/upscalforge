--!strict
-- Character cosmetics: titles above the head and trails behind the player. Look only, no power.

export type Title = { id: string, text: string, color: Color3 }
export type Trail = { id: string, name: string, colors: { Color3 } }
-- Rides: something the character stands on. Every ride gives the same speed, so they're look only.
export type Ride = { id: string, name: string, style: string, color: Color3, glow: Color3 }

local titles: { Title } = {
	{ id = "VIP", text = "VIP", color = Color3.fromRGB(255, 215, 90) },
	{ id = "Supporter", text = "Supporter", color = Color3.fromRGB(255, 215, 90) },
	{ id = "S1_Rookie", text = "Cube Rookie", color = Color3.fromRGB(150, 220, 255) },
	{ id = "S1_Collector", text = "Collector", color = Color3.fromRGB(120, 230, 160) },
	{ id = "S1_Hunter", text = "Big Hunter", color = Color3.fromRGB(240, 138, 45) },
	{ id = "S1_Tamer", text = "Titan Tamer", color = Color3.fromRGB(255, 120, 200) },
	{ id = "S1_Pixel", text = "Pixel Legend", color = Color3.fromRGB(185, 140, 255) },
	{ id = "S1_Champion", text = "Season 1 Champion", color = Color3.fromRGB(255, 200, 60) },
	-- Achievements
	{ id = "A_EggMaster", text = "Egg Master", color = Color3.fromRGB(255, 240, 200) },
	{ id = "A_Rich", text = "Billionaire", color = Color3.fromRGB(245, 197, 66) },
	{ id = "A_PixelHunter", text = "Pixel Hunter", color = Color3.fromRGB(185, 140, 255) },
	{ id = "A_Whisperer", text = "Titan Whisperer", color = Color3.fromRGB(255, 120, 200) },
	{ id = "A_Reloaded", text = "Reloaded", color = Color3.fromRGB(140, 120, 240) },
	{ id = "A_Loyal", text = "Loyal", color = Color3.fromRGB(120, 230, 160) },
	{ id = "A_Collector", text = "Master Collector", color = Color3.fromRGB(80, 220, 255) },
	-- Events
	{ id = "E_Spooky", text = "Spooky", color = Color3.fromRGB(255, 140, 40) },
	{ id = "E_Frosty", text = "Frosty", color = Color3.fromRGB(150, 220, 255) },
	-- Clans
	{ id = "C_TopClan", text = "Top Clan", color = Color3.fromRGB(255, 200, 90) },
	-- Rank
	{ id = "R_Explorer", text = "Explorer", color = Color3.fromRGB(150, 220, 255) },
	{ id = "R_Veteran", text = "Veteran", color = Color3.fromRGB(255, 170, 90) },
	{ id = "R_Legend", text = "Cube Legend", color = Color3.fromRGB(255, 215, 90) },
}

local trails: { Trail } = {
	{ id = "S1_Sky", name = "Sky Trail", colors = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255) } },
	{ id = "S1_Lava", name = "Lava Trail", colors = { Color3.fromRGB(255, 120, 30), Color3.fromRGB(255, 220, 80) } },
	{ id = "S1_Neon", name = "Neon Trail", colors = { Color3.fromRGB(43, 245, 154), Color3.fromRGB(20, 120, 80) } },
	{ id = "S1_Pixel", name = "Pixel Trail", colors = { Color3.fromRGB(142, 91, 217), Color3.fromRGB(255, 90, 200) } },
	{ id = "E_Pumpkin", name = "Pumpkin Trail", colors = { Color3.fromRGB(255, 140, 40), Color3.fromRGB(90, 40, 120) } },
	{ id = "E_Snow", name = "Snow Trail", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 220, 255) } },
	{
		id = "S1_Rainbow",
		name = "Rainbow Trail",
		colors = {
			Color3.fromRGB(255, 107, 107),
			Color3.fromRGB(255, 217, 61),
			Color3.fromRGB(107, 203, 119),
			Color3.fromRGB(77, 150, 255),
			Color3.fromRGB(199, 125, 255),
		},
	},
}

local rides: { Ride } = {
	{ id = "Skateboard", name = "Skateboard", style = "board", color = Color3.fromRGB(229, 83, 75), glow = Color3.fromRGB(255, 220, 120) },
	{ id = "S1_Hoverboard", name = "Hoverboard", style = "board", color = Color3.fromRGB(60, 70, 100), glow = Color3.fromRGB(91, 184, 245) },
	{ id = "PixelBoard", name = "Pixel Board", style = "board", color = Color3.fromRGB(40, 30, 60), glow = Color3.fromRGB(185, 140, 255) },
	{ id = "S1_Cloud", name = "Cloud", style = "cloud", color = Color3.fromRGB(245, 248, 255), glow = Color3.fromRGB(200, 230, 255) },
	{ id = "E_Broom", name = "Broom Board", style = "board", color = Color3.fromRGB(90, 60, 40), glow = Color3.fromRGB(255, 140, 40) },
	{ id = "E_Sled", name = "Snow Sled", style = "board", color = Color3.fromRGB(200, 60, 60), glow = Color3.fromRGB(150, 220, 255) },
}

local titleById: { [string]: Title } = {}
for _, title in titles do
	titleById[title.id] = title
end
local trailById: { [string]: Trail } = {}
for _, trail in trails do
	trailById[trail.id] = trail
end
local rideById: { [string]: Ride } = {}
for _, ride in rides do
	rideById[ride.id] = ride
end

return {
	titles = titles,
	trails = trails,
	titleById = titleById,
	trailById = trailById,
	rides = rides,
	rideById = rideById,
	RIDE_SPEED = 1.25,
}
