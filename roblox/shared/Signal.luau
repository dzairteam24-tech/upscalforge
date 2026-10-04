--!strict
-- Minimal signal that passes arguments by reference.
-- BindableEvent copies tables, which would hand listeners copies of live game state.

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> () -> (),
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}
	local signal = {}

	function signal.Connect(_self: any, fn: (T...) -> ()): () -> ()
		table.insert(listeners, fn)
		return function()
			local index = table.find(listeners, fn)
			if index then
				table.remove(listeners, index)
			end
		end
	end

	function signal.Fire(_self: any, ...: T...)
		for _, fn in table.clone(listeners) do
			task.spawn(fn, ...)
		end
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
