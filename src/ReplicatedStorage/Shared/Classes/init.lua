--!strict

-- Class registry. Auto-loads child ModuleScripts (uma classe por arquivo)
-- na primeira vez que esse módulo é required. Cada arquivo exporta uma
-- ClassDefinition seguindo o contrato abaixo. Adicionar nova classe = criar
-- um arquivo novo aqui — sem editar este init.lua.

local script_ = script :: any

export type ClassDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	IconAssetId: string,
	Price: number,
	IsDefault: boolean,
	Moves: { [string]: any }, -- chaves arbitrárias por classe; cada move define Next pra encadear
	ComboStarter: string, -- chave do primeiro move do combo (M1 inicial)
	HeavyKey: string?, -- chave do move pesado (M2); nil = classe sem heavy
}

local Classes = {}

local catalog: { [string]: ClassDefinition } = {}
local defaultId: string? = nil
local orderedIds: { string } = {}

local function register(def: ClassDefinition)
	if typeof(def.Id) ~= "string" or def.Id == "" then
		error("Class.Id must be non-empty string")
	end
	if catalog[def.Id] ~= nil then
		error(string.format("Duplicate class registered: %s", def.Id))
	end
	catalog[def.Id] = def
	table.insert(orderedIds, def.Id)
	if def.IsDefault then
		-- if-then-error em vez de assert: assert avalia o segundo argumento
		-- antes de checar a condição, então string.format(..., defaultId, ...)
		-- explodiria quando defaultId == nil (caso normal: primeira classe
		-- default registrando).
		if defaultId ~= nil then
			error(string.format(
				"Multiple default classes (%s and %s) — apenas uma pode ter IsDefault=true",
				defaultId :: string, def.Id
			))
		end
		defaultId = def.Id
	end
end

for _, child in ipairs(script_:GetChildren()) do
	if child:IsA("ModuleScript") then
		local def = require(child) :: ClassDefinition
		assert(
			def.Id == child.Name,
			string.format("Class module name '%s' must match its Id '%s'", child.Name, def.Id)
		)
		register(def)
	end
end

assert(defaultId, "No default class found — pelo menos uma classe precisa de IsDefault=true")

function Classes.GetClass(id: string): ClassDefinition?
	return catalog[id]
end

function Classes.GetDefault(): ClassDefinition
	return catalog[defaultId :: string]
end

function Classes.GetDefaultId(): string
	return defaultId :: string
end

function Classes.Has(id: string): boolean
	return catalog[id] ~= nil
end

function Classes.GetCatalog(): { ClassDefinition }
	-- Retorna lista ordenada estável (ordem de descoberta dos child modules).
	-- Útil pra UI: ordem consistente entre clientes.
	local list: { ClassDefinition } = {}
	for _, id in ipairs(orderedIds) do
		table.insert(list, catalog[id])
	end
	return list
end

return Classes
