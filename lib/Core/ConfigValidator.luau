--!strict
local root = script.Parent.Parent
local DEFAULTS = require(root.Defaults) :: any

local Validator = {}

Validator.OPAQUE = {
	["PACKETS"] = true,
	["AUDIO.SOURCES"] = true,
	["AUDIO.RESOLVERS"] = true,
	["INPUT.CONFIG"] = true,
} :: { [string]: boolean }

-- Controller -> controllers it hard-requires
local DEPENDENCIES: { [string]: { string } } = {
	CHARACTER = { "ENTITY" },
}

local DEVICES = { Keyboard = true, Mouse = true, Gamepad = true, Touch = true }
local AXIS_SOURCES = { WASD = true, MouseDelta = true, Thumbstick1 = true, Thumbstick2 = true, Touchpad = true }

type Report = { errors: { string }, warnings: { string } }

--[=[
	@priv
]=]
local function joinPath(path: string, key: any): string
	return if path == "" then tostring(key) else `{path}.{key}`
end

--[=[
	@priv
	Unknown keys, wrong types, empty strings
]=]
local function walk(actual: any, schema: any, path: string, r: Report)
	for key, value in actual do
		local p = joinPath(path, key)
		local expected = schema[key]

		if expected == nil then
			table.insert(r.errors, `unknown setting "{p}" (typo?)`)
		elseif Validator.OPAQUE[p] then
			if type(value) ~= "table" then
				table.insert(r.errors, `"{p}" must be a table, got {typeof(value)}`)
			end
		elseif type(expected) == "table" then
			if type(value) ~= "table" then
				table.insert(r.errors, `"{p}" must be a table, got {typeof(value)}`)
			else
				walk(value, expected, p, r)
			end
		elseif typeof(value) ~= typeof(expected) then
			table.insert(r.errors, `"{p}" must be a {typeof(expected)}, got {typeof(value)}`)
		elseif value == "" then
			table.insert(r.errors, `"{p}" cannot be an empty string`)
		end
	end
end

local function distinct(label: string, values: { [string]: any }, r: Report)
	local seen: { [any]: string } = {}
	for key, value in values do
		if seen[value] then
			table.insert(r.errors, `{label}.{key} and {label}.{seen[value]} both use "{tostring(value)}"`)
		else
			seen[value] = key
		end
	end
end

--[=[
	@priv
]=]
local function checkRanges(c: any, r: Report)
	local function check(ok: boolean, msg: string)
		if not ok then
			table.insert(r.errors, msg)
		end
	end

	check(c.ANIMATION.MAX_CONCURRENT_MARKER_FETCHES >= 1, "ANIMATION.MAX_CONCURRENT_MARKER_FETCHES must be >= 1")
	check(
		c.ANIMATION.MARKER_FETCH_RETRIES >= 1 and c.ANIMATION.MARKER_FETCH_RETRIES % 1 == 0,
		"ANIMATION.MARKER_FETCH_RETRIES must be a whole number >= 1"
	)
	check(c.ANIMATION.MARKER_FETCH_BACKOFF_SECONDS >= 0, "ANIMATION.MARKER_FETCH_BACKOFF_SECONDS must be >= 0")
	check(c.CHARACTER.CLIENT_CHARACTER_MODEL_TIMEOUT > 0, "CHARACTER.CLIENT_CHARACTER_MODEL_TIMEOUT must be > 0")
	check(c.ENTITY.CLIENT_ENTITY_GUID_TIMEOUT > 0, "ENTITY.CLIENT_ENTITY_GUID_TIMEOUT must be > 0")
	check(
		c.INPUT.THUMBSTICK_DEADZONE >= 0 and c.INPUT.THUMBSTICK_DEADZONE < 1,
		"INPUT.THUMBSTICK_DEADZONE must be in [0, 1)"
	)
end

--[=[
	@priv
	Anything that would silently overwrite something else at runtime
]=]
local function checkCollisions(c: any, r: Report)
	distinct("TAGS", c.TAGS, r)
	distinct("ATTRIBUTES", c.ATTRIBUTES, r)
	distinct("COLLISION_GROUPS", c.COLLISION_GROUPS, r)
	distinct("METHODS", { INIT = c.INIT_METHOD, AWAKE = c.AWAKE_METHOD, START = c.START_METHOD }, r)
end

--[=[
	@priv
]=]
local function checkDependencies(c: any, r: Report)
	for controller, requires in DEPENDENCIES do
		if not c.ENABLED_CONTROLLERS[controller] then
			continue
		end
		for _, dependency in requires do
			if not c.ENABLED_CONTROLLERS[dependency] then
				table.insert(r.errors, `ENABLED_CONTROLLERS.{controller} requires ENABLED_CONTROLLERS.{dependency}`)
			end
		end
	end
end

--[=[
	@priv
]=]
local function checkPackets(packets: any, r: Report)
	local names: { [string]: string } = {}
	for key, packet in packets do
		local where = `PACKETS.{key}`
		if type(packet) ~= "table" then
			table.insert(r.errors, `{where} must be a table`)
		elseif type(packet.NAME) ~= "string" or packet.NAME == "" then
			table.insert(r.errors, `{where}.NAME must be a non-empty string`)
		elseif names[packet.NAME] then
			table.insert(r.errors, `{where}.NAME "{packet.NAME}" is already used by PACKETS.{names[packet.NAME]}`)
		else
			names[packet.NAME] = tostring(key)
			if packet.UNRELIABLE ~= nil and type(packet.UNRELIABLE) ~= "boolean" then
				table.insert(r.errors, `{where}.UNRELIABLE must be a boolean`)
			end
		end
	end
