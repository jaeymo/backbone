--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent
local packages = root.Parent

local Config = require(root.Core.Config)
local Enums = require(root.Enums)
local Promise = require(packages.Promise)
local Signal = require(packages.Signal)
local Types = require(root.Types)

local IS_SERVER = RunService:IsServer()
local CONSTANTS = require(root.Constants)

local AMOUNT_LIFECYCLE_PHASES, INDEX_TO_PHASE = (function()
	local list = {}

	local count = 0

	for _, v in Enums.LifecyclePhase do
		list[v.Priority] = v
		count += 1
	end

	return count, list
end)()

local ImportLayer = {
	Phase = Enums.LifecyclePhase.Dead :: LifecyclePhaseEnum,
	PhaseChanged = Signal.new() :: Signal.Signal<LifecyclePhaseEnum>,
	Cached = {} :: { [Instance]: any },
}

export type RequireAttemptResult = Types.RequireAttemptResult

export type LifecyclePhaseEnum = Types.LifecyclePhaseEnum

export type LifecyclePhaseName = Types.LifecyclePhaseName

export type ImportLayer = typeof(ImportLayer)

function ImportLayer.Start(self: ImportLayer, directories: Instance | { Instance })
	local config = Config.get()

	return Promise.new(function(resolve, reject)
		self:Bootstrap(directories)

		local initPromises: { Promise.TypedPromise<any> } = {}

		self:ToNextPhase()

		for instance, cachedImport in self.Cached do
			local name = instance:HasTag(config.INTERNAL_CONTROLLER_TAG) and CONSTANTS.AWAKE_METHOD
				or config.AWAKE_METHOD

			self:_invoke(cachedImport, name, false)
		end

		self:ToNextPhase()

		for instance, cachedImport in self.Cached do
			local name = instance:HasTag(config.INTERNAL_CONTROLLER_TAG) and CONSTANTS.INIT_METHOD or config.INIT_METHOD
			local promise = self:_invoke(cachedImport, name, true)

			if promise then
				table.insert(initPromises, promise)
			end
		end

		Promise.all(initPromises)
			:andThen(function()
				self:ToNextPhase()

				for instance, cachedImport in self.Cached do
					local name = instance:HasTag(config.INTERNAL_CONTROLLER_TAG) and CONSTANTS.START_METHOD
						or config.START_METHOD

					task.spawn(function()
						self:_invoke(cachedImport, name, false)
					end)
				end

				self:ToNextPhase()

				resolve()
			end)
			:catch(function(err)
				reject(err)
			end)
	end)
end

function ImportLayer.Bootstrap(self: ImportLayer, directories: Instance | { Instance })
	self:_loadDirectory(root.Controllers)

	if typeof(directories) == "Instance" then
		self:_loadDirectory(directories)
	elseif typeof(directories) == "table" then
		for _, directory in directories do
			if typeof(directory) == "Instance" then
				self:_loadDirectory(directory)
			else
				warn(
					`[BACKBONE] Invalid directory type in bootstrapping list (must be an Instance!): {typeof(directory)}`
				)
			end
		end
	else
		error(
			`[BACKBONE] Bootstrapping process expects an instance or a table of instances. Got: {typeof(directories)}`
		)
	end
end

function ImportLayer.GetPhase(self: ImportLayer): LifecyclePhaseEnum
	return self.Phase
end

function ImportLayer.SetPhase(self: ImportLayer, phase: LifecyclePhaseName)
	local config = Config.get()

	local enum = Enums.LifecyclePhase[phase]
	if not enum then
		warn(`[{script.Name}] Invalid phase: {phase}`)
		return
	end

	if enum.Name == self.Phase.Name then
		return
	end

	local previousPhase = self.Phase

	self.Phase = enum

	if config.LOGGING.PHASE_CHANGED then
		print(`[BACKBONE] Phase changed: {previousPhase.Name} -> {enum.Name}`)
	end

	self.PhaseChanged:Fire(enum)
end

