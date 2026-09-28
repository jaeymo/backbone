--!strict
local root = script.Parent
local packages = root.Parent

local Janitor = require(packages.Janitor)
local Packet = require(packages.Packet)
local Promise = require(packages.Promise)
local Signal = require(packages.Signal)

export type BackboneConfig = {
	INIT_METHOD: string,
	AWAKE_METHOD: string,
	START_METHOD: string,

	MODULE_ATTRIBUTE_GUID_NAME: string,
	IGNORE_MODULE_LOAD_TAG_NAME: string,
	INTERNAL_CONTROLLER_TAG: string,

	PACKETS: { [string]: NetworkPacketConfig },

	TAGS: {
		ACTOR: string,
		ENTITY: string,
		CHARACTER: string,
	},

	ATTRIBUTES: {
		ENTITY_ID: string,
		ENTITY_GUID: string,
		ENTITY_TYPE: string,
		ENTITY_SPAWN_TIME: string,
		ENTITY_DEFINITION: string,
	},

	AUDIO: {
		SOURCES: { Instance },
		RESOLVERS: AudioResolvers,
	},

	COLLISION_GROUPS: {
		CHARACTER: string,
		CHARACTER_ROOT: string,
	},

	ENABLED_CONTROLLERS: {
		ANIMATION: boolean,
		INTERFACE: boolean,
		CHARACTER: boolean,
		PHYSICS: boolean,
		ENTITY: boolean,
		AUDIO: boolean,
		INPUT: boolean,
	},

	LOGGING: {
		MODULE_NAME_ON_REQUIRE: boolean,
		BACKBONE_AWOKEN: boolean,
		PHASE_CHANGED: boolean,

		CHARACTER: boolean,
		ENTITY: boolean,
		AUDIO: boolean,
		INPUT: boolean,
	},

	ANIMATION: {
		MAX_CONCURRENT_MARKER_FETCHES: number,
		MARKER_FETCH_RETRIES: number,
		MARKER_FETCH_BACKOFF_SECONDS: number,
	},

	CHARACTER: {
		CLIENT_CHARACTER_MODEL_TIMEOUT: number,
		BIND_TO_COLLISION_GROUP: true,
	},

	ENTITY: {
		CLIENT_ENTITY_GUID_TIMEOUT: number,
		PROXY_FOLDER_NAME: "__proxies",
	},

	INPUT: {
		CONFIG: InputConfig,
		THUMBSTICK_DEADZONE: number,
	},
}

export type BackboneConfigInput = {
	INIT_METHOD: string?,
	AWAKE_METHOD: string?,
	START_METHOD: string?,

	MODULE_ATTRIBUTE_GUID_NAME: string?,
	IGNORE_MODULE_LOAD_TAG_NAME: string?,
	INTERNAL_CONTROLLER_TAG: string?,

	PACKETS: { [string]: NetworkPacketConfig }?,

	TAGS: {
		ACTOR: string?,
		ENTITY: string?,
		CHARACTER: string?,
	}?,

	ATTRIBUTES: {
		ENTITY_ID: string?,
		ENTITY_GUID: string?,
		ENTITY_TYPE: string?,
		ENTITY_SPAWN_TIME: string?,
		ENTITY_DEFINITION: string?,
	}?,

	AUDIO: {
		SOURCES: { Instance }?,
		RESOLVERS: AudioResolvers?,
	}?,

	COLLISION_GROUPS: {
		CHARACTER: string?,
		CHARACTER_ROOT: string?,
	}?,

	ENABLED_CONTROLLERS: {
		ANIMATION: boolean?,
		INTERFACE: boolean?,
		CHARACTER: boolean?,
		PHYSICS: boolean?,
		ENTITY: boolean?,
		AUDIO: boolean?,
		INPUT: boolean?,
	}?,

	LOGGING: {
		MODULE_NAME_ON_REQUIRE: boolean?,
		BACKBONE_AWOKEN: boolean?,
		PHASE_CHANGED: boolean?,

		CHARACTER: boolean?,
		ENTITY: boolean?,
		AUDIO: boolean?,
		INPUT: boolean?,
	}?,

	ANIMATION: {
		MAX_CONCURRENT_MARKER_FETCHES: number?,
		MARKER_FETCH_RETRIES: number?,
		MARKER_FETCH_BACKOFF_SECONDS: number?,
	},

	CHARACTER: {
		CLIENT_CHARACTER_MODEL_TIMEOUT: number?,
		BIND_TO_COLLISION_GROUP: boolean?,
	}?,

	ENTITY: {
		CLIENT_ENTITY_GUID_TIMEOUT: number?,
		PROXY_FOLDER_NAME: string?,
	}?,

	INPUT: {
		THUMBSTICK_DEADZONE: number?,
		CONFIG: InputConfig?,
	}?,
}

