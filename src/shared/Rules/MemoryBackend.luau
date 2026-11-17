--!strict
-- In-memory stand-ins for DataStores and MemoryStore sorted maps, with the same small
-- interface the real adapters (src/serverlib/Stores.luau) give. Used by Lune tests and by
-- Studio when the place is not published. Values are deep-copied in and out, like the real
-- services, so callers can't change stored data by accident.
--
-- Store:     get(key) -> (ok, value); set(key, value) -> ok; remove(key) -> ok;
--            update(key, fn(old) -> new | nil) -> (ok, value)   (nil from fn = no write)
-- SortedMap: the same plus a ttl (seconds) on set/update, and range(count) -> { {key, value} }
--            sorted by key.

local MemoryBackend = {}

export type Store = {
	get: (key: string) -> (boolean, any),
	set: (key: string, value: any) -> boolean,
	remove: (key: string) -> boolean,
	update: (key: string, fn: (any) -> any) -> (boolean, any),
	failNext: (n: number) -> (),
}

export type SortedMap = {
	get: (key: string) -> (boolean, any),
	set: (key: string, value: any, ttl: number) -> boolean,
	remove: (key: string) -> boolean,
	update: (key: string, fn: (any) -> any, ttl: number) -> (boolean, any),
	range: (count: number) -> (boolean, { { key: string, value: any } }),
	failNext: (n: number) -> (),
}

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end
MemoryBackend.copy = copy

function MemoryBackend.store(): Store
	local data: { [string]: any } = {}
	local failures = 0
	local function fail(): boolean
		if failures > 0 then
			failures -= 1
			return true
		end
		return false
	end
	local self = {}
	function self.get(key: string): (boolean, any)
		if fail() then
			return false, nil
		end
		return true, copy(data[key])
	end
	function self.set(key: string, value: any): boolean
		if fail() then
			return false
		end
		data[key] = copy(value)
		return true
	end
	function self.remove(key: string): boolean
		if fail() then
			return false
		end
		data[key] = nil
		return true
	end
	function self.update(key: string, fn: (any) -> any): (boolean, any)
		if fail() then
			return false, nil
		end
		local new = fn(copy(data[key]))
		if new ~= nil then
			data[key] = copy(new)
		end
		return true, copy(data[key])
	end
	function self.failNext(n: number)
		failures = n
	end
	return self :: any
end

function MemoryBackend.sortedMap(clock: () -> number): SortedMap
	local data: { [string]: { value: any, expires: number } } = {}
	local failures = 0
	local function fail(): boolean
		if failures > 0 then
			failures -= 1
			return true
		end
		return false
	end
	local function live(key: string): any
		local e = data[key]
		if e and e.expires <= clock() then
			data[key] = nil
			return nil
		end
		return e and e.value
	end
	local self = {}
	function self.get(key: string): (boolean, any)
		if fail() then
			return false, nil
		end
		return true, copy(live(key))
	end
	function self.set(key: string, value: any, ttl: number): boolean
		if fail() then
			return false
		end
		data[key] = { value = copy(value), expires = clock() + ttl }
		return true
	end
	function self.remove(key: string): boolean
		if fail() then
			return false
		end
		data[key] = nil
		return true
	end
	function self.update(key: string, fn: (any) -> any, ttl: number): (boolean, any)
		if fail() then
			return false, nil
		end
		local new = fn(copy(live(key)))
		if new ~= nil then
			data[key] = { value = copy(new), expires = clock() + ttl }
		end
		return true, copy(live(key))
	end
	function self.range(count: number): (boolean, { { key: string, value: any } })
		if fail() then
			return false, {}
		end
		local keys = {}
		for key in data do
			if live(key) ~= nil then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local out = {}
		for i = 1, math.min(count, #keys) do
			table.insert(out, { key = keys[i], value = copy(data[keys[i]].value) })
		end
		return true, out
	end
	function self.failNext(n: number)
		failures = n
	end
	return self :: any
end

return MemoryBackend
