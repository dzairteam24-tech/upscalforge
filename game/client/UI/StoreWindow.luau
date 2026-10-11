--!strict
-- The Robux shop (Config/Robux): time, comfort and looks only. Fast Hatch (a game pass), Hatch All Now (each
-- time), and the floating seats (looks: every seat rides the same). Buying asks the server (RobuxService), which
-- shows Roblox's purchase prompt; until an item's id is set on the website it says coming soon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Robux = require(Shared.Config.Robux)
local SeatLooks = require(Shared.Config.SeatLooks)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local StoreWindow = {}

local ROBUX = utf8.char(0xE002) -- (Roblox's Robux sign, in its own fonts)

function StoreWindow.mount(gui: Instance)
	local window, content = Theme.window(gui, "🛒 Shop", Vector2.new(820, 620), Theme.green)

	local function header(order: number, text: string)
		Theme.bold(content, { Text = text, Size = UDim2.new(1, -8, 0, 36), TextColor3 = Color3.fromRGB(255, 120, 230), LayoutOrder = order, MaxText = 32 })
	end

	local function rebuild()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = Store.data
		header(1, "-- SAVE TIME --")
		local grid = Theme.grid(content, 2, 2, 230)
		for i, entry in { { item = Robux.FAST_HATCH, key = "FastHatch", pass = true }, { item = Robux.HATCH_ALL, key = "HatchAll", pass = false } } do
			local item = entry.item
			local card = Theme.card(grid, if entry.pass then Color3.fromRGB(150, 90, 255) else Color3.fromRGB(255, 140, 60), { LayoutOrder = i })
			Theme.text(card, { Text = item.icon, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 8) })
			Theme.bold(card, { Text = item.name, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 88), MaxText = 30 })
			Theme.bold(card, { Text = item.text, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 124), Font = Theme.font, TextWrapped = true, MaxText = 18 })
			local buy = Theme.button(card, if item.id == 0 then "Soon" else ROBUX .. " " .. item.price, if item.id == 0 then Theme.gray else Theme.green, function()
				Net.event("BuyRobux"):FireServer(entry.key)
			end)
			buy.AnchorPoint = Vector2.new(0.5, 1)
			buy.Position = UDim2.new(0.5, 0, 1, -10)
			buy.Size = UDim2.new(0.8, 0, 0, 48)
		end
		header(3, "-- FLOATING SEATS --")
		Theme.text(content, { Text = "Looks only: every seat rides the same", Size = UDim2.new(1, -8, 0, 22), TextColor3 = Theme.soft, LayoutOrder = 4 })
		local seats = Theme.grid(content, 5, 4, 120)
		local owned = if data and data.seats then data.seats else {}
		for i, look in SeatLooks do
			local id = Robux.SEATS[look.name] or 0
			local card = Theme.card(seats, Theme.lighten(look.light, 0.2), { LayoutOrder = i })
			Theme.bold(card, { Text = look.title, Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 8), TextWrapped = true, MaxText = 20 })
			local has = owned[look.name] == true
			local buy = Theme.button(card, if has then "Owned ✓" elseif id == 0 then "Soon" else ROBUX .. " " .. Robux.SEAT_PRICE, if has or id == 0 then Theme.gray else Theme.green, function()
				if not has then
					Net.event("BuyRobux"):FireServer("Seat:" .. look.name)
				end
			end)
			buy.AnchorPoint = Vector2.new(0.5, 1)
			buy.Position = UDim2.new(0.5, 0, 1, -8)
			buy.Size = UDim2.new(1, -16, 0, 40)
		end
	end

	Windows.register("Store", window, rebuild)
	Store.Changed:Connect(function()
		if window.Visible then
			rebuild()
		end
	end)
end

return StoreWindow