end

--[=[
	@priv
]=]
local function checkAudio(audio: any, r: Report)
	for i, source in audio.SOURCES do
		if typeof(source) ~= "Instance" then
			table.insert(r.errors, `AUDIO.SOURCES[{i}] must be an Instance, got {typeof(source)}`)
		end
	end
	for name, resolver in audio.RESOLVERS do
		if type(resolver) ~= "function" then
			table.insert(r.errors, `AUDIO.RESOLVERS.{name} must be a function`)
		end
	end
	if #audio.SOURCES == 0 then
		table.insert(
			r.warnings,
			"AUDIO is enabled but AUDIO.SOURCES is empty; sounds must be added via :RegisterSound()"
		)
	end
end

--[=[
	@priv
]=]
local function checkBinding(where: string, binding: any, r: Report)
	if type(binding) ~= "table" or (binding.Keycode == nil and binding.UserInputType == nil) then
		table.insert(r.errors, `{where} needs a Keycode or UserInputType`)
	elseif binding.Keycode ~= nil and typeof(binding.Keycode) ~= "EnumItem" then
		table.insert(r.errors, `{where}.Keycode must be an Enum.KeyCode`)
	elseif binding.UserInputType ~= nil and typeof(binding.UserInputType) ~= "EnumItem" then
		table.insert(r.errors, `{where}.UserInputType must be an Enum.UserInputType`)
	end
end

--[=[
	@priv
]=]
local function checkInput(input: any, r: Report)
	if type(input.Actions) ~= "table" or type(input.Axes) ~= "table" then
		table.insert(r.errors, "INPUT.CONFIG must contain Actions and Axes tables")
		return
	end

	local holdOwners: { [string]: string } = {}

	for name, action in input.Actions do
		local where = `INPUT.CONFIG.Actions.{name}`

		if type(action) ~= "table" then
			table.insert(r.errors, `{where} must be a table`)
			continue
		end

		if action.Name ~= nil and action.Name ~= name then
			table.insert(r.warnings, `{where}.Name is "{action.Name}" but the key is "{name}"; the key is what's used`)
		end

		if type(action.Defaults) ~= "table" then
			table.insert(r.errors, `{where}.Defaults must be a table`)
		else
			for device, bindings in action.Defaults do
				if not DEVICES[device] then
					table.insert(r.errors, `{where}.Defaults has unknown device "{tostring(device)}"`)
				elseif type(bindings) ~= "table" then
					table.insert(r.errors, `{where}.Defaults.{device} must be a list of bindings`)
				else
					for i, binding in bindings do
						checkBinding(`{where}.Defaults.{device}[{i}]`, binding, r)
					end
				end
			end
		end

		local hold = action.Hold
		if hold ~= nil then
			if
				type(hold) ~= "table"
				or type(hold.Name) ~= "string"
				or type(hold.Duration) ~= "number"
				or hold.Duration <= 0
			then
				table.insert(r.errors, `{where}.Hold needs a string Name and a Duration > 0`)
			elseif input.Actions[hold.Name] ~= nil then
				-- _registerAction would overwrite the real action
				table.insert(r.errors, `{where}.Hold.Name "{hold.Name}" collides with an existing action`)
			elseif holdOwners[hold.Name] then
				table.insert(
					r.errors,
					`{where}.Hold.Name "{hold.Name}" is also used by Actions.{holdOwners[hold.Name]}`
				)
			else
				holdOwners[hold.Name] = tostring(name)
			end
		end
	end

	for name, axis in input.Axes do
		local where = `INPUT.CONFIG.Axes.{name}`

		if type(axis) ~= "table" or type(axis.Sources) ~= "table" then
			table.insert(r.errors, `{where}.Sources must be a table`)
			continue
		end

		for device, source in axis.Sources do
			if not DEVICES[device] then
				table.insert(r.errors, `{where}.Sources has unknown device "{tostring(device)}"`)
			elseif not AXIS_SOURCES[source] then
				table.insert(r.errors, `{where}.Sources.{device} has unknown source "{tostring(source)}"`)
			end
		end

		if axis.Sensitivity ~= nil and type(axis.Sensitivity) ~= "number" then
			table.insert(r.errors, `{where}.Sensitivity must be a number`)
		end

		-- _isBlocked looks in actions first and then axes, so shared names cross-block
		if input.Actions[name] ~= nil then
			table.insert(r.warnings, `"{name}" is both an Action and an Axis; Block("{name}") affects both`)
		end
	end
end

--[=[
	@priv
]=]
function Validator.check(config: any)
	local r: Report = { errors = {}, warnings = {} }

	walk(config, DEFAULTS, "", r)

	if #r.errors == 0 then
		checkRanges(config, r)
		checkCollisions(config, r)
		checkDependencies(config, r)
		checkPackets(config.PACKETS, r)

		if config.ENABLED_CONTROLLERS.AUDIO then
			checkAudio(config.AUDIO, r)
		end
		if config.ENABLED_CONTROLLERS.INPUT then
			checkInput(config.INPUT.CONFIG, r)
		end
	end

	for _, message in r.warnings do
		warn(`[BACKBONE] {message}`)
	end

	if #r.errors > 0 then
		table.sort(r.errors)
		error(`[BACKBONE] Invalid config ({#r.errors} problem(s)):\n  - {table.concat(r.errors, "\n  - ")}`, 0)
	end
end

return Validator
