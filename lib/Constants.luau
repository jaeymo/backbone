return {
	-- Storing defaults to fallback on in-case of a internal Backbone controller require, we don't want to rely on the user-supplied setting

	INIT_METHOD = "OnInit", -- Perform asynchronous tasks here
	AWAKE_METHOD = "OnAwake", -- Runs as soon as the module loads
	START_METHOD = "OnStart", -- Runs once all asynchronous start tasks are complete

	-- Keys match ENABLED_CONTROLLERS
	CLIENT_ONLY_CONTROLLERS = { INPUT = true, INTERFACE = true } :: { [string]: boolean },
	SERVER_ONLY_CONTROLLERS = {} :: { [string]: boolean },

	PLAYER_MODULE_NAME = "PlayerModule",
	INPUT_LEGACY_WAIT_SECONDS = 5,
	INPUT_MODERN_WAIT_SECONDS = 3,
}
