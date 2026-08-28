local V = ...

local MAX_LEVEL = 100
local MAX_DV = 15
local MAX_STAT_EXP = 65535

local GameVersion = require("src.core.GameVersion")
local Growth = require("src.pokemon.Growth")
local Merge = require("src.mods.Merge")

local Legality = {}

local function crystal251(mod) return mod.find and mod.find("CRYSTAL_251") end

local function isInt(n) return type(n) == "number" and n == math.floor(n) end

local function clamp(v, min, max)
  if not isInt(v) then
    v = tonumber(v)
    v = v and math.floor(v + 0.5) or min
  end
  if v < min then return min end
  if v > max then return max end
  return v
end

local function fixSpecialPair(t, maxVal, alwaysDefault)
  if t.special ~= nil then
    t.special = clamp(t.special, 0, maxVal)
  elseif alwaysDefault or t.specialAttack ~= nil or t.specialDefense ~= nil then
    local spc = clamp(t.specialAttack or t.specialDefense, 0, maxVal)
    t.specialAttack, t.specialDefense = spc, spc
  end
end

local function specialValue(value)
  if value.special ~= nil then return value.special end
  if value.specialAttack ~= nil and value.specialDefense ~= nil and value.specialAttack ~= value.specialDefense then return nil end
  return value.specialAttack or value.specialDefense
end

local function hpDvFromBits(atk, def, spd, spc)
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok then return nil end
  return Mon.hpDV({ attack = atk, defense = def, speed = spd, special = spc })
end

local function ppStep(mdef)
  return math.floor((mdef and mdef.pp or 0) / 5)
end

local function crystal251Gender(mod, species, dvs, c251)
  local Gender = c251 and c251.exports and c251.exports.crystalGender
  local value = Gender and Gender.forSpeciesDVs(species, dvs or {})
  if value == "M" then return "male" end
  if value == "F" then return "female" end
  return nil
end

local function isNoEggSpecies(def, c251)
  if c251 then
    local groups = def.crystalEggGroups
    if type(groups) ~= "table" then return true end
    return tonumber(groups[1]) == 15 and tonumber(groups[2]) == 15
  end
  if type(def.eggGroupsRaw) == "number" then return def.eggGroupsRaw == 0xFF end
  local groups = def.eggGroups
  if type(groups) ~= "table" then return true end
  return groups[1] == "EGG_NONE" and groups[2] == "EGG_NONE"
end

local function eggMoveKnown(mod, def, moveId, c251)
  if mod.exports.speciesKnowsMove and mod.exports.speciesKnowsMove(def, moveId) then return true end
  if c251 and type(def.crystalEggMoves) == "table" then
    for _, id in ipairs(def.crystalEggMoves) do
      if id == moveId then return true end
    end
  end
  return false
end

local function checkLevel(game, def, mon)
  local level = mon.level
  if not isInt(level) or level < 1 or level > MAX_LEVEL then
    return false, "level out of range"
  end
  local expVal = mon.exp or mon.experience
  if expVal ~= nil and def.growthRate then
    local rates = game.data.growth_rates
    local expected = Growth.levelForExp(def.growthRate, expVal, MAX_LEVEL, rates)
    if expected ~= level then return false, "level does not match exp" end
  end
  return true
end

local function fixLevel(game, def, mon)
  local expVal = mon.exp or mon.experience
  if expVal ~= nil and def.growthRate then
    local rates = game.data.growth_rates
    local expected = Growth.levelForExp(def.growthRate, expVal, MAX_LEVEL, rates)
    if isInt(expected) and expected >= 1 and expected <= MAX_LEVEL then
      mon.level = expected
      return
    end
  end
  mon.level = clamp(mon.level, 1, MAX_LEVEL)
end

local function checkDVs(mon)
  local dvs = mon.dvs
  if type(dvs) ~= "table" then return false, "missing dvs" end
  for _, key in ipairs({ "attack", "defense", "speed" }) do
    local v = dvs[key]
    if not isInt(v) or v < 0 or v > MAX_DV then return false, "dv out of range: " .. key end
  end
  local spc = specialValue(dvs)
  if not isInt(spc) or spc < 0 or spc > MAX_DV then return false, "dv out of range: special" end
  local expectedHp = hpDvFromBits(dvs.attack, dvs.defense, dvs.speed, spc)
  if dvs.hp ~= nil and expectedHp ~= nil and dvs.hp ~= expectedHp then
    return false, "hp dv does not match its own bits"
  end
  return true
