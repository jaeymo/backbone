--!strict
--[=[
	PhysicsController

	Two jobs: configuring collision groups, and toggling physics (anchoring) on registered
	objects by distance, e.g. to put far-away props to sleep.

	Collision groups are configured with a matrix, either in config (applied on Awake) or at
	runtime with `:ApplyCollisionMatrix()`. Only declare the pairs that should collide: every
	other pair of different groups the matrix names is set non-collidable. A group's collision
	with itself, and groups the matrix doesn't name, are only changed if you declare them.
	Groups are registered for you.

	```lua
	Backbone:Configure({
		PHYSICS = {
			COLLISION_MATRIX = {
				Character = { Default = true, Debris = true },
				Debris = { Default = true, Debris = false },
				-- Debris <-> Debris is declared false, Character <-> Character keeps colliding
			},
		},
	})

	-- One-off changes
	PhysicsController:SetGroupsCollidable("Character", "Debris", false)
	```

	Physics objects anchor every BasePart under `source` while disabled:

	```lua
	local object = PhysicsController.newPhysicsObject(crate, true, function()
		return crate:GetPivot()
	end)
	PhysicsController:RegisterPhysicsObject(guid, object)

	PhysicsController:DeactivatePhysicsWithinRadius(500, Vector3.zero)
	object.PhysicsStateChanged:Connect(function(isEnabled) end)
	```
]=]
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
	Canonical key so matrix[A][B] and matrix[B][A] refer to the same pair
]=]
local function pairKey(a: string, b: string): string
	return if a <= b then `{a}|{b}` else `{b}|{a}`
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

--[=[
	Applies `matrix`: declared pairs are set as declared, and every undeclared pair of different
	groups the matrix names is set non-collidable. Undeclared self pairs (A <-> A) and groups
	the matrix doesn't name are left untouched.
]=]
function PhysicsController.ApplyCollisionMatrix(self: PhysicsController, matrix: CollisionMatrix)
	ValidateDisabledController("PHYSICS")

	local groups: { string } = {}
	local known: { [string]: boolean } = {}
	local declared: { [string]: boolean } = {}

	local function addGroup(name: string)
		if known[name] then
			return
		end

		known[name] = true
		table.insert(groups, name)
		ensureGroup(name)
	end

	for a, row in matrix do
		addGroup(a)

		for b, collidable in row do
			addGroup(b)

			local key = pairKey(a, b)
			local existing = declared[key]

			if existing ~= nil and existing ~= collidable then
				warn(`[BACKBONE] Collision matrix conflict for "{a}" <-> "{b}", defaulting to non-collidable`)
				declared[key] = false
			else
				declared[key] = collidable
			end
		end
	end

	for i, a in groups do
		-- Defaulting A <-> A too would break e.g. Default <-> Default just because Default was named
		local selfCollidable = declared[pairKey(a, a)]
		if selfCollidable ~= nil then
			PhysicsService:CollisionGroupSetCollidable(a, a, selfCollidable)
		end

		for j = i + 1, #groups do
			local b = groups[j]
			PhysicsService:CollisionGroupSetCollidable(a, b, declared[pairKey(a, b)] == true)
		end
	end
end

return PhysicsController
