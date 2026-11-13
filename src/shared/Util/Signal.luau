--!strict
-- Minimal event object for module-to-module communication on the same machine.
--   local changed = Signal.new() :: Signal.Signal<Player>
--   local conn = changed:Connect(function(player) ... end)
--   changed:Fire(somePlayer)
--   conn:Disconnect()
-- Each listener runs in its own thread, so one erroring listener can't break the others.

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}

	local signal: Signal<T...> = {
		Connect = function(_self: Signal<T...>, listener: (T...) -> ()): Connection
			table.insert(listeners, listener)
			local connected = true
			return {
				Disconnect = function(_conn: Connection)
					if not connected then
						return
					end
					connected = false
					local index = table.find(listeners, listener)
					if index ~= nil then
						table.remove(listeners, index)
					end
				end,
			}
		end,

		Fire = function(_self: Signal<T...>, ...: T...)
			for _, listener in table.clone(listeners) do
				task.spawn(listener, ...)
			end
		end,
	}

	return signal
end

return table.freeze(Signal)
