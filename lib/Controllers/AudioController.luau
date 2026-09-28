--!strict
local root = script.Parent.Parent
local util = root.Util

local Config = require(root.Core.Config)
local CooldownClass = require(util.CooldownClass)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

-- Part to use when placing sounds in the world
local CACHED_PART = (function()
	local part = Instance.new("Part")
	part.Name = "Sound"
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
}

--[=[
    Called when Backbone awakens this module. Perform synchronous setup here.
]=]
function AudioController.OnAwake(self: AudioController)
	ValidateDisabledController("AUDIO")

	for _, source in Config.get().AUDIO.SOURCES do
		for _, object in source:GetDescendants() do
			if object:IsA("Sound") then
				if self.Registry[object.Name] then
					warn(`[{script.Name}] Duplicate sound name "{object.Name}" in {object:GetFullName()}`)
				end
				self:RegisterSound(object.Name, object)
			end
		end
	end
end

export type Options = {
	Weld: BasePart?, -- attaches to an instance in the world
	Visualize: boolean?, -- should we visualize the sound instance?
	Context: AudioContext?, -- context passed to resolverss
	Properties: SoundProperties?, -- sound properties
}

export type SoundProperties = Types.SoundProperties

export type AudioContext = Types.AudioContext

export type SoundRequest = Types.SoundRequest

export type AudioController = typeof(AudioController)

function AudioController.CreateRequest(self: AudioController, soundName: string, options: Options?): SoundRequest?
	local config = Config.get()

	local resolvers = config.AUDIO.RESOLVERS
	local resolver = resolvers[soundName]

	if resolver then
		return resolver(options and options.Context)
	end

	local sound = self.Registry[soundName]

	if not sound then
		if config.LOGGING.AUDIO then
			warn(`[{script.Name}] Unknown sound "{soundName}"`)
		end

		return nil
	end

	return {
		Sound = sound,
		Weld = options and options.Weld,
		Properties = options and options.Properties,
		Visualize = options and options.Visualize or false,
	}
end

function AudioController.RegisterSound(self: AudioController, name: string, sound: Sound)
	local config = Config.get()

	self.Registry[name] = sound

	if config.LOGGING.AUDIO then
		print(`[{script.Name}] Registered sound "{name}"`)
	end
end

function AudioController.RegisterGroup(self: AudioController, name: string, folder: Instance)
	local config = Config.get()

	local sounds = {}

	for _, object in folder:GetChildren() do
		if object:IsA("Sound") then
			table.insert(sounds, object)
		end
	end

	self.Groups[name] = sounds

	if config.LOGGING.AUDIO then
		print(`[{script.Name}] Registered group "{name}" ({#sounds} sounds)`)
	end
end

function AudioController.Play(self: AudioController, soundName: string, options: Options?): Sound?
	local request = self:CreateRequest(soundName, options)

	if not request then
		return nil
	end

	return self:PlayRequest(request)
end

function AudioController.PlayAt(self: AudioController, soundName: string, position: Vector3, options: Options?): Sound?
	local request = self:CreateRequest(soundName, options)

	if not request then
		return nil
	end

	request.Position = position

	return self:PlayRequest(request)
end

function AudioController.PlayOn(self: AudioController, soundName: string, parent: Instance, options: Options?): Sound?
	local request = self:CreateRequest(soundName, options)

	if not request then
		return nil
	end

	request.Parent = parent

	return self:PlayRequest(request)
end

function AudioController.PlayRequest(self: AudioController, request: SoundRequest): Sound?
	local config = Config.get()

	if request.Cooldown then
		if self.Cooldowns:IsOnCooldown(request.Cooldown.Key) then
			if config.LOGGING.AUDIO then
				print(`[{script.Name}] Cooldown blocked "{request.Sound.Name}" ({request.Cooldown.Key})`)
			end

			return nil
		end

		self.Cooldowns:Set(request.Cooldown.Key, request.Cooldown.Duration)
	end

	local sound = request.Sound:Clone()

	if request.Properties then
		for property, value in request.Properties :: { [string]: any } do
			-- continue here because we don't want to burn a RNG call on this property
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

	local parent: Instance?

	if request.Parent then
		parent = request.Parent
	else
		parent = CACHED_PART:Clone()

		parent.CFrame = if request.Position
			then CFrame.new(request.Position)
			elseif request.Weld then request.Weld.CFrame
			else CFrame.new()

		parent.Parent = workspace

		if request.Visualize then
			parent.Transparency = 0.75
		end

		if request.Weld then
			local weld = Instance.new("WeldConstraint")

			weld.Part0 = request.Weld
			weld.Part1 = parent
			weld.Parent = parent
		end
	end

	sound.Parent = parent
	sound:Play()

	if config.LOGGING.AUDIO then
		print(`[{script.Name}] Playing "{request.Sound.Name}"`)
	end

	if not sound.Looped then
		sound.Ended:Once(function()
			if parent and parent ~= request.Parent then
				parent:Destroy()
			end
		end)
	end

	return sound
end

return AudioController
