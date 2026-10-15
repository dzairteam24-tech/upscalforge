--!strict
-- The first minutes: a few short hints, one at a time, each when it matters. How far it got is saved, so a
-- player who comes back isn't told again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.UI.Ui)

local Guide = {}

local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- the hints, in order, and when each is done
local STEPS = {
	{ text = "RUN! Grab the glowing orbs: each one makes you faster, for good.", done = function(d: any) return d.stats.orbs >= 8 end },
	{ text = if touch then "Dodge the obstacles. Tap JUMP to leap over the red lasers." else "Dodge the obstacles. Press SPACE to leap over the red lasers.", done = function(d: any) return d.stats.orbs >= 25 end },
	{ text = "At the end, a wall of cubes. Fast enough? Run right through it!", done = function(d: any) return d.stats.smashes >= 1 end },
	{ text = "Spend coins on UPGRADES: more speed from every orb.", done = function(d: any) return (d.upgrades.orb or 0) >= 1 end },
}

function Guide.init(screen: ScreenGui)
	local box = Ui.panel(screen, UDim2.fromOffset(560, 54), UDim2.new(0.5, -280, 1, -150), Ui.cyan)
	box.Visible = false
	local label = Ui.label(box, "", UDim2.new(1, -28, 1, -18), UDim2.fromOffset(14, 9), Ui.text, Ui.heavy)
	label.TextWrapped = true
	local step = -1
	Store.onChanged(function()
		local data = Store.data
		local at = data.guide
		while at < #STEPS and STEPS[at + 1].done(data) do
			at += 1
		end
		if at ~= data.guide then
			Net.event("GuideDone"):FireServer(at)
			data.guide = at
		end
		if at ~= step then
			step = at
			if at >= #STEPS then
				box.Visible = false
			else
				label.Text = STEPS[at + 1].text
				box.Visible = true
				box.Position = UDim2.new(0.5, -280, 1, -130)
				TweenService:Create(box, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, -280, 1, -150) }):Play()
			end
		end
	end)
end

return Guide
