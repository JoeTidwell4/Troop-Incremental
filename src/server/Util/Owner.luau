--!strict
-- Is this player the game's owner? (The user who owns the game, or the owner rank 255 of
-- the group that owns it.) Studio counts as the owner, for testing. Cached per player.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Owner = {}

local cache: { [Player]: boolean } = {}

function Owner.is(player: Player): boolean
	local cached = cache[player]
	if cached ~= nil then
		return cached
	end
	local result = false
	if RunService:IsStudio() then
		result = true
	elseif game.CreatorType == Enum.CreatorType.User then
		result = player.UserId == game.CreatorId
	else
		local ok, rank = pcall(function(): number
			return player:GetRankInGroupAsync(game.CreatorId)
		end)
		result = ok and rank >= 255
	end
	cache[player] = result
	return result
end

Players.PlayerRemoving:Connect(function(player: Player)
	cache[player] = nil
end)

return Owner
