-- Small shared UI state so windows can hand work to each other without requiring each other:
--   pick:          the Pets window is choosing a creature for something (sticking a sticker)
--   itemsTab:      the Items window should open on this tab
--   stickerTarget: the creature a sticker will go on (chosen from the Pets window first)

local Bus = {
	pick = nil :: { text: string, fn: (petId: string) -> () }?,
	itemsTab = nil :: string?,
	stickerTarget = nil :: string?,
}

local changed = Instance.new("BindableEvent")
Bus.Changed = changed.Event

function Bus.startPick(text: string, fn: (petId: string) -> ())
	Bus.pick = { text = text, fn = fn }
	changed:Fire()
end

function Bus.cancelPick()
	Bus.pick = nil
	changed:Fire()
end

return Bus
