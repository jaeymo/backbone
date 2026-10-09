--!strict
--[=[

    ============= EXAMPLE USAGE =============

    Layers, lowest to highest: Effects < HUD < Menu < PopUp < Toast < Tooltip < Mask < Overlay.
    Everything below Mask is hidden by a fade to black; Overlay draws above it.

```lua
    -- Effects: full-screen, non-interactive visuals behind the HUD
    InterfaceController:Register("LowHealthVignette", {
        Instance = effects.LowHealthVignette.Root,
        Layer = "Effects",
    })

    -- HUD: always-on gameplay info. No group, pieces coexist
    InterfaceController:Register("AmmoCounter", {
        Instance = hud.AmmoCounter.Root,
        Layer = "HUD",
    })

    -- Menu: panels the player opens. Shared group => opening one closes the others
    InterfaceController:Register("Inventory", {
        Instance = menus.Inventory.Root,
        Group = "Menus",
        Layer = "Menu",
    })

    -- PopUp: dialogs that need an answer. Not in "Menus", so it opens over a menu without closing it
    InterfaceController:Register("DropAllConfirm", {
        Instance = popups.DropAllConfirm.Root,
        Layer = "PopUp",
    })

    -- Toast: brief, non-blocking notices that dismiss themselves. No group
    InterfaceController:Register("KillFeed", {
        Instance = toasts.KillFeed.Root,
        Layer = "Toast",
        OnOpen = function(entry)
            entry.Janitor:Add(task.delay(2, function()
                InterfaceController:Close("KillFeed")
            end))
        end,
    })

    -- Tooltip: follows the cursor, never interactive (item hover stats, dragged item icon)
    InterfaceController:Register("ItemTooltip", {
        Instance = tooltips.ItemTooltip.Root,
        Layer = "Tooltip",
    })

    -- Mask: the full-screen frame UIMaskController fades (death, teleport, scene change)
    InterfaceController:Register("Mask", {
        Instance = masks.Mask.Root,
        Layer = "Mask",
    })

    -- Overlay: must stay readable above the mask ("YOU DIED", loading text, fatal errors)
    InterfaceController:Register("DeathText", {
        Instance = overlays.DeathText.Root,
        Layer = "Overlay",
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

local LAYER_INSETS: { [string]: Enum.ScreenInsets } = {
	Effects = Enum.ScreenInsets.None,
	Mask = Enum.ScreenInsets.None,
	Tooltip = Enum.ScreenInsets.DeviceSafeInsets,
	Overlay = Enum.ScreenInsets.DeviceSafeInsets,
}
local InterfaceController = {
	InterfaceOpened = Signal.new(),
	InterfaceClosed = Signal.new(),
	Registry = {},
	GroupState = {},
	_guiLayers = setmetatable({}, { __mode = "k" }) :: { [ScreenGui]: InterfaceLayer },
	_layerCounts = {} :: { [string]: number },
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
	if not Enums.InterfaceLayerOrder[layer] then
		warn(`[{script.Name}] "{name}" has unknown Layer "{layer}", falling back to HUD`)
		layer = "HUD"
	end

	self:_configureGui(name, registration.Instance, layer)

	local entry = {
		Name = name,
		Instance = registration.Instance,
		Group = registration.Group,
		Layer = layer,
		IsOpen = registration.Instance.Visible,
		Janitor = Janitor.new(),
		OnOpen = registration.OnOpen,
		OnClose = registration.OnClose,
	}

	self.Registry[name] = entry

	if entry.IsOpen and entry.Group then
		self.GroupState[entry.Group] = name
	end
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
	ValidateDisabledController("INTERFACE")

	local entry = self.Registry[name]
	return entry ~= nil and entry.IsOpen
end

function InterfaceController.GetOpenInGroup(self: InterfaceController, group: string)
	ValidateDisabledController("INTERFACE")

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

--[=[
    @priv
    Applies a layer to the premade ScreenGui containing `instance`.
]=]
function InterfaceController._configureGui(
	self: InterfaceController,
	name: string,
	instance: GuiObject,
	layer: Types.InterfaceLayer
)
	local gui = instance:FindFirstAncestorWhichIsA("ScreenGui")
	if not gui then
		warn(`[{script.Name}] "{name}" isn't inside a ScreenGui, so Layer "{layer}" can't be applied`)
		return
	end

	local assigned = self._guiLayers[gui]
	if assigned then
		if assigned ~= layer then
			warn(
				`[{script.Name}] "{name}" wants Layer "{layer}" but its ScreenGui "{gui.Name}" is already on "{assigned}"; keeping "{assigned}"`
			)
		end
		return
	end

	local count = self._layerCounts[layer] or 0
	self._layerCounts[layer] = count + 1
	self._guiLayers[gui] = layer

	gui.DisplayOrder = Enums.InterfaceLayerOrder[layer].Order + count
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local insets = LAYER_INSETS[layer]
	if insets then
		gui.ScreenInsets = insets
	end
end

return InterfaceController
