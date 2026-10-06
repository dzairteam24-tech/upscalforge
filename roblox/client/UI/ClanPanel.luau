-- Clan window: create or join a clan, see members and their weekly points, and the top clans.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClanConfig = require(Shared.Config.Clans)
local Format = require(Shared.Logic.Format)
local Net = require(Shared.Net)

local Notify = require(script.Parent.Notify)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local ClanPanel = {}

local function box(placeholder: string): TextBox
	local b = Instance.new("TextBox")
	b.PlaceholderText = placeholder
	b.Text = ""
	b.ClearTextOnFocus = false
	b.Font = Theme.font
	b.TextScaled = true
	b.TextColor3 = Theme.text
	b.BackgroundColor3 = Theme.card
	b.Size = UDim2.new(1, -12, 0, 40)
	Theme.corner(b, 8)
	return b
end

function ClanPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Clans", function()
		Windows.close("Clan")
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	Theme.list(scroll, 8)
	scroll.Parent = content

	local order = 0
	local function add(object: GuiObject)
		order += 1
		object.LayoutOrder = order
		object.Parent = scroll
	end
	local function text(value: string, props: { [string]: any }?)
		local p = props or {}
		local label = Theme.label({
			Text = value,
			Font = p.Font or Enum.Font.Gotham,
			TextColor3 = p.TextColor3 or Theme.muted,
			Size = UDim2.new(1, -12, 0, p.height or 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = p.MaxTextSize or 15,
		})
		add(label)
		return label
	end
	local function title(value: string)
		text(value, { Font = Theme.titleFont, TextColor3 = Theme.text, MaxTextSize = 20, height = 30 })
	end
	local function button(label: string, color: Color3, onPress: () -> ())
		local b = Theme.button({ Text = label, Size = UDim2.new(1, -12, 0, 42), BackgroundColor3 = color, MaxTextSize = 18 })
		b.Activated:Connect(onPress)
		add(b)
	end

	local function show(info: { [string]: any }?, top: { { [string]: any } }, available: boolean)
		Theme.clear(scroll)
		order = 0
		if not available then
			text("Clans turn on when the game is published (they're saved across servers).", { height = 40 })
		end
		if info then
			title(("🛡️ [%s] %s"):format(info.tag, info.name))
			text(("Code: %s · share it so friends can join · %d/%d members"):format(info.id, #info.members, ClanConfig.MAX_MEMBERS))
			text(
				("This week: %s points%s"):format(Format.abbrev(info.points), if info.rank then (" · #%d"):format(info.rank) else ""),
				{ TextColor3 = Theme.gold, Font = Theme.font }
			)
			local isOwner = info.owner == Players.LocalPlayer.UserId
			for i, member in info.members do
				local row = text(
					("%d. %s%s · %s"):format(i, member.name, if member.id == info.owner then " 👑" else "", Format.abbrev(member.points)),
					{ TextColor3 = Theme.text }
				)
				if isOwner and member.id ~= info.owner then
					row.Size = UDim2.new(1, -112, 0, row.Size.Y.Offset)
					local kick = Theme.button({
						Text = "Remove",
						Size = UDim2.new(0, 90, 0, 22),
						Position = UDim2.new(1, -100, 0, 2),
						BackgroundColor3 = Theme.red,
						MaxTextSize = 13,
					})
					kick.Position = UDim2.new(1, 6, 0, 2)
					kick.Parent = row
					-- Tap twice: it can't be undone and uses today's removal
					local armed = false
					kick.Activated:Connect(function()
						if not armed then
							armed = true
							kick.Text = "Sure?"
							task.delay(3, function()
								armed = false
								if kick.Parent then
									kick.Text = "Remove"
								end
							end)
							return
						end
						Net.event("ClanKick"):FireServer(member.id)
					end)
				end
			end
			if isOwner then
				text("You can remove one member a day. Their points stay with the clan.")
			end
			button("Leave clan", Theme.red, function()
				Net.event("ClanLeave"):FireServer()
			end)
		else
			title("Join a clan")
			local code = box("Clan code")
			add(code)
			button("Join", Theme.green, function()
				Net.event("ClanJoin"):FireServer(code.Text)
			end)
			title(("Or create one · 💎 %d"):format(ClanConfig.CREATE_COST))
			local name = box(("Name (%d-%d letters)"):format(ClanConfig.NAME_MIN, ClanConfig.NAME_MAX))
			add(name)
			local tag = box(("Tag (%d-%d letters)"):format(ClanConfig.TAG_MIN, ClanConfig.TAG_MAX))
			add(tag)
			button("Create clan", Theme.purple, function()
				Net.event("ClanCreate"):FireServer(name.Text, tag.Text)
			end)
		end
		title("🏆 Top clans this week")
		text("Members of the top 10 get gems every week, and the Top Clan title.")
		if #top == 0 then
			text("No points yet this week. Break sources, hatch and beat guardians to earn some!")
		end
		for i, entry in top do
			text(("#%d [%s] %s · %s"):format(i, entry.tag, entry.name, Format.abbrev(entry.points)), { TextColor3 = Theme.text })
		end
	end

	Net.event("ClanData").OnClientEvent:Connect(function(info, top, available: boolean, message: string?)
		show(info, top or {}, available)
		if message then
			Notify.show(message, "success", 5)
		end
	end)
	Windows.register("Clan", window, function()
		Net.event("ClanRequest"):FireServer()
	end)
end

return ClanPanel
