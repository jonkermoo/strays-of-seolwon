--!strict
-- Entry place server (the start place): a light menu that routes players into campaigns.
--   public server : the player presses Play (auto-match) or picks a row of the server list
--   private server: everyone goes straight to this private server's own campaign
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Campaigns = require(game:GetService("ServerScriptService").Lib.Campaigns)

for name in Net.Messages do
	Net.remote(name :: any)
end

local status = Net.remote("Status")
local listRows = Net.remote("ListRows")
local busy: { [Player]: boolean } = {}

local function guarded(p: Player, f: () -> string)
	if busy[p] then
		return
	end
	busy[p] = true
	local ok, msg = pcall(f)
	busy[p] = nil
	status:FireClient(p, if ok then msg else "Something went wrong, try again.")
end

local isPrivate = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0

if isPrivate then
	local function route(p: Player)
		guarded(p, function()
			local rec = Campaigns.forPrivate(game.PrivateServerId, game.PrivateServerOwnerId)
			if rec == nil then
				return "Could not open this private campaign, try again."
			end
			local sent = Campaigns.teleport(rec, { p }, "private")
			return if sent
				then "Joining your private campaign..."
				else "Private campaign ready (not sent)."
		end)
	end
	Players.PlayerAdded:Connect(route)
	for _, p in Players:GetPlayers() do
		task.spawn(route, p)
	end
else
	Net.remote("MatchRequest").OnServerEvent:Connect(function(p)
		guarded(p, function()
			return Campaigns.autoMatch(p)
		end)
	end)
	Net.remote("ListRequest").OnServerEvent:Connect(function(p)
		listRows:FireClient(p, Campaigns.rows(p))
	end)
	Net.remote("JoinRequest").OnServerEvent:Connect(function(p, id)
		if type(id) == "string" then
			guarded(p, function()
				return Campaigns.joinById(p, id)
			end)
		end
	end)
end

Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)
