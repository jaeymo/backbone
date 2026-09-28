--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent
local util = root.Util
local packages = root.Parent

local CharacterClass = require(root.Classes.Character)
local Config = require(root.Core.Config)
local EntityController = require(root.Controllers.EntityController)
local Signal = require(packages.Signal)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local IS_CLIENT = RunService:IsClient()
local IS_SERVER = RunService:IsServer()

local CharacterController = {
	CharacterAdded = Signal.new() :: Signal.Signal<Types.Character>,
	CharacterRemoved = Signal.new() :: Signal.Signal<Types.Character>,

	LocalCharacter = (nil :: any) :: Character?,
	_playerToCharacter = {} :: { [Player]: Character },
}

--[=[
	@priv
]=]
local function getPlayerFromCharacter(character: Character): Player?
	return Players:GetPlayerFromCharacter(character.Agent:GetModel())
end

--[=[
	@priv 
]=]
local function getVariables(characterModel: Model): Types.CharacterRuntimeBuildDefinition?
	local humanoid = characterModel:WaitForChild("Humanoid") :: Humanoid?
	local animator = humanoid and humanoid:WaitForChild("Animator") :: Animator?
	local root = characterModel:WaitForChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not animator or not root then
		warn(
			`[{script.Name}] Character "{characterModel.Name}" is missing one of the following: Humanoid: [{humanoid}] Animator: [{animator}] Root: [{root}]`
		)
		return nil
	end

	return {
		Character = characterModel,
		Humanoid = humanoid,
		Root = root,
		Animator = animator,
	}
end