function ImportLayer.WaitForPhase(
	self: ImportLayer,
	phase: LifecyclePhaseName
): Promise.TypedPromise<LifecyclePhaseEnum>
	local targetPhase = Enums.LifecyclePhase[phase]
	if not targetPhase then
		return Promise.reject(`Invalid lifecycle phase: {phase}`)
	end

	if self.Phase.Priority >= targetPhase.Priority then
		return Promise.resolve(self.Phase)
	end

	return Promise.new(function(resolve, _, onCancel)
		local connection: Signal.Connection

		connection = self.PhaseChanged:Connect(function(currentPhase)
			if currentPhase.Priority >= targetPhase.Priority then
				connection:Disconnect()
				resolve(currentPhase)
			end
		end)

		onCancel(function()
			connection:Disconnect()
		end)

		if self.Phase.Priority >= targetPhase.Priority then
			connection:Disconnect()
			resolve(self.Phase)
		end
	end)
end

function ImportLayer.ToNextPhase(self: ImportLayer)
	local currentPhase = self.Phase
	local nextIndex = currentPhase.Priority + 1

	if nextIndex > AMOUNT_LIFECYCLE_PHASES then
		warn(`[BACKBONE] Can't move to next phase, max index reached!`)
		return
	end

	local nextPhase = INDEX_TO_PHASE[nextIndex]
	if not nextPhase then
		warn(`[BACKBONE] Failed to fetch phase from index: {tostring(nextIndex)}`)
		return
	end

	self:SetPhase(nextPhase.Name)
end

--[=[
	@priv 
]=]
function ImportLayer._loadDirectory(self: ImportLayer, directory: Instance)
	local config = Config.get()

	for _, import in directory:GetDescendants() do
		if not import:IsA("ModuleScript") or import == root or self.Cached[import] then
			continue
		end

		local isController = import:HasTag(config.INTERNAL_CONTROLLER_TAG)

		-- Backbone internals (Core, Classes, Util...) are never lifecycle modules
		if import:IsDescendantOf(root) and not isController then
			continue
		end

		if import:HasTag(config.IGNORE_MODULE_LOAD_TAG_NAME) then
			continue
		end

		if isController then
			-- "EntityController" -> "ENTITY"
			local key = (import.Name:gsub("Controller$", "")):upper()

			local wrongRealm = if IS_SERVER
				then CONSTANTS.CLIENT_ONLY_CONTROLLERS[key]
				else CONSTANTS.SERVER_ONLY_CONTROLLERS[key]

			if wrongRealm or not (config :: any).ENABLED_CONTROLLERS[key] then
				continue
			end
		end

		local result = self:_require(import)
		if result.Success then
			self.Cached[import] = result.Module
		else
			warn(`[BACKBONE] Failed to require {import:GetFullName()}:\n{tostring(result.Module)}`)
		end
	end
end

--[=[
	@priv 
]=]
function ImportLayer._require(self: ImportLayer, module: ModuleScript): RequireAttemptResult
	local config = Config.get()

	local moduleGuid = HttpService:GenerateGUID(false)
	module:SetAttribute(config.MODULE_ATTRIBUTE_GUID_NAME, moduleGuid)

	local success, result = pcall(require, module)

	local requireResult: RequireAttemptResult = {
		Success = success,
		Module = result,
	}

	if success and config.LOGGING.MODULE_NAME_ON_REQUIRE then
		print(`[{script.Name}] Required: {module.Name}`)
	end

	return requireResult
end

--[=[
	@priv 
]=]
function ImportLayer._invoke(self, import: any, methodName: string, allowPromise: boolean): Promise.TypedPromise<()>?
	if type(import) ~= "table" then
		return nil
	end

	local method = import[methodName]
	if type(method) ~= "function" then
		return nil
	end

	local success, result = pcall(function()
		return method(import)
	end)

	if not success then
		warn(`[BACKBONE] {tostring(import)}.{methodName} failed:\n{tostring(result)}`)
		return nil
	end

	if Promise.is(result) then
		if not allowPromise then
			warn(`[BACKBONE] {tostring(import)}.{methodName} returned a Promise but must be synchronous. Ignoring.`)
			return nil
		end
		return result
	end

	return nil
end

return ImportLayer
