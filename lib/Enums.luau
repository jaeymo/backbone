--!strict
local root = script.Parent

local Types = require(root.Types)

return {
	InterfaceLayerOrder = {
		Effects = { Order = 50 },
		HUD = { Order = 100 },
		Menu = { Order = 200 },
		PopUp = { Order = 300 },
		Toast = { Order = 350 },
		Tooltip = { Order = 400 },
		Mask = { Order = 500 },
		Overlay = { Order = 600 },
	} :: { [Types.InterfaceLayer]: { Order: number } },

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
