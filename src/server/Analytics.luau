--!strict
-- Player-progress analytics (Roblox AnalyticsService). Answers: how many players reach each
-- marks/rank step, how long and how many sessions it takes, and who is at each step now, so we
-- know when to design rank badges past 5,000 marks (user, 2026-11-19).
-- Event names and where to read them: jarvis notes/ideas/korea-pve/16-analytics.md.
--
-- PlayerData calls this; nothing else should. Every call is wrapped so analytics can never
-- break gameplay. AnalyticsService only records from published servers: in Studio the events
-- are printed to the output instead ("[Analytics] ...").

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Config.Progression)
local Servers = require(Shared.Config.Servers)
local RankTrack = require(Shared.Rules.RankTrack)(Progression)

local Analytics = {}
Analytics.RankTrack = RankTrack

-- Names (keep stable: renaming starts a new series on the dashboard).
local PATH = "MarksRank" -- funnel and progression path
local CURRENCY = "Marks"
local EV_HOURS = "RankReachedPlayHours"
local EV_SESSIONS = "RankReachedSessions"
local EV_DAYS = "RankReachedDays"
local EV_AT_JOIN = "RankAtJoin"
local FLUSH_SECONDS = 60 -- marks economy events are summed per source, then sent this often

local STUDIO = RunService:IsStudio()
local F1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name

type Save = { [string]: any } -- PlayerSave.Save (only the analytics fields are touched)
type State = { tick: number, pending: { [string]: number } }
local states: { [Player]: State } = {}

local function excluded(player: Player): boolean
	-- Admin test grants would pollute the real numbers.
	return not STUDIO and table.find(Servers.Admins, player.UserId) ~= nil
end

local function send(what: string, fn: () -> ())
	if STUDIO then
		print("[Analytics] " .. what)
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		warn(`[Analytics] {what} failed: {err}`)
	end
end

local function field(name: string)
	return { [F1] = name }
end

-- Add play time since the last call to the save.
function Analytics.accrue(player: Player, save: Save)
	local st = states[player]
	if not st then
		return
	end
	local t = os.clock()
	save.playSeconds += math.max(0, t - st.tick)
	st.tick = t
end

-- Report every rank step crossed since the last report (once per player per step, saved).
function Analytics.checkRank(player: Player, save: Save)
	if not states[player] then
		return
	end
	local crossed = RankTrack.crossed(save.rankLogged, save.marks)
	if #crossed == 0 then
		return
	end
	Analytics.accrue(player, save)
	local hours = save.playSeconds / 3600
	local days = math.max(0, os.time() - save.firstJoin) / 86400
	for _, s in crossed do
		send(`rank {s.name} (step {s.index}) {hours} h, {save.sessions} sessions`, function()
			AnalyticsService:LogFunnelStepEvent(player, PATH, nil :: any, s.index, s.name)
			AnalyticsService:LogProgressionCompleteEvent(player, PATH, s.index, s.name)
			AnalyticsService:LogCustomEvent(player, EV_HOURS, hours, field(s.name))
			AnalyticsService:LogCustomEvent(player, EV_SESSIONS, save.sessions, field(s.name))
			AnalyticsService:LogCustomEvent(player, EV_DAYS, days, field(s.name))
		end)
		save.rankLogged = s.at
	end
end

-- After a save loads on a campaign server.
function Analytics.join(player: Player, save: Save)
	if excluded(player) then
		return
	end
	states[player] = { tick = os.clock(), pending = {} }
	save.sessions += 1
	local step = RankTrack.stepFor(save.marks)
	send(`join at {step.name} ({save.marks} marks), session {save.sessions}`, function()
		-- Step 1 ("joined") makes the funnel start at every player; repeats are ignored.
		local first = RankTrack.steps[1]
		AnalyticsService:LogFunnelStepEvent(player, PATH, nil :: any, first.index, first.name)
		AnalyticsService:LogCustomEvent(player, EV_AT_JOIN, save.marks, field(step.name))
	end)
	Analytics.checkRank(player, save) -- old saves and restores catch up here
end

-- Marks were awarded (after PlayerSave.award). Economy events are batched per source.
function Analytics.marks(player: Player, save: Save, source: string, added: number)
	local st = states[player]
	if not st then
		return
	end
	if added > 0 and source ~= "admin" then
		st.pending[source] = (st.pending[source] or 0) + added
	end
	Analytics.checkRank(player, save)
end

local function flush(player: Player, save: Save?)
	local st = states[player]
	if not st or not save then
		return
	end
	for source, amount in st.pending do
		local kind = if source == Progression.ReleaseCode.source
			then Enum.AnalyticsEconomyTransactionType.Onboarding.Name
			else Enum.AnalyticsEconomyTransactionType.Gameplay.Name
		send(`marks +{amount} from {source} (balance {save.marks})`, function()
			AnalyticsService:LogEconomyEvent(
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				CURRENCY,
				amount,
				save.marks,
				kind,
				source
			)
		end)
	end
	table.clear(st.pending)
end

-- Before the player's last save on this server.
function Analytics.leave(player: Player, save: Save?)
	if save then
		flush(player, save)
		Analytics.accrue(player, save)
	end
	states[player] = nil
end

function Analytics.start(getSave: (Player) -> Save?)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for p in states do
				if p.Parent == Players then
					flush(p, getSave(p))
				end
			end
		end
	end)
end

return Analytics
