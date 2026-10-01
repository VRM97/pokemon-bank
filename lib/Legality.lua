local V = ...

local MAX_LEVEL = 100
local MAX_DV = 15
local MAX_STAT_EXP = 65535
local MAX_STAT_EXP_TOTAL_GEN2 = 65535

local MAX_IV_GEN3 = 31
local MAX_EV_GEN3 = 255
local MAX_EV_TOTAL_GEN3 = 510

local NATIONAL_KANTO_GEN3 = 151
local NATIONAL_LAST_GEN3 = 386
local BALL_MIN_GEN3 = 1
local BALL_MAX_GEN3 = 12
local UNAVAILABLE_BALLS_GEN3 = {
  [7] = true,
  [12] = true
}
local FATEFUL_LOCATION_GEN3 = 255
local IV_KEYS_GEN3 = { "hp", "atk", "def", "spe", "spa", "spd" }

local GameVersion = require("src.core.GameVersion")
local Growth = require("src.pokemon.Growth")
local Merge = require("src.mods.Merge")
local Species = V.require("Species")
local Personality = V.require("Personality")
local StatsValues = V.require("StatsValues")
local MoveSet = V.require("MoveSet")

local Legality = {}

local function crystal251(mod) return mod.find("CRYSTAL_251") end

local function gen1Breeds(mod) return mod.find("CRYSTAL_251") or mod.find("Kanto-Reforged") end

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
  if t.special ~= nil then t.special = clamp(t.special, 0, maxVal)
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

local function ppStep(mdef) return math.floor((mdef and mdef.pp or 0) / 5) end

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
  for _, group in ipairs(groups) do
    if group == "UNDISCOVERED" then return true end
  end
  return groups[1] == "EGG_NONE" and groups[2] == "EGG_NONE"
end

local function eggMoveKnown(mod, def, moveId, c251)
  if mod.exports.speciesKnowsMove and mod.exports.speciesKnowsMove(def, moveId) then return true end
  if c251 and type(def.crystalEggMoves) == "table" then
    for _, id in ipairs(def.crystalEggMoves) do
      if id == moveId then return true end
    end
  end
  for _, id in ipairs(type(def.eggMoves) == "table" and def.eggMoves or {}) do
    if id == moveId then return true end
  end
  return false
end

local function checkLevel(game, def, mon)
  local level = mon.level
  if not isInt(level) or level < 1 or level > MAX_LEVEL then return false, "level out of range" end
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
  if dvs.hp ~= nil and expectedHp ~= nil and dvs.hp ~= expectedHp then return false, "hp dv does not match its own bits" end
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
    if v ~= nil and (not isInt(v) or v < 0 or v > MAX_STAT_EXP) then return false, "stat exp out of range: " .. key end
  end
  local spc = se.special or se.specialAttack or se.specialDefense
  if spc ~= nil and (not isInt(spc) or spc < 0 or spc > MAX_STAT_EXP) then return false, "stat exp out of range: special" end
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
  if not isInt(total) or total < 0 or total > MAX_STAT_EXP_TOTAL_GEN2 then
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
  if se.special ~= nil then se.special = math.floor(se.special * factor)
  elseif se.specialAttack ~= nil or se.specialDefense ~= nil then
    local newSpc = math.floor(spc * factor)
    se.specialAttack, se.specialDefense = newSpc, newSpc
  end
end