--[=[
	Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function CharacterController.OnAwake(self: CharacterController)
	ValidateDisabledController("CHARACTER")

	local config = Config.get()
	self:_bindCharacterEventsToEntity()

	EntityController:RegisterType("Character", {
		Class = CharacterClass,
		Definitions = nil, -- We don't need definitions for characters
		BeforeSpawn = function(registrationContext: Types.RegistrationContext)
			if IS_CLIENT then
				local timeout = config.CHARACTER.CLIENT_CHARACTER_MODEL_TIMEOUT
				local object: Character = registrationContext.Object

				local characterModel: Model?
				local start = os.clock()

				repeat
					task.wait()

					characterModel = registrationContext.Entity.Model:FindFirstChildOfClass("Model")

					if os.clock() - start >= timeout then
						warn(`[{script.Name}] It took longer than {timeout}s to load the character under the entity.`)
						break
					end
				until characterModel

				if not characterModel then
					return
				end

				local runtimeDefinition = getVariables(characterModel)
				if not runtimeDefinition then
					return
				end

				object:Init(runtimeDefinition)
			end
		end,
	})
end

--[=[
    Called after all modules have finished initializing. Begin runtime behavior here.
]=]
function CharacterController.OnStart(self: CharacterController)
	ValidateDisabledController("CHARACTER")

	self:_bindPlayers()
end

export type Character = Types.Character

export type CharacterController = typeof(CharacterController)

--[=[
	Returns the currently tracked `Character` for `player`, if one exists.
]=]
function CharacterController.GetCharacterForPlayer(self: CharacterController, player: Player): Character?
	return self._playerToCharacter[player]
end

--[=[
	Fires `callback` whenever `player`'s character is added — immediately if a
	`Character` is already tracked for them, and again on every future respawn.
]=]
function CharacterController.BindAddedToPlayer(
	self: CharacterController,
	player: Player,
	callback: (character: Character) -> ()
): Signal.Connection
	local existing = self._playerToCharacter[player]
	if existing then
		task.spawn(callback, existing)
	end

	return self.CharacterAdded:Connect(function(character: Character)
		if getPlayerFromCharacter(character) == player then
			callback(character)
		end
	end)
end

--[=[
	Fires `callback` whenever `player`'s character is removed
]=]
function CharacterController.BindRemovingToPlayer(
	self: CharacterController,
	player: Player,
	callback: (character: Character) -> ()
)
	return self.CharacterRemoved:Connect(function(character: Character)
		if getPlayerFromCharacter(character) == player then
			callback(character)
		end
	end)
end

--[=[
    @priv  
]=]
function CharacterController._onCharacterAdded(self: CharacterController, character: Model, isLocal: boolean?)
	local config = Config.get()

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local runtimeDefinition = getVariables(character)
	if not runtimeDefinition then
		return
	end

	if IS_SERVER then
		local objects = EntityController:ConstructBlank({
			Type = "Character",
			Id = tostring(player.UserId),
		})

		local entity, characterObject: Character? = objects and objects.Entity, objects and objects.Object
		if not entity or not characterObject then
			warn(`[{script.Name}] Failed to construct "Entity" or "Character"`)
			return
		end

		-- Initialize the Character before entity registration so the Actor is prepared
		characterObject:Init(runtimeDefinition)

		-- We must setup the primary part of both the entity container and the character container
		entity.Model.PrimaryPart = runtimeDefinition.Root
		characterObject.Agent:GetModel().PrimaryPart = runtimeDefinition.Root

		character.Parent = characterObject.Entity.Model

		EntityController:RegisterExisting({
			Type = characterObject.Entity.Type,
			Object = characterObject,
			Entity = entity,
			Parent = workspace,
			-- Parent = self.CharacterContainer,
		})

		character:AddTag(config.TAGS.CHARACTER)
	end

	if config.LOGGING.CHARACTER then
		print(`[{script.Name}] Character added: `, character)
	end
end

--[=[
    @priv
]=]
function CharacterController._onCharacterRemoving(self: CharacterController, character: Model, isLocal: boolean?)
	local config = Config.get()

	if isLocal and self.LocalCharacter and self.LocalCharacter.Agent:GetModel() == character then
		self.LocalCharacter = nil
	end

	if config.LOGGING.CHARACTER then
		print(`[{script.Name}] Character removing: `, character)
	end
end

--[=[
	@priv 
]=]
function CharacterController._bindCharacterEventsToEntity(self: CharacterController)
	EntityController.EntitySpawned:Connect(function(entity: EntityController.Entity, character: Character)
		if entity.Type ~= "Character" then
			return
		end

		if
			IS_CLIENT
			and Players.LocalPlayer.Character
			and Players.LocalPlayer.Character == character.Agent:GetModel()
		then
			self.LocalCharacter = character
			character.IsLocal = true
		end

		local player = getPlayerFromCharacter(character)
		if player then
			self._playerToCharacter[player] = character
		end

		self.CharacterAdded:Fire(character)
	end)

	EntityController.EntityDestroyed:Connect(function(entity: EntityController.Entity, character: Character)
		if entity.Type == "Character" then
			local player = getPlayerFromCharacter(character)
			if player and self._playerToCharacter[player] == character then
				self._playerToCharacter[player] = nil
			end

			self.CharacterRemoved:Fire(character)
		end
	end)
end

--[=[
	@priv 
]=]
function CharacterController._bindPlayers(self: CharacterController)
	ValidateDisabledController("CHARACTER")

	local config = Config.get()

	if IS_CLIENT then
		local player = Players.LocalPlayer

		for _, v in CollectionService:GetTagged(config.TAGS.CHARACTER) do
			if v:IsA("Model") then
				local isLocal = player.Character and player.Character == v
				self:_onCharacterAdded(v, isLocal)
			end
		end

		CollectionService:GetInstanceAddedSignal(config.TAGS.CHARACTER):Connect(function(character: Instance)
			if character:IsA("Model") then
				local isLocal = player.Character and player.Character == character
				self:_onCharacterAdded(character, isLocal)
			end
		end)

		CollectionService:GetInstanceRemovedSignal(config.TAGS.CHARACTER):Connect(function(character: Instance)
			if character:IsA("Model") then
				local isLocal = player.Character and player.Character == character
				self:_onCharacterRemoving(character, isLocal)
			end
		end)

		EntityController.EntitySpawned:Connect(function(entity: EntityController.Entity, character: Character)
			if entity.Type == "Character" and player.Character and character.Agent:GetModel() == player.Character then
				self.LocalCharacter = character
			end
		end)
	else
		Players.PlayerAdded:Connect(function(player: Player)
			if player.Character then
				task.spawn(function()
					self:_onCharacterAdded(player.Character, false)
				end)
			end

			player.CharacterAdded:Connect(function(character: Model)
				self:_onCharacterAdded(character, false)
			end)
		end)

		Players.PlayerRemoving:Connect(function(player: Player)
			if player.Character then
				self:_onCharacterRemoving(player.Character, false)
			end
		end)
	end
end

return CharacterController
