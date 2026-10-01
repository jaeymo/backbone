--!strict
local root = script.Parent.Parent
local packages = root.Parent

local Enums = require(root.Enums)
local ImportLayer = require(root.Core.ImportLayer)
local Promise = require(packages.Promise)
local Types = require(root.Types)

type Connection = Types.Connection
type DeferOptions = Types.DeferOptions

export type Deferred = {
	Handler: (...any) -> (),
	Cancel: () -> (),
}

local DeferToPhase = {}

--[=[
	Wraps `callback` so it only ever runs once `phase` has been reached.
	Calls made earlier are queued (or dropped with `Drop = true`) and flushed in order.
]=]
function DeferToPhase.new(phase: Types.LifecyclePhaseName, callback: (...any) -> (), options: DeferOptions?): Deferred
	local target = Enums.LifecyclePhase[phase]
	if not target then
		error(`[BACKBONE] DeferToPhase: invalid lifecycle phase: {tostring(phase)}`, 2)
	end

	local drop = options ~= nil and options.Drop == true
	local ready = ImportLayer:GetPhase().Priority >= target.Priority
	local cancelled = false
	local queue: { { any } } = {}
	local waiting: Promise.TypedPromise<any>? = nil

	if not ready then
		waiting = ImportLayer:WaitForPhase(phase):andThen(function()
			-- index loop so anything queued mid-flush still runs, in order
			local i = 1
			while i <= #queue and not cancelled do
				local args = queue[i]
				task.spawn(callback, table.unpack(args, 1, (args :: any).n))
				i += 1
			end

			table.clear(queue)
			ready = true
		end)
	end

	local function handler(...: any)
		if cancelled then
			return
		end

		if ready then
			callback(...)
			return
		end

		if drop then
			return
		end

		table.insert(queue, table.pack(...))
	end

	local function cancel()
		cancelled = true
		table.clear(queue)

		if waiting then
			(waiting :: any):cancel()
		end
	end

	return { Handler = handler, Cancel = cancel }
end

--[=[
	Shorthand: connect now, run later. Works with Signal, RBXScriptSignal, or Packet events.
]=]
function DeferToPhase.Connect(
	signal: any,
	phase: Types.LifecyclePhaseName,
	callback: (...any) -> (),
	options: DeferOptions?
): Connection
	local deferred = DeferToPhase.new(phase, callback, options)
	local connection = signal:Connect(deferred.Handler)

	return {
		Disconnect = function()
			connection:Disconnect()
			deferred.Cancel()
		end,
	}
end

return DeferToPhase
