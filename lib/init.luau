--!strict
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_RUNNING = RunService:IsRunning()

local Types = require(script.Types)

local DEFAULTS = require(script.Defaults)

local Backbone = {
	Version = "0.1.5",
}

export type Backbone = typeof(Backbone)
export type BackboneConfig = Types.BackboneConfig
export type BackboneConfigInput = Types.BackboneConfigInput

export type ClientRuntime = Types.ClientRuntime
export type ServerRuntime = Types.ServerRuntime
export type SharedRuntime<T> = Types.SharedRuntime<T>

export type ImportLayer = Types.ImportLayer
export type LifecyclePhaseName = Types.LifecyclePhaseName
export type LifecyclePhaseEnum = Types.LifecyclePhaseEnum
export type RequireAttemptResult = Types.RequireAttemptResult

export type NetworkLayer = Types.NetworkLayer
export type NetworkPacketConfig = Types.NetworkPacketConfig
export type Connection = Types.Connection
export type Packet = Types.Packet

export type EntityController = Types.EntityController
export type Entity = Types.Entity
export type EntityTypeRegistration = Types.EntityTypeRegistration
export type EntityConstructionContext = Types.EntityConstructionContext
export type GenericSpawnContext<T> = Types.GenericSpawnContext<T>
export type RegistrationContext = Types.RegistrationContext
export type SpawnContext = Types.SpawnContext

export type Agent = Types.Agent

export type ClientControllers = Types.ClientControllers
export type ServerControllers = Types.ServerControllers
export type SharedControllers = Types.SharedControllers

export type AudioController = Types.AudioController
export type AudioResolvers = Types.AudioResolvers
export type AudioOptions = Types.AudioOptions

export type SoundProperties = Types.SoundProperties
export type AudioContext = Types.AudioContext
export type SoundRequest = Types.SoundRequest

export type CharacterController = Types.CharacterController
export type CharacterRuntimeBuildDefinition = Types.CharacterRuntimeBuildDefinition
export type Character = Types.Character

export type AnimationDefinition = Types.AnimationDefinition
export type AnimationVariantTable = Types.AnimationVariantTable
export type AnimatorConfig = Types.AnimatorConfig
export type AnimationPlayOverrides = Types.AnimationPlayOverrides
export type AnimationInternalEntry = Types.AnimationInternalEntry
export type MarkerReachedPayload = Types.MarkerReachedPayload
export type AnimationController = Types.AnimationController
export type PlayInOrderPredicate = Types.PlayInOrderPredicate
export type AnimatorClass = Types.AnimatorClass

export type InputDevice = Types.InputDevice
export type InputBinding = Types.InputBinding
export type InputSystem = Types.InputSystem
export type ActionConfig = Types.ActionConfig
export type AxisSource = Types.AxisSource
export type AxisConfig = Types.AxisConfig
export type InputConfig = Types.InputConfig
export type HoldConfig = Types.HoldConfig
export type MoveProvider = Types.MoveProvider
export type ActionState = Types.ActionState
export type BoundCallback = Types.BoundCallback
export type ActionRuntime = Types.ActionRuntime
export type AxisRuntime = Types.AxisRuntime
export type InputController = Types.InputController

export type PhysicsObject = Types.PhysicsObject
export type PhysicsController = Types.PhysicsController
export type InterfaceLayer = Types.InterfaceLayer
export type InterfaceRegistration = Types.InterfaceRegistration
export type InterfaceEntry = Types.InterfaceEntry
export type InterfaceController = Types.InterfaceController

-- Give all controllers the internal controller tag
for _, v in script:GetDescendants() do
	if v:IsA("ModuleScript") and v.Parent == script.Controllers then
		v:AddTag(DEFAULTS.INTERNAL_CONTROLLER_TAG)
	end
end

function Backbone.Server(self: Backbone): ServerRuntime
	if not IS_SERVER then
		error(`[BACKBONE] Cannot call :Server() on the client!`)
	end

	return require(script.Core.Process.ServerRuntime) :: any
end

function Backbone.Client(self: Backbone): ClientRuntime
	if IS_SERVER then
		error(`[BACKBONE] Cannot call :Client() on the server!`)
	end

	local server = script.Core.Process:FindFirstChild("ServerRuntime")
	if server and IS_RUNNING then
		server:Destroy()
	end

	return require(script.Core.Process.ClientRuntime) :: any
end

function Backbone.Shared(self: Backbone): SharedRuntime<SharedControllers>
	return require(script.Core.Process.SharedRuntime) :: any
end

return Backbone