export type ClientRuntime = {
	_initialized: boolean,
	Start: (self: ClientRuntime, directories: Instance | { Instance }) -> Promise.TypedPromise<()>,
} & SharedRuntime<ClientControllers>

export type ServerRuntime = {
	_initialized: boolean,
	Start: (self: ServerRuntime, directories: Instance | { Instance }) -> Promise.TypedPromise<()>,
} & SharedRuntime<ServerControllers>

export type SharedRuntime<T> = {
	PhaseChanged: Signal.Signal<LifecyclePhaseEnum>,
	Controllers: T,

	Configure: (self: SharedRuntime<T>, config: BackboneConfigInput) -> (),
	GetNetworkLayer: (self: SharedRuntime<T>) -> NetworkLayer,
	GetPromise: (self: SharedRuntime<T>) -> typeof(Promise),
	GetImportLayer: (self: SharedRuntime<T>) -> ImportLayer,
	GetControllers: (self: SharedRuntime<T>) -> T,
}

export type ImportLayer = {
	Start: (self: ImportLayer, directories: Instance | { Instance }) -> Promise.TypedPromise<>,
	Bootstrap: (self: ImportLayer, directories: Instance | { Instance }) -> (),
	GetPhase: (self: ImportLayer) -> LifecyclePhaseEnum,
	SetPhase: (self: ImportLayer, phase: LifecyclePhaseEnum) -> (),
	WaitForPhase: (self: ImportLayer, phase: LifecyclePhaseName) -> Promise.TypedPromise<LifecyclePhaseEnum>,
	ToNextPhase: (self: ImportLayer) -> (),
}

export type Packet = Packet.Packet<...any, ...any>

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type NetworkPacketConfig = {
	NAME: string,
	PAYLOAD: any?,
	RESPONSE: any?,
	UNRELIABLE: boolean?,
}

export type NetworkLayer = {
	Packets: { [string]: Packet }?,

	CreatePacket: (self: NetworkLayer, ...any) -> Packet,
	GetPacket: (self: NetworkLayer, packetName: string) -> Packet,
	Inject: (self: NetworkLayer, packets: { [string]: any }) -> (),
	SendClient: (self: NetworkLayer, packetName: string, client: Player, ...any) -> ...any,
	SendServer: (self: NetworkLayer, packetName: string, ...any) -> ...any,
	Broadcast: (self: NetworkLayer, packetName: string, ...any) -> (),
	BroadcastExcept: (self: NetworkLayer, packetName: string, except: Player | { Player }, ...any) -> (),

	BroadcastInRange: (
		self: NetworkLayer,
		packetName: string,
		position: Vector3,
		range: number,
		except: (Player | { Player })?,
		...any
	) -> (),

	OnInvoke: (self: NetworkLayer, packetName: string, callback: (...any) -> ...any?) -> (),
	OnServer: (self: NetworkLayer, packetName: string, callback: (Player, ...any) -> ()) -> Connection,
	OnClient: (self: NetworkLayer, packetName: string, callback: (...any) -> ()) -> Connection,

	BuildPacketsFromConfig: (
		self: NetworkLayer,
		packets: { [string]: NetworkPacketConfig }
	) -> { [string]: Packet },
}

export type RequireAttemptResult = {
	Module: any,
	Success: boolean,
}

export type LifecyclePhaseName = "Dead" | "Awake" | "Init" | "Start" | "Done"

export type LifecyclePhaseEnum = {
	Name: LifecyclePhaseName,
	Priority: number,
}

export type Entity = {
	Id: string,
	Model: Model,
	Guid: string,
	Type: string,
	Janitor: Janitor.Janitor,

	Parent: (self: Entity, parent: Instance?) -> (),
	Destroy: (self: Entity) -> (),
	_cleaned: boolean,
}

