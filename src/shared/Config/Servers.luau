--!strict
-- Server lifecycle, matchmaking and saving numbers. Pure data.

return table.freeze({
	-- Place ids (fill in once the experience exists; 0 = not published, Studio mock mode).
	EntryPlaceId = 0, -- the light start place: auto-match, server list
	CampaignPlaceId = 0, -- the map; every campaign is a reserved server of this place

	MaxPlayers = 50,
	-- Auto-match (user, 2026-11-17): friends first; fill the fullest server under Target;
	-- when all are at Target+, the smallest under SoftCap; then wake a frozen campaign;
	-- only when none is frozen, start a new Day 0.
	MatchTarget = 20,
	MatchSoftCap = 45, -- leaves room for friends
	JoinWindowSeconds = 90, -- seats promised to teleports count this long

	-- Campaigns: endless. The world freezes when the last player leaves.
	DayLengthSeconds = 40 * 60,
	FreezeEndSeconds = 24 * 60 * 60, -- empty this long: the campaign ends
	PrivateNeverEnds = true, -- private servers freeze but never end (owner can reset)

	-- How often a campaign server reports itself and saves its record.
	HeartbeatSeconds = 15,
	ListEntryTtlSeconds = 60, -- a live entry disappears this long after its server dies
	RecordSaveSeconds = 60,
	ListMax = 200,

	-- Player saves.
	SchemaVersion = 1,
	AutosaveSeconds = 60,
	LockStaleSeconds = 150, -- a lock not refreshed this long is from a dead server
	LockRetrySeconds = 3,
	LockRetries = 10,
	MarksLogLength = 20,

	Stores = table.freeze({
		Players = "Players_v1",
		MarksHigh = "MarksHigh_v1", -- ordered backup of every player's highest marks
		Campaigns = "Campaigns_v1",
		PrivateCampaigns = "PrivateCampaigns_v1",
		ServerList = "ServerList_v1", -- MemoryStore sorted map
	}),

	-- Admin user ids (debug grants outside Studio). Studio is always admin.
	Admins = table.freeze({} :: { number }),
})
