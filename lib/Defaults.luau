--!strict
local SoundService = game:GetService("SoundService")

local root = script.Parent

local Types = require(root.Types)

local BACKBONE_DEFAULTS: Types.BackboneConfig = {
	INIT_METHOD = "OnInit", -- Perform asynchronous tasks here
	AWAKE_METHOD = "OnAwake", -- Runs as soon as the module loads
	START_METHOD = "OnStart", -- Runs once all asynchronous start tasks are complete

	MODULE_ATTRIBUTE_GUID_NAME = "__guid",
	IGNORE_MODULE_LOAD_TAG_NAME = "__ignore",
	INTERNAL_CONTROLLER_TAG = "__backboneController",

	PACKETS = {},

	ENABLED_CONTROLLERS = {
		ANIMATION = true,
		INTERFACE = true,
		CHARACTER = true,
		PHYSICS = true,
		ENTITY = true,
		AUDIO = true,
		INPUT = true,
	},

	LOGGING = {
		MODULE_NAME_ON_REQUIRE = false, -- Log the module name when it is required
		BACKBONE_AWOKEN = false, -- When Backbone is started
		PHASE_CHANGED = false, -- When the lifecycle phase is changed

		CHARACTER = false, -- Character Events
		ENTITY = false, -- Entity: Constructed, Spawned, Destroyed.
		AUDIO = false, -- Audio events
		INPUT = false, -- Input events
	},

	TAGS = {
		ACTOR = "Actor",
		ENTITY = "Entity",
		CHARACTER = "Character",
	},

	ATTRIBUTES = {
		ENTITY_ID = "Id",
		ENTITY_GUID = "Guid",
		ENTITY_TYPE = "Type",
		ENTITY_SPAWN_TIME = "SpawnTime",
		ENTITY_DEFINITION = "__definition",
	},

	COLLISION_GROUPS = {
		CHARACTER = "Character",
		CHARACTER_ROOT = "CharacterRoot",
	},

	AUDIO = {
		SOURCES = { SoundService },
		RESOLVERS = {},
	},

	ANIMATION = {
		DEFAULT_VARIANT_KEY = "Default",
		MAX_CONCURRENT_MARKER_FETCHES = 3,
		MARKER_FETCH_RETRIES = 3,
		MARKER_FETCH_BACKOFF_SECONDS = 0.5, -- Multiplied by attempt number
	},

	CHARACTER = {
		CLIENT_CHARACTER_MODEL_TIMEOUT = 10,
		BIND_TO_COLLISION_GROUP = true, -- Should the CharacterController update character collision groups based on the config?
	},

	ENTITY = {
		CLIENT_ENTITY_GUID_TIMEOUT = 10, -- How long will the client wait for an entity to have a Guid?
		PROXY_FOLDER_NAME = "__proxies", -- Folder inside of the ReplicatedStorage where entities, that don't yet exist in the world, live.
	},

	INPUT = {
		THUMBSTICK_DEADZONE = 0.15, -- How little wiggle-room a mobile thumbstick has before dispatching

		-- Blank Config
		CONFIG = {
			Actions = {},
			Axes = {},
		},
	},
}

return BACKBONE_DEFAULTS