export type EntityTypeRegistration = {
	BeforeSpawn: ((context: RegistrationContext) -> ())?,
	Definitions: any?,
	Class: any,
}

export type Agent = {
	Entity: Entity,
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Animator: Animator,
	Janitor: Janitor.Janitor,

	GetModel: (self: Agent) -> Model,
	GetRoot: (self: Agent) -> BasePart,
	GetHumanoid: (self: Agent) -> Humanoid,
	GetAnimator: (self: Agent) -> Animator,
	Destroy: (self: Agent) -> (),
}

export type ClientControllers = {
	InputController: InputController,
	InterfaceController: InterfaceController,
} & SharedControllers

export type ServerControllers = {} & SharedControllers

export type SharedControllers = {
	AnimationController: AnimationController,
	CharacterController: CharacterController,
	EntityController: EntityController,
	AudioController: AudioController,
	PhysicsController: PhysicsController,
}

export type EntityController = {
	EntityConstructed: Signal.Signal<Entity, any?>,
	EntityDestroyed: Signal.Signal<Entity, any?>,
	EntitySpawned: Signal.Signal<Entity, any?>,

	RegisterType: (self: EntityController, type: string, registration: EntityTypeRegistration) -> (),
	RegisterExisting: (self: EntityController, context: RegistrationContext) -> (),
	GetRegisteredType: (self: EntityController, type: string) -> EntityTypeRegistration?,

	ForAllFromType: (
		self: EntityController,
		type: string,
		callback: (Entity, any?) -> (),
		async: boolean?
	) -> (),

	ConstructBlank: (
		self: EntityController,
		context: EntityConstructionContext
	) -> {
		Entity: Entity,
		Object: any,
	}?,

	ConstructFromExisting: (self: EntityController, model: Model) -> {
		Entity: Entity,
		Object: any,
	}?,

	GetEntityByGuid: (self: EntityController, guid: string) -> Entity?,
	GetEntityByModel: (self: EntityController, model: Model) -> Entity?,
	GetObjectByGuid: (self: EntityController, guid: string) -> any?,
	GetObjectByModel: (self: EntityController, model: Model) -> any?,

	SpawnAt: (self: EntityController, context: SpawnContext) -> (),
}

export type EntityConstructionContext = {
	Id: string,
	Type: string,
	Definition: any?,
}

export type RegistrationContext = GenericSpawnContext<CFrame?>

export type SpawnContext = GenericSpawnContext<CFrame>

export type GenericSpawnContext<T> = {
	Type: string,
	Entity: Entity,
	Object: any,
	CFrame: T,
	Parent: Instance?,
}

export type AudioController = {
	Cooldowns: any,

	Registry: { [string]: Sound },
	Groups: { [string]: { Sound } },
	Resolvers: AudioResolvers?,

	CreateRequest: (self: AudioController, soundName: string, options: AudioOptions?) -> SoundRequest?,
	RegisterSound: (self: AudioController, name: string, sound: Sound) -> (),
	RegisterGroup: (self: AudioController, name: string, folder: Instance) -> (),
	Play: (self: AudioController, soundName: string, options: AudioOptions?) -> Sound?,
	PlayAt: (
		self: AudioController,
		soundName: string,
		position: Vector3,
		options: AudioOptions?
	) -> Sound?,
	PlayOn: (self: AudioController, soundName: string, parent: Instance, options: AudioOptions?) -> Sound?,
	PlayRequest: (self: AudioController, request: SoundRequest) -> Sound?,
}

export type AudioResolvers = { [string]: (context: AudioContext?) -> SoundRequest? }

export type AudioOptions = {
	Weld: BasePart?,
	Visualize: boolean?,
	Context: AudioContext?,
	Properties: SoundProperties?,
}

export type SoundProperties = {
	RollOffMode: Enum.RollOffMode? | (() -> Enum.RollOffMode?),
	RollOffMinDistance: number? | (() -> number?),
	RollOffMaxDistance: number? | (() -> number?),
	Volume: number? | (() -> number?),
	PlaybackSpeed: number? | (() -> number?),
	Looped: boolean? | (() -> boolean?),
	TimePosition: number? | (() -> number?),
	SoundGroup: SoundGroup? | (() -> SoundGroup?),
	RandomizePitch: (() -> number)?,
}

