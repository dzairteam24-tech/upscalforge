-- Cube Stack: a cube slides left and right; tap to drop it on the stack. What hangs over the edge falls off.
-- The game runs here; the server only times it and pays the score (MinigameService).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared.Logic.Progress)
local MinigameConfig = require(Shared.Config.Minigame)
local Minigame = require(Shared.Logic.Minigame)
local Net = require(Shared.Net)

local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Theme)
local Windows = require(script.Parent.Windows)

local StackPanel = {}

local FIELD_W, CUBE_H, START_W = 300, 22, 160
local COLORS = {
	Color3.fromRGB(91, 184, 245),
	Color3.fromRGB(245, 166, 91),
	Color3.fromRGB(123, 211, 137),
	Color3.fromRGB(185, 166, 245),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(245, 210, 70),
}

function StackPanel.mount(gui: ScreenGui)
	local window, content = Theme.window(gui, "Cube Stack", function()
		Windows.close("Stack")
	end)

	local info = Theme.label({
		Text = "",
		Size = UDim2.new(1, -12, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
	})
	info.Parent = content

	local field = Theme.frame({
		Name = "Field",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 32),
		Size = UDim2.new(0, FIELD_W, 1, -92),
		BackgroundColor3 = Color3.fromRGB(24, 28, 44),
		ClipsDescendants = true,
	})
	Theme.corner(field, 12)
	field.Parent = content

	local scoreLabel = Theme.label({
		Text = "",
		Font = Theme.titleFont,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = Color3.new(1, 1, 1),
		MaxTextSize = 34,
		ZIndex = 5,
	})
	scoreLabel.Parent = field

	local play = Theme.button({
		Text = "Play",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(220, 48),
		BackgroundColor3 = Theme.green,
		MaxTextSize = 22,
	})
	play.Parent = content

	-- Game state
	type Block = { frame: Frame, left: number, width: number }
	local stack: { Block } = {}
	local moving: Block? = nil
	local direction, speed = 1, 160
	local playing = false
	local score = 0

	local function clearField()
		for _, child in field:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(stack)
		moving = nil
	end

	local function rowY(index: number): number
		-- Keep the top of the stack in view: older rows scroll down
		local height = Theme.layoutSize(field).Y
		local top = math.max(0, #stack - math.max(1, math.floor((height - 120) / CUBE_H)))
		return height - (index - top) * CUBE_H
	end

	local function layout()
		for i, block in stack do
			block.frame.Position = UDim2.fromOffset(block.left, rowY(i))
		end
		if moving then
			moving.frame.Position = UDim2.fromOffset(moving.left, rowY(#stack + 1))
		end
	end

	local function newBlock(left: number, width: number, index: number): Block
		local frame = Theme.frame({ Size = UDim2.fromOffset(width, CUBE_H - 2), BackgroundColor3 = COLORS[(index - 1) % #COLORS + 1], BorderSizePixel = 0 })
		Theme.corner(frame, 4)
		frame.Parent = field
		return { frame = frame, left = left, width = width }
	end

	local function spawnNext()
		local below = stack[#stack]
		local fromLeft = (#stack % 2 == 0)
		moving = newBlock(if fromLeft then -below.width else FIELD_W, below.width, #stack + 1)
		direction = if fromLeft then 1 else -1
		speed = math.min(420, 160 + #stack * 9)
		layout()
	end

	local function finish()
		playing = false
		moving = nil
		play.Visible = true
		scoreLabel.Text = ("%d cubes!"):format(score)
		Net.event("StackEnd"):FireServer(score)
	end

	local function drop()
		local block = moving
		if not playing or not block then
			return
		end
		local below = stack[#stack]
		local left, width = Minigame.place(below.left, below.width, block.left, block.width)
		if width < 2 then
			block.frame:Destroy()
			finish()
			return
		end
		block.left, block.width = left, width
		block.frame.Size = UDim2.fromOffset(width, CUBE_H - 2)
		table.insert(stack, block)
		score += 1
		scoreLabel.Text = tostring(score)
		moving = nil
		if score >= MinigameConfig.MAX_SCORE then
			finish()
			return
		end
		spawnNext()
	end

	local function begin()
		clearField()
		score = 0
		scoreLabel.Text = "0"
		local base = newBlock((FIELD_W - START_W) / 2, START_W, 0)
		base.frame.BackgroundColor3 = Color3.fromRGB(70, 75, 95)
		table.insert(stack, base)
		playing = true
		play.Visible = false
		spawnNext()
	end

	RunService.RenderStepped:Connect(function(dt)
		local block = moving
		if not playing or not block or not window.Visible then
			return
		end
		block.left += direction * speed * dt
		if block.left + block.width > FIELD_W + 40 then
			direction = -1
		elseif block.left < -40 then
			direction = 1
		end
		block.frame.Position = UDim2.fromOffset(block.left, rowY(#stack + 1))
	end)

	-- Tap anywhere on the field (or press space) to drop
	field.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drop()
		end
	end)
	-- Space drops too, and doesn't make the character jump while the game is open
	window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			ContextActionService:BindActionAtPriority("StackDrop", function(_, state)
				if state == Enum.UserInputState.Begin then
					drop()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
		else
			ContextActionService:UnbindAction("StackDrop")
		end
	end)

	play.Activated:Connect(function()
		Net.event("StackStart"):FireServer()
	end)
	Net.event("StackGo").OnClientEvent:Connect(function()
		if not window.Visible then
			Windows.open("Stack")
		end
		begin()
	end)

	local function update()
		local data = Store.data
		local arcade = data and (data :: any).arcade
		local today = Progress.day(os.time())
		local used = if arcade and arcade.day == today then arcade.plays else 0
		local left = math.max(0, MinigameConfig.PLAYS_PER_DAY - used)
		info.Text = ("Plays left today: %d · Best: %d · 1 🎟️ every %d cubes"):format(left, arcade and arcade.best or 0, MinigameConfig.TICKETS_EVERY)
		if not playing then
			play.Text = if left > 0 then "Play" else "Come back tomorrow"
			play.BackgroundColor3 = if left > 0 then Theme.green else Theme.panel
		end
		layout()
	end
	Store.DataChanged:Connect(function()
		if window.Visible then
			update()
		end
	end)
	Windows.register("Stack", window, function()
		if not playing then
			clearField()
			scoreLabel.Text = "Tap to drop the cube"
		end
		update()
	end)
end

return StackPanel
