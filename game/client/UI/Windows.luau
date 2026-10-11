--!strict
-- The windows by name, one open at a time (the shops' prompts and the HUD's buttons open them).

local TweenService = game:GetService("TweenService")

local Windows = {}

local windows: { [string]: { frame: GuiObject, onOpen: (() -> ())? } } = {}

function Windows.register(name: string, frame: GuiObject, onOpen: (() -> ())?)
	windows[name] = { frame = frame, onOpen = onOpen }
end

function Windows.open(name: string): boolean
	local entry = windows[name]
	if not entry then
		return false
	end
	for other, w in windows do
		if other ~= name then
			w.frame.Visible = false
		end
	end
	if not entry.frame.Visible then
		local scale = entry.frame:FindFirstChildOfClass("UIScale")
		if scale then -- (it pops open)
			scale.Scale = 0.7
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	entry.frame.Visible = true
	if entry.onOpen then
		entry.onOpen()
	end
	return true
end

function Windows.toggle(name: string)
	local entry = windows[name]
	if entry and entry.frame.Visible then
		entry.frame.Visible = false
	else
		Windows.open(name)
	end
end

function Windows.isOpen(name: string): boolean
	local entry = windows[name]
	return entry ~= nil and entry.frame.Visible
end

return Windows