local function checkMoves(mod, core, game, mon)
  local moves = mon.moves
  if type(moves) ~= "table" or #moves < 1 or #moves > 4 then return false, "invalid move count" end
  local canLearn = mod.exports.canLearn
  local seen = {}
  for _, mv in ipairs(moves) do
    local id = core.moveEntryId(mv)
    if type(id) ~= "string" or seen[id] then return false, "duplicate or invalid move" end
    seen[id] = true
    if canLearn and not canLearn(game, mon, id) then return false, "unlearnable move: " .. id end
    if type(mv) == "table" then
      local mdef = game.data.moves and game.data.moves[id]
      if mdef then
        local step = ppStep(mdef)
        if mv.maxPp ~= nil then
          local valid = false
          for k = 0, 3 do
            if mv.maxPp == mdef.pp + k * step then
              valid = true
              break
            end
          end
          if not valid then return false, "invalid max pp: " .. id end
        elseif mv.ppUps ~= nil and (not isInt(mv.ppUps) or mv.ppUps < 0 or mv.ppUps > 3) then return false, "invalid pp ups: " .. id
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
        elseif mv.ppUps ~= nil then mv.ppUps = clamp(mv.ppUps, 0, 3)
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
  local species = Species.key(mon)
  local seen = { [species] = true }
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
    if c251 and mon.gender == crystal251Gender(mod, Species.key(mon), mon.dvs, c251) then return true end
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
      mon.gender = crystal251Gender(mod, Species.key(mon), mon.dvs, c251)
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
  if GameVersion.generation() == 1 and not gen1Breeds(mod) then return false, "eggs are not valid in this game" end
  if isNoEggSpecies(def, c251) then return false, "species cannot produce eggs" end
  local moves = mon.moves
  if type(moves) == "table" then
    for _, mv in ipairs(moves) do
      local id = core.moveEntryId(mv)
      if id and not eggMoveKnown(mod, def, id, c251) then return false, "unlearnable egg move: " .. id end
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
    mon.item, mon.heldItem, mon.heldItemAlt = nil, nil, nil
  end
end

local SHINY_ATTACK = { [2] = true, [3] = true, [6] = true, [7] = true, [10] = true, [11] = true, [14] = true, [15] = true }

function Legality.genderRatio(mod, game, mon)
  local def = game and game.data and game.data.pokemon and game.data.pokemon[Species.key(mon)]
  if type(def) ~= "table" then return nil end
  local c251 = GameVersion.generation() == 1 and crystal251(mod)
  local Gender = c251 and c251.exports and c251.exports.crystalGender
  local ratio = Gender and Gender.ratio and Gender.ratio(Species.key(mon))
  if type(ratio) == "number" then return ratio end
  if type(def.genderRatio) == "number" then return def.genderRatio end
  if type(def.genderRate) == "number" then
    if def.genderRate < 0 then return 255 end
    return math.min(254, math.floor(def.genderRate * 32))
  end
  return nil
end

function Legality.knownGender(mod, game, mon)
  local g = mon.gender
  if g == "male" or g == "M" then return "male" end
  if g == "female" or g == "F" then return "female" end
  if GameVersion.generation() == 1 then
    local c251 = crystal251(mod)
    if c251 then return crystal251Gender(mod, Species.key(mon), mon.dvs, c251) end
    return nil
  end
  local def = game and game.data and game.data.pokemon and game.data.pokemon[Species.key(mon)]
  local ok, Mon = pcall(require, "src.battle.gen2.Mon")
  if not (def and ok and type(mon.dvs) == "table" and Mon.vanillaGender) then return nil end
  local derived = Mon.vanillaGender(def, mon.dvs)
  if derived == "male" or derived == "female" then return derived end
  return nil
end

function Legality.knownUnownForm(mod, mon)
  if Species.key(mon) ~= "UNOWN" then return nil end
  if type(mon.unownLetter) == "number" and mon.unownLetter >= 1 and mon.unownLetter <= 26 then return mon.unownLetter - 1 end
  if type(mon.crystal251Form) == "string" and #mon.crystal251Form == 1 then
    local at = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):find(mon.crystal251Form:upper(), 1, true)
    if at then return at - 1 end
  end
  local d = mon.dvs
  if type(d) ~= "table" then return nil end
  local function middle(dv) return math.floor((dv or 0) / 2) % 4 end
  local special = d.special or d.specialAttack
  local packed = middle(d.attack) * 64 + middle(d.defense) * 16 + middle(d.speed) * 4 + middle(special)
  return math.min(25, math.floor(packed / 10))
end

function Legality.knownShiny(mod, mon)
  if mon.shiny ~= nil then return mon.shiny == true end
  local d = mon.dvs
  if type(d) ~= "table" or GameVersion.generation() == 3 then return false end
  if GameVersion.generation() == 1 and not crystal251(mod) then return false end
  local special = d.special or d.specialAttack
  return d.defense == 10 and d.speed == 10 and special == 10 and SHINY_ATTACK[d.attack] == true
end

local function engineGen3(name)
  local ok, module = pcall(require, name)
  return ok and type(module) == "table" and module or nil
