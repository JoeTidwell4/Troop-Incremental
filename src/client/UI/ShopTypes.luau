--!strict
-- Types shared by ShopUI and its tabs (TroopTab, GearTab, PackTab).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- What ShopUI gives each tab.
export type Context = {
	getMode: () -> string, -- "One" | "Ten" | "Max"
	showStatus: (text: string) -> (), -- short message in the shop header
	failMessage: (reason: string?) -> string, -- friendly text for a server error reason
}

-- What each tab gives back to ShopUI.
export type Tab = {
	title: string,
	frame: GuiObject,
	modes: { string }, -- buy-mode buttons to show in the header for this tab (may be empty)
	render: (snapshot: Types.Snapshot) -> (),
}

return {}
