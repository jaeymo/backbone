--!strict
local root = script.Parent.Parent.Parent

local Config = require(root.Core.Config)
local Types = require(root.Types)

local Registry = {
	EntityTypes = {} :: { [string]: Types.EntityTypeRegistration },
	EntityTypeObjects = {} :: { [string]: any },
	Entities = {} :: { [string]: Types.Entity },
}

export type Registry = typeof(Registry)

function Registry.RegisterType(self: Registry, type: string, registration: Types.EntityTypeRegistration)
	self.EntityTypes[type] = registration
end

function Registry.RegisterObject(self: Registry, guid: string, object: any)
	self.EntityTypeObjects[guid] = object
end

function Registry.UnregisterObject(self: Registry, guid: string)
	self.EntityTypeObjects[guid] = nil
end

function Registry.RegisterEntity(self: Registry, guid: string, entity: Types.Entity)
	self.Entities[guid] = entity
end

function Registry.UnregisterEntity(self: Registry, guid: string)
	self.Entities[guid] = nil
end

function Registry.fromModel(model: Model, from: "Object" | "Entity"): Types.Entity?
	local config = Config.get()

	local guid = model:GetAttribute(config.ATTRIBUTES.ENTITY_GUID) :: string?
	if not guid then
		warn(`[{script.Name}] Failed to get guid for model: {model:GetFullName()}`)
		return nil
	end

	return Registry.fromGuid(guid, from)
end

function Registry.fromGuid(guid: string, from: "Object" | "Entity"): Types.Entity?
	local registry = from == "Object" and Registry.EntityTypeObjects or Registry.Entities
	return registry[guid]
end

function Registry.fromType(type: string): Types.EntityTypeRegistration?
	return Registry.EntityTypes[type]
end

return Registry