export type AudioContext = {
	Animator: Animator,
	Parameter: string,
}

export type SoundRequest = {
	Sound: Sound,
	Position: Vector3?,
	Parent: Instance?,
	Weld: BasePart?,

	Cooldown: {
		Duration: number,
		Key: string,
	}?,

	Properties: SoundProperties?,
	Visualize: boolean?,
}

export type Character = {
	Entity: Entity,
	Agent: Agent,
	IsLocal: boolean,
	Player: Player,

	Init: (self: Character, runtimeDefinition: CharacterRuntimeBuildDefinition) -> (),
	Destroy: (self: Character) -> (),

	_watchCollisionGroup: (self: Character) -> (),
}

export type CharacterRuntimeBuildDefinition = {
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Animator: Animator,
}

export type CharacterController = {
	LocalCharacter: Character?,
	CharacterContainer: Folder?,

	CharacterAdded: Signal.Signal<Character>,
	CharacterRemoved: Signal.Signal<Character>,

	GetCharacterForPlayer: (self: CharacterController, player: Player) -> Character?,

	BindAddedToPlayer: (
		self: CharacterController,
		player: Player,
		callback: (character: Character) -> ()
	) -> Signal.Connection,

	BindRemovingToPlayer: (
		self: CharacterController,
		player: Player,
		callback: (character: Character) -> ()
	) -> Signal.Connection,
}

export type AnimationDefinition = {
	Id: number,
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Looped: boolean?,
	Priority: Enum.AnimationPriority?,
}

export type AnimationFamilyTable = { [string]: string }

export type AnimatorConfig = {
	Animations: { [string]: AnimationDefinition },
	Families: { [string]: AnimationFamilyTable }?,
}

export type AnimationPlayOverrides = {
	SkipIfPlaying: boolean?,
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
}

export type AnimationInternalEntry = {
	Name: string,
	Id: number,
	Definition: AnimationDefinition,
	Guid: string,
	Track: AnimationTrack,
	MarkersLoaded: boolean,
	MarkerJanitor: Janitor.Janitor,
}

export type MarkerReachedPayload = {
	MarkerName: string,
	GroupId: string,
	AnimationName: string,
	Animator: Animator,
	Track: AnimationTrack,
	Parameters: { any },
}

export type AnimationController = {
	Objects: { [string]: AnimatorClass },
	DefaultVariantKey: string,
	AnimationMarkerReached: Signal.Signal<MarkerReachedPayload>,

	new: (groupId: string, animator: Animator?) -> AnimatorClass,
	Get: (self: AnimationController, groupId: string, animator: Animator?) -> AnimatorClass,
	Destroy: (self: AnimationController, groupId: string) -> (),
}

