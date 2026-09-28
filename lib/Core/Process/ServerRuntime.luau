--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent.Parent

local Config = require(root.Core.Config)
local Promise = require(ReplicatedStorage.Packages.Promise)
local SharedRuntime = require(root.Core.Process.SharedRuntime)
local Types = require(root.Types)

--[=[
    @module ServerRuntime
    Server-sided bootstrapper and manager of the Backbone framework.  
]=]
local ServerRuntime = {
	_initialized = false,
}

setmetatable(ServerRuntime, { __index = SharedRuntime })

export type ServerRuntime = Types.ServerRuntime

function ServerRuntime.Start(self: ServerRuntime, directories: Instance | { Instance })
	Config.ensure()
	local config = Config.get()

	if self._initialized then
		error(`[BACKBONE] Server should only be started once!`)
	end

	self._initialized = true

	local networkLayer = self:GetNetworkLayer()
	networkLayer:Inject(networkLayer:BuildPacketsFromConfig(config.PACKETS))

	if config.LOGGING.BACKBONE_AWOKEN then
		print("======== BACKBONE STARTED ========")
		print("▸ Framework awoken.")
		print("▸ Runtime initialized.")
		print("▸ Import layer standing by.")
	end

	return Promise.new(function(resolve)
		self:GetImportLayer():Start(directories):finally(function()
			resolve()
		end)
	end):catch(function(err)
		warn("[BACKBONE] Startup failed:", err)
	end)
end

return ServerRuntime :: Types.ServerRuntime
