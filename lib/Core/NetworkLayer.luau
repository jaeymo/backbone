--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent

local Packet = require(ReplicatedStorage.Packages.Packet)
local Types = require(root.Types)

local IS_SERVER = RunService:IsServer()

local NetworkLayer = {
	Packets = nil :: { [string]: Packet }?,
}

type Packet = Types.Packet

type Connection = Types.Connection

export type NetworkLayer = Types.NetworkLayer

--[=[
    @priv
]=]
local function buildExcluded(except: (Player | { Player })?): { [Player]: boolean }
	local excluded: { [Player]: boolean } = {}

	if typeof(except) == "Instance" then
		if except:IsA("Player") then
			excluded[except] = true
		end
	elseif type(except) == "table" then
		for _, v in except do
			if typeof(v) == "Instance" and v:IsA("Player") then
				excluded[v] = true
			end
		end
	end

	return excluded
end

function NetworkLayer.CreatePacket(self: NetworkLayer, ...: any): Packet
	return Packet.new(...)
end

function NetworkLayer.GetPacket(self: NetworkLayer, packetName: string): Packet
	if type(packetName) ~= "string" then
		error(`[{script.Name}] "PacketName" is not a string, got: {type(packetName)}`)
	end

	if not self.Packets then
		error(`[{script.Name}] Packets have not been injected`)
	end

	local packet = self.Packets[packetName]
	if not packet then
		error(`[{script.Name}] Missing packet with name: {packetName}`)
	end

	return self.Packets[packetName]
end

function NetworkLayer.Inject(self: NetworkLayer, packets: { [string]: any })
	if self.Packets then
		error(`[{script.Name}] Cannot inject multiple packet registries`)
	end

	self.Packets = packets
end

function NetworkLayer.SendClient(self: NetworkLayer, packetName: string, client: Player, ...: any): ...any
	assert(client:IsA("Player"), `[{script.Name}] "Client" is not a player!`)

	return self:GetPacket(packetName):FireClient(client, ...)
end

function NetworkLayer.SendServer(self: NetworkLayer, packetName: string, ...: any): ...any
	return self:GetPacket(packetName):Fire(...)
end

function NetworkLayer.Broadcast(self: NetworkLayer, packetName: string, ...: any)
	return self:GetPacket(packetName):Fire(...)
end

function NetworkLayer.BroadcastExcept(self: NetworkLayer, packetName: string, except: Player | { Player }, ...: any)
	if type(packetName) ~= "string" then
		error(`[{script.Name}] PacketName is not a string, got: {type(packetName)}`)
	end

	local fetched = self:GetPacket(packetName)

	if not IS_SERVER then
		error(`[{script.Name}] Cannot call ":BroadcastExcept()" on the client!`)
		return
	end

	local excluded = buildExcluded(except)

	for _, player in Players:GetPlayers() do
		if excluded[player] then
			continue
		end

		fetched:FireClient(player, ...)
	end
end

function NetworkLayer.BroadcastInRange(
	self: NetworkLayer,
	packetName: string,
	position: Vector3,
	range: number,
	except: (Player | { Player })?,
	...: any
)
	local fetched = self:GetPacket(packetName)

	if not IS_SERVER then
		error(`[{script.Name}] Cannot call ":BroadcastInRange()" on the client!`)
		return
	end

	local excluded = buildExcluded(except)

	for _, player in Players:GetPlayers() do
		if excluded[player] then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		if (character:GetPivot().Position - position).Magnitude <= range then
			fetched:FireClient(player, ...)
		end
	end
end

function NetworkLayer.OnInvoke(self: NetworkLayer, packetName: string, callback: (...any) -> ...any?)
	local fetched = self:GetPacket(packetName)

	if IS_SERVER then
		fetched.OnServerInvoke = callback
	else
		fetched.OnClientInvoke = callback
	end
end

function NetworkLayer.OnServer(self: NetworkLayer, packetName: string, Callback: (Player, ...any) -> ()): Connection
	assert(IS_SERVER, `[{script.Name}] OnServer called on client!`)

	return self:GetPacket(packetName).OnServerEvent:Connect(Callback) :: Connection
end

function NetworkLayer.OnClient(self: NetworkLayer, packetName: string, Callback: (...any) -> ()): Connection
	assert(not IS_SERVER, `[{script.Name}] OnClient called on server!`)

	return self:GetPacket(packetName).OnClientEvent:Connect(Callback) :: Connection
end

function NetworkLayer.BuildPacketsFromConfig(
	self: NetworkLayer,
	packets: Types.NetworkPacketConfig & { [string]: any } -- casted to { [string]: any } so we don't have type errors, but the true type is sourced in /Types.luau
): { [string]: Packet }
	local build = {}

	for _, config: Types.NetworkPacketConfig in packets do
		local packet = (Packet :: any).new(config.NAME, config.PAYLOAD) :: Packet

		if config.RESPONSE ~= nil then
			packet = packet:Response(config.RESPONSE)
		end

		build[config.NAME] = packet

		if config.UNRELIABLE ~= true then
			continue
		end

		if IS_SERVER then
			local unreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
			unreliableRemoteEvent.Name = packet.Name
			unreliableRemoteEvent.Parent = ReplicatedStorage

			unreliableRemoteEvent.OnServerEvent:Connect(function(player, ...)
				packet.OnServerEvent:Fire(player, packet:Deserialize(...))
			end)

			packet.Fire = function(self: Packet, ...)
				unreliableRemoteEvent:FireAllClients(self:Serialize(...))
			end

			packet.FireClient = function(self: Packet, player: Player, ...)
				unreliableRemoteEvent:FireClient(player, self:Serialize(...))
			end
		else
			local unreliableRemoteEvent = ReplicatedStorage:WaitForChild(packet.Name) :: UnreliableRemoteEvent

			unreliableRemoteEvent.OnClientEvent:Connect(function(...)
				packet.OnClientEvent:Fire(packet:Deserialize(...))
			end)

			packet.Fire = function(self: Packet, ...)
				unreliableRemoteEvent:FireServer(self:Serialize(...))
			end
		end
	end

	return build
end

return NetworkLayer