end

local function fatefulCheckAppliesGen3(mon)
  local origin = tonumber(mon.originGeneration)
  return not (origin and origin < 3 and mon.minGeneration == nil)
end

local function derivedHpIVGen3(ivs)
  local function dv(iv) return math.floor(clamp(iv, 0, MAX_IV_GEN3) / 2) end
  return StatsValues.hpDV(dv(ivs.atk), dv(ivs.def), dv(ivs.spe), dv(ivs.spa)) * 2 + 1
end

local function fromEarlierGenerationGen3(mon)
  local origin = tonumber(mon.originGeneration)
  return origin ~= nil and origin < 3
end

local function nationalUnlockedGen3(game)
  local D = engineGen3("src.core.game3.pokedex_data")
  local session = game and game.save and game.save.gen3
  if not (D and D.isNationalUnlocked and session) then return true end
  local ok, unlocked = pcall(D.isNationalUnlocked, session)
  return not ok or unlocked == true
end

local function checkSpeciesGen3(game, mon)
  local species, P = Species.number(mon), engineGen3("src.core.game3.pokemon")
  if not species then return false, "unknown species" end
  if not (P and P.national) then return true end
  local national = P.national(species)
  if not national or national > NATIONAL_LAST_GEN3 then return false, "species is not in Gen 3" end
  if national > NATIONAL_KANTO_GEN3 and not nationalUnlockedGen3(game) then return false, "species needs the national dex" end
  return true
end

local function checkLevelGen3(mon)
  if not isInt(mon.level) or mon.level < 1 or mon.level > MAX_LEVEL then return false, "level out of range" end
  local S = engineGen3("src.core.game3.summary_data")
  if S and S.expForLevel and mon.growthRate ~= nil and isInt(mon.exp) then
    local floor = S.expForLevel(mon.growthRate, mon.level)
    local ceiling = mon.level < MAX_LEVEL and S.expForLevel(mon.growthRate, mon.level + 1) or math.huge
    if mon.exp < floor or mon.exp >= ceiling then return false, "level does not match its exp" end
  end
  return true
end

local function fixLevelGen3(mon)
  local S = engineGen3("src.core.game3.summary_data")
  if S and S.expForLevel and mon.growthRate ~= nil and isInt(mon.exp) then
    local level = 1
    while level < MAX_LEVEL and mon.exp >= S.expForLevel(mon.growthRate, level + 1) do level = level + 1 end
    mon.level = level
    return
  end
  mon.level = clamp(mon.level, 1, MAX_LEVEL)
end

local function checkIVsGen3(mon)
  if type(mon.ivs) ~= "table" then return false, "missing ivs" end
  for _, key in ipairs(IV_KEYS_GEN3) do
    local v = mon.ivs[key]
    if not isInt(v) or v < 0 or v > MAX_IV_GEN3 then return false, "iv out of range: " .. key end
  end
  if fromEarlierGenerationGen3(mon) and mon.ivs.hp ~= derivedHpIVGen3(mon.ivs) then
    return false, "hp iv does not match the bits of the others"
  end
  return true
end

local function fixIVsGen3(mon)
  if type(mon.ivs) ~= "table" then mon.ivs = {} end
  local orig, outOfRange = {}, false
  for _, key in ipairs(IV_KEYS_GEN3) do orig[key] = mon.ivs[key] end
  for _, key in ipairs(IV_KEYS_GEN3) do
    local v = orig[key]
    if not (isInt(v) and v >= 0 and v <= MAX_IV_GEN3) then outOfRange = true end
    mon.ivs[key] = clamp(v, 0, MAX_IV_GEN3)
  end
  if fromEarlierGenerationGen3(mon) then mon.ivs.hp = derivedHpIVGen3(orig) end
  mon.ivs.hp = clamp(mon.ivs.hp, 0, MAX_IV_GEN3)
  return outOfRange
end

local function fixCorrelationGen3(mon, ivsClamped)
  if not ivsClamped or mon.pidIvExempt ~= nil or not isInt(mon.personality) then return end
  if not fromEarlierGenerationGen3(mon) then return end
  if Personality.matchesIVs(mon.personality, mon.ivs) then return end
  local shiny = Personality.isShiny(mon.personality, tonumber(mon.otId) or 0, tonumber(mon.otSecretId) or 0)
  mon.pidIvExempt = shiny and "shiny" or "unmatched"
