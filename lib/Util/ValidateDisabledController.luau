--!strict
local root = script.Parent.Parent

local Config = require(root.Core.Config)

local DEFAULTS = require(root.Defaults)

return function(controllerName: keyof<typeof(DEFAULTS.ENABLED_CONTROLLERS)>): boolean
	local config = Config.get()

	-- shut up luau, this keyof is correct
	local isEnabled = (config :: any).ENABLED_CONTROLLERS[controllerName]
	if not isEnabled then
		error(`[BACKBONE] Cannot use "{controllerName}" because it is disabled in the config!`)
	end

	return isEnabled
end
