--!strict
-- Trails (Config/Trails): bought with coins at the Trail Shop, worn one at a time. The worn one streams behind
-- the player (a Trail between two attachments on their root) and multiplies every treadmill step (WildService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trails = require(Shared.Config.Trails)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IslandService = require(script.Parent.IslandService)

local TrailService = {}

-- Draws the worn trail behind the player (or none)
local function show(player: Player)
	local data = DataService.get(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		return
	end
	for _, name in { "TrailTop", "TrailBottom", "Trail" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local trail = Trails.byId[data.trail]
	if not trail then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 0.8, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -1.6, 0.4)
	bottom.Parent = root
	local streak = Instance.new("Trail")
	streak.Name = "Trail"
	streak.Attachment0, streak.Attachment1 = top, bottom
	local keys = {}
	for i, color in trail.colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #trail.colors == 1 then 0 else (i - 1) / (#trail.colors - 1), color))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, trail.colors[1]))
	end
	streak.Color = ColorSequence.new(keys)
	streak.Transparency = NumberSequence.new(0.15, 1)
	streak.Lifetime = 0.45
	streak.LightEmission = 0.5
	streak.FaceCamera = true
	streak.Parent = root
end

local function buy(player: Player, id: any)
	local data = DataService.get(player)
	local trail = if type(id) == "string" then Trails.byId[id] else nil
	if not data or not trail then
		return
	end
	if data.trails[trail.id] then
		data.trail = trail.id -- (owned: wear it)
	elseif data.coins < trail.price then
		IslandService.notify(player, ("You need 🪙 %s"):format(Format.abbrev(trail.price)), "error")
		return
	else
		data.coins -= trail.price
		data.trails[trail.id] = true
		data.trail = trail.id
		IslandService.notify(player, ("✨ %s! Every treadmill step gives ×%s ⚡"):format(trail.name, tostring(trail.mult)), "success")
	end
	show(player)
	IslandService.push(player)
end

function TrailService.init()
	Net.event("BuyTrail").OnServerEvent:Connect(buy)
	DataService.onLoaded(function(player)
		show(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			show(player)
		end)
	end)
end

return TrailService
