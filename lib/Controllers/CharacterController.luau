--!strict
--[=[
	CharacterController

	Tracks every player's character on both the server and the client, and wraps each one in a
	`CharacterObject`: a typed handle to the Roblox character `Model` and its essential parts.

	```lua
	character.Player     -- Player
	character.Model      -- the Roblox character Model (what `player.Character` points to)
	character.Humanoid   -- Humanoid
	character.Root       -- HumanoidRootPart
	character.Animator   -- Animator
	character.Animation  -- AnimatorClass? (local character only, see CHARACTER.ANIMATION_GROUP_ID)
	character.IsLocal    -- true for the local player's character on the client
	character.Janitor    -- cleaned up when this character is removed
	```

	A `CharacterObject` lives for one life. Respawning creates a new one, so don't hold on to it
	across respawns. Attach per-life work to `character.Janitor` instead and it cleans itself up.

	Lifecycle:
	- `CharacterAdded` fires once the character's Humanoid, HumanoidRootPart and Animator exist
	  (waiting at most `CHARACTER.LOAD_TIMEOUT` seconds).
	- `CharacterRemoved` fires when Roblox removes the Model (respawn or leaving), not on death.
	  Use `character.Humanoid.Died` for death. Fields are still readable during this signal;
	  the object is destroyed right after.
	- The `LocalCharacter*` signals fire on the client for the local player's character only.

	Getting the local character (client only):

	```lua
	-- Right now, or nil if it hasn't spawned yet (or is between lives)
	local character = CharacterController:GetLocalCharacter()

	-- Waits for it if needed. Returns a Promise
	CharacterController:GetLocalCharacterAsync():andThen(function(character)
		character.Humanoid.WalkSpeed = 24
	end)

	-- Or yield the current thread
	local character = CharacterController:GetLocalCharacterAsync():expect()
	```

	Running something for every life:

	```lua
	-- Fires right away for the current character (if any), then again on every respawn
	CharacterController:BindAddedToPlayer(Players.LocalPlayer, function(character)
		character.Janitor:Add(character.Humanoid.Died:Connect(function()
			print("died")
		end))
	end)

	-- Server: every player's character
	CharacterController.CharacterAdded:Connect(function(character)
		print(`{character.Player.Name} spawned`)
	end)

	-- Hit detection: resolve a part back to its character
	local hitCharacter = CharacterController:GetCharacterFromInstance(raycastResult.Instance)
	```

	Integrating your own Entity system: CharacterController doesn't depend on EntityController.
	Wrap characters yourself and tie the wrapper to the character's lifetime.

	```lua
	CharacterController.CharacterAdded:Connect(function(character)
		local entity = MyEntities.fromCharacter(character)
		character.Janitor:Add(entity, "Destroy")
	end)
	```
]=]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local root = script.Parent.Parent
local util = root.Util
local packages = root.Parent

local CharacterClass = require(root.Classes.Character)
local Config = require(root.Core.Config)
local Janitor = require(packages.Janitor)
local Promise = require(packages.Promise)
local Signal = require(packages.Signal)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local IS_CLIENT = RunService:IsClient()
local IS_SERVER = RunService:IsServer()

-- Members renamed in 0.2.0. They keep working, but warn once
local RENAMED_MEMBERS: { [string]: string } = {
	LocalCharacter = "LocalCharacterObject",
	BindRemovingToPlayer = "BindRemovedToPlayer",
}

export type CharacterObject = Types.CharacterObject

type CharacterParts = CharacterClass.CharacterParts

local CharacterController = {
	CharacterAdded = Signal.new() :: Signal.Signal<CharacterObject>,
	CharacterRemoved = Signal.new() :: Signal.Signal<CharacterObject>,
	LocalCharacterAdded = Signal.new() :: Signal.Signal<CharacterObject>,
	LocalCharacterRemoved = Signal.new() :: Signal.Signal<CharacterObject>,

	LocalCharacterObject = nil :: CharacterObject?,

	_characters = {} :: { [Player]: CharacterObject },
	_playerJanitors = {} :: { [Player]: Janitor.Janitor },
}

export type CharacterController = typeof(CharacterController)

do
	local warned: { [string]: boolean } = {}

	setmetatable(CharacterController :: any, {
		__index = function(self: any, key: string): any
			local replacement = RENAMED_MEMBERS[key]
			if not replacement then
				return nil
			end

			if not warned[key] then
				warned[key] = true
				local traceback = debug.traceback("", 2)
				warn(
					`[BACKBONE] CharacterController.{key} is deprecated, use CharacterController.{replacement} instead.{traceback}`
				)
			end

			return rawget(self, replacement)
		end,
	})
end

