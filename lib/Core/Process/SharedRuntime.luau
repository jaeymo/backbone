--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent.Parent

local Config = require(root.Core.Config)
local ImportLayer = require(root.Core.ImportLayer)
local NetworkLayer = require(root.Core.NetworkLayer)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Types = require(root.Types)

local SharedRuntime = {
	PhaseChanged = ImportLayer.PhaseChanged,
	Controllers = {} :: any,
}

local function keyFor(name: string): string
	return (string.gsub(name, "Controller$", "")):upper() -- "InputController" -> "INPUT"
end

local loaded = {} :: { [string]: any }
for _, v in root.Controllers:GetChildren() do
	loaded[v.Name] = (require :: any)(v)
end

SharedRuntime.Controllers = setmetatable({}, {
	__index = function(t, name: string)
		local enabled = (Config.get().ENABLED_CONTROLLERS :: any)[keyFor(name)]
		local value = if enabled
			then loaded[name]
			else setmetatable({}, {
				__index = function(_, member)
					error(`[BACKBONE] {name}.{tostring(member)} used, but {name} is disabled in your config`, 2)
				end,
			})
		rawset(t, name, value)
		return value
	end,
})

export type SharedRuntime = typeof(SharedRuntime)

function SharedRuntime.Configure(self: SharedRuntime, config: Types.BackboneConfigInput)
	Config.set(config)
end

function SharedRuntime.GetPromise(): typeof(Promise)
	return Promise
end

function SharedRuntime.GetImportLayer(self: SharedRuntime): Types.ImportLayer
	return ImportLayer :: any
end

function SharedRuntime.GetControllers(self: SharedRuntime): typeof(SharedRuntime.Controllers)
	return self.Controllers
end

function SharedRuntime.GetNetworkLayer(self: SharedRuntime): Types.NetworkLayer
	return NetworkLayer :: any
end

return SharedRuntime
