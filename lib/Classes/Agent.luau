--!strict
local root = script.Parent.Parent
local packages = root.Parent

local Config = require(root.Core.Config)
local Janitor = require(packages.Janitor)
local Types = require(root.Types)

local Agent = {}
Agent.__index = Agent

export type Agent = Types.Agent

function Agent.new(entity: Types.Entity, model: Model, root: BasePart, humanoid: Humanoid, animator: Animator): Agent
	local config = Config.get()

	local subJanitor = Janitor.new()
	entity.Janitor:Add(subJanitor, "Destroy")

	model:AddTag(config.TAGS.ACTOR)

	return setmetatable({
		Entity = entity,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Animator = animator,
		Janitor = subJanitor,
	}, Agent) :: Agent
end

function Agent.GetModel(self: Agent): Model
	return self.Model
end

function Agent.GetRoot(self: Agent): BasePart
	return self.Root
end

function Agent.GetHumanoid(self: Agent): Humanoid
	return self.Humanoid
end

function Agent.GetAnimator(self: Agent): Animator
	return self.Animator
end

function Agent.Destroy(self: Agent)
	local config = Config.get()
	self:GetModel():RemoveTag(config.TAGS.ACTOR)
	self.Janitor:Cleanup()
end

return Agent
