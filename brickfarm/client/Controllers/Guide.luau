--!strict
-- The first minutes: one short hint at a time, each when it matters. How far it got is saved, so a farmer who
-- comes back isn't told again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Land = require(Shared.Logic.Land)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Ui = require(script.Parent.Parent.UI.Ui)

local Guide = {}

local STEPS = {
	{ text = "Tap a brown tile of your farm to plant a carrot!", done = function(d: any) return d.stats.planted >= 1 end },
	{ text = "Watch it grow... when it bounces, it's ready: tap it to harvest!", done = function(d: any) return d.stats.harvested >= 1 end },
	{ text = "Open the BARN and sell your carrots for coins.", done = function(d: any) return d.stats.sold >= 1 end },
	{ text = "Buy more seeds in SEEDS. Drag across tiles to plant many at once!", done = function(d: any) return d.stats.planted >= 10 end },
	{ text = "Your farm can grow: buy more land with LAND.", done = function(d: any) return d.tiles > Land.START end },
	{ text = "Hop in your TRACTOR and drive to town: the ORDERS board pays well!", done = function(d: any) return (d.stats.orders or 0) >= 1 end },
	{ text = "Put crops on your FARM STAND (by your gate): neighbours buy them, even while you're away.", done = function(d: any) return next(d.stand or {}) ~= nil or (d.stats.standSold or 0) > 0 end },
}

function Guide.init(screen: ScreenGui)
	local box = Ui.panel(screen, UDim2.fromOffset(560, 56), UDim2.new(0.5, -280, 1, -190), Ui.yellow)
	box.Visible = false
	local label = Ui.label(box, "", UDim2.new(1, -28, 1, -18), UDim2.fromOffset(14, 9))
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
				box.Position = UDim2.new(0.5, -280, 1, -170)
				TweenService:Create(box, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, -280, 1, -190) }):Play()
			end
		end
	end)
end

return Guide
