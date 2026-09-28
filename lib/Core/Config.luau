--!strict
local root = script.Parent.Parent

local DEFAULTS = require(root.Defaults)
local Types = require(root.Types)
local Validator = require(script.Parent.ConfigValidator)

local Config = {
	_resolved = nil :: BackboneConfig?,
}

type BackboneConfig = Types.BackboneConfig

--[=[
	@priv
]=]
local function joinPath(path: string, key: any): string
	return if path == "" then tostring(key) else `{path}.{key}`
end

--[=[
	@priv
]=]
local function deepCopy(value: any): any
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return value
	end

	local out = {}
	for key, child in value do
		out[key] = deepCopy(child)
	end
	return out
end

--[=[
	@priv
]=]
local function merge(base: any, override: any, path: string): any
	for key, value in override do
		local p = joinPath(path, key)
		local existing = base[key]

		if Validator.OPAQUE[p] or type(value) ~= "table" or type(existing) ~= "table" or getmetatable(value) ~= nil then
			base[key] = value
		else
			base[key] = merge(existing, value, p)
		end
	end

	return base
end

--[=[
	@priv
]=]
local function deepFreeze(tbl: any, path: string)
	for key, value in tbl do
		local p = joinPath(path, key)
		if type(value) == "table" and getmetatable(value) == nil and not Validator.OPAQUE[p] then
			deepFreeze(value, p)
		end
	end

	table.freeze(tbl)
end

function Config.set(input: Types.BackboneConfigInput)
	assert(Config._resolved == nil, "[BACKBONE] Already configured. Configure() must be called once, before Start()")
	assert(type(input) == "table", "[BACKBONE] Configure() expects a table")

	local merged = merge(deepCopy(DEFAULTS), input, "")
	Validator.check(merged)

	deepFreeze(merged, "")
	Config._resolved = merged
end

function Config.ensure()
	if not Config._resolved then
		Config.set({} :: any) -- cast to any!
	end
end

function Config.get(): BackboneConfig
	assert(
		Config._resolved,
		`[BACKBONE] Config read before Configure()/Start(). Read config inside lifecycle methods, not at module scope.`
	)

	return Config._resolved
end

return Config
