--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local root = script.Parent.Parent
local packages = root.Parent
local util = root.Util
local localPlayer = Players.LocalPlayer

local Config = require(root.Core.Config)
local Promise = require(packages.Promise)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local InputController = {
	_actions = {} :: { [string]: ActionRuntime },
	_axes = {} :: { [string]: AxisRuntime },
	_blockCounts = {} :: { [string]: number },
	_bindingIndex = {} :: { [Enum.KeyCode | Enum.UserInputType]: { string } },
	_controls = nil :: any,
}

export type HoldConfig = Types.HoldConfig

export type InputDevice = Types.InputDevice

export type InputBinding = Types.InputBinding

export type ActionConfig = Types.ActionConfig

--[=[
	Movement (WASD/Thumbstick1) and camera/viewmodel sway (MouseDelta/Thumbstick2) 
    are BOTH Axes, on purpose, so consumers read them through the exact same Vector2 
    API regardless of device.
]=]
export type AxisSource = Types.AxisSource

export type AxisConfig = Types.AxisConfig

export type InputConfig = Types.InputConfig

export type ActionState = Types.ActionState

export type BoundCallback = Types.BoundCallback

export type ActionRuntime = Types.ActionRuntime

export type AxisRuntime = Types.AxisRuntime

export type InputController = Types.InputController