end

local function fixDVs(mon)
  local dvs = mon.dvs
  if type(dvs) ~= "table" then
    dvs = {}
    mon.dvs = dvs
  end
  dvs.attack = clamp(dvs.attack, 0, MAX_DV)
  dvs.defense = clamp(dvs.defense, 0, MAX_DV)
  dvs.speed = clamp(dvs.speed, 0, MAX_DV)
  fixSpecialPair(dvs, MAX_DV, true)
  local expectedHp = hpDvFromBits(dvs.attack, dvs.defense, dvs.speed, specialValue(dvs))
  if expectedHp ~= nil then dvs.hp = expectedHp end
end

local function checkStatExp(mon)
  local se = mon.statExp
  if type(se) ~= "table" then return true end
  for _, key in ipairs({ "hp", "attack", "defense", "speed" }) do
    local v = se[key]
    if v ~= nil and (not isInt(v) or v < 0 or v > MAX_STAT_EXP) then
      return false, "stat exp out of range: " .. key
    end
  end
  local spc = se.special or se.specialAttack or se.specialDefense
  if spc ~= nil and (not isInt(spc) or spc < 0 or spc > MAX_STAT_EXP) then
    return false, "stat exp out of range: special"
  end
  return true
end

local function fixStatExp(mon)
  local se = mon.statExp
  if type(se) ~= "table" then return end
  for _, key in ipairs({ "hp", "attack", "defense", "speed" }) do
    if se[key] ~= nil then se[key] = clamp(se[key], 0, MAX_STAT_EXP) end
  end
  fixSpecialPair(se, MAX_STAT_EXP, false)
end

local function checkStatExpTotal(mon)
  if GameVersion.generation() ~= 2 then return true end
  local se = mon.statExp
  if type(se) ~= "table" then return true end
  local total = (se.hp or 0) + (se.attack or 0) + (se.defense or 0) + (se.speed or 0) + (specialValue(se) or 0)
  if not isInt(total) or total < 0 or total > MAX_STAT_EXP then
    return false, "stat exp total out of range"
  end
  return true
end

local function fixStatExpTotal(mon)
  if GameVersion.generation() ~= 2 then return end
  local se = mon.statExp
  if type(se) ~= "table" then return end
  local spc = specialValue(se) or 0
  local total = (se.hp or 0) + (se.attack or 0) + (se.defense or 0) + (se.speed or 0) + spc
  if total <= MAX_STAT_EXP then return end
  local factor = MAX_STAT_EXP / total
  for _, key in ipairs({ "hp", "attack", "defense", "speed" }) do
    if se[key] ~= nil then se[key] = math.floor(se[key] * factor) end
  end
  if se.special ~= nil then
    se.special = math.floor(se.special * factor)
  elseif se.specialAttack ~= nil or se.specialDefense ~= nil then
    local newSpc = math.floor(spc * factor)
    se.specialAttack, se.specialDefense = newSpc, newSpc
  end
end

local function checkMoves(mod, core, game, mon)
  local moves = mon.moves
  if type(moves) ~= "table" or #moves < 1 or #moves > 4 then
    return false, "invalid move count"
  end
  local canLearn = mod.exports.canLearn
  local seen = {}
  for _, mv in ipairs(moves) do
    local id = core.moveEntryId(mv)
    if type(id) ~= "string" or seen[id] then return false, "duplicate or invalid move" end
    seen[id] = true
    if canLearn and not canLearn(game, mon, id) then
      return false, "unlearnable move: " .. id
    end
    if type(mv) == "table" then
      local mdef = game.data.moves and game.data.moves[id]
      if mdef then
        local step = ppStep(mdef)
        if mv.maxPp ~= nil then
          local valid = false
          for k = 0, 3 do
            if mv.maxPp == mdef.pp + k * step then valid = true break end
          end
          if not valid then return false, "invalid max pp: " .. id end
        elseif mv.ppUps ~= nil and (not isInt(mv.ppUps) or mv.ppUps < 0 or mv.ppUps > 3) then
          return false, "invalid pp ups: " .. id
        end
      end
    end
  end
  return true