end

local function evTotalGen3(evs)
  local total = 0
  for _, key in ipairs(IV_KEYS_GEN3) do total = total + (tonumber(evs[key]) or 0) end
  return total
end

local function checkEVsGen3(mon)
  if mon.evs == nil then return true end
  if type(mon.evs) ~= "table" then return false, "evs is not a table" end
  for _, key in ipairs(IV_KEYS_GEN3) do
    local v = mon.evs[key]
    if v ~= nil and (not isInt(v) or v < 0 or v > MAX_EV_GEN3) then return false, "ev out of range: " .. key end
  end
  if evTotalGen3(mon.evs) > MAX_EV_TOTAL_GEN3 then return false, "ev total out of range" end
  return true
end

local function fixEVsGen3(mon)
  if type(mon.evs) ~= "table" then return end
  for _, key in ipairs(IV_KEYS_GEN3) do
    if mon.evs[key] ~= nil then mon.evs[key] = clamp(mon.evs[key], 0, MAX_EV_GEN3) end
  end
  local total = evTotalGen3(mon.evs)
  if total <= MAX_EV_TOTAL_GEN3 then return end
  local factor = MAX_EV_TOTAL_GEN3 / total
  for _, key in ipairs(IV_KEYS_GEN3) do
    if mon.evs[key] ~= nil then mon.evs[key] = math.floor(mon.evs[key] * factor) end
  end
end

local function checkPersonalityGen3(mon, P)
  local pid = mon.personality
  if not (isInt(pid) and pid >= 0 and pid < 4294967296) then return false, "missing personality" end
  if mon.nature ~= nil and mon.nature ~= Personality.nature(pid) then return false, "nature does not match its personality" end
  local species = Species.number(mon)
  if P and species then
    if mon.abilityId ~= nil and P.abilityId and mon.abilityId ~= P.abilityId(species, pid) then
      return false, "ability does not match its personality"
    end
    if mon.gender ~= nil and P.gender and mon.gender ~= P.gender(species, pid) then
      return false, "gender does not match its personality"
    end
  end
  if mon.isShiny ~= nil then
    local shiny = Personality.isShiny(pid, tonumber(mon.otId) or 0, tonumber(mon.otSecretId) or 0)
    if (mon.isShiny == true) ~= shiny then return false, "shininess does not match its personality" end
  end
  return true
end

local function fixPersonalityGen3(mon, P)
  local pid = mon.personality
  if not isInt(pid) then return end
  mon.nature = Personality.nature(pid)
  local species = Species.number(mon)
  if P and species then
    if P.abilityId then
      mon.abilityId = P.abilityId(species, pid)
      mon.ability = mon.abilityId
    end
    if P.gender then mon.gender = P.gender(species, pid) end
  end
  mon.isShiny = nil
end

local function checkCorrelationGen3(mon)
  if mon.pidIvExempt then return true end
  if not Personality.matchesIVs(mon.personality, mon.ivs) then return false, "personality does not go with its ivs" end
  return true
end

local function moveIdsGen3(game, mon)
  local ids = {}
  for i, number in ipairs(mon.moves) do ids[i] = MoveSet.toText(game, number) end
  return ids
end

local function checkMovesGen3(mod, game, mon)
  if type(mon.moves) ~= "table" or #mon.moves < 1 or #mon.moves > 4 then return false, "invalid move count" end
  local ids, seen = moveIdsGen3(game, mon), {}
  for i, number in ipairs(mon.moves) do
    if type(number) ~= "number" or not ids[i] then return false, "unknown move" end
    if seen[number] then return false, "duplicate move" end
    seen[number] = true
    if not (mod.exports.canLearn and mod.exports.canLearn(game, mon, ids[i])) then return false, "unlearnable move: " .. ids[i] end
  end
  return true
end

