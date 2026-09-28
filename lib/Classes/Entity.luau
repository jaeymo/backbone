--!strict
local root = script.Parent.Parent
local packages = root.Parent

local Janitor = require(packages.Janitor)
local Types = require(root.Types)

local Entity = {}
Entity.__index = Entity

export type Entity = Types.Entity

function Entity.new(id: string, guid: string, type: string, model: Model): Entity
	local janitor = Janitor.new()
	janitor:Add(model)

	return setmetatable({
		Model = model,
		Guid = guid,
		Type = type,
		Id = id,
		Janitor = janitor,
		_cleaned = false,
	}, Entity) :: Entity
end

-- Clean little shorthand
function Entity.Parent(self: Entity, parent: Instance?)
	self.Model.Parent = parent
end

function Entity.Destroy(self: Entity)
	if self._cleaned then
		return
	end

	self._cleaned = true

	self.Janitor:Cleanup()
	setmetatable(self, nil)
end

return Entity
