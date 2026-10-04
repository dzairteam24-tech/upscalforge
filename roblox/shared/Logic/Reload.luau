--!strict
-- Reload (our rebirth): start World 1 again with a permanent coin multiplier and one more cartridge slot.
-- Kept: creatures, items, cartridges, upgrades, gems, cosmetics and the pass. Reset: coins, gates, zone progress.

local Config = script.Parent.Parent.Config
local Constants = require(Config.Constants)
local World1 = require(Config.World1)
local Gear = require(script.Parent.Gear)
local Types = require(script.Parent.Types)

type PlayerData = Types.PlayerData

export type Preview = {
	reloads: number, -- after reloading
	coinMult: number,
	cartridgeSlots: number,
}

local Reload = {}

-- Every Reload paints the world in a new palette (tint used by the client's ColorCorrection).
Reload.PALETTE = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 228, 214),
	Color3.fromRGB(214, 236, 255),
	Color3.fromRGB(232, 214, 255),
	Color3.fromRGB(214, 255, 224),
	Color3.fromRGB(255, 244, 196),
	Color3.fromRGB(255, 210, 236),
}

function Reload.coinMult(reloads: number): number
	return Constants.RELOAD_COIN_MULT ^ reloads
end

function Reload.tint(reloads: number): Color3
	return Reload.PALETTE[(reloads % #Reload.PALETTE) + 1]
end

function Reload.requiredZoneName(): string
	local zone = World1.zonesById[Constants.RELOAD_REQUIRED_ZONE]
	return if zone then zone.name else ("Zone " .. Constants.RELOAD_REQUIRED_ZONE)
end

function Reload.canReload(data: PlayerData): (boolean, string?)
	if not data.unlockedZones[tostring(Constants.RELOAD_REQUIRED_ZONE)] then
		return false, "Unlock " .. Reload.requiredZoneName() .. " to Reload"
	end
	return true, nil
end

function Reload.preview(data: PlayerData): Preview
	local reloads = data.reloads + 1
	return {
		reloads = reloads,
		coinMult = Reload.coinMult(reloads),
		cartridgeSlots = Gear.slots(reloads),
	}
end

-- Resets the run. Call `canReload` first.
function Reload.apply(data: PlayerData)
	data.reloads += 1
	data.coins = 0
	data.unlockedZones = { ["0"] = true, ["1"] = true }
	data.zoneProgress = {}
	data.stats.reloads = data.reloads
end

return Reload
