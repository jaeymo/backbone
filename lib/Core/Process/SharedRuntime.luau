--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent.Parent
local packages = root.Parent

local Config = require(root.Core.Config)
local Enums = require(root.Enums)
local ImportLayer = require(root.Core.ImportLayer)
local NetworkLayer = require(root.Core.NetworkLayer)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(packages.Signal)
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

--[=[
	Runs a callback when the runtime reaches the specified lifecycle phase.

	If the runtime has already reached the phase, the callback is scheduled
	immediately. The returned connection can be disconnected to cancel the callback.

	@param phase The lifecycle phase to wait for.
	@param callback The function to execute when the phase is reached.
	@return A connection if the phase has not been reached yet, otherwise nil.
]=]
function SharedRuntime.OnPhase(
	self: SharedRuntime,
	phase: Types.LifecyclePhaseName,
	callback: () -> ()
): Signal.Connection?
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

return SharedRuntime
