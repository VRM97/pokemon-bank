local GameVersion = require("src.core.GameVersion")

local Species = {}

local FIRST_NON_GEN2_SPECIES = 252

local function gen3Module(name)
  local ok, module = pcall(require, name)
  return ok and type(module) == "table" and module or nil
end

local dexCache = setmetatable({}, { __mode = "k" })

local function idForDex(pokemon, dex)
  local byDex = dexCache[pokemon]
  if not byDex then
    byDex = {}
    for id, def in pairs(pokemon) do
      local n = type(def) == "table" and tonumber(def.dex)
      if n and (byDex[n] == nil or tostring(id) < byDex[n]) then byDex[n] = id end
    end
    dexCache[pokemon] = byDex
  end
  return byDex[dex]
end

function Species.text(mon)
  if type(mon) ~= "table" then return nil end
  if type(mon.species) == "string" then return mon.species end
  if type(mon.speciesAlt) == "string" then return mon.speciesAlt end
  return nil
end

function Species.number(mon)
  if type(mon) ~= "table" then return nil end
  if type(mon.species) == "number" then return mon.species end
  if type(mon.speciesAlt) == "number" then return mon.speciesAlt end
  return nil
end

function Species.key(mon) return Species.text(mon) or (type(mon) == "table" and mon.species) or nil end

function Species.setText(mon, text) if type(mon.species) == "string" then mon.species = text else mon.speciesAlt = text end end

function Species.toNumber(game, text)
  if type(text) ~= "string" then return nil end
  if GameVersion.generation() == 3 then
    local Compat = gen3Module("src.mods.Gen3Compat")
    local n = Compat and Compat.speciesId and Compat.speciesId(text)
    return type(n) == "number" and n or nil
  end
  local pokemon = game and game.data and game.data.pokemon
  local def = pokemon and pokemon[text]
  local dex = def and tonumber(def.dex)
  if not dex then return nil end
  if dex < FIRST_NON_GEN2_SPECIES then return dex end
  return nil
end

function Species.toText(game, number)
  if type(number) ~= "number" then return nil end
  local Compat
  if GameVersion.generation() == 3 then
    Compat = gen3Module("src.mods.Gen3Compat")
    local name = Compat and Compat.speciesName and Compat.speciesName(number)
    return type(name) == "string" and name or nil
  end
  local pokemon = game and game.data and game.data.pokemon
  if number < FIRST_NON_GEN2_SPECIES then
    return pokemon and idForDex(pokemon, number) or nil
  end
  return nil
end

function Species.pair(game, mon)
  if type(mon) ~= "table" then return false end
  if type(mon.species) == "string" and type(mon.speciesAlt) ~= "number" then
    local n = Species.toNumber(game, mon.species)
    if n then mon.speciesAlt = n return true end
  elseif type(mon.species) == "number" and type(mon.speciesAlt) ~= "string" then
    local t = Species.toText(game, mon.species)
    if t then mon.speciesAlt = t return true end
  end
  return false
end

function Species.reshape(game, mon)
  if type(mon) ~= "table" then return false end
  local changed = Species.pair(game, mon)
  if GameVersion.generation() == 3 then
    if type(mon.species) == "string" and type(mon.speciesAlt) == "number" then
      mon.species, mon.speciesAlt = mon.speciesAlt, mon.species
      mon.speciesId = mon.species
      return true
    end
  elseif type(mon.species) == "number" and type(mon.speciesAlt) == "string" then
    mon.species, mon.speciesAlt = mon.speciesAlt, mon.species
    return true
  end
  return changed
end

return Species
