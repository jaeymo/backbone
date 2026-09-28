--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent

local Agent = require(root.Classes.Agent)
local Config = require(root.Core.Config)
local Types = require(root.Types)

local IS_SERVER = RunService:IsServer()

local Character = {}
Character.__index = Character

export type Character = Types.Character

function Character.new(entity: Types.Entity): Character
	return setmetatable({
		Entity = entity,
		IsLocal = false,
	}, Character) :: Character
end

function Character.Init(self: Character, runtimeDefinition: Types.CharacterRuntimeBuildDefinition)
	local config = Config.get()

	self.Player = Players:GetPlayerFromCharacter(runtimeDefinition.Character) :: Player

	self.Agent = Agent.new(
		self.Entity,
		runtimeDefinition.Character,
		runtimeDefinition.Root,
		runtimeDefinition.Humanoid,
		runtimeDefinition.Animator
	)

	if IS_SERVER and config.CHARACTER.BIND_TO_COLLISION_GROUP then
		self:_watchCollisionGroup()
	end
end

function Character.Destroy(self: Character)
	self.Agent:Destroy()
	self.Entity:Destroy()
end

--[=[
	@priv
]=]
function Character._watchCollisionGroup(self: Character)
	local config = Config.get()

	local function setCollisionGroup(part: BasePart)
		local isRoot = part.Name == "HumanoidRootPart"
		part.CollisionGroup = isRoot and config.COLLISION_GROUPS.CHARACTER_ROOT or config.COLLISION_GROUPS.CHARACTER
	end

	for _, v in self.Agent:GetModel():GetDescendants() do
		if v:IsA("BasePart") then
			setCollisionGroup(v)
		end
	end

	self.Entity.Janitor:Add(self.Agent:GetModel().DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			setCollisionGroup(descendant)
		end
	end))
end

return Character