end

local function fixMoves(mod, core, game, mon)
  local moves = mon.moves
  if type(moves) ~= "table" then return false end
  local canLearn = mod.exports.canLearn
  local seen, kept = {}, {}
  for _, mv in ipairs(moves) do
    local id = core.moveEntryId(mv)
    if type(id) == "string" and not seen[id] and not (canLearn and not canLearn(game, mon, id)) then
      seen[id] = true
      kept[#kept + 1] = mv
    end
  end
  while #kept > 4 do table.remove(kept) end
  if #kept == 0 then return false end
  for _, mv in ipairs(kept) do
    if type(mv) == "table" then
      local id = core.moveEntryId(mv)
      local mdef = game.data.moves and game.data.moves[id]
      if mdef then
        local step = ppStep(mdef)
        if mv.maxPp ~= nil then
          local ppUps = clamp(step > 0 and (mv.maxPp - mdef.pp) / step or 0, 0, 3)
          mv.maxPp = mdef.pp + ppUps * step
        elseif mv.ppUps ~= nil then
          mv.ppUps = clamp(mv.ppUps, 0, 3)
        end
      end
    end
  end
  mon.moves = kept
  return true
end

local function checkCatchRate(mod, game, def, mon)
  if GameVersion.generation() ~= 1 or mon.catchRate == nil then return true end
  if mon.catchRate == def.catchRate then return true end
  local prevolutionOf = mod.exports.prevolutionOf
  if not prevolutionOf then return true end
  local species, seen = mon.species, { [mon.species] = true }
  while true do
    local prev = prevolutionOf(game, species)
    if not prev or seen[prev] then break end
    seen[prev] = true
    local prevDef = game.data.pokemon[prev]
    if prevDef and mon.catchRate == prevDef.catchRate then return true end
    species = prev
  end
  return false, "catch rate matches no stage of its own line"
end

local function fixCatchRate(mod, game, def, mon)
  if GameVersion.generation() ~= 1 or mon.catchRate == nil then return end
  mon.catchRate = def.catchRate
end

local function checkGender(mod, def, mon)
  if GameVersion.generation() == 1 then
    local c251 = crystal251(mod)
    if c251 and mon.gender == crystal251Gender(mod, mon.species, mon.dvs, c251) then return true end
  elseif GameVersion.generation() == 2 and def.genderRatio == nil then return true end
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok then return true end
  if mon.gender == Mon.vanillaGender(def, mon.dvs or {}) then return true end
  return false, "gender does not match its own dvs"
end

local function fixGender(mod, def, mon)
  if GameVersion.generation() == 1 then
    local c251 = crystal251(mod)
    if c251 then
      mon.gender = crystal251Gender(mod, mon.species, mon.dvs, c251)
      return
    end
  elseif GameVersion.generation() == 2 and def.genderRatio == nil then return end
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok then return end
  mon.gender = Mon.vanillaGender(def, mon.dvs or {})
end

local function checkShiny(mon)
  if GameVersion.generation() ~= 2 then return true end
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok then return true end
  local shiny = mon.shiny or false
  if shiny ~= Mon.vanillaShiny(mon.dvs or {}) then return false, "shiny does not match its own dvs" end
  return true
end

local function fixShiny(mon)
  if GameVersion.generation() ~= 2 then return end
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not ok then return end
  mon.shiny = Mon.vanillaShiny(mon.dvs or {})
end

local function checkEgg(mod, core, def, mon)
  local c251 = GameVersion.generation() == 1 and crystal251(mod)
  if GameVersion.generation() == 1 and not c251 then return false, "eggs are not valid in this game" end
  if isNoEggSpecies(def, c251) then return false, "species cannot produce eggs" end
  local moves = mon.moves
  if type(moves) == "table" then
    for _, mv in ipairs(moves) do
      local id = core.moveEntryId(mv)
      if id and not eggMoveKnown(mod, def, id, c251) then
        return false, "unlearnable egg move: " .. id
      end
    end
  end
  return true
end

local function fixEggMoves(mod, core, def, mon, c251)
  local moves = mon.moves
  if type(moves) ~= "table" then return end
  local kept = {}
  for _, mv in ipairs(moves) do
    local id = core.moveEntryId(mv)
    if id and eggMoveKnown(mod, def, id, c251) then kept[#kept + 1] = mv end
  end
  mon.moves = kept
end

local function checkHeldItem(mod, game, mon)
  if GameVersion.generation() ~= 1 then return true end
  local item = mon.heldItem or mon.item
  if not item then return true end
  if GameVersion.generation() == 1 then
    local c251 = crystal251(mod)
    if not c251 then return true end
    local canGive = c251.exports and c251.exports.heldItemManagement and c251.exports.heldItemManagement.canGive
    if not canGive then return true end
    local ok, reason = canGive(game.data, mon, item)
    if not ok then return false, "invalid held item: " .. (reason or "?") end
  elseif GameVersion.generation() == 2 then
    local def = game.data.items and game.data.items[item]
    if not def then return false, "unknown held item" end
    if def.pocket == "KEY_ITEM" then return false, "held item is a key item" end
    if def.canToss == false then return false, "held item cannot be held" end
  end
  return true
end

local function fixHeldItem(mod, game, mon)
  local ok = checkHeldItem(mod, game, mon)
  if not ok then
    mon.item = nil
    mon.heldItem = nil
  end
end

function Legality.isLegal(mod, core, game, mon)
  if type(mon) ~= "table" then return false, "not a pokemon" end
  if not (game and game.data and game.data.pokemon) then return true end
  local def = game.data.pokemon[mon.species]
  if not def then return false, "unknown species" end
  if mon.isEgg then return checkEgg(mod, core, def, mon) end
  local ok, reason = checkLevel(game, def, mon)
  if not ok then return false, reason end
  ok, reason = checkDVs(mon)
  if not ok then return false, reason end
  ok, reason = checkStatExp(mon)
  if not ok then return false, reason end
  ok, reason = checkStatExpTotal(mon)
  if not ok then return false, reason end
  ok, reason = checkMoves(mod, core, game, mon)
  if not ok then return false, reason end
  ok, reason = checkCatchRate(mod, game, def, mon)
  if not ok then return false, reason end
  ok, reason = checkGender(mod, def, mon)
  if not ok then return false, reason end
  ok, reason = checkShiny(mon)
  if not ok then return false, reason end
  ok, reason = checkHeldItem(mod, game, mon)
  if not ok then return false, reason end
  return true
end

function Legality.fix(mod, core, game, mon)
  if type(mon) ~= "table" then return false, "not a pokemon" end
  if not (game and game.data and game.data.pokemon) then return true end
  local def = game.data.pokemon[mon.species]
  if not def then return false, "unknown species" end

  local snapshot = Merge.deepCopy(mon)
  local function restore()
    for k in pairs(mon) do mon[k] = nil end
    for k, v in pairs(snapshot) do mon[k] = v end
  end

  if mon.isEgg then
    local c251 = GameVersion.generation() == 1 and crystal251(mod)
    if GameVersion.generation() == 1 and not c251 then return false, "eggs are not valid in this game" end
    if isNoEggSpecies(def, c251) then return false, "species cannot produce eggs" end
    fixEggMoves(mod, core, def, mon, c251)
  else
    fixLevel(game, def, mon)
    fixDVs(mon)
    fixStatExp(mon)
    fixStatExpTotal(mon)
    if not fixMoves(mod, core, game, mon) then
      restore()
      return false, "invalid move count"
    end
    fixCatchRate(mod, game, def, mon)
    fixGender(mod, def, mon)
    fixShiny(mon)
  end
  fixHeldItem(mod, game, mon)

  local ok, reason = Legality.isLegal(mod, core, game, mon)
  if not ok then
    restore()
    return false, reason
  end
  return true
end

return Legality
