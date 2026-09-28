--!strict
local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = script.Parent.Parent
local util = root.Util

local Config = require(root.Core.Config)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Promise = require(ReplicatedStorage.Packages.Promise)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local AnimationController = {
	Objects = {} :: { [string]: AnimatorClass },
	DefaultVariantKey = "Default",
	AnimationMarkerReached = Signal.new() :: Signal.Signal<Types.MarkerReachedPayload>,
}

--[=[
	@class AnimatorClass 
]=]
local AnimatorClass = {}
AnimatorClass.__index = AnimatorClass

local activeMarkerFetches = 0

--[=[
    @priv  
]=]
local function waitForFetchSlot(maxConcurrentMarketFetches: number)
	while activeMarkerFetches >= maxConcurrentMarketFetches do
		task.wait()
	end

	activeMarkerFetches += 1
end

--[=[
    @priv
]=]
local function releaseFetchSlot()
	activeMarkerFetches = math.max(0, activeMarkerFetches - 1)
end

--[=[
    @priv
]=]
local function recurseMarkers(instance: Instance, output: { Instance })
	for _, child in instance:GetChildren() do
		if child:IsA("KeyframeMarker") then
			table.insert(output, child)
		end
		recurseMarkers(child, output)
	end
end

--[=[
    @priv
]=]
local function fetchKeyframeMarkers(id: number): { Instance }?
	local config = Config.get()

	local retries, maxConcurrent, backoff =
		config.ANIMATION.MARKER_FETCH_RETRIES,
		config.ANIMATION.MAX_CONCURRENT_MARKER_FETCHES,
		config.ANIMATION.MARKER_FETCH_BACKOFF_SECONDS

	waitForFetchSlot(maxConcurrent)

	local sequence: KeyframeSequence? = nil
	local lastError: string? = nil

	for attempt = 1, retries do
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:GetKeyframeSequenceAsync(`rbxassetid://{id}`)
		end)

		if ok then
			sequence = result :: KeyframeSequence
			break
		end

		lastError = tostring(result)
		if attempt < retries then
			task.wait(backoff * attempt)
		end
	end

	releaseFetchSlot()

	if not sequence then
		warn(`[AnimationController] Failed to load markers for rbxassetid://{id} after {retries} attempts: {lastError}`)
		return nil
	end

	local markers = {}
	recurseMarkers(sequence, markers)
	return markers
end
--[=[
	@priv
]=]
local function shouldSkip(track: AnimationTrack, overrides: PlayOverrides?): boolean
	return overrides ~= nil and overrides.SkipIfPlaying == true and track.IsPlaying
end

type AnimatorClass = Types.AnimatorClass

type AnimationController = Types.AnimationController

type AnimationDefinition = Types.AnimationDefinition

type FamilyTable = Types.AnimationFamilyTable

type AnimatorConfig = Types.AnimatorConfig

type PlayOverrides = Types.AnimationPlayOverrides

type InternalEntry = Types.AnimationInternalEntry

type MarkerReachedPayload = Types.MarkerReachedPayload

type PlayInOrderPredicate = (self: AnimatorClass, entry: InternalEntry) -> boolean

function AnimatorClass.new(groupId: string, animator: Animator?): AnimatorClass
	return setmetatable({
		Animator = animator,
		GroupId = groupId,
		Janitor = Janitor.new(),
		Played = Signal.new(),
		Entries = {},
		Adhoc = {},
		Families = {},
		ActiveVariant = {},
		_sequenceToken = 0,
	}, AnimatorClass) :: AnimatorClass
end

function AnimatorClass.SetAnimator(self: AnimatorClass, animator: Animator)
	if self.Animator and self.Animator ~= animator then
		warn(`[{script.Name}] ":SetAnimator()" called with different animator for "{self.GroupId}"`)
		return
	end

	self.Animator = animator
end

function AnimatorClass.IsRegistered(self: AnimatorClass): boolean
	return self.Animator ~= nil
end

function AnimatorClass.LoadFromConfig(self: AnimatorClass, config: AnimatorConfig): Promise.TypedPromise<()>
	return Promise.new(function(resolve, reject)
		if not self:_assertRegistered() then
			reject(`[{script.Name}] Animator is not registered`)
			return
		end

		-- Hard cast here because we called :_assertRegistered()
		if not (self.Animator :: Animator):IsDescendantOf(workspace) then
			reject(`[{script.Name}] Animator must be a descendant of workspace`)
			return
		end

		for name, definition in config.Animations do
			self:LoadAnimation(name, definition)
		end

		if config.Families then
			for familyName, familyTable in config.Families do
				if not familyTable[AnimationController.DefaultVariantKey] then
					warn(
						`[{script.Name}] Family "{familyName}" on "{self.GroupId}" has no "{AnimationController.DefaultVariantKey}" variant.`
					)
				end

				self.Families[familyName] = familyTable
				if not self.ActiveVariant[familyName] then
					self.ActiveVariant[familyName] = AnimationController.DefaultVariantKey
				end
			end
		end

		resolve()
	end)
