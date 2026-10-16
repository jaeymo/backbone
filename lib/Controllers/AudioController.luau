--!strict
local SoundService = game:GetService("SoundService")

local root = script.Parent.Parent
local util = root.Util

local Config = require(root.Core.Config)
local CooldownClass = require(util.CooldownClass)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local GROUP_ATTRIBUTE = "SoundGroup"

-- Part to use when placing audio in the world
local CACHED_PART = (function()
	local part = Instance.new("Part")
	part.Name = "Audio"
	part.Transparency = 1
	part.Material = Enum.Material.Plastic
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.one
	part.CanTouch = false
	part.Anchored = true

	return part
end)()

local AudioController = {
	Cooldowns = CooldownClass.new(),
	Registry = {} :: { [string]: Sound },
	Groups = {} :: { [string]: { Sound } },

	_groupCache = setmetatable({}, { __mode = "k" }) :: { [Sound]: SoundGroup | boolean },
	_warnedGroups = {} :: { [string]: boolean },
}

export type AudioOptions = Types.AudioOptions

export type AudioProperties = Types.AudioProperties

export type AudioContext = Types.AudioContext

export type AudioRequest = Types.AudioRequest

export type AudioResolver = Types.AudioResolver

export type AudioController = typeof(AudioController)

--[=[
    Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function AudioController.OnAwake(self: AudioController)
	ValidateDisabledController("AUDIO")

	for _, source in Config.get().AUDIO.SOURCES do
		for _, object in source:GetDescendants() do
			if object:IsA("Sound") then
				if self.Registry[object.Name] then
					warn(`[{script.Name}] Duplicate audio name "{object.Name}" in {object:GetFullName()}`)
				end
				self:RegisterAudio(object.Name, object)
			end
		end
	end
end

function AudioController.RegisterAudio(self: AudioController, name: string, sound: Sound)
	self.Registry[name] = sound

	if Config.get().LOGGING.AUDIO then
		print(`[{script.Name}] Registered audio "{name}"`)
	end
end

function AudioController.RegisterGroup(self: AudioController, name: string, folder: Instance)
	local sounds = {}

	for _, object in folder:GetChildren() do
		if object:IsA("Sound") then
			table.insert(sounds, object)
		end
	end

	self.Groups[name] = sounds

	if Config.get().LOGGING.AUDIO then
		print(`[{script.Name}] Registered group "{name}" ({#sounds} sounds)`)
	end
end

function AudioController.CreateRequests(
	self: AudioController,
	audioName: string,
	options: AudioOptions?
): { AudioRequest }
	local config = Config.get()
	local resolved: AudioOptions = options or {}
	local requests: { AudioRequest } = {}

	local resolver = config.AUDIO.RESOLVERS[audioName]

	if resolver then
		local result = resolver(resolved.Context or {}, resolved)

		if result == nil then
			return requests
		end

		if (result :: any).Audio ~= nil then
			requests = { result :: AudioRequest }
		else
			requests = result :: { AudioRequest }
		end
	else
		local sound = self.Registry[audioName]

		if not sound then
			if config.LOGGING.AUDIO then
				warn(`[{script.Name}] Unknown audio "{audioName}"`)
			end

			return requests
		end

		requests = { { Audio = sound } }
	end

	local applied: { AudioRequest } = {}

	for index, request in requests do
		applied[index] = self:_applyOptions(request, resolved)
	end

	return applied
end

function AudioController.Play(self: AudioController, audioName: string, options: AudioOptions?): { Sound }
	local sounds: { Sound } = {}

	for _, request in self:CreateRequests(audioName, options) do
		local sound = self:PlayRequest(request)

		if sound then
			table.insert(sounds, sound)
		end
	end

	return sounds
end

function AudioController.PlayAt(
	self: AudioController,
	audioName: string,
	position: Vector3,
	options: AudioOptions?
): { Sound }
	local merged: AudioOptions = table.clone(options or {}) :: AudioOptions
	merged.Position = position

	return self:Play(audioName, merged)
end

function AudioController.PlayOn(
	self: AudioController,
	audioName: string,
	parent: Instance,
	options: AudioOptions?
): { Sound }
	local merged: AudioOptions = table.clone(options or {}) :: AudioOptions
	merged.Parent = parent

	return self:Play(audioName, merged)
end

function AudioController.PlayRequest(self: AudioController, request: AudioRequest): Sound?
	local config = Config.get()

	if request.Cooldown then
		if self.Cooldowns:IsOnCooldown(request.Cooldown.Key) then
			if config.LOGGING.AUDIO then
				print(`[{script.Name}] Cooldown blocked "{request.Audio.Name}" ({request.Cooldown.Key})`)
			end

			return nil
		end

		self.Cooldowns:Set(request.Cooldown.Key, request.Cooldown.Duration)
	end

	local sound = request.Audio:Clone()

	if not sound.SoundGroup then
		sound.SoundGroup = self:_getSoundGroup(request.Audio)
	end

	if request.Properties then
		for property, value in request.Properties :: { [string]: any } do
			if property == "RandomizePitch" then
				continue
			end

			pcall(function()
				if typeof(value) == "function" then
					(sound :: any)[property] = (value :: any)()
				else
					(sound :: any)[property] = value
				end
			end)
		end

		if request.Properties.RandomizePitch then
			local pitch = Instance.new("PitchShiftSoundEffect")
			pitch.Octave = request.Properties.RandomizePitch()
			pitch.Parent = sound
		end
	end

	local parent: Instance
	local ownsPart = false

	if request.Parent then
		parent = request.Parent
	elseif request.Position or request.Weld then
		local part = CACHED_PART:Clone()

		part.CFrame = if request.Position then CFrame.new(request.Position) else (request.Weld :: BasePart).CFrame
		part.Parent = config.AUDIO.CONTAINER

		if request.Visualize then
			part.Transparency = 0.75
		end

		if request.Weld then
			local weld = Instance.new("WeldConstraint")

			weld.Part0 = request.Weld
			weld.Part1 = part
			weld.Parent = part
		end

		parent = part
		ownsPart = true
	else
		parent = SoundService
	end

	sound.Parent = parent
	sound:Play()

	if config.LOGGING.AUDIO then
		print(`[{script.Name}] Playing "{request.Audio.Name}"`)
	end

	if not sound.Looped then
		sound.Ended:Once(function()
			if ownsPart then
				parent:Destroy()
			elseif parent == SoundService then
				sound:Destroy()
			end
		end)
	end

	return sound
end

--[=[
    @priv
    Fills in anything the request doesn't specify from the call options.
    The request always wins. Returns a copy, so shared resolver tables are never mutated.
]=]
function AudioController._applyOptions(
	self: AudioController,
	request: AudioRequest,
	options: AudioOptions
): AudioRequest
	local applied = table.clone(request)

	applied.Position = request.Position or options.Position
	applied.Parent = request.Parent or options.Parent
	applied.Weld = request.Weld or options.Weld

	if request.Visualize == nil then
		applied.Visualize = options.Visualize
	end

	if options.Properties or request.Properties then
		local properties: { [string]: any } = table.clone((options.Properties or {}) :: any)

		for key, value in (request.Properties or {}) :: { [string]: any } do
			properties[key] = value
		end

		applied.Properties = properties :: any
	end

	return applied
end

--[=[
    @priv
    Finds the SoundGroup in SoundService that a SoundGroup attribute refers to.
    Accepts a plain name ("Effects", searched recursively) or a path ("World/Effects").
]=]
function AudioController._findGroup(self: AudioController, reference: string): SoundGroup?
	local found: Instance? = SoundService

	for _, segment in string.split(reference, "/") do
		found = if found == SoundService
			then SoundService:FindFirstChild(segment, true)
			else if found then found:FindFirstChild(segment) else nil

		if not found then
			return nil
		end
	end

	if found and found:IsA("SoundGroup") then
		return found
	end

	return nil
end

--[=[
    @priv
    Walks up from the asset to the nearest SoundGroup attribute and resolves it. Cached per asset.
    Resolved lazily (at play time, not registration) so SoundService has had time to replicate its groups.
    Failed lookups are not cached, so a group that shows up later still gets picked up.
]=]
function AudioController._getSoundGroup(self: AudioController, asset: Sound): SoundGroup?
	local cached = self._groupCache[asset]

	if cached ~= nil then
		return if typeof(cached) == "Instance" then cached else nil
	end

	local node: Instance? = asset

	while node do
		local reference = node:GetAttribute(GROUP_ATTRIBUTE)

		if typeof(reference) == "string" then
			local group = self:_findGroup(reference)

			if group then
				self._groupCache[asset] = group
				return group
			end

			if not self._warnedGroups[reference] then
				self._warnedGroups[reference] = true
				warn(`[{script.Name}] "{asset:GetFullName()}" references missing SoundGroup "{reference}"`)
			end

			return nil
		end

		node = node.Parent
	end

	self._groupCache[asset] = false

	return nil
end

return AudioController
