--!strict
-- The ONLY place client/server message names are defined.
-- Add a name here, then use Net.remote(name) on both sides.

local Net = {}

Net.Messages = table.freeze({
	Ping = "Ping",
	-- player data (campaign place)
	DataState = "DataState", -- server -> client: marks, unlocks, guide, class
	GuideFinish = "GuideFinish", -- client -> server: the guide's last page was reached
	PickClass = "PickClass", -- client -> server: classId
	DebugGrant = "DebugGrant", -- client -> server: amount (Studio / admins only)
	-- campaign (campaign place)
	CampaignState = "CampaignState", -- server -> client: id, day, state, players, private
	ResetCampaign = "ResetCampaign", -- client -> server: private owner only
	-- server list and matching (both places)
	ListRequest = "ListRequest", -- client -> server
	ListRows = "ListRows", -- server -> client: rows
	JoinRequest = "JoinRequest", -- client -> server: campaign id
	MatchRequest = "MatchRequest", -- client -> server (entry place): auto-match
	Status = "Status", -- server -> client: short text for the debug UI
})

export type MessageName =
	"Ping"
	| "DataState"
	| "GuideFinish"
	| "PickClass"
	| "DebugGrant"
	| "CampaignState"
	| "ResetCampaign"
	| "ListRequest"
	| "ListRows"
	| "JoinRequest"
	| "MatchRequest"
	| "Status"

-- Roblox services are fetched lazily so the name table above stays testable in Lune.
function Net.remote(name: MessageName): RemoteEvent
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		assert(RunService:IsServer(), "Remotes folder missing; the server must create it first")
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		folder = created
	end
	local remote = folder:FindFirstChild(name)
	if not remote then
		assert(RunService:IsServer(), "Remote missing: " .. name)
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = folder
		remote = created
	end
	return remote :: RemoteEvent
end

-- Client side: wait for a remote the server creates.
function Net.wait(name: MessageName): RemoteEvent
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
