--!strict
-- Where a player's battlefield is, from the plot number the server gives them.
-- The server stores it as the "PlotIndex" attribute on the Player.

local WorldConfig = require(script.Parent.Config.WorldConfig)

local Plots = {
	ATTRIBUTE = "PlotIndex",
}

function Plots.origin(plotIndex: number): Vector3
	return WorldConfig.PLOT_BASE + Vector3.new((plotIndex - 1) * WorldConfig.PLOT_SPACING, 0, 0)
end

return table.freeze(Plots)
