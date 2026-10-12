--!strict
-- The Wild's guardians asleep (WildService marks their model Asleep): "Z z Z" float up from them, one letter at a
-- time, growing as they rise and fading away, like a cartoon's. Only for the ones near the camera.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local GuardianClient = {}

local EVERY = 0.7 -- seconds between two letters
local RANGE = 160 -- studs: further away, nothing

local LETTERS = { "Z", "z", "Z" }

local function floatZ(model: Model, body: BasePart, n: number)
	local height = model:GetAttribute("Height")
	local top = (if type(height) == "number" then height else 4) * 0.6
	local gui = Instance.new("BillboardGui")
	gui.Name = "Zzz"
	gui.Size = UDim2.fromScale(3, 3)
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = Vector3.new(0.6, top, 0)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.LuckiestGuy
	text.Text = LETTERS[(n - 1) % #LETTERS + 1]
	text.TextColor3 = Color3.fromRGB(70, 170, 255) -- (light blue with a white edge, like Steal an Egg's)
	text.TextStrokeColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), Color3.fromRGB(40, 130, 230))
	shade.Parent = text
	text.Rotation = -15
	text.Parent = gui
	gui.Parent = body
	-- (up and a little to the side, swaying, bigger as it goes, then gone)
	local rise = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local side = if n % 2 == 0 then 1.4 else 2.4
	TweenService:Create(gui, rise, { StudsOffsetWorldSpace = Vector3.new(side, top + 5, 0), Size = UDim2.fromScale(5, 5) }):Play()
	TweenService:Create(text, rise, { Rotation = 15 }):Play()
	TweenService:Create(text, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(2.6, gui.Destroy, gui)
end

function GuardianClient.init()
	task.spawn(function()
		local n = 0
		while true do
			task.wait(EVERY)
			n += 1
			local camera = workspace.CurrentCamera
			local eye = if camera then camera.CFrame.Position else Vector3.zero
			for _, model in CollectionService:GetTagged("Guardian") do
				local body = if model:IsA("Model") then model.PrimaryPart else nil
				if body and model:GetAttribute("Asleep") == true and (body.Position - eye).Magnitude < RANGE then
					floatZ(model, body, n)
				end
			end
		end
	end)
end

return GuardianClient
