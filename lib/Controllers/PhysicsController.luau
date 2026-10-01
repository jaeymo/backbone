--!strict
local PhysicsService = game:GetService("PhysicsService")

local root = script.Parent.Parent
local classes = root.Classes
local util = root.Util

local Config = require(root.Core.Config)
local PhysicsObject = require(classes.Physics)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local CONSTANTS = require(root.Constants)

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

(PhysicsController :: any)[CONSTANTS.AWAKE_METHOD] = function(self: PhysicsController)
	local physicsConfig = Config.get().PHYSICS
	local matrix = physicsConfig.COLLISION_MATRIX

	if next(matrix :: any) then
		self:ApplyCollisionMatrix(matrix)
	end
end

--[=[
	@priv
]=]
local function ensureGroup(name: string)
	if PhysicsService:IsCollisionGroupRegistered(name) then
		return
	end

	local ok, err = pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, name)
	if not ok then
		warn(`[BACKBONE] Failed to register collision group "{name}": {tostring(err)}`)
	end
end

export type PhysicsObject = Types.PhysicsObject

export type PhysicsController = Types.PhysicsController

export type CollisionMatrix = Types.CollisionMatrix

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

function PhysicsController.SetGroupsCollidable(self: PhysicsController, a: string, b: string, collidable: boolean)
	ValidateDisabledController("PHYSICS")

	ensureGroup(a)
	ensureGroup(b)
	PhysicsService:CollisionGroupSetCollidable(a, b, collidable)
end

function PhysicsController.ApplyCollisionMatrix(self: PhysicsController, matrix: CollisionMatrix)
	ValidateDisabledController("PHYSICS")

	local resolved: { [string]: boolean } = {}
	local endpoints: { [string]: { string } } = {}

	for a, row in matrix do
		ensureGroup(a)

		for b, collidable in row do
			ensureGroup(b)

			-- canonical ordering so matrix[A][B] and matrix[B][A] hit the same key
			local first, second = if a <= b then a else b, if a <= b then b else a
			local key = `{first}|{second}`

			local existing = resolved[key]
			if existing ~= nil and existing ~= collidable then
				warn(`[BACKBONE] Collision matrix conflict for "{first}" <-> "{second}", defaulting to non-collidable`)
				resolved[key] = false
			else
				resolved[key] = collidable
			end

			endpoints[key] = { first, second }
		end
	end

	for key, collidable in resolved do
		local pair = endpoints[key]
		PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], collidable)
	end
end

return PhysicsController
