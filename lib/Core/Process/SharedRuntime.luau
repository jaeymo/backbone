--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent.Parent
local packages = root.Parent

local Config = require(root.Core.Config)
local Defaults = require(root.Defaults)
local DeferToPhase = require(root.Util.DeferToPhase)
local Enums = require(root.Enums)
local ImportLayer = require(root.Core.ImportLayer)
local NetworkLayer = require(root.Core.NetworkLayer)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(packages.Signal)
local Types = require(root.Types)

local SharedRuntime = {
	Defaults = Defaults,
	PhaseChanged = ImportLayer.PhaseChanged,
	Controllers = {} :: any,
}

type OnPhaseOverloads =
	((self: SharedRuntime, phase: "Init", callback: () -> Promise.TypedPromise<()>) -> Signal.Connection?)
	& ((self: SharedRuntime, phase: "Awake" | "Start" | "Done", callback: () -> ()) -> Signal.Connection?)

--[=[
	@priv
]=]
local function keyFor(name: string): string
	return (string.gsub(name, "Controller$", "")):upper() -- "InputController" -> "INPUT"
end

local loaded: { [string]: any }

do
	loaded = {}
	for _, v in root.Controllers:GetChildren() do
		loaded[v.Name] = (require :: any)(v)
	end
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

function SharedRuntime.GetDefaults(self: SharedRuntime): typeof(Defaults)
	return self.Defaults
end

function SharedRuntime.DeferConnect(
	self: SharedRuntime,
	signal: any,
	phase: Types.LifecyclePhaseName,
	callback: (...any) -> (),
	options: Types.DeferOptions?
): Types.Connection
	return DeferToPhase.Connect(signal, phase, callback, options)
end

--[=[
	@priv
]=]
local function onPhase(self: SharedRuntime, phase: Types.LifecyclePhaseName, callback: () -> ...any): Signal.Connection?
	local import = self:GetImportLayer()
	local targetPhase = Enums.LifecyclePhase[phase]

	if not targetPhase then
		error(`Invalid lifecycle phase: {phase}`)
	end

	if import:GetPhase().Priority >= targetPhase.Priority then
		task.spawn(callback)
		return nil
	end

	local connection: Signal.Connection
	connection = self.PhaseChanged:Connect(function(currentPhase)
		if currentPhase.Priority >= targetPhase.Priority then
			connection:Disconnect()
			task.spawn(callback)
		end
	end)

	return connection
end

SharedRuntime.OnPhase = onPhase :: OnPhaseOverloads

return SharedRuntime