local function fixMovesGen3(mod, game, mon)
  if type(mon.moves) ~= "table" then return false end
  local ids, seen = moveIdsGen3(game, mon), {}
  local moves, pp, maxPp = {}, {}, {}
  for i, number in ipairs(mon.moves) do
    if #moves < 4 and type(number) == "number" and ids[i] and not seen[number]
        and mod.exports.canLearn and mod.exports.canLearn(game, mon, ids[i]) then
      seen[number] = true
      moves[#moves + 1] = number
      pp[#pp + 1] = mon.pp and mon.pp[i]
      maxPp[#maxPp + 1] = mon.maxPp and mon.maxPp[i]
    end
  end
  if #moves == 0 then return false end
  mon.moves, mon.pp, mon.maxPp = moves, pp, maxPp
  return true
end

local function validMaxPpGen3(game, id, number, maxPp)
  local base = MoveSet.basePp(game, id, number)
  if not base then return maxPp end
  local step = math.floor(base / 5)
  local ups = step > 0 and math.max(0, math.min(3, math.floor(((tonumber(maxPp) or base) - base) / step + 0.5))) or 0
  return base + ups * step
end

local function checkPPGen3(game, mon)
  if type(mon.pp) ~= "table" or type(mon.maxPp) ~= "table" then return false, "missing pp" end
  local ids = moveIdsGen3(game, mon)
  for i, number in ipairs(mon.moves) do
    local pp, maxPp = mon.pp[i], mon.maxPp[i]
    if not (isInt(pp) and isInt(maxPp)) or pp < 0 or pp > maxPp then return false, "pp out of range" end
    if ids[i] and maxPp ~= validMaxPpGen3(game, ids[i], number, maxPp) then return false, "max pp is not a valid number of pp ups" end
  end
  return true
end

local function fixPPGen3(game, mon)
  mon.pp, mon.maxPp = mon.pp or {}, mon.maxPp or {}
  local ids = moveIdsGen3(game, mon)
  for i, number in ipairs(mon.moves) do
    local base = ids[i] and MoveSet.basePp(game, ids[i], number)
    local max = ids[i] and validMaxPpGen3(game, ids[i], number, mon.maxPp[i]) or clamp(mon.maxPp[i], 0, 99)
    mon.maxPp[i] = max or base or 0
    mon.pp[i] = clamp(mon.pp[i] or mon.maxPp[i], 0, mon.maxPp[i])
  end
end

local function checkOriginGen3(mon)
  local ball = mon.pokeball
  if ball ~= nil and (not isInt(ball) or ball < BALL_MIN_GEN3 or ball > BALL_MAX_GEN3 or UNAVAILABLE_BALLS_GEN3[ball]) then
    return false, "ball does not exist in this game"
  end
  if mon.metLevel ~= nil and (not isInt(mon.metLevel) or mon.metLevel < 0 or mon.metLevel > (tonumber(mon.level) or MAX_LEVEL)) then
    return false, "met level is above its level"
  end
  if mon.metLocation == FATEFUL_LOCATION_GEN3 and mon.fatefulEncounter ~= true and fatefulCheckAppliesGen3(mon) then
    return false, "fateful encounter location without the fateful encounter flag"
  end
  return true
end

local function fixOriginGen3(mon)
  local ball = mon.pokeball
  if ball ~= nil and (not isInt(ball) or ball < BALL_MIN_GEN3 or ball > BALL_MAX_GEN3 or UNAVAILABLE_BALLS_GEN3[ball]) then mon.pokeball = 4 end
  if mon.metLevel ~= nil then mon.metLevel = clamp(mon.metLevel, 0, tonumber(mon.level) or MAX_LEVEL) end
  if mon.metLocation == FATEFUL_LOCATION_GEN3 and fatefulCheckAppliesGen3(mon) then mon.fatefulEncounter = true end
end

local function checkVitalsGen3(mon)
  if mon.hp ~= nil and (not isInt(mon.hp) or mon.hp < 0 or (isInt(mon.maxHp) and mon.hp > mon.maxHp)) then
    return false, "hp above its maximum"
  end
  for _, key in ipairs({ "friendship", "pokerus" }) do
    local v = mon[key]
    if v ~= nil and (not isInt(v) or v < 0 or v > 255) then return false, key .. " out of range" end
  end
  return true
end

local function fixVitalsGen3(mon)
  if mon.hp ~= nil then mon.hp = clamp(mon.hp, 0, isInt(mon.maxHp) and mon.maxHp or 999) end
  for _, key in ipairs({ "friendship", "pokerus" }) do
    if mon[key] ~= nil then mon[key] = clamp(mon[key], 0, 255) end
  end
end

local function checkHeldItemGen3(mon)
  local item = mon.heldItem or mon.item
  if item == nil or item == 0 then return true end
  local D = engineGen3("src.core.game3.items_data")
  if not (D and D.info) then return true end
  local number = tonumber(item) or (D.toNumericId and D.toNumericId(item))
  if not number then return false, "unknown held item" end
  local info = D.info(number)
  if type(info) == "table" and (info.pocket == "KEY_ITEMS" or info.pocket == "TM_CASE" or (tonumber(info.importance) or 0) > 0) then
    return false, "held item cannot be held"
  end
  return true
end

local function checkEggGen3(mon)
  local cycles = mon.eggCycles or mon.friendship
  if cycles ~= nil and (not isInt(cycles) or cycles < 0 or cycles > 255) then return false, "egg cycles out of range" end
  return checkOriginGen3(mon)
end

local function checkGen3(mod, core, game, mon)
  local ok, reason = checkSpeciesGen3(game, mon)
  if not ok then return false, reason end
  if mon.isEgg then return checkEggGen3(mon) end
  local P = engineGen3("src.core.game3.pokemon")
  for _, check in ipairs({
    function() return checkLevelGen3(mon) end,
    function() return checkIVsGen3(mon) end,
    function() return checkEVsGen3(mon) end,
    function() return checkPersonalityGen3(mon, P) end,
    function() return checkCorrelationGen3(mon) end,
    function() return checkMovesGen3(mod, game, mon) end,
    function() return checkPPGen3(game, mon) end,
    function() return checkOriginGen3(mon) end,
    function() return checkVitalsGen3(mon) end,
    function() return checkHeldItemGen3(mon) end,
  }) do
    ok, reason = check()
    if not ok then return false, reason end
  end
  return true
end

local function fixGen3(mod, core, game, mon)
  if mon.isEgg then
    fixOriginGen3(mon)
    return true
  end
  local P = engineGen3("src.core.game3.pokemon")
  fixLevelGen3(mon)
  fixCorrelationGen3(mon, fixIVsGen3(mon))
  fixEVsGen3(mon)
  fixPersonalityGen3(mon, P)
  if not fixMovesGen3(mod, game, mon) then return false, "invalid move count" end
  fixPPGen3(game, mon)
  fixOriginGen3(mon)
  fixVitalsGen3(mon)
  if not checkHeldItemGen3(mon) then
    mon.heldItem, mon.item, mon.heldItemAlt = nil, nil, nil
  end
  return true
end

function Legality.isLegal(mod, core, game, mon)
  if type(mon) ~= "table" then return false, "not a pokemon" end
  if not (game and game.data and game.data.pokemon) then return true end
  if GameVersion.generation() == 3 then return checkGen3(mod, core, game, mon) end
  local def = game.data.pokemon[Species.key(mon)]
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
  local snapshot, ok, reason
  local function restore()
    for k in pairs(mon) do mon[k] = nil end
    for k, v in pairs(snapshot) do mon[k] = v end
  end

  if type(mon) ~= "table" then return false, "not a pokemon" end
  if not (game and game.data and game.data.pokemon) then return true end
  if GameVersion.generation() == 3 then
    snapshot = Merge.deepCopy(mon)
    local fixed, why = fixGen3(mod, core, game, mon)
    if not fixed then
      restore()
      return false, why
    end
    ok, reason = checkGen3(mod, core, game, mon)
    if not ok then
      restore()
      return false, reason
    end
    return true
  end
  local def = game.data.pokemon[Species.key(mon)]
  if not def then return false, "unknown species" end
  snapshot = Merge.deepCopy(mon)
  if mon.isEgg then
    local c251 = GameVersion.generation() == 1 and crystal251(mod)
    if GameVersion.generation() == 1 and not gen1Breeds(mod) then return false, "eggs are not valid in this game" end
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
  ok, reason = Legality.isLegal(mod, core, game, mon)
  if not ok then
    restore()
    return false, reason
  end
  return true
end

return Legality
