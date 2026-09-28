--!strict
local root = script.Parent.Parent
local classes = root.Classes
local util = root.Util

local PhysicsObject = require(classes.Physics)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

--[=[
	@priv
]=]
local function isWithinRadius(position: Vector3, radius: number, origin: Vector3): boolean
	local offset = origin - position
	return offset:Dot(offset) < radius ^ 2
end

--[=[
	@module 
]=]
local PhysicsController = {
	_registry = {} :: { [string]: PhysicsObject.PhysicsObject },
}

export type PhysicsObject = Types.PhysicsObject

export type PhysicsController = Types.PhysicsController

function PhysicsController.newPhysicsObject(
	source: Instance,
	initialState: boolean,
	getCFrame: () -> CFrame
): PhysicsObject
	ValidateDisabledController("PHYSICS")

	return PhysicsObject.new(source, initialState, getCFrame) :: PhysicsObject
end

function PhysicsController.RegisterPhysicsObject(self: PhysicsController, guid: string, object: PhysicsObject)
	ValidateDisabledController("PHYSICS")

	if self._registry[guid] then
		return
	end

	self._registry[guid] = object
end

function PhysicsController.UnregisterPhysicsObject(self: PhysicsController, guid: string)
	ValidateDisabledController("PHYSICS")

	if not self._registry[guid] then
		return
	end

	self._registry[guid] = nil
end

function PhysicsController.ForAllPhysicsObjects(
	self: PhysicsController,
	callback: (object: PhysicsObject) -> (),
	async: boolean?
)
	ValidateDisabledController("PHYSICS")

	for _, v in self._registry do
		if async then
			task.spawn(callback, v)
		else
			callback(v)
		end
	end
end

function PhysicsController.ForAllInRadius(
	self: PhysicsController,
	radius: number,
	origin: Vector3,
	callback: (object: PhysicsObject) -> (),
	async: boolean?
)
	ValidateDisabledController("PHYSICS")

	for _, physicsObject: PhysicsObject in self._registry do
		if isWithinRadius(physicsObject.GetCFrame().Position, radius, origin) then
			if async then
				task.spawn(callback, physicsObject)
			else
				callback(physicsObject)
			end
		end
	end
end

function PhysicsController.ActivatePhysicsWithinRadius(self: PhysicsController, radius: number, origin: Vector3)
	ValidateDisabledController("PHYSICS")

	self:ForAllInRadius(radius, origin, function(physicsObject: PhysicsObject)
		physicsObject:EnablePhysics()
	end, false)
end

function PhysicsController.DeactivatePhysicsWithinRadius(self: PhysicsController, radius: number, origin: Vector3)
	ValidateDisabledController("PHYSICS")

	self:ForAllInRadius(radius, origin, function(physicsObject: PhysicsObject)
		physicsObject:DisablePhysics()
	end, false)
end

return PhysicsController