export type AnimatorClass = {
	GroupId: string,
	Animator: Animator?,
	Janitor: Janitor.Janitor,
	Played: Signal.Signal<AnimationInternalEntry>,
	Entries: { [string]: AnimationInternalEntry },
	Adhoc: { [number]: AnimationInternalEntry },
	Families: { [string]: AnimationFamilyTable },
	ActiveVariant: { [string]: string },
	_sequenceToken: number,

	SetAnimator: (self: AnimatorClass, animator: Animator) -> (),
	IsRegistered: (self: AnimatorClass) -> boolean,
	LoadFromConfig: (self: AnimatorClass, config: AnimatorConfig) -> Promise.TypedPromise<()>,
	LoadAnimation: (self: AnimatorClass, name: string, definition: AnimationDefinition) -> AnimationInternalEntry?,
	GetRegistered: (self: AnimatorClass, name: string) -> AnimationInternalEntry?,
	GetLoadedNames: (self: AnimatorClass) -> { string },
	GetMarkerReachedSignal: (self: AnimatorClass, name: string, marker: string) -> RBXScriptSignal?,
	GetTimePosition: (self: AnimatorClass, name: string) -> number?,
	SetTimePosition: (self: AnimatorClass, name: string, position: number) -> (),
	SeekToProgress: (self: AnimatorClass, name: string, alpha: number) -> (),
	GetProgress: (self: AnimatorClass, name: string) -> number?,
	BindToProgress: (self: AnimatorClass, name: string, alpha: number, callback: () -> ()) -> (() -> ())?,
	SetFamilyVariant: (self: AnimatorClass, familyName: string, variantKey: string) -> (),
	GetFamilyVariant: (self: AnimatorClass, familyName: string) -> string?,
	Play: (self: AnimatorClass, name: string, overrides: AnimationPlayOverrides?) -> AnimationTrack?,
	PlayFamily: (self: AnimatorClass, familyName: string, overrides: AnimationPlayOverrides?) -> AnimationTrack?,
	PlayById: (self: AnimatorClass, id: number, overrides: AnimationPlayOverrides?) -> AnimationTrack?,
	IsPlaying: (self: AnimatorClass, name: string) -> boolean,
	IsAdhocPlaying: (self: AnimatorClass, id: number) -> boolean,
	Stop: (self: AnimatorClass, name: string, fadeTime: number?) -> AnimationTrack?,
	StopFamily: (self: AnimatorClass, familyName: string, fadeTime: number?) -> AnimationTrack?,
	StopAll: (self: AnimatorClass, fadeTime: number?) -> (),
	Reset: (self: AnimatorClass) -> (),
	Reload: (self: AnimatorClass, config: AnimatorConfig) -> Promise.TypedPromise<()>,
	Destroy: (self: AnimatorClass) -> (),

	_loadMarkersAsync: (self: AnimatorClass, entry: AnimationInternalEntry) -> (),
	_assertRegistered: (self: AnimatorClass) -> boolean,
}

export type InputDevice = "Keyboard" | "Mouse" | "Gamepad" | "Touch"

export type InputBinding = {
	Keycode: Enum.KeyCode?,
	UserInputType: Enum.UserInputType?,
}

export type ActionConfig = {
	Name: string,
	Group: string?, -- e.g. "Combat" / "Movement" -- used for bulk Block/Unblock
	Defaults: { [InputDevice]: { InputBinding } },
	Hold: HoldConfig?,
	Rebindable: boolean?,
	Blockable: boolean?,
	CreateTouchButton: boolean?,
	TouchButtonImage: string?,
}

export type AxisSource = "WASD" | "MouseDelta" | "Thumbstick1" | "Thumbstick2" | "Touchpad"

export type AxisConfig = {
	Name: string,
	Group: string?,
	Sources: { [InputDevice]: AxisSource },
	Sensitivity: number?, -- post-read multiplier (mainly for MouseDelta)
	Invert: { X: boolean?, Y: boolean? }?,
	Blockable: boolean?,
}

export type InputConfig = {
	Actions: { [string]: ActionConfig },
	Axes: { [string]: AxisConfig },
}

export type HoldConfig = {
	Duration: number,
	Name: string,
}

export type ActionState = "Began" | "Ended"

export type BoundCallback = {
	Callback: (ActionState, InputObject) -> (),
	Priority: number,
}

export type ActionRuntime = {
	Config: ActionConfig,
	ActiveBindings: { [InputDevice]: { InputBinding } },
	Callbacks: { BoundCallback },
	IsDown: boolean,
	HoldThread: thread?,
	SuppressEnded: boolean?,
}

export type AxisRuntime = {
	Config: AxisConfig,
	Value: Vector2,
	_mouseDeltaBuffer: Vector2, -- used only when Sources.Mouse == "MouseDelta"
}