--[=[
	@priv
	Waits for the parts every CharacterObject needs, sharing one deadline between them.
]=]
local function waitForParts(model: Model, timeout: number): (CharacterParts?, string?)
	local deadline = os.clock() + timeout

	local function waitFor(parent: Instance, name: string): Instance?
		local child = parent:FindFirstChild(name)
		local remaining = deadline - os.clock()

		if child or remaining <= 0 then
			return child
		end

		return parent:WaitForChild(name, remaining)
	end

	local humanoid = waitFor(model, "Humanoid")
	local rootPart = waitFor(model, "HumanoidRootPart")
	local animator = if humanoid then waitFor(humanoid, "Animator") else nil

	if
		humanoid
		and humanoid:IsA("Humanoid")
		and rootPart
		and rootPart:IsA("BasePart")
		and animator
		and animator:IsA("Animator")
	then
		return {
			Model = model,
			Humanoid = humanoid,
			Root = rootPart,
			Animator = animator,
		}, nil
	end

	return nil, `Humanoid: [{humanoid}] HumanoidRootPart: [{rootPart}] Animator: [{animator}]`
end

--[=[
	Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function CharacterController.OnAwake(self: CharacterController)
	ValidateDisabledController("CHARACTER")
end

--[=[
	Called after all modules have finished initializing. Begin runtime behavior here.
]=]
function CharacterController.OnStart(self: CharacterController)
	ValidateDisabledController("CHARACTER")

	-- Deferred so listeners connected in any module's OnStart still see the characters that already exist
	task.defer(self._bindPlayers, self)
end

--[=[
	Client only. Returns the local player's `CharacterObject`, or nil if it hasn't spawned yet
	or is between lives. Same as reading `LocalCharacterObject`.
]=]
function CharacterController.GetLocalCharacter(self: CharacterController): CharacterObject?
	if not IS_CLIENT then
		error(`[{script.Name}] :GetLocalCharacter() is client-only`, 2)
	end

	return self.LocalCharacterObject
end

--[=[
	Client only. Resolves with the local player's `CharacterObject`: immediately if it exists,
	otherwise as soon as the next one loads. Each call resolves with the character current
	at that moment; it won't follow respawns. Use `:expect()` to yield instead.
]=]
function CharacterController.GetLocalCharacterAsync(self: CharacterController): Promise.TypedPromise<CharacterObject>
	if not IS_CLIENT then
		error(`[{script.Name}] :GetLocalCharacterAsync() is client-only`, 2)
	end

	return self:GetCharacterForPlayerAsync(Players.LocalPlayer)
end

--[=[
	Returns `player`'s current `CharacterObject`, or nil if they don't have one loaded.
]=]
function CharacterController.GetCharacterForPlayer(self: CharacterController, player: Player): CharacterObject?
	return self._characters[player]
end

--[=[
	Resolves with `player`'s `CharacterObject`: immediately if it exists, otherwise as soon as
	the next one loads. Rejects if the player leaves first.
]=]
function CharacterController.GetCharacterForPlayerAsync(
	self: CharacterController,
	player: Player
): Promise.TypedPromise<CharacterObject>
	local existing = self._characters[player]
	if existing then
		return Promise.resolve(existing)
	end

	return Promise.new(function(resolve, reject, onCancel)
		if player.Parent == nil then
			reject(`[{script.Name}] {player.Name} left before their character loaded`)
			return
		end

		local janitor = Janitor.new()

		janitor:Add(self.CharacterAdded:Connect(function(character: CharacterObject)
			if character.Player == player then
				janitor:Destroy()
				resolve(character)
			end
		end))

		janitor:Add(Players.PlayerRemoving:Connect(function(leaving: Player)
			if leaving == player then
				janitor:Destroy()
				reject(`[{script.Name}] {player.Name} left before their character loaded`)
			end
		end))

		onCancel(function()
			janitor:Destroy()
		end)
	end)
end

--[=[
	Returns the `CharacterObject` whose Model is, or contains, `instance`. Handy for resolving
	a hit part back to a character.
]=]
function CharacterController.GetCharacterFromInstance(self: CharacterController, instance: Instance): CharacterObject?
	for _, character in self._characters do
		if instance == character.Model or instance:IsDescendantOf(character.Model) then
			return character
		end
	end

	return nil
end

--[=[
	Returns an array of all currently tracked `CharacterObject`s.
]=]
function CharacterController.GetCharacters(self: CharacterController): { CharacterObject }
	local characters = {}
	for _, character in self._characters do
		table.insert(characters, character)
	end
	return characters
end

--[=[
	Calls `callback` with `player`'s character right away if one is loaded, and again on
	every future respawn. Disconnect the returned connection to stop.
]=]
function CharacterController.BindAddedToPlayer(
	self: CharacterController,
	player: Player,
	callback: (character: CharacterObject) -> ()
): Signal.Connection
	local existing = self._characters[player]
	if existing then
		task.spawn(callback, existing)
	end

	return self.CharacterAdded:Connect(function(character: CharacterObject)
		if character.Player == player then
			callback(character)
		end
	end)
end

--[=[
	Calls `callback` whenever `player`'s character is removed. Disconnect the returned
	connection to stop.
]=]
function CharacterController.BindRemovedToPlayer(
	self: CharacterController,
	player: Player,
	callback: (character: CharacterObject) -> ()
): Signal.Connection
	return self.CharacterRemoved:Connect(function(character: CharacterObject)
		if character.Player == player then
			callback(character)
		end
	end)
end

--[=[
	Client only. Returns whether the local player is currently shift-locked.
]=]
function CharacterController.IsShiftLocked(self: CharacterController): boolean
	return Players.LocalPlayer.DevEnableMouseLock and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

--[=[
	Returns the movement direction relative to the character's facing.
	`directional` controls, per mode (shift-locked or default), whether 4D direction
	is used. When it's off for the current mode, this always returns "Forward".
	Omitting it enables 4D in both modes.
	`previous` adds hysteresis on diagonals so animations don't flicker, and is
	returned as-is when the character isn't moving.
]=]
function CharacterController.GetMoveDirection(
	self: CharacterController,
	character: CharacterObject,
	previous: Types.Direction?,
	directional: Types.DirectionalModes?
): Types.Direction
	if directional then
		local enabled = if self:IsShiftLocked() then directional.ShiftLocked else directional.Default
		if not enabled then
			return "Forward"
		end
	end

	local last: Types.Direction = previous or "Forward"
	local moveDirection = character.Humanoid.MoveDirection

	if moveDirection.Magnitude == 0 then
		return last
	end

	local localMove = character.Root.CFrame:VectorToObjectSpace(moveDirection)
	local x, z = localMove.X, localMove.Z

	local bias = 0.1
	local zWeight = math.abs(z) + if last == "Forward" or last == "Backward" then bias else 0
	local xWeight = math.abs(x) + if last == "Left" or last == "Right" then bias else 0

	if zWeight >= xWeight then
		return if z < 0 then "Forward" else "Backward"
	end

	return if x > 0 then "Right" else "Left"
end

--[=[
	@priv
]=]
function CharacterController._bindPlayers(self: CharacterController)
	for _, player in Players:GetPlayers() do
		self:_watchPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_watchPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_unwatchPlayer(player)
	end)
end

--[=[
	@priv
]=]
function CharacterController._watchPlayer(self: CharacterController, player: Player)
	if self._playerJanitors[player] then
		return
	end

	local janitor = Janitor.new()
	self._playerJanitors[player] = janitor

	janitor:Add(player.CharacterAdded:Connect(function(model: Model)
		self:_onCharacterAdded(player, model)
	end))

	janitor:Add(player.CharacterRemoving:Connect(function(model: Model)
		local character = self._characters[player]
		if character and character.Model == model then
			self:_removeCharacter(character)
		end
	end))

	if player.Character then
		task.spawn(self._onCharacterAdded, self, player, player.Character)
	end
end

--[=[
	@priv
]=]
function CharacterController._unwatchPlayer(self: CharacterController, player: Player)
	local character = self._characters[player]
	if character then
		self:_removeCharacter(character)
	end

	local janitor = self._playerJanitors[player]
	if janitor then
		self._playerJanitors[player] = nil
		janitor:Destroy()
	end
end

--[=[
	@priv
]=]
function CharacterController._onCharacterAdded(self: CharacterController, player: Player, model: Model)
	local config = Config.get()

	local parts, missing = waitForParts(model, config.CHARACTER.LOAD_TIMEOUT)

	-- The player may have respawned or left while we were waiting
	if player.Character ~= model or not self._playerJanitors[player] then
		return
	end

	if not parts then
		warn(
			`[{script.Name}] Character "{model:GetFullName()}" didn't load within {config.CHARACTER.LOAD_TIMEOUT}s, missing one of: {missing}`
		)
		return
	end

	local previous = self._characters[player]
	if previous then
		if previous.Model == model then
			return
		end

		self:_removeCharacter(previous)
	end

	local isLocal = IS_CLIENT and player == Players.LocalPlayer
	local character = CharacterClass.new(player, parts, isLocal)

	-- Backstop for Models destroyed without CharacterRemoving firing
	character.Janitor:Add(model.Destroying:Connect(function()
		self:_removeCharacter(character)
	end))

	self._characters[player] = character

	if isLocal then
		self.LocalCharacterObject = character
	end

	if IS_SERVER then
		model:AddTag(config.TAGS.CHARACTER)
	end

	if config.LOGGING.CHARACTER then
		print(`[{script.Name}] Character added: `, model)
	end

	self.CharacterAdded:Fire(character)

	if isLocal then
		self.LocalCharacterAdded:Fire(character)
	end
end

--[=[
	@priv
]=]
function CharacterController._removeCharacter(self: CharacterController, character: CharacterObject)
	if self._characters[character.Player] ~= character then
		return
	end

	self._characters[character.Player] = nil

	if self.LocalCharacterObject == character then
		self.LocalCharacterObject = nil
	end

	if Config.get().LOGGING.CHARACTER then
		print(`[{script.Name}] Character removed: `, character.Model)
	end

	self.CharacterRemoved:Fire(character)

	if character.IsLocal then
		self.LocalCharacterRemoved:Fire(character)
	end

	character:Destroy()
end

return CharacterController
