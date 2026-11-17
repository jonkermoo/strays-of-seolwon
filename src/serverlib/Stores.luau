--!strict
-- The stores every server uses, behind the small interface of Rules/MemoryBackend:
-- real DataStores / MemoryStore in a live game, in-memory stand-ins in Studio (the place is
-- not published yet, user 2026-11-17). Calls yield and retry a few times.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Servers = require(Shared.Config.Servers)
local MemoryBackend = require(Shared.Rules.MemoryBackend)

local Stores = {}

-- Studio uses the mock unless the workspace has the attribute LiveStores = true
-- (then the place must be published with Studio API access on).
Stores.mock = RunService:IsStudio() and workspace:GetAttribute("LiveStores") ~= true

local RETRIES = 3

local function retry<T...>(f: () -> T...): (boolean, T...)
	local results
	for attempt = 1, RETRIES do
		results = table.pack(pcall(f))
		if results[1] then
			return true, table.unpack(results, 2, results.n)
		end
		warn(`[Stores] attempt {attempt} failed: {results[2]}`)
		if attempt < RETRIES then
			task.wait(attempt)
		end
	end
	return false
end

local function realStore(ds: GlobalDataStore): MemoryBackend.Store
	local self = {}
	function self.get(key: string): (boolean, any)
		return retry(function()
			return ds:GetAsync(key)
		end)
	end
	function self.set(key: string, value: any): boolean
		return (retry(function()
			ds:SetAsync(key, value)
		end))
	end
	function self.remove(key: string): boolean
		return (retry(function()
			ds:RemoveAsync(key)
		end))
	end
	function self.update(key: string, fn: (any) -> any): (boolean, any)
		return retry(function()
			return ds:UpdateAsync(key, function(old)
				return fn(old)
			end)
		end)
	end
	function self.failNext(_n: number) end
	return self :: any
end

local function realMap(map: MemoryStoreSortedMap): MemoryBackend.SortedMap
	local self = {}
	function self.get(key: string): (boolean, any)
		return retry(function()
			return map:GetAsync(key)
		end)
	end
	function self.set(key: string, value: any, ttl: number): boolean
		return (retry(function()
			map:SetAsync(key, value, ttl)
		end))
	end
	function self.remove(key: string): boolean
		return (retry(function()
			map:RemoveAsync(key)
		end))
	end
	function self.update(key: string, fn: (any) -> any, ttl: number): (boolean, any)
		return retry(function()
			return map:UpdateAsync(key, function(old)
				return fn(old)
			end, ttl)
		end)
	end
	function self.range(count: number): (boolean, { { key: string, value: any } })
		local ok, items = retry(function()
			return map:GetRangeAsync(Enum.SortDirection.Ascending, count)
		end)
		return ok, if ok then items else {}
	end
	function self.failNext(_n: number) end
	return self :: any
end

local cache: { [string]: any } = {}

function Stores.data(name: string): MemoryBackend.Store
	if not cache[name] then
		cache[name] = if Stores.mock
			then MemoryBackend.store()
			else realStore(DataStoreService:GetDataStore(name))
	end
	return cache[name]
end

-- Ordered store (numbers only), e.g. the highest-marks backup.
function Stores.ordered(name: string): MemoryBackend.Store
	local k = "ordered:" .. name
	if not cache[k] then
		cache[k] = if Stores.mock
			then MemoryBackend.store()
			else realStore(DataStoreService:GetOrderedDataStore(name) :: any)
	end
	return cache[k]
end

function Stores.sortedMap(name: string): MemoryBackend.SortedMap
	local k = "map:" .. name
	if not cache[k] then
		cache[k] = if Stores.mock
			then MemoryBackend.sortedMap(os.time)
			else realMap(MemoryStoreService:GetSortedMap(name))
	end
	return cache[k]
end

Stores.names = Servers.Stores

return Stores
