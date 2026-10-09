--!strict
-- Character cosmetics: titles above the head and trails behind the player. Look only, no power.

local SeatLooks = require(script.Parent.SeatLooks)

export type Title = { id: string, text: string, color: Color3 }
export type Trail = { id: string, name: string, colors: { Color3 } }
-- Rides: something the character stands on. Every ride gives the same speed, so they're look only.
-- The "seat" style is a floating seat the player sits on cross-legged (SeatModel; `seat` names its model in
-- art/models/Seats.glb, SeatLooks). Three per zone. The meadow's Cloud Seat is everyone's from the start and
-- can't be traded; the others come from the Battle Pass (SEAT_PASS) or as gifts (`gift`: the daily reward's
-- mystery seat) and can be traded.
export type Ride = {
	id: string,
	name: string,
	style: string,
	color: Color3,
	glow: Color3,
	seat: string?,
	tradeable: boolean?,
	gift: boolean?,
}
-- Auras: particles around the character that everyone sees. Hatch effects: how your own hatch screen
-- celebrates. Both are sold for Robux and give no power at all.
export type Aura = { id: string, name: string, style: string, colors: { Color3 } }
export type HatchFx = { id: string, name: string, style: string, colors: { Color3 } }

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
	-- Journey
	{ id = "J_Hero", text = "Valley Hero", color = Color3.fromRGB(120, 230, 160) },
	-- Fishing
	{ id = "F_Angler", text = "Angler", color = Color3.fromRGB(91, 184, 245) },
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

local rides: { Ride } = {} -- the floating seats, below

local auras: { Aura } = {
	{ id = "Sparkle", name = "Sparkle Aura", style = "sparkle", colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 255, 255) } },
	{ id = "Frost", name = "Frost Aura", style = "sparkle", colors = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(230, 250, 255) } },
	{ id = "Flame", name = "Flame Aura", style = "flame", colors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 30) } },
	{ id = "Toxic", name = "Toxic Aura", style = "flame", colors = { Color3.fromRGB(150, 255, 90), Color3.fromRGB(30, 140, 60) } },
	{ id = "Pixel", name = "Pixel Aura", style = "cubes", colors = { Color3.fromRGB(185, 140, 255), Color3.fromRGB(255, 90, 200) } },
	{ id = "Galaxy", name = "Galaxy Aura", style = "ring", colors = { Color3.fromRGB(120, 90, 255), Color3.fromRGB(80, 220, 255) } },
}

local hatchFx: { HatchFx } = {
	{ id = "Confetti", name = "Confetti Hatch", style = "confetti", colors = { Color3.fromRGB(255, 107, 107), Color3.fromRGB(255, 217, 61), Color3.fromRGB(77, 150, 255), Color3.fromRGB(107, 203, 119) } },
	{ id = "Gold", name = "Golden Hatch", style = "rays", colors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(255, 245, 200) } },
	{ id = "Pixel", name = "Pixel Hatch", style = "confetti", colors = { Color3.fromRGB(185, 140, 255), Color3.fromRGB(255, 90, 200), Color3.fromRGB(80, 220, 255) } },
	{ id = "Galaxy", name = "Galaxy Hatch", style = "rays", colors = { Color3.fromRGB(120, 90, 255), Color3.fromRGB(80, 220, 255) } },
}

local titleById: { [string]: Title } = {}
for _, title in titles do
	titleById[title.id] = title
end
local trailById: { [string]: Trail } = {}
for _, trail in trails do
	trailById[trail.id] = trail
end
-- The floating seats, from their models' looks (zone order). Season 1's Battle Pass gives these (one every 5
-- premium levels, Progression); every other seat but the Cloud is a gift.
local SEAT_FREE = "Cloud"
local SEAT_PASS = { "Blossom", "Stump", "Shell", "RedShroom", "Cactus", "Snowman", "Lava", "Ice", "Cube", "Dragon" }
local inPass: { [string]: boolean } = {}
for _, name in SEAT_PASS do
	inPass[name] = true
end
for _, look in SeatLooks do
	table.insert(rides, {
		id = "Seat_" .. look.name,
		name = look.title,
		style = "seat",
		seat = look.name,
		color = look.colors[look.model.ref] or Color3.new(1, 1, 1),
		glow = look.light,
		tradeable = look.name ~= SEAT_FREE,
		gift = look.name ~= SEAT_FREE and not inPass[look.name],
	})
end

local rideById: { [string]: Ride } = {}
for _, ride in rides do
	rideById[ride.id] = ride
end

local auraById: { [string]: Aura } = {}
for _, aura in auras do
	auraById[aura.id] = aura
end
local hatchFxById: { [string]: HatchFx } = {}
for _, fx in hatchFx do
	hatchFxById[fx.id] = fx
end

return {
	titles = titles,
	trails = trails,
	titleById = titleById,
	trailById = trailById,
	rides = rides,
	rideById = rideById,
	auras = auras,
	auraById = auraById,
	hatchFx = hatchFx,
	hatchFxById = hatchFxById,
	RIDE_SPEED = 1.6,
	SEAT_HIP = 2.6, -- the rider's HipHeight on a floating seat, roughly (RideClient sets the exact one)
	RIDE_DEFAULT = "Seat_Cloud", -- what the Ride button puts you on
	RIDE_STARTERS = { "Seat_Cloud" }, -- every player has these
}
