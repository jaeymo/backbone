--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent.Parent

local Config = require(root.Core.Config)
local Promise = require(ReplicatedStorage.Packages.Promise)
local SharedRuntime = require(root.Core.Process.SharedRuntime)
local Types = require(root.Types)

--[=[
    @module ClientRuntime
    Client-sided bootstrapper and manager of the Backbone framework.  
]=]
local ClientRuntime = {
	_initialized = false,
}

setmetatable(ClientRuntime, { __index = SharedRuntime })

export type ClientRuntime = Types.ClientRuntime

function ClientRuntime.Start(self: ClientRuntime, directories: Instance | { Instance })
	if self._initialized then
		error(`[BACKBONE] Client should only be started once!`)
	end

	Config.ensure()
	local config = Config.get()
	self._initialized = true

	local networkLayer = self:GetNetworkLayer()
	networkLayer:Inject(networkLayer:BuildPacketsFromConfig(config.PACKETS))

	return Promise.new(function(resolve)
		self:GetImportLayer():Start(directories):finally(function()
			resolve()
		end)
	end):catch(function(err)
		warn("[BACKBONE] Startup failed:", err)
	end)
end

return ClientRuntime :: Types.ClientRuntime
