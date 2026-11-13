--!strict
-- Types shared by ClanUI and its tabs (ClanMembersTab, ClanBankTab, ClanRaidTab).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type Context = {
	showStatus: (text: string) -> (),
	failMessage: (reason: string?) -> string,
	-- Sends a clan request and shows any error. Yields.
	request: (action: string, arg: any?) -> Types.ClanResult,
}

export type Tab = {
	title: string,
	frame: Frame,
	render: (view: Types.ClanView, snapshot: Types.Snapshot?) -> (),
}

return {}