end

function AnimatorClass.LoadAnimation(self: AnimatorClass, name: string, definition: AnimationDefinition): InternalEntry?
	if not self:_assertRegistered() then
		return nil
	end

	if self.Entries[name] then
		warn(`[{script.Name}] "{name}" already loaded on "{self.GroupId}", skipping.`)
		return self.Entries[name]
	end

	local animator = self.Animator :: Animator -- Hard cast here cuz we called :_assertRegistered()

	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{definition.Id}`

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok then
		warn(
			`[AnimationController] Failed to load animation "{name}" ({definition.Id}) on "{self.GroupId}": {trackOrError}`
		)
		return nil
	end

	local track = trackOrError :: AnimationTrack

	if definition.Looped ~= nil then
		track.Looped = definition.Looped :: boolean
	end
	if definition.Priority then
		track.Priority = definition.Priority :: Enum.AnimationPriority
	end

	local entry: InternalEntry = {
		Name = name,
		Id = definition.Id,
		Definition = definition,
		Track = track,
		Guid = HttpService:GenerateGUID(false),
		MarkersLoaded = false,
		MarkerJanitor = Janitor.new(),
	}

	self.Entries[name] = entry

	self.Janitor:Add(track, "Destroy", entry.Guid)
	self.Janitor:Add(entry.MarkerJanitor, "Destroy", entry.Guid .. "_markers")

	self:_loadMarkersAsync(entry)

	return entry
end

function AnimatorClass.GetRegistered(self: AnimatorClass, name: string): InternalEntry?
	return self.Entries[name]
end

function AnimatorClass.GetLoadedNames(self: AnimatorClass): { string }
	local names = {}
	for name in self.Entries do
		table.insert(names, name)
	end
	return names
end

function AnimatorClass.PlayInOrder(
	self: AnimatorClass,
	names: { string },
	overrides: PlayOverrides?,
	predicate: PlayInOrderPredicate?
): Promise.TypedPromise<()>
	local cancelled = false

	self._sequenceToken = (self._sequenceToken or 0) + 1

	local token = self._sequenceToken

	return Promise.new(function(resolve, reject, onCancel)
		onCancel(function()
			cancelled = true
		end)

		task.spawn(function()
			for _, name in names do
				if cancelled or token ~= self._sequenceToken then
					resolve()
					return
				end

				local track = self:Play(name, overrides)
				local entry = self:GetRegistered(name)

				if not track or not entry then
					continue
				end

				if track.Looped then
					warn(`[{script.Name}] Cannot call ":PlayInOrder()" with track "{name}" because it is looped`)
					continue
				end

				if predicate then
					while
						not cancelled
						and token == self._sequenceToken
						and not (predicate :: PlayInOrderPredicate)(self, entry) -- What is wrong with the typechecking here..?
					do
						task.wait()
					end
				else
					track.Ended:Wait()
				end
			end

			if not cancelled and token == self._sequenceToken then
				resolve()
			end
		end)
	end)
end

function AnimatorClass.GetMarkerReachedSignal(self: AnimatorClass, name: string, marker: string): RBXScriptSignal?
	local entry = self:GetRegistered(name)
	if not entry then
		warn(`[{script.Name}] No loaded animation named "{name}" on "{self.GroupId}"`)
		return nil
	end

	return entry.Track:GetMarkerReachedSignal(marker)
end

function AnimatorClass.SetFamilyVariant(self: AnimatorClass, familyName: string, variantKey: string)
	if not self.Families[familyName] then
		warn(`[{script.Name}] No family named "{familyName}" on "{self.GroupId}"`)
		return
	end

	self.ActiveVariant[familyName] = variantKey
end

function AnimatorClass.GetFamilyVariant(self: AnimatorClass, familyName: string): string?
	return self.ActiveVariant[familyName]
end

function AnimatorClass.GetTimePosition(self: AnimatorClass, name: string): number?
	local entry = self:GetRegistered(name)
	return entry and entry.Track.TimePosition
end

function AnimatorClass.SetTimePosition(self: AnimatorClass, name: string, position: number)
	local entry = self:GetRegistered(name)
	if not entry then
		warn(`[{script.Name}] No loaded animation named "{name}" on "{self.GroupId}"`)
		return
	end
	entry.Track.TimePosition = position
end

function AnimatorClass.SeekToProgress(self: AnimatorClass, name: string, alpha: number)
	local entry = self:GetRegistered(name)
	if not entry then
		return
	end
	entry.Track.TimePosition = math.clamp(alpha, 0, 1) * entry.Track.Length
end

function AnimatorClass.GetProgress(self: AnimatorClass, name: string): number?
	local entry = self:GetRegistered(name)
	if not entry or entry.Track.Length <= 0 then
		return nil
	end
	return entry.Track.TimePosition / entry.Track.Length
end

function AnimatorClass.BindToProgress(self: AnimatorClass, name: string, alpha: number, callback: () -> ()): (() -> ())?
	local entry = self:GetRegistered(name)
	if not entry then
		warn(`[{script.Name}] No loaded animation named "{name}" on "{self.GroupId}"`)
		return nil
	end

	local track = entry.Track
	local fired = false

	local heartbeatConn = RunService.Heartbeat:Connect(function()
		if not track.IsPlaying or track.Length <= 0 then
			return
		end

		local progress = track.TimePosition / track.Length
		if not fired and progress >= alpha then
			fired = true
			callback()
		end
	end)

	local resetConn = track:GetPropertyChangedSignal("TimePosition"):Connect(function()
		if track.TimePosition < (alpha * track.Length) then
			fired = false
		end
	end)

	entry.MarkerJanitor:Add(heartbeatConn)
	entry.MarkerJanitor:Add(resetConn)

	return function()
		heartbeatConn:Disconnect()
		resetConn:Disconnect()
	end
end

function AnimatorClass.Play(self: AnimatorClass, name: string, overrides: PlayOverrides?): AnimationTrack?
	if not self:_assertRegistered() then
		return nil
	end

	local entry = self:GetRegistered(name)
	if not entry then
		warn(`[{script.Name}] No loaded animation named "{name}" on "{self.GroupId}"`)
		return nil
	end

	if shouldSkip(entry.Track, overrides) then
		return entry.Track
	end

	local fadeTime = (overrides and overrides.FadeTime) or entry.Definition.FadeTime
	local weight = (overrides and overrides.Weight) or entry.Definition.Weight
	local speed = (overrides and overrides.Speed) or entry.Definition.Speed

	self.Played:Fire(entry)
	entry.Track:Play(fadeTime, weight, speed)

	return entry.Track
end

function AnimatorClass.PlayFamily(self: AnimatorClass, familyName: string, overrides: PlayOverrides?): AnimationTrack?
	local family = self.Families[familyName]
	if not family then
		warn(`[{script.Name}] No family named "{familyName}" on "{self.GroupId}"`)
		return nil
	end

	local variantKey = self.ActiveVariant[familyName] or AnimationController.DefaultVariantKey
	local animationName = family[variantKey] or family[AnimationController.DefaultVariantKey]

	if not animationName then
		warn(
			`[{script.Name}] Family "{familyName}" has no variant "{variantKey}" and no "{AnimationController.DefaultVariantKey}" fallback on "{self.GroupId}"`
		)
		return nil
	end

	return self:Play(animationName, overrides)
end

function AnimatorClass.PlayById(self: AnimatorClass, id: number, overrides: PlayOverrides?): AnimationTrack?
	if not self:_assertRegistered() then
		return nil
	end

	local entry = self.Adhoc[id]
	if not entry then
		local animator = self.Animator :: Animator

		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{id}`

		local ok, trackOrError = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		animation:Destroy()

		if not ok then
			warn(`[{script.Name}] Failed to load ad-hoc animation {id} on "{self.GroupId}": {trackOrError}`)
			return nil
		end

		local track = trackOrError :: AnimationTrack

		entry = {
			Name = `_adhoc:{id}`,
			Id = id,
			Definition = { Id = id },
			Track = track,
			Guid = HttpService:GenerateGUID(false),
			MarkersLoaded = false,
			MarkerJanitor = Janitor.new(),
		} :: InternalEntry

		self.Adhoc[id] = entry
		self.Janitor:Add(track, "Destroy", entry.Guid)
		self.Janitor:Add(entry.MarkerJanitor, "Destroy", entry.Guid .. "_markers")
		self:_loadMarkersAsync(entry)
	end

	if shouldSkip(entry.Track, overrides) then
		return entry.Track
	end

	self.Played:Fire(entry)

	local ovr = overrides
	entry.Track:Play(ovr and ovr.FadeTime, ovr and ovr.Weight, ovr and ovr.Speed)

	return entry.Track