export type InputController = {
	_actions: { [string]: ActionRuntime },
	_axes: { [string]: AxisRuntime },
	_blockCounts: { [string]: number },
	_bindingIndex: {
		[Enum.KeyCode | Enum.UserInputType]: { string },
	},
	_controls: any,

	BindAction: (
		self: InputController,
		name: string,
		callback: (ActionState, InputObject) -> (),
		priority: number?
	) -> () -> (),

	UnbindAction: (self: InputController, name: string, callback: (ActionState, InputObject) -> ()) -> (),
	Block: (self: InputController, nameOrGroup: string) -> (),
	Unblock: (self: InputController, nameOrGroup: string) -> (),
	Rebind: (
		self: InputController,
		actionName: string,
		device: InputDevice,
		bindings: { InputBinding }
	) -> (),

	IsActionDown: (self: InputController, name: string) -> boolean,
	GetAxis: (self: InputController, name: string) -> Vector2,

	_registerAction: (self: InputController, name: string, config: ActionConfig) -> (),
	_rebuildBindingIndex: (self: InputController) -> (),
	_isBlocked: (self: InputController, name: string) -> boolean,
	_connectInput: (self: InputController) -> (),
	_procInputChanged: (self: InputController) -> (),
	_fireBegan: (self: InputController, name: string, input: InputObject) -> (),
	_fireEnded: (self: InputController, name: string, input: InputObject) -> (),
	_dispatch: (self: InputController, name: string, state: ActionState, input: InputObject) -> (),
	_connectAxisUpdate: (self: InputController) -> (),
	_resolveDevice: (self: InputController) -> InputDevice,
	_readSource: (self: InputController, source: AxisSource, runtime: AxisRuntime) -> Vector2,
	_readThumbstick: (self: InputController, thumbstick: Enum.KeyCode) -> Vector2,
	_readTouchpad: (self: InputController) -> Vector2,
}

export type PhysicsObject = {
	Source: Instance,
	PhysicsStateChanged: Signal.Signal<boolean>,
	GetCFrame: () -> CFrame,

	IsPhysicsEnabled: (self: PhysicsObject) -> boolean,
	SetPhysicsStateEnabled: (self: PhysicsObject, isEnabled: boolean) -> (),
	EnablePhysics: (self: PhysicsObject) -> (),
	DisablePhysics: (self: PhysicsObject) -> (),
	Destroy: (self: PhysicsObject) -> (),

	_enabled: boolean,
	_forEveryBasePart: (self: PhysicsObject, callback: (BasePart) -> ()) -> (),
}

export type PhysicsController = {
	_registry: { [string]: PhysicsObject },
	newPhysicsObject: (source: Instance, initialState: boolean, getCFrame: () -> CFrame) -> PhysicsObject,
	RegisterPhysicsObject: (self: PhysicsController, guid: string, object: PhysicsObject) -> (),
	UnregisterPhysicsObject: (self: PhysicsController, guid: string) -> (),
	ActivatePhysicsWithinRadius: (self: PhysicsController, radius: number, origin: Vector3) -> (),
	DeactivatePhysicsWithinRadius: (self: PhysicsController, radius: number, origin: Vector3) -> (),

	ForAllPhysicsObjects: (self: PhysicsController, callback: (object: PhysicsObject) -> (), async: boolean?) -> (),
	ForAllInRadius: (
		self: PhysicsController,
		radius: number,
		origin: Vector3,
		callback: (object: PhysicsObject) -> (),
		async: boolean?
	) -> (),
}

export type InterfaceLayer = "HUD" | "Menu" | "Overlay" | "Popup"

export type InterfaceRegistration = {
	Instance: GuiObject,
	Group: string?, -- nil = independent, co-exists with everything
	Layer: InterfaceLayer?,
	OnOpen: ((self: InterfaceEntry, ...any) -> ())?,
	OnClose: ((self: InterfaceEntry) -> ())?,
}

export type InterfaceEntry = {
	Name: string,
	Instance: GuiObject,
	Group: string?,
	Layer: InterfaceLayer,
	IsOpen: boolean,
	Janitor: Janitor.Janitor,
	OnOpen: ((self: InterfaceEntry, ...any) -> ())?,
	OnClose: ((self: InterfaceEntry) -> ())?,
}

export type InterfaceController = {
	InterfaceOpened: Signal.Signal<string>,
	InterfaceClosed: Signal.Signal<string>,

	Registry: { [string]: InterfaceEntry },
	GroupState: { [string]: string? }, -- Group -> currently-open interface name

	Register: (self: InterfaceController, name: string, registration: InterfaceRegistration) -> (),
	Open: (self: InterfaceController, name: string, ...any) -> (),
	Close: (self: InterfaceController, name: string) -> (),
	Toggle: (self: InterfaceController, name: string, ...any) -> (),
	CloseGroup: (self: InterfaceController, group: string) -> (),
	IsOpen: (self: InterfaceController, name: string) -> boolean,
	GetOpenInGroup: (self: InterfaceController, group: string) -> string?,

	_setVisible: (self: InterfaceController, entry: InterfaceEntry, visible: boolean, ...any) -> (),
}

return {}
