-- Keeps one window open at a time.

local Windows = {}

type Entry = { frame: GuiObject, onOpen: (() -> ())? }

local entries: { [string]: Entry } = {}
local current: string? = nil
local gate: ((name: string) -> boolean)? = nil

-- A check run before a window opens (locked systems say why and stay closed).
function Windows.setGate(fn: (name: string) -> boolean)
	gate = fn
end

function Windows.register(name: string, frame: GuiObject, onOpen: (() -> ())?)
	entries[name] = { frame = frame, onOpen = onOpen }
end

function Windows.open(name: string)
	if gate and not gate(name) then
		return
	end
	if current and current ~= name and entries[current] then
		entries[current].frame.Visible = false
	end
	local entry = entries[name]
	if not entry then
		return
	end
	current = name
	entry.frame.Visible = true
	if entry.onOpen then
		entry.onOpen()
	end
end

function Windows.close(name: string?)
	local target = name or current
	if target and entries[target] then
		entries[target].frame.Visible = false
	end
	if target == current then
		current = nil
	end
end

function Windows.toggle(name: string)
	if current == name then
		Windows.close(name)
	else
		Windows.open(name)
	end
end

function Windows.isOpen(name: string): boolean
	return current == name
end

return Windows
