-- Reload (our rebirth): back to the start of World 1 with x1.5 coins forever and one more cartridge slot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local MapLayout = require(Shared.Logic.MapLayout)
local Reload = require(Shared.Logic.Reload)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GameService = require(script.Parent.GameService)
local State = require(script.Parent.State)

local ReloadService = {}

local function reload(player: Player, confirmed: any)
	local data = DataService.get(player)
	local runtime = State.get(player)
	if not data or not runtime or confirmed ~= true then
		return
	end
	if not State.throttle(runtime, "Reload", 3) then
		return
	end
	local ok, err = Reload.canReload(data)
	if not ok then
		GameService.notify(player, err or "You can't Reload yet", "error")
		return
	end
	Reload.apply(data)

	-- Back to the hub before gate checks run again
	runtime.target = nil
	runtime.combo = 0
	runtime.zoneId = 0
	player:SetAttribute("Target", "")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = CFrame.new(MapLayout.center(0) + Vector3.new(0, 5, 20))
	end

	GameService.progress(player, "Reload", 1)
	GameService.notify(
		player,
		("🔄 World reloaded! Reload %d, coins %s forever"):format(data.reloads, Format.mult(Reload.coinMult(data.reloads))),
		"rare"
	)
	GameService.refresh(player)
end

function ReloadService.init()
	Net.event("Reload").OnServerEvent:Connect(reload)
end

return ReloadService