--[=[
	Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function InputController.OnAwake(self: InputController)
	assert(RunService:IsClient(), `[{script.Name}] InputController is client-only`)

	ValidateDisabledController("INPUT")

	local config = Config.get()

	local INPUTS = config.INPUT.CONFIG

	for name, cfg in INPUTS.Actions do
		self:_registerAction(name, cfg)

		-- The Hold target isn't in Config.Actions -- it relies on its
		-- parent's binding
		if cfg.Hold then
			self:_registerAction(cfg.Hold.Name, {
				Name = cfg.Hold.Name,
				Group = cfg.Group,
				Defaults = {},
				Blockable = cfg.Blockable,
				Rebindable = false,
			})
		end
	end

	for name, cfg in INPUTS.Axes do
		self._axes[name] = {
			Config = cfg,
			Value = Vector2.zero,
			_mouseDeltaBuffer = Vector2.zero,
		}
	end

	self:_rebuildBindingIndex()
end

--[=[
	Called after the Awake phase. Perform asynchronous initialization here.
]=]
function InputController.OnInit(self: InputController): Promise.TypedPromise<()>
	return Promise.new(function(resolve)
		-- Cast to any because we won't have types for the PlayerModule
		local playerModule = (require :: any)(localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		print(playerModule)
		self._controls = playerModule:GetControls()
	end)
end

--[=[
    Called after all modules have finished initializing. Begin runtime behavior here.
]=]
function InputController.OnStart(self: InputController)
	ValidateDisabledController("INPUT")

	self:_connectInput()
	self:_connectAxisUpdate()
end

function InputController.BindAction(
	self: InputController,
	name: string,
	callback: (ActionState, InputObject) -> (),
	priority: number?
): () -> ()
	local runtime = self._actions[name]
	if not runtime then
		warn(`[{script.Name}] Attempted to bind to unknown Action "{name}"`)
		return function() end
	end

	local bound: BoundCallback = { Callback = callback, Priority = priority or 0 }
	table.insert(runtime.Callbacks, bound)

	table.sort(runtime.Callbacks, function(a: BoundCallback, b: BoundCallback)
		return a.Priority > b.Priority
	end)

	return function()
		self:UnbindAction(name, callback)
	end
end

function InputController.UnbindAction(self: InputController, name: string, callback: (ActionState, InputObject) -> ())
	local runtime = self._actions[name]
	if not runtime then
		return
	end

	for index, bound in runtime.Callbacks do
		if bound.Callback == callback then
			table.remove(runtime.Callbacks, index)
			break
		end
	end
end

--[=[
	Blocks an Action, or every Action in a Group, refcounted so overlapping
	systems can block the same name without stepping on each other's Unblock.
	Cancels any in-flight Hold thread for affected Actions.
]=]
function InputController.Block(self: InputController, nameOrGroup: string)
	self._blockCounts[nameOrGroup] = (self._blockCounts[nameOrGroup] or 0) + 1

	for name, runtime in self._actions do
		if name == nameOrGroup or runtime.Config.Group == nameOrGroup then
			if runtime.IsDown then
				runtime.IsDown = false
				runtime.SuppressEnded = true
			end

			if runtime.HoldThread then
				task.cancel(runtime.HoldThread)
				runtime.HoldThread = nil
			end
		end
	end
end

function InputController.Unblock(self: InputController, nameOrGroup: string)
	local count = self._blockCounts[nameOrGroup]
	if not count then
		return
	end

	self._blockCounts[nameOrGroup] = math.max(0, count - 1)
end

--[=[
	Replaces an Action's bindings for one device. Rebuilds the dispatch index
	so the change takes effect immediately. A Hold target rides along
	automatically since it shares its parent's binding, not its own.
]=]
function InputController.Rebind(
	self: InputController,
	actionName: string,
	device: InputDevice,
	bindings: { InputBinding }
)
	local runtime = self._actions[actionName]
	if not runtime then
		warn(`[{script.Name}] Attempted to rebind unknown Action "{actionName}"`)
		return
	end

	if runtime.Config.Rebindable == false then
		warn(`[{script.Name}] Action "{actionName}" is not Rebindable`)
		return
	end

	runtime.ActiveBindings[device] = bindings
	self:_rebuildBindingIndex()
end

function InputController.IsActionDown(self: InputController, name: string): boolean
	local runtime = self._actions[name]
	return runtime ~= nil and runtime.IsDown
end

--[=[
	Returns this frame's raw value for a 2D Axis. Look is raw mouse/thumbstick delta for the
	frame, not an accumulation, so smoothing should be applied externally
]=]
function InputController.GetAxis(self: InputController, name: string): Vector2
	local runtime = self._axes[name]
	if not runtime then
		warn(`[{script.Name}] Attempted to read unknown Axis "{name}"`)
		return Vector2.zero
	end

	if runtime.Config.Blockable ~= false and self:_isBlocked(name) then
		return Vector2.zero
	end

	return runtime.Value
end

--[=[
	@priv
]=]
function InputController._registerAction(self: InputController, name: string, config: ActionConfig)
	local activeBindings = {} :: { [InputDevice]: { InputBinding } }

	for device, bindings in config.Defaults do
		local copy = table.create(#bindings)

		for i, binding in bindings do
			copy[i] = binding
		end

		activeBindings[device] = copy :: any
	end

	self._actions[name] = {
		Config = config,
		ActiveBindings = activeBindings,
		Callbacks = {},
		IsDown = false,
		HoldThread = nil,
	}
end

--[=[
	@priv
	Flattens every Action's ActiveBindings into a single physical-input ->
	{actionNames} lookup.
]=]
function InputController._rebuildBindingIndex(self: InputController)
	table.clear(self._bindingIndex)

	for name, runtime in self._actions do
		for _, bindings in runtime.ActiveBindings do
			for _, binding in bindings do
				local key = binding.Keycode or binding.UserInputType
				if not key then
					continue
				end

				local list = self._bindingIndex[key]

				if not list then
					list = {}
					self._bindingIndex[key] = list
				end

				table.insert(list, name)
			end
		end
	end
end

--[=[
	@priv
]=]
function InputController._isBlocked(self: InputController, name: string): boolean
	local runtime = self._actions[name] or self._axes[name]
	if runtime and runtime.Config.Blockable == false then
		return false
	end

	if (self._blockCounts[name] or 0) > 0 then
		return true
	end

	if runtime and runtime.Config.Group and (self._blockCounts[runtime.Config.Group] or 0) > 0 then
		return true
	end

	return false
end

--[=[
	@priv
]=]
function InputController._connectInput(self: InputController)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		local key = (input.KeyCode ~= Enum.KeyCode.None and input.KeyCode) or input.UserInputType
		local names = self._bindingIndex[key]
		if not names then
			return
		end

		for _, name in names do
			self:_fireBegan(name, input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
		local key = (input.KeyCode ~= Enum.KeyCode.None and input.KeyCode) or input.UserInputType
		local names = self._bindingIndex[key]
		if not names then
			return
		end

		for _, name in names do
			self:_fireEnded(name, input)
		end
	end)

	self:_procInputChanged()
end

function InputController._procInputChanged(self: InputController)
	local inputChangedEntries: { [string]: AxisRuntime } = {}
	local canContinueToConnection = false

	for i, j in self._axes do
		for _, k in j.Config.Sources do
			if k == "MouseDelta" then
				inputChangedEntries[i] = j
				canContinueToConnection = true
			end
		end
	end

	if not canContinueToConnection then
		return
	end

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			for i, v in inputChangedEntries do
				v._mouseDeltaBuffer += Vector2.new(input.Delta.X, input.Delta.Y)
			end
		end
	end)
end

--[=[
	@priv
]=]
function InputController._fireBegan(self: InputController, name: string, input: InputObject)
	local runtime = self._actions[name]
	if not runtime or runtime.IsDown or self:_isBlocked(name) then
		return
	end

	runtime.IsDown = true

	local hold = runtime.Config.Hold
	if not hold then
		self:_dispatch(name, "Began", input)
		return
	end

	runtime.HoldThread = task.delay(hold.Duration, function()
		runtime.HoldThread = nil
		self:_dispatch(hold.Name, "Began", input)
	end)
end

--[=[
    @priv
]=]
function InputController._fireEnded(self: InputController, name: string, input: InputObject)
	local runtime = self._actions[name]
	if not runtime then
		return
	end

	if runtime.SuppressEnded then
		runtime.SuppressEnded = false
		return
	end

	if not runtime.IsDown then
		return
	end

	runtime.IsDown = false

	local hold = runtime.Config.Hold
	if not hold then
		self:_dispatch(name, "Ended", input)
		return
	end

	if runtime.HoldThread then
		-- Released before the threshold: this was a tap, not a hold.
		task.cancel(runtime.HoldThread)
		runtime.HoldThread = nil
		self:_dispatch(name, "Began", input)
		self:_dispatch(name, "Ended", input)
	else
		-- Threshold already won; the hold target is live
		self:_dispatch(hold.Name, "Ended", input)
	end
end

--[=[
    @priv
]=]
function InputController._dispatch(self: InputController, name: string, state: ActionState, input: InputObject)
	local config = Config.get()

	local runtime = self._actions[name]
	if not runtime then
		return
	end

	if config.LOGGING.INPUT then
		print(`[{script.Name}] Action "{name}" -> {state}`)
	end

	for _, bound in runtime.Callbacks do
		task.spawn(bound.Callback, state, input)
	end
end

--[=[
	@priv
	Axes read once per RenderStepped, sourced from whichever device the
	player last touched (UserInputService:GetLastInputType), so a stray
	thumbstick twitch doesn't stack with keyboard input.
]=]
function InputController._connectAxisUpdate(self: InputController)
	RunService.RenderStepped:Connect(function()
		local device = self:_resolveDevice()

		for name, runtime in self._axes do
			local source = runtime.Config.Sources[device]
			local value = source and self:_readSource(source, runtime) or Vector2.zero

			if runtime.Config.Sensitivity then
				value *= runtime.Config.Sensitivity
			end

			if runtime.Config.Invert then
				value = Vector2.new(
					runtime.Config.Invert.X and -value.X or value.X,
					runtime.Config.Invert.Y and -value.Y or value.Y
				)
			end

			runtime.Value = value
		end
	end)
end

--[=[
    @priv
]=]
function InputController._resolveDevice(self: InputController): InputDevice
	local lastInputType = UserInputService:GetLastInputType()

	if lastInputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif lastInputType.Name:match("^Gamepad") then
		return "Gamepad"
	elseif lastInputType == Enum.UserInputType.MouseMovement or lastInputType.Name:match("^MouseButton") then
		return "Mouse"
	end

	return "Keyboard"
end

--[=[
    @priv
]=]
function InputController._readSource(self: InputController, source: AxisSource, runtime: AxisRuntime): Vector2
	if source == "WASD" then
		local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
			- (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
		local y = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
			- (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
		local vector = Vector2.new(x, y)
		return vector.Magnitude > 0 and vector.Unit or Vector2.zero
	elseif source == "MouseDelta" then
		local delta = runtime._mouseDeltaBuffer
		runtime._mouseDeltaBuffer = Vector2.zero
		return delta
	elseif source == "Thumbstick1" then
		return self:_readThumbstick(Enum.KeyCode.Thumbstick1)
	elseif source == "Thumbstick2" then
		return self:_readThumbstick(Enum.KeyCode.Thumbstick2)
	elseif source == "Touchpad" then
		return self:_readTouchpad()
	end

	return Vector2.zero
end

--[=[
    @priv
]=]
function InputController._readThumbstick(self: InputController, thumbstick: Enum.KeyCode): Vector2
	local config = Config.get()
	local gamepadState = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)

	for _, input in gamepadState do
		if input.KeyCode == thumbstick then
			local position = input.Position
			return position.Magnitude > config.INPUT.THUMBSTICK_DEADZONE and Vector2.new(position.X, position.Y)
				or Vector2.zero
		end
	end

	return Vector2.zero
end

--[=[
    @priv
]=]
function InputController._readTouchpad(self: InputController): Vector2
	local config = Config.get()
	local moveVector = self._controls:GetMoveVector()
	local value = Vector2.new(moveVector.X, -moveVector.Z)

	return value.Magnitude > config.INPUT.THUMBSTICK_DEADZONE and value or Vector2.zero
end

return InputController
