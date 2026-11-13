--!strict
-- Turns clicks/taps on the battlefield into "Tap" messages for the server.
-- Taps are grouped and sent every TAP_SEND_INTERVAL seconds instead of one message per
-- click. The server decides how many of them actually count.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("CombatConfig"))

local pendingTaps = 0

local InputController = {
	-- Fires on every local click so visuals can react instantly (cosmetic only).
	Tapped = Signal.new() :: Signal.Signal<()>,
}

function InputController.start()
	local tapRemote = Remotes.waitForEvent(Remotes.Events.Tap)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true when the click hit a UI button, so shop clicks don't attack.
		if gameProcessed then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			pendingTaps += 1
			InputController.Tapped:Fire()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CombatConfig.TAP_SEND_INTERVAL)
			if pendingTaps > 0 then
				local count = math.min(pendingTaps, CombatConfig.TAP_MAX_PER_PACKET)
				pendingTaps = 0
				tapRemote:FireServer(count)
			end
		end
	end)
end

return InputController
