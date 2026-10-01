export type function DeepPartial(ty)
	local MAX_DEPTH = 16

	local function optional(t)
		if t:is("union") then
			for _, component in t:components() do
				if component:is("nil") then
					return t
				end
			end
		end
		return types.optional(t)
	end

	local function visit(t, depth)
		if depth > MAX_DEPTH then
			return t -- guard against self-referential types
		end

		if t:is("table") then
			local result = types.newtable()

			for key, prop in t:properties() do
				if prop.read then
					result:setreadproperty(key, optional(visit(prop.read, depth + 1)))
				end
				if prop.write then
					result:setwriteproperty(key, optional(visit(prop.write, depth + 1)))
				end
			end

			local indexer = t:indexer()
			if indexer then
				result:setindexer(indexer.index, visit(indexer.readresult, depth + 1))
			end

			local mt = t:metatable()
			if mt then
				result:setmetatable(mt)
			end

			return result
		elseif t:is("union") then
			local parts = {}
			for _, component in t:components() do
				table.insert(parts, visit(component, depth + 1))
			end
			return types.unionof(table.unpack(parts))
		end

		return t
	end

	return visit(ty, 0)
end

return {}
