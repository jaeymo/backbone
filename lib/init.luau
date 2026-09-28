--!strict
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_RUNNING = RunService:IsRunning()

local Types = require(script.Types)

local DEFAULTS = require(script.Defaults)

local Backbone = {
	Version = "1.0.0",
}

export type Backbone = typeof(Backbone)

-- Give all controllers the internal controller tag
for _, v in script:GetDescendants() do
	if v:IsA("ModuleScript") and v.Parent == script.Controllers then
		v:AddTag(DEFAULTS.INTERNAL_CONTROLLER_TAG)
	end
end

function Backbone.Server(self: Backbone): Types.ServerRuntime
	if not IS_SERVER then
		error(`[BACKBONE] Cannot call :Server() on the client!`)
	end

	return require(script.Core.Process.ServerRuntime) :: any
end

function Backbone.Client(self: Backbone): Types.ClientRuntime
	if IS_SERVER then
		error(`[BACKBONE] Cannot call :Client() on the server!`)
	end

	local server = script.Core.Process:FindFirstChild("ServerRuntime")
	if server and IS_RUNNING then
		server:Destroy()
	end

	return require(script.Core.Process.ClientRuntime) :: any
end

return Backbone