end

function AnimatorClass.IsPlaying(self: AnimatorClass, name: string): boolean
	local entry = self:GetRegistered(name)
	return entry ~= nil and entry.Track.IsPlaying
end

function AnimatorClass.IsAdhocPlaying(self: AnimatorClass, id: number): boolean
	local entry = self.Adhoc[id]
	return entry ~= nil and entry.Track.IsPlaying
end

function AnimatorClass.Stop(self: AnimatorClass, name: string, fadeTime: number?): AnimationTrack?
	local entry = self:GetRegistered(name)
	if not entry then
		warn(`[{script.Name}] No loaded animation named "{name}" on "{self.GroupId}"`)
		return nil
	end

	entry.Track:Stop(fadeTime)
	return entry.Track
end

function AnimatorClass.StopFamily(self: AnimatorClass, familyName: string, fadeTime: number?): AnimationTrack?
	local family = self.Families[familyName]
	if not family then
		return nil
	end

	local variantKey = self.ActiveVariant[familyName] or AnimationController.DefaultVariantKey
	local animationName = family[variantKey] or family[AnimationController.DefaultVariantKey]
	if not animationName then
		return nil
	end

	return self:Stop(animationName, fadeTime)
end

function AnimatorClass.StopAll(self: AnimatorClass, fadeTime: number?)
	for _, entry in self.Entries do
		entry.Track:Stop(fadeTime)
	end

	for _, entry in self.Adhoc do
		entry.Track:Stop(fadeTime)
	end
