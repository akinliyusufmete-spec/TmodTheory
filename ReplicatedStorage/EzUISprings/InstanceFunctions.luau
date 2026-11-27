local InstanceFunctions = {}

function InstanceFunctions:Populate(Instance: Instance, Properties: {any}) -- this literally just applies properties to instances, that's it.
	local function RecurseProperty(Instance: Instance, Table: {any}, DeepTab: {any})
		Table = Table or {}
		DeepTab = DeepTab or {}

		for PropertyName, Value in Table do
			if PropertyName == "__index" then
				continue
			end

			if typeof(Value) == "table" then
				table.insert(DeepTab, PropertyName)
				RecurseProperty(Instance[PropertyName], Value, DeepTab)
			end

			local _, Error = pcall(function ()
				Instance[PropertyName] = Value
			end)

			if Error then
				warn(Error)
				continue
			end
		end
	end

	Properties = Properties or {}
	for PropertyName, Value in Properties do

		if PropertyName == "__index" then
			continue
		end

		if typeof(Value) == "table" then
			RecurseProperty(Instance[PropertyName], Value)
		end

		local _, Error = pcall(function ()
			Instance[PropertyName] = Value
		end)

		if Error then
			warn(Error)
			continue
		end
	end
	
	return Instance
end

return InstanceFunctions