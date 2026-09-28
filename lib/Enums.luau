--!strict
local root = script.Parent

local Types = require(root.Types)

return {
	InterfaceLayerOrder = {
		Hud = {
			Order = 100,
		},
		Menu = {
			Order = 200,
		},
		Overlay = {
			Order = 300,
		},
		Popup = {
			Order = 400,
		},
	},

	LifecyclePhase = {
		Dead = {
			Priority = 0,
			Name = "Dead",
		},
		Awake = {
			Priority = 1,
			Name = "Awake",
		},
		Init = {
			Priority = 2,
			Name = "Init",
		},
		Start = {
			Priority = 3,
			Name = "Start",
		},
		Done = {
			Priority = 4,
			Name = "Done",
		},
	} :: { [Types.LifecyclePhaseName]: Types.LifecyclePhaseEnum },
}
