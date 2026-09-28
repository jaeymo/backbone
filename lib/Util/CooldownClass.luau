--!strict
local CooldownClass = {}
CooldownClass.__index = CooldownClass

export type CooldownClass = typeof(setmetatable(
	{} :: {
		_cooldowns: { [string]: number },
	},
	CooldownClass
))

function CooldownClass.new(): CooldownClass
	return setmetatable({
		_cooldowns = {},
	}, CooldownClass)
end

function CooldownClass.IsOnCooldown(self: CooldownClass, id: string): boolean
	local expires = self._cooldowns[id]
	return expires ~= nil and expires > os.clock()
end

function CooldownClass.GetRemaining(self: CooldownClass, id: string): number
	local expires = self._cooldowns[id]

	if not expires then
		return 0
	end

	return math.max(0, expires - os.clock())
end

function CooldownClass.Set(self: CooldownClass, id: string, duration: number)
	if duration <= 0 then
		return
	end

	self._cooldowns[id] = os.clock() + duration
end

function CooldownClass.Clear(self: CooldownClass, id: string)
	self._cooldowns[id] = nil
end

return CooldownClass
