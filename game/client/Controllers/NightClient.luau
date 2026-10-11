--!strict
-- Night (Logic/Night) on this screen: the sky darkens while it lasts (eggs grow faster then), and lights up again.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Night = require(Shared.Logic.Night)

local NightClient = {}

local DAY, DARK = 14, 0 -- (Lighting.ClockTime)
local FADE = TweenInfo.new(2, Enum.EasingStyle.Sine)

function NightClient.init()
	task.spawn(function()
		local night: boolean? = nil
		while true do
			local now = Night.isNight(workspace:GetServerTimeNow())
			if now ~= night then
				night = now
				TweenService:Create(Lighting, FADE, { ClockTime = if now then DARK else DAY }):Play()
			end
			task.wait(0.25)
		end
	end)
end

return NightClient
