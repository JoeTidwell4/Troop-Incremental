--!strict
-- Asks the server to use abilities, from the ability bar buttons or keys 1/2/3.
-- The server decides whether it's actually allowed (unlocked, off cooldown).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local AbilityConfig = require(Shared:WaitForChild("Config"):WaitForChild("AbilityConfig"))
local StateController = require(script.Parent.StateController)

local useRemote: RemoteEvent? = nil
local slotRemote: RemoteEvent? = nil

local AbilityController = {}

function AbilityController.use(abilityId: string)
	if useRemote ~= nil then
		useRemote:FireServer(abilityId)
	end
end

-- Equips `abilityId` in loadout slot 1..3 (the server checks it's allowed).
function AbilityController.equip(slot: number, abilityId: string)
	if slotRemote ~= nil then
		slotRemote:FireServer(slot, abilityId)
	end
end

-- The ability in a loadout slot right now (nil before the first snapshot).
function AbilityController.inSlot(slot: number): string?
	local snapshot = StateController.get()
	return if snapshot ~= nil then snapshot.abilityLoadout[slot] else nil
end

function AbilityController.start()
	useRemote = Remotes.waitForEvent(Remotes.Events.UseAbility)
	slotRemote = Remotes.waitForEvent(Remotes.Events.SetAbilitySlot)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true while typing in chat, so "1" in a message won't fire Rally.
		if gameProcessed then
			return
		end
		for slot, key in AbilityConfig.SLOT_KEYS do
			if input.KeyCode == key then
				local abilityId = AbilityController.inSlot(slot)
				if abilityId ~= nil then
					AbilityController.use(abilityId)
				end
			end
		end
	end)
end

return AbilityController
