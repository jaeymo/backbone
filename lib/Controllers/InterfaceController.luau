--!strict

--[=[

    ============= EXAMPLE USAGE ============= 

    ```lua
    InterfaceController:Register("Inventory", {
        Instance = hud.Inventory.Root,
        Group = "Menus", -- exclusive: opening this auto-closes Settings/Map/whatever else is in "Menus"
        Layer = "Menu",
    })

    InterfaceController:Register("KillFeed", {
        Instance = overlays.KillFeed.Root,
        -- no Group => independent, stays up regardless of what menu is open
        Layer = "Overlay",
    })

    InterfaceController:Register("KillConfirm", {
        Instance = overlays.KillConfirm.Root,
        Layer = "Popup",
        OnOpen = function(entry)
            entry.Janitor:Add(task.delay(2, function()
                InterfaceController:Close("KillConfirm")
            end))
        end,
    })
    ```
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = script.Parent.Parent
local util = root.Util

local Enums = require(root.Enums)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Types = require(root.Types)
local ValidateDisabledController = require(util.ValidateDisabledController)

local InterfaceController = {
	InterfaceOpened = Signal.new(),
	InterfaceClosed = Signal.new(),
	Registry = {},
	GroupState = {},
}

export type InterfaceLayer = Types.InterfaceLayer

export type InterfaceRegistration = Types.InterfaceRegistration

export type InterfaceEntry = Types.InterfaceEntry

export type InterfaceController = Types.InterfaceController

function InterfaceController.Register(self: InterfaceController, name: string, registration: InterfaceRegistration)
	ValidateDisabledController("INTERFACE")

	if self.Registry[name] ~= nil then
		warn(`[{script.Name}] "{name}" is already registered.`)
		return
	end

	local layer: Types.InterfaceLayer = registration.Layer or "HUD"
	local screenGui = registration.Instance:FindFirstAncestorWhichIsA("ScreenGui")

	if screenGui then
		if (Enums.InterfaceLayerOrder :: any)[layer] then
			screenGui.DisplayOrder = (Enums.InterfaceLayerOrder :: any)[layer]
		end
	end

	self.Registry[name] = {
		Name = name,
		Instance = registration.Instance,
		Group = registration.Group,
		Layer = layer,
		IsOpen = registration.Instance.Visible,
		Janitor = Janitor.new(),
		OnOpen = registration.OnOpen,
		OnClose = registration.OnClose,
	}
end

function InterfaceController.Open(self: InterfaceController, name: string, ...)
	ValidateDisabledController("INTERFACE")

	local entry = self.Registry[name]
	if not entry then
		warn(`[{script.Name}] Unknown interface: "{name}"`)
		return
	end

	if entry.Group then
		local openInGroup = self.GroupState[entry.Group]
		if openInGroup and openInGroup ~= name then
			self:Close(openInGroup)
		end

		self.GroupState[entry.Group] = name
	end

	self:_setVisible(entry, true, ...)
end

function InterfaceController.Close(self: InterfaceController, name: string)
	ValidateDisabledController("INTERFACE")
	local entry = self.Registry[name]
	if not entry then
		warn(`[{script.Name}] Unknown interface: "{name}"`)
		return
	end

	if entry.Group and self.GroupState[entry.Group] == name then
		self.GroupState[entry.Group] = nil
	end

	self:_setVisible(entry, false)
end

function InterfaceController.Toggle(self: InterfaceController, name: string, ...)
	ValidateDisabledController("INTERFACE")
	if self:IsOpen(name) then
		self:Close(name)
	else
		self:Open(name, ...)
	end
end

function InterfaceController.CloseGroup(self: InterfaceController, group: string)
	ValidateDisabledController("INTERFACE")

	local openInGroup = self.GroupState[group]
	if openInGroup then
		self:Close(openInGroup)
	end
end

function InterfaceController.IsOpen(self: InterfaceController, name: string)
	assert(
		ValidateDisabledController("INTERFACE", true),
		`[BACKBONE] Cannot use "INTERFACE" because it is disabled in the config!`
	)

	local entry = self.Registry[name]
	return entry ~= nil and entry.IsOpen
end

function InterfaceController.GetOpenInGroup(self: InterfaceController, group: string)
	assert(
		ValidateDisabledController("INTERFACE", true),
		`[BACKBONE] Cannot use "INTERFACE" because it is disabled in the config!`
	)

	return self.GroupState[group]
end

--[=[
    @priv
]=]
function InterfaceController._setVisible(self: InterfaceController, entry: InterfaceEntry, visible: boolean, ...: any)
	if entry.IsOpen == visible then
		return
	end
	entry.IsOpen = visible
	entry.Instance.Visible = visible

	if visible then
		if entry.OnOpen then
			entry.OnOpen(entry, ...)
		end
		self.InterfaceOpened:Fire(entry.Name)
	else
		entry.Janitor:Cleanup()
		if entry.OnClose then
			entry.OnClose(entry)
		end
		self.InterfaceClosed:Fire(entry.Name)
	end
end

return InterfaceController
