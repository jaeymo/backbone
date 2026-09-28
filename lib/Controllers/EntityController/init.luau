--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent
local util = root.Util
local packages = root.Parent

-- So we don't have to constantly call `Instance.new("Model")`
local MODEL_PROXY = Instance.new("Model")

-- ...Is Client?
local IS_CLIENT = RunService:IsClient()

-- ...Is Server?
local IS_SERVER = RunService:IsServer()

local Classy = require(packages.Classy)
local Config = require(root.Core.Config)
local EntityClass = require(root.Classes.Entity)
local Signal = require(packages.Signal)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local EntityController = {
	EntityConstructed = Signal.new() :: Signal.Signal<Types.Entity, any?>,
	EntityDestroyed = Signal.new() :: Signal.Signal<Types.Entity, any?>,
	EntitySpawned = Signal.new() :: Signal.Signal<Types.Entity, any?>,

	Registry = require(script.Registry),
	_proxies = (nil :: any) :: Folder, -- set in OnAwake, well exist in any OnInit or OnStart call
}

--[=[
    Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function EntityController.OnAwake(self: EntityController)
	ValidateDisabledController("ENTITY")

	local config = Config.get()
	local proxies = ReplicatedStorage:FindFirstChild(config.ENTITY.PROXY_FOLDER_NAME) :: Folder

	if not proxies then
		proxies = Instance.new("Folder")
		proxies.Name = config.ENTITY.PROXY_FOLDER_NAME
		proxies.Parent = ReplicatedStorage
	end

	self._proxies = proxies
end

--[=[
    Called after all modules have finished initializing. Begin runtime behavior here.
]=]
function EntityController.OnStart(self: EntityController)
	ValidateDisabledController("ENTITY")

	self:_watchWorldLifecycle()
end

export type Entity = Types.Entity

export type EntityController = typeof(EntityController)

export type RegistrationContext = GenericSpawnContext<CFrame?>

export type SpawnContext = GenericSpawnContext<CFrame>

export type ConstructionContext = Types.EntityConstructionContext

export type GenericSpawnContext<T> = Types.GenericSpawnContext<T>

--[=[
    @priv  
]=]
local function createProxy(name: string, guid: string): Model
	local proxy = MODEL_PROXY:Clone()
	proxy.Name = `{name}_{guid}`

	return proxy
end

function EntityController.RegisterType(self: EntityController, type: string, registration: Types.EntityTypeRegistration)
	self.Registry:RegisterType(type, registration)
end

function EntityController.GetRegisteredType(self: EntityController, type: string): Types.EntityTypeRegistration?
	return self.Registry.fromType(type)
end

function EntityController.ForAllFromType(
	self: EntityController,
	type: string,
	callback: (Entity, any?) -> (),
	async: boolean?
)
	for _, entity in self.Registry.EntityTypeObjects do
		if entity.Type ~= type then
			continue
		end

		local object = self:GetObjectByGuid(entity.Guid)
		if not object then
			warn(`[{script.Name}] Failed to get object with guid: {entity.Guid}`)
			continue
		end

		if async then
			task.spawn(callback, entity, object)
		else
			callback(entity, object)
		end
	end
end

function EntityController.ConstructBlank(
	self: EntityController,
	context: ConstructionContext
): {
	Entity: Entity,
	Object: any,
}?
	ValidateDisabledController("ENTITY")

	local config = Config.get()

	local typeRegistration = self.Registry.fromType(context.Type)
	if not typeRegistration then
		warn(`[{script.Name}] Failed to get type registration for: {context.Type}`)
		return nil
	end

	if not typeRegistration.Class then
		warn(`[{script.Name}] EntityType "{context.Type}" is missing a Class to construct objects from!`)
		return nil
	end

	local guid = HttpService:GenerateGUID(false)
	local model = createProxy(context.Id, guid)

	local entity = EntityClass.new(context.Id, guid, context.Type, model)

	-- Verifying context
	if context.Definition then
		for _, v in context.Definition do
			if typeof(v) == "Instance" then
				warn(`[{script.Name}] Cannot pass an instance in an entity runtime definition: context -> {context}`)
				return nil
			end
		end

		model:SetAttribute(config.ATTRIBUTES.ENTITY_DEFINITION, HttpService:JSONEncode(context.Definition))
	end

	model:SetAttribute(config.ATTRIBUTES.ENTITY_ID, context.Id)
	model:SetAttribute(config.ATTRIBUTES.ENTITY_GUID, guid)
	model:SetAttribute(config.ATTRIBUTES.ENTITY_TYPE, context.Type)

	local object = typeRegistration.Class.new(entity, context.Definition)

	self.Registry:RegisterEntity(guid, entity)
	self.Registry:RegisterObject(guid, object)

	model.Parent = self._proxies
	model:AddTag(config.TAGS.ENTITY)

	self.EntityConstructed:Fire(entity, object)

	if config.LOGGING.ENTITY then
		print(`[{script.Name}] Entity entered lifecycle phase "Constructed" with object: `, object)
	end

	return {
		Entity = entity,
		Object = object,
	}
end

function EntityController.ConstructFromExisting(
	self: EntityController,
	model: Model
): {
	Entity: Entity,
	Object: any,
}?
	ValidateDisabledController("ENTITY")

	local config = Config.get()

	local id, guid, entityType, definition =
		model:GetAttribute(config.ATTRIBUTES.ENTITY_ID) :: string?,
		model:GetAttribute(config.ATTRIBUTES.ENTITY_GUID) :: string?,
		model:GetAttribute(config.ATTRIBUTES.ENTITY_TYPE) :: string?,
		model:GetAttribute(config.ATTRIBUTES.ENTITY_DEFINITION) :: any?

	if definition then
		definition = HttpService:JSONDecode(definition)
	end

	if not id or not guid or not entityType then
		warn(
			`[{script.Name}] Entity is not initialized, missing either "id", "guid", or "entityType" attribute: {model} + {id}_{guid}_{entityType}`
		)
		return nil
	end

	local typeRegistration = self.Registry.fromType(entityType)
	if not typeRegistration then
		warn(`[{script.Name}] Failed to get type registration for: {entityType}`)
		return nil
	end

	local entity = EntityClass.new(id, guid, entityType, model)
	local object = typeRegistration.Class.new(entity, definition)

	-- Write to nil because we don't need the client storing anymore data than it needs to
	if definition then
		model:SetAttribute(config.ATTRIBUTES.ENTITY_DEFINITION, nil)
	end

	self.Registry:RegisterEntity(guid, entity)
	self.Registry:RegisterObject(guid, object)

	self.EntityConstructed:Fire(entity, object)

	if config.LOGGING.ENTITY then
		print(`[{script.Name}] Entity entered lifecycle phase "Constructed" with object: `, object)
	end

	return {
		Entity = entity,
		Object = object,
	}
end

function EntityController.GetEntityByGuid(self: EntityController, guid: string): Entity?
	return self.Registry.fromGuid(guid, "Entity")
end

function EntityController.GetEntityByModel(self: EntityController, model: Model): Entity?
	return self.Registry.fromModel(model, "Entity")
end

function EntityController.GetObjectByGuid(self: EntityController, guid: string): Entity?
	return self.Registry.fromGuid(guid, "Object")
end

function EntityController.GetObjectByModel(self: EntityController, model: Model): Entity?
	return self.Registry.fromModel(model, "Object")
end

--[=[
	**WARNING:**
	To spawn something like an item or mob, use their respective service/controller.

	Example Usage:

	```lua
	EntityService:SpawnAt({
		Entity = someEntity,
		Object = someMob,
		CFrame = CFrame.new(0, 0, 0),
		Parent = workspace.someFolder,
	})
	```
]=]
function EntityController.SpawnAt(self: EntityController, spawnContext: SpawnContext)
	self:_register({
		Type = spawnContext.Type,
		CFrame = spawnContext.CFrame,
		Entity = spawnContext.Entity,
		Parent = spawnContext.Parent,
		Object = spawnContext.Object,
	})
end

function EntityController.RegisterExisting(self: EntityController, registrationContext: RegistrationContext)
	self:_register({
		Type = registrationContext.Type,
		Entity = registrationContext.Entity,
		Object = registrationContext.Object,
		Parent = registrationContext.Parent,
	})
end

--[=[
	@priv 
]=]
function EntityController._register(self: EntityController, context: RegistrationContext)
	ValidateDisabledController("ENTITY")

	local config = Config.get()
	local entity = context.Entity

	local registration = self.Registry.fromType(context.Type)
	if registration and registration.BeforeSpawn then
		registration.BeforeSpawn(context)
	end

	if context.CFrame then
		entity.Model:PivotTo(context.CFrame)
	end

	if context.Parent then
		entity.Model.Parent = context.Parent
	end

	if IS_SERVER then
		entity.Model:SetAttribute(config.ATTRIBUTES.ENTITY_SPAWN_TIME, workspace:GetServerTimeNow())
	end

	if config.LOGGING.ENTITY then
		print(`[{script.Name}] Entity entered lifecycle phase "Spawned" with object: `, context.Object)
	end

	self.EntitySpawned:Fire(entity, context.Object)
end

--[=[
	@priv
]=]
function EntityController._watchWorldLifecycle(self: EntityController)
	ValidateDisabledController("ENTITY")

	local config = Config.get()
	if IS_CLIENT then
		Classy.new(config.TAGS.ENTITY, function(instance, _)
			local result = self:ConstructFromExisting(instance :: Model)

			if result then
				self:RegisterExisting({
					Entity = result.Entity,
					Object = result.Object,
					Type = result.Entity.Type,
				})
			end

			return {
				Destroy = function()
					local s, e = pcall(function()
						if result and result.Object then
							result.Object:Destroy()
						end
					end)

					if not s then
						warn(e)
					end

					if not result or not result.Entity or not result.Object then
						warn(
							`[{script.Name}] Missing the "Entity" or "Object" from the entity construction result: `,
							result and result.Entity,
							result and result.Object
						)
						return
					end

					self.EntityDestroyed:Fire(result.Entity, result.Object)

					if config.LOGGING.ENTITY then
						print(`[{script.Name}] Entity entered lifecycle phase "Destroyed" with object: `, result.Object)
					end
				end,
			}
		end, {
			Nuke = false,
			Predicate = function(instance: Instance)
				local start = os.clock()

				while
					not instance:GetAttribute(config.ATTRIBUTES.ENTITY_ID)
					and not instance:GetAttribute(config.ATTRIBUTES.ENTITY_GUID)
				do
					if os.clock() - start > config.ENTITY.CLIENT_ENTITY_GUID_TIMEOUT then
						warn(`[{script.Name}] Client timed out when constructing entity [{instance:GetFullName()}]`)
						return false
					end

					task.wait()
				end

				return true
			end,
		}):Init()
	else
		Classy.new(config.TAGS.ENTITY, function(instance: Instance, _)
			local guid = instance:GetAttribute(config.ATTRIBUTES.ENTITY_GUID) :: string
			local type = instance:GetAttribute(config.ATTRIBUTES.ENTITY_TYPE) :: string

			local object = self.Registry.fromGuid(guid, "Object")
			local entity = self.Registry.fromGuid(guid, "Entity")

			if not entity then
				error(
					`[{script.Name} The object with an entity type of "{type}" does not have the "Entity" property pointing to the entity object`
				)
			end

			if not object then
				error(`[{script.Name}] Failed to get the object for entity type: "{type}"`)
			end

			return {
				Destroy = function()
					object:Destroy()

					self.Registry:UnregisterEntity(guid)
					self.Registry:UnregisterObject(guid)

					self.EntityDestroyed:Fire(entity, object)

					if config.LOGGING.ENTITY then
						print(`[{script.Name}] Entity entered lifecycle phase "Destroyed" with object: `, object)
					end
				end,
			}
		end, {
			Nuke = false,
			Predicate = function(instance: Instance)
				return instance:GetAttribute(config.ATTRIBUTES.ENTITY_GUID) ~= nil
			end,
		}):Init()
	end
end

return EntityController
