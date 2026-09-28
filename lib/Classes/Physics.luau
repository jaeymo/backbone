--!strict
local root = script.Parent.Parent
local packages = root.Parent

local Signal = require(packages.Signal)
local Types = require(root.Types)

local PhysicsObject = {}
PhysicsObject.__index = PhysicsObject

export type PhysicsObject = Types.PhysicsObject

function PhysicsObject.new(source: Instance, initialState: boolean, getCFrame: () -> CFrame): PhysicsObject
	local self = setmetatable({
		Source = source,
		PhysicsStateChanged = Signal.new(),
		GetCFrame = getCFrame,
		_enabled = initialState,
	}, PhysicsObject) :: PhysicsObject

	self:SetPhysicsStateEnabled(initialState)

	return self
end

function PhysicsObject.IsPhysicsEnabled(self: PhysicsObject): boolean
	return self._enabled
end

function PhysicsObject.SetPhysicsStateEnabled(self: PhysicsObject, isEnabled: boolean)
	if isEnabled then
		self:EnablePhysics()
	else
		self:DisablePhysics()
	end
end

function PhysicsObject.EnablePhysics(self: PhysicsObject)
	if self:IsPhysicsEnabled() then
		return
	end

	self._enabled = true

	self:_forEveryBasePart(function(part: BasePart)
		part.Anchored = false
	end)

	self.PhysicsStateChanged:Fire(true)
end

function PhysicsObject.DisablePhysics(self: PhysicsObject)
	if not self:IsPhysicsEnabled() then
		return
	end

	self._enabled = false

	self:_forEveryBasePart(function(part: BasePart)
		part.Anchored = true
	end)

	self.PhysicsStateChanged:Fire(false)
end

function PhysicsObject.Destroy(self: PhysicsObject)
	self.PhysicsStateChanged:Destroy()
end

--[=[
    @priv
]=]
function PhysicsObject._forEveryBasePart(self: PhysicsObject, callback: (BasePart) -> ())
	for _, v in self.Source:GetDescendants() do
		if v:IsA("BasePart") then
			callback(v)
		end
	end
end

return PhysicsObject
