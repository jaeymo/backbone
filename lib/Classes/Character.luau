--!strict
local RunService = game:GetService("RunService")

local root = script.Parent.Parent
local packages = root.Parent

local AnimationController = require(root.Controllers.AnimationController)
local Config = require(root.Core.Config)
local Janitor = require(packages.Janitor)
local Types = require(root.Types)

local IS_CLIENT = RunService:IsClient()
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

-- Members removed in 0.2.0. Reading one errors with a pointer to its replacement instead of silently returning nil
local REMOVED_MEMBERS: { [string]: string } = {
	Agent = "Agent was merged into CharacterObject; use character.Model, .Humanoid, .Root, .Animator and .Janitor",
	Entity = "CharacterObject is no longer an Entity; see CharacterController's docs for integrating your own Entity system",
	Init = "CharacterObjects are created and initialized by CharacterController",
}

export type CharacterObject = Types.CharacterObject

export type CharacterParts = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Animator: Animator,
}

--[=[
	@priv
]=]
local function countDictionary(dictionary: { [any]: any }): number
	local count = 0

	for _ in dictionary do
		count += 1
	end

	return count
end

local Character = {}

Character.__index = function(_: CharacterObject, key: string): any
	local member = (Character :: any)[key]
	if member ~= nil then
		return member
	end

	local hint = REMOVED_MEMBERS[key]
	if hint then
		error(`[BACKBONE] CharacterObject.{key} was removed: {hint}`, 2)
	end

	return nil
end

function Character.new(player: Player, parts: CharacterParts, isLocal: boolean): CharacterObject
	local config = Config.get()

	local self = setmetatable({
		Player = player,
		Model = parts.Model,
		Humanoid = parts.Humanoid,
		Root = parts.Root,
		Animator = parts.Animator,
		Animation = nil,
		IsLocal = isLocal,
		Janitor = Janitor.new(),
		_destroyed = false,
	}, Character) :: any

	local groupId = config.CHARACTER.ANIMATION_GROUP_ID

	-- Remote characters animate from their owner's client, so only the local character needs an animation group
	if IS_CLIENT and isLocal and config.ENABLED_CONTROLLERS.ANIMATION and groupId ~= "" then
		-- A group still bound to a previous life's animator can't be rebound, so replace it
		local existing = AnimationController.Objects[groupId]
		if existing and existing.Animator ~= nil and existing.Animator ~= parts.Animator then
			AnimationController:Destroy(groupId)
		end

		self.Animation = AnimationController.new(groupId, parts.Animator)
	end

	if IS_SERVER and config.CHARACTER.BIND_TO_COLLISION_GROUP then
		self:_watchCollisionGroup()
	end

	if config.CHARACTER.DESTROY_ROOT_SOUNDS then
		self:_destroyRootSounds()
	end

	return self :: CharacterObject
end

--[=[
	Cleans up everything tied to this character's lifetime, including `Janitor`.
	CharacterController calls this when the character is removed; you don't need to.
	The Roblox Model is left alone since Roblox owns its lifetime.
]=]
function Character.Destroy(self: CharacterObject)
	if self._destroyed then
		return
	end

	self._destroyed = true

	local animation = self.Animation
	if animation and AnimationController.Objects[animation.GroupId] == animation then
		AnimationController:Destroy(animation.GroupId)
	end

	self.Janitor:Destroy()
end

--[=[
	@priv
]=]
function Character._watchCollisionGroup(self: CharacterObject)
	local config = Config.get()

	local function setCollisionGroup(part: BasePart)
		local isRoot = part.Name == "HumanoidRootPart"
		part.CollisionGroup = isRoot and config.COLLISION_GROUPS.CHARACTER_ROOT or config.COLLISION_GROUPS.CHARACTER
	end

	for _, v in self.Model:GetDescendants() do
		if v:IsA("BasePart") then
			setCollisionGroup(v)
		end
	end

	self.Janitor:Add(self.Model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			setCollisionGroup(descendant)
		end
	end))
end

--[=[
	@priv
]=]
function Character._destroyRootSounds(self: CharacterObject)
	local marked = {} :: { [string]: boolean }
	local cleaned = false

	local function handleDescendant(descendant: Instance)
		if descendant:IsA("Sound") and ROOT_SOUNDS[descendant.Name] then
			descendant:Destroy()
			marked[descendant.Name] = true

			if countDictionary(marked) >= countDictionary(ROOT_SOUNDS) then
				cleaned = true
				self.Janitor:Remove("DestroyRootSounds")
			end
		end
	end

	for _, v in self.Root:GetDescendants() do
		handleDescendant(v)
	end

	if cleaned then
		return
	end

	self.Janitor:Add(self.Root.DescendantAdded:Connect(handleDescendant), nil, "DestroyRootSounds")
end

return Character
