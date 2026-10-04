-- Sound effects and music on the client. Events: coin breaks, jackpots, hatches, notifications and
-- button clicks. Turned off with the Sound effects / Music settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)

local SoundClient = {}

local folder = Instance.new("Folder")
folder.Name = "CubelingsSounds"
local templates: { [string]: Sound } = {}
local music: Sound? = nil
local coinTimes: { number } = {}

local function enabled(key: string): boolean
	local data = Store.data
	return data == nil or data.settings[key] ~= false
end

function SoundClient.play(name: string)
	if not enabled("sfx") then
		return
	end
	local template = templates[name]
	if not template then
		return
	end
	if name == "Coin" then
		-- Cap coin sounds so big combos don't turn into noise
		local now = os.clock()
		while coinTimes[1] and now - coinTimes[1] > 1 do
			table.remove(coinTimes, 1)
		end
		if #coinTimes >= Sounds.COIN_SOUNDS_PER_SECOND then
			return
		end
		table.insert(coinTimes, now)
	end
	SoundService:PlayLocalSound(template)
end

local function updateMusic()
	if music then
		local on = enabled("music")
		if on and not music.IsPlaying then
			music:Play()
		elseif not on and music.IsPlaying then
			music:Stop()
		end
	end
end

function SoundClient.init()
	folder.Parent = SoundService
	for name, def in Sounds.effects do
		if def.id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = def.id
			sound.Volume = def.volume
			sound.PlaybackSpeed = def.speed or 1
			sound.Parent = folder
			templates[name] = sound
		end
	end
	if Sounds.MUSIC ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "Music"
		sound.SoundId = Sounds.MUSIC
		sound.Volume = Sounds.MUSIC_VOLUME
		sound.Looped = true
		sound.Parent = folder
		music = sound
	end
	Store.DataChanged:Connect(updateMusic)
	updateMusic()

	Net.event("BreakFx").OnClientEvent:Connect(function(_position, _coins, jackpot: boolean, golden: boolean)
		SoundClient.play(if jackpot or golden then "Jackpot" else "Coin")
	end)
	Net.event("HatchResult").OnClientEvent:Connect(function()
		SoundClient.play("Hatch")
	end)
	Net.event("Notify").OnClientEvent:Connect(function(_text: string, kind: string)
		if kind == "rare" then
			SoundClient.play("Rare")
		elseif kind == "error" then
			SoundClient.play("Error")
		elseif kind == "success" then
			SoundClient.play("Success")
		end
	end)
	Net.event("WheelResult").OnClientEvent:Connect(function()
		for i = 0, 10 do
			task.delay(i * i * 0.035, SoundClient.play, "Spin")
		end
	end)
end

return SoundClient