end

function AnimatorClass.Reset(self: AnimatorClass)
	local function cleanEntry(entry: InternalEntry)
		entry.Track:Stop(0)
		entry.MarkerJanitor:Cleanup()
		entry.Track:Destroy()

		self.Janitor:RemoveNoClean(entry.Guid)
		self.Janitor:RemoveNoClean(entry.Guid .. "_markers")
	end

	for _, entry in self.Entries do
		cleanEntry(entry)
	end

	for _, entry in self.Adhoc do
		cleanEntry(entry)
	end

	self.Entries = {}
	self.Adhoc = {}
	self.Families = {}
	self.ActiveVariant = {}
end

function AnimatorClass.Reload(self: AnimatorClass, config: AnimatorConfig): Promise.TypedPromise<()>
	self:Reset()
	return self:LoadFromConfig(config)
end

function AnimatorClass.Destroy(self: AnimatorClass)
	self:Reset()
	self.Janitor:Destroy()
end

--[=[
    @priv
]=]
function AnimatorClass._loadMarkersAsync(self: AnimatorClass, entry: InternalEntry)
	task.spawn(function()
		local markers = fetchKeyframeMarkers(entry.Id)

		-- Entry may have been reset/removed while this was in action
		if not markers or (self.Entries[entry.Name] ~= entry and self.Adhoc[entry.Id] ~= entry) then
			return
		end

		local connectedMarkers = {} :: { [string]: boolean }

		for _, marker in markers do
			if connectedMarkers[marker.Name] then
				continue
			end

			connectedMarkers[marker.Name] = true

			entry.MarkerJanitor:Add(entry.Track:GetMarkerReachedSignal(marker.Name):Connect(function(...)
				if not self.Animator then
					return
				end

				AnimationController.AnimationMarkerReached:Fire({
					MarkerName = marker.Name,
					GroupId = self.GroupId,
					AnimationName = entry.Name,
					Animator = self.Animator,
					Track = entry.Track,
					Parameters = { ... },
				} :: MarkerReachedPayload)
			end))
		end

		entry.MarkersLoaded = true
	end)
end

--[=[
    @priv
]=]
function AnimatorClass._assertRegistered(self: AnimatorClass): boolean
	if not self:IsRegistered() then
		warn(`[{script.Name}] "{self.GroupId}" has no Animator set yet.`)
		return false
	end
	return true
end

function AnimationController.new(groupId: string, animator: Animator?): AnimatorClass
	assert(
		ValidateDisabledController("ANIMATION"),
		`[BACKBONE] Cannot use "ANIMATION" because it is disabled in the config!`
	)

	return AnimationController:Get(groupId, animator)
end

function AnimationController.Get(self: AnimationController, groupId: string, animator: Animator?): AnimatorClass
	assert(
		ValidateDisabledController("ANIMATION"),
		`[BACKBONE] Cannot use "ANIMATION" because it is disabled in the config!`
	)

	local existing = self.Objects[groupId]
	if existing then
		if animator then
			existing:SetAnimator(animator)
		end
		return existing
	end

	local created = AnimatorClass.new(groupId, animator)
	self.Objects[groupId] = created

	return created
end

function AnimationController.Destroy(self: AnimationController, groupId: string)
	assert(
		ValidateDisabledController("ANIMATION"),
		`[BACKBONE] Cannot use "ANIMATION" because it is disabled in the config!`
	)

	local existing = self.Objects[groupId]
	if not existing then
		return
	end

	existing:Destroy()
	self.Objects[groupId] = nil
end

return AnimationController
