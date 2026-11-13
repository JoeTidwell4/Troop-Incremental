--!strict
-- Asks the server to use abilities, from the ability bar buttons or keys 1/2/3.
-- The server decides whether it's actually allowed (unlocked, off cooldown).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))

local useRemote: RemoteEvent? = nil

local AbilityController = {}

function AbilityController.use(abilityId: string)
	if useRemote ~= nil then
		useRemote:FireServer(abilityId)
	end
end

function AbilityController.start()
	useRemote = Remotes.waitForEvent(Remotes.Events.UseAbility)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true while typing in chat, so "1" in a message won't fire Rally.
		if gameProcessed then
			return
		end
		for _, abilityId in AbilityConfig.ORDER do
			if input.KeyCode == AbilityConfig.ABILITIES[abilityId].key then
				AbilityController.use(abilityId)
			end
		end
	end)
end

return AbilityController
