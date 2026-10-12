--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent

local Agent = require(root.Classes.Agent)
local AnimationController = require(root.Controllers.AnimationController)
local Config = require(root.Core.Config)
local Types = require(root.Types)

local IS_SERVER = RunService:IsServer()

local ROOT_SOUNDS = {
	["Climbing"] = true,
	["Died"] = true,
	["FreeFalling"] = true,
	["GettingUp"] = true,
	["Jumping"] = true,
	["Landing"] = true,
	["Running"] = true,
	["Splash"] = true,
	["Swimming"] = true,
}

--[=[
	@priv
]=]
local function countDictionary(dictionary: { [any]: any }): number
	local count = 0

	for _, v in dictionary do
		count += 1
	end

	return count
end

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

	local player = Players:GetPlayerFromCharacter(runtimeDefinition.Character)
	if not player then
		error(`[{script.Name}] Failed to get player from: {runtimeDefinition.Character}`)
	end

	self.Player = player

	self.Agent = Agent.new(
		self.Entity,
		runtimeDefinition.Character,
		runtimeDefinition.Root,
		runtimeDefinition.Humanoid,
		runtimeDefinition.Animator
	)

	if not IS_SERVER and config.CHARACTER.ANIMATION_GROUP_ID and config.CHARACTER.ANIMATION_GROUP_ID ~= "" then
		local animationComponent =
			AnimationController.new(config.CHARACTER.ANIMATION_GROUP_ID, self.Agent:GetAnimator())

		self.Animation = animationComponent
	end

	if IS_SERVER and config.CHARACTER.BIND_TO_COLLISION_GROUP then
		self:_watchCollisionGroup()
	end

	if config.CHARACTER.DESTROY_ROOT_SOUNDS then
		self:_destroyRootSounds()
	end
end

function Character.Destroy(self: Character)
	if self.Animation then
		self.Animation:Destroy()
	end

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

function Character._destroyRootSounds(self: Character)
	local marked = {} :: { [string]: boolean }
	local cleaned = false

	local function handleDescendant(descendant: Instance)
		if descendant:IsA("Sound") and ROOT_SOUNDS[descendant.Name] then
			descendant:Destroy()
			marked[descendant.Name] = true

			local markedLength, rootSoundsLength = countDictionary(marked), countDictionary(ROOT_SOUNDS)
			if markedLength >= rootSoundsLength then
				cleaned = true
				self.Agent.Janitor:Remove("DestroyRootSounds")
			end
		end
	end

	for _, v in self.Agent:GetRoot():GetDescendants() do
		handleDescendant(v)
	end

	if cleaned then
		return
	end

	self.Agent.Janitor:Add(
		self.Agent:GetRoot().DescendantAdded:Connect(function(descendant: Instance)
			handleDescendant(descendant)
		end),
		nil,
		"DestroyRootSounds"
	)
end

return Character
