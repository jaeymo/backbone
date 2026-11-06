--!strict
--[=[
	InterfaceController (client only)

	Registers GUI elements by name and owns opening and closing them. It handles mutually
	exclusive menus (Groups), draw order (Layers), per-open cleanup (`entry.Janitor`) and
	open/close signals, so the rest of your code only deals with names.

	Registering. `Instance` is the GuiObject that gets shown or hidden. Its starting
	`Visible` value decides whether it starts open.

	```lua
	InterfaceController:Register("Inventory", {
		Instance = playerGui.Menus.Inventory,
		Group = "Menus", -- optional: only one interface per Group is open at a time
		Layer = "Menu",  -- optional: defaults to "HUD"

		-- `...` is whatever was passed to :Open() / :Toggle()
		OnOpen = function(entry, tab: string?)
			selectTab(tab or "Weapons")

			-- Anything added to entry.Janitor is cleaned up when the interface closes
			entry.Janitor:Add(InputController:BindAction("Back", function(state)
				if state == "Began" then
					InterfaceController:Close("Inventory")
				end
			end))
		end,

		OnClose = function(entry)
			saveLayout()
		end,
	})
	```

	Opening and closing:

	```lua
	InterfaceController:Open("Inventory", "Armor") -- extra arguments go to OnOpen
	InterfaceController:Close("Inventory")
	InterfaceController:Toggle("Inventory")        -- also forwards arguments when opening

	InterfaceController:Open("Shop")               -- same Group: Inventory closes first
	InterfaceController:GetOpenInGroup("Menus")    --> "Shop"
	InterfaceController:CloseGroup("Menus")        -- closes whichever menu is open

	if InterfaceController:IsOpen("Shop") then end
	```

	Reacting from elsewhere:

	```lua
	InterfaceController.InterfaceOpened:Connect(function(name: string)
		if name == "Inventory" then
			InputController:Block("Combat")
		end
	end)

	InterfaceController.InterfaceClosed:Connect(function(name: string)
		if name == "Inventory" then
			InputController:Unblock("Combat")
		end
	end)
	```

	Common shapes:

	```lua
	-- Always-on HUD piece: no Group, so it coexists with everything
	InterfaceController:Register("AmmoCounter", { Instance = hud.AmmoCounter, Layer = "HUD" })

	-- Confirmation dialog: no Group, so it opens over a menu without closing it
	InterfaceController:Register("DropAllConfirm", { Instance = popups.DropAllConfirm, Layer = "PopUp" })

	-- Self-dismissing toast: the delay is cancelled if it's closed early
	InterfaceController:Register("Notice", {
		Instance = toasts.Notice,
		Layer = "Toast",
		OnOpen = function(entry, text: string)
			toasts.Notice.Label.Text = text
			entry.Janitor:Add(task.delay(3, function()
				InterfaceController:Close("Notice")
			end))
		end,
	})
	```

	Layers, lowest to highest: Effects < HUD < Menu < PopUp < Toast < Tooltip < Mask < Overlay.
	Use Mask for a full-screen fade (death, teleport) and Overlay for anything that must stay
	readable above it.

	Things to know:
	- A Layer is applied to the ScreenGui that contains `Instance` (DisplayOrder, ResetOnSpawn =
	  false, Sibling ZIndexBehavior). A ScreenGui has one Layer: the first interface registered
	  in it decides, so keep interfaces on different Layers in different ScreenGuis.
	- `Visible` changes immediately. OnOpen runs after the interface is shown, and OnClose runs
	  after it's hidden and after `entry.Janitor` is cleaned.
	- Opening an interface that's already open does nothing: OnOpen doesn't run again and the
	  new arguments are ignored. Close it first if you need to re-run OnOpen.
	- Registering a name twice warns and keeps the first registration.
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
