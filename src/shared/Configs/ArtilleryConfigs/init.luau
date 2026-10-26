-- Collects every artillery config in this folder: ArtilleryConfigs.FieldArtillery, ...
local configs: { [string]: any } = {}
for _, module in script:GetChildren() do
	if module:IsA("ModuleScript") then
		local config = require(module)
		config.Id = module.Name -- so the server can tell clients which artillery to draw
		configs[module.Name] = config
	end
end
return configs
