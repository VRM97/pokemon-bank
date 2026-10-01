local V = ...

local GameVersion = require("src.core.GameVersion")
local Stats = require("src.pokemon.Stats")
local Party = require("src.pokemon.Party")
local Strings = require("src.core.Strings")

local SCREEN_ID = "PokemonBankBox"
local TRANSFER_BOX_SCREEN_ID = "PokemonBankTransferBox"
local MOVE_SCREEN_ID = "PokemonBankMovePkmn"

local POKE_BALL_BY_NUMBER = {
  "MASTER_BALL", "ULTRA_BALL", "GREAT_BALL", "POKE_BALL", "SAFARI_BALL", "NET_BALL",
  "DIVE_BALL", "NEST_BALL", "REPEAT_BALL", "TIMER_BALL", "LUXURY_BALL", "PREMIER_BALL",
}
local POKE_BALL_BY_TEXT = {}
for number, id in ipairs(POKE_BALL_BY_NUMBER) do POKE_BALL_BY_TEXT[id] = number end

local Module = {}

function Module.install(mod, core)
  local GenerationMap = V.require("GenerationMap")
  local Species = V.require("Species")
  local MoveSet = V.require("MoveSet")
  local StatsValues = V.require("StatsValues")
  local Legality = V.require("Legality")
  local Personality = V.require("Personality")
  local BoxAccess = V.require("BoxAccess")
  local BagAccess = V.require("BagAccess")
  local Pickers = V.require("Pickers")
  local Utils = V.require("Utils")
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local normalizeBoxes = core.normalizeBoxes
  local message = core.message
  local monName = core.monName
  local boxLabel = core.boxLabel
  local pcBoxLabel = core.pcBoxLabel
  local pcBoxName = core.pcBoxName
  local pcBoxNamesTable = core.pcBoxNamesTable
  local boxCapacity = core.boxCapacity

  local Pokemon = {
    screenId = SCREEN_ID,
    transferBoxScreenId = TRANSFER_BOX_SCREEN_ID,
    moveScreenId = MOVE_SCREEN_ID
  }

  function Pokemon.speciesName(game, mon)
    if type(mon) ~= "table" then return "" end
    if mon.isEgg then return "EGG" end
    local key = Species.key(mon)
    local def = game.data.pokemon[key]
    return (def and def.name) or tostring(key)
  end

  local function gen2StatsComplete(stats)
    return stats and type(stats.hp) == "number" and type(stats.attack) == "number" and type(stats.defense) == "number" and type(stats.speed) == "number" and type(stats.specialAttack) == "number" and type(stats.specialDefense) == "number"
  end

  local function ensureStats(game, mon)
    if type(mon) ~= "table" then return mon end
    -- A Gen 3 mon keeps its own flat stats
    if GameVersion.generation() == 3 then return mon end
    if GameVersion.generation() == 2 then
      if gen2StatsComplete(mon.stats) then return mon end
      local def = game.data.pokemon[Species.key(mon)]
      if not (def and def.baseStats) then return mon end
      local stats = require("src.battle.gen2.Mon").stats(def.baseStats, mon.dvs or {}, mon.level or 1, mon.statExp)
      mon.stats = stats
      mon.hp = math.max(0, math.min(tonumber(mon.hp) or stats.hp, stats.hp))
      return mon
    end
    local def = game.data.pokemon[Species.key(mon)]
    if def then Stats.ensure(def, mon) end
    return mon
  end

  local function healMon(game, mon)
    if type(mon) ~= "table" then return mon end
    if type(mon.stats) == "table" and mon.stats.hp then mon.hp = mon.stats.hp end
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    if MoveSet.form(mon.moves) == "number" and type(mon.maxPp) == "table" then
      mon.pp = mon.pp or {}
      for i = 1, #mon.moves do mon.pp[i] = mon.maxPp[i] or mon.pp[i] end
    end
    local movesData = game and game.data and game.data.moves
    if movesData and type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        if type(mv) == "table" and mv.id then
          local def = movesData[mv.id]
          if def then
            if GameVersion.generation() == 2 then mv.pp = mv.maxPp or def.pp
            else mv.pp = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5) end
          end
        end
      end
    end
    return mon
  end

  local function healBank(game)
    if not (game and game.data) then return 0 end
    local s = loadStorage()
    local count = 0
    for _, box in ipairs(s.entries.boxes) do
      for _, mon in ipairs(box.content) do
        healMon(game, mon)
        count = count + 1
      end
    end
    if count > 0 then markDirty() end
    return count
  end

  local function autoHealMon(trigger, game, mon)
    if game and mod.options:get("auto_heal") == trigger then healMon(game, mon) end
  end

  local function mirrorHeldItem(mon) BagAccess.reshapeHeldItem(mon) end

  local function mirrorEggFields(mon)
    if type(mon) ~= "table" then return end
    if mon.isEgg ~= true and mon.egg == true then mon.isEgg = true end
    if mon.isEgg ~= true then return end
    local crystal251 = mod.find("CRYSTAL_251")
    local generation = GameVersion.generation()
    local cycles = mon.friendship
    if mon.eggSteps ~= nil or mon.eggCycles ~= nil then cycles = math.min(mon.eggSteps or mon.eggCycles, mon.eggCycles or mon.eggSteps) end
    if cycles ~= nil then
      if generation == 2 then
        mon.eggSteps, mon.eggCycles, mon.friendship = cycles, nil, nil
      elseif generation == 3 then
        mon.eggCycles, mon.friendship, mon.eggSteps = cycles, cycles, nil
      else
        mon.eggCycles, mon.eggSteps, mon.friendship = cycles, nil, nil
      end
    end
    mon.egg = generation == 3 and true or nil
    if crystal251 and GameVersion.generation() == 1 then
      if type(mon.moves) == "table" and #mon.moves > 0 then
        mon.eggMoves = mon.eggMoves or mon.moves
        mon.moves = {}
      end
    elseif type(mon.eggMoves) == "table" and #mon.eggMoves > 0
        and (type(mon.moves) ~= "table" or #mon.moves == 0) then
      mon.moves = mon.eggMoves
      mon.eggMoves = nil
    end
  end

  local function reshapeMoves(game, mon)
    local movesData = game and game.data and game.data.moves
    if not (movesData and type(mon.moves) == "table") then return end
    for _, mv in ipairs(mon.moves) do
      if type(mv) == "table" and mv.id then
        local def = movesData[mv.id]
        if def then
          local step = math.floor(def.pp / 5)
          if GameVersion.generation() == 2 then
            if mv.maxPp == nil then mv.maxPp = def.pp + (mv.ppUps or 0) * step end
          elseif mv.ppUps == nil and mv.maxPp then mv.ppUps = step > 0 and math.max(0, math.min(3, math.floor((mv.maxPp - def.pp) / step + 0.5))) or 0 end
        end
      end
    end
  end

  local STATUS = {
    { "SLP", "sleep", "SLP" },
    { "PSN", "poison", "PSN" },
    { "PSN", "toxic", "TOX" },
    { "BRN", "burn", "BRN" },
    { "FRZ", "freeze", "FRZ" },
    { "PAR", "paralyze", "PAR" }
  }
  local STATUS_TO_GEN1 = { sleep = "SLP", poison = "PSN", toxic = "PSN", TOX = "PSN", burn = "BRN", freeze = "FRZ", paralyze = "PAR" }
  local STATUS_TO_GEN2 = { SLP = "sleep", PSN = "poison", TOX = "toxic", BRN = "burn", FRZ = "freeze", PAR = "paralyze" }
  local STATUS_TO_GEN3 = { sleep = "SLP", poison = "PSN", toxic = "TOX", burn = "BRN", freeze = "FRZ", paralyze = "PAR" }

  local function reshapeStatus(mon)
    if type(mon) ~= "table" then return end
    local generation = GameVersion.generation()
    local sleepTurns = mon.sleep
    if generation ~= 3 then mon.sleep = nil end
    if mon.status == nil then return end
    if generation == 2 then
      mon.status = STATUS_TO_GEN2[mon.status] or mon.status
      if mon.status == "sleep" and mon.statusTurns == nil then mon.statusTurns = sleepTurns end
    elseif generation == 3 then
      mon.status = STATUS_TO_GEN3[mon.status] or mon.status
      if mon.status == "SLP" and mon.statusTurns ~= nil then mon.sleep = mon.statusTurns end
      mon.statusTurns = nil
      mon.toxicCounter = nil
    else
      mon.status = STATUS_TO_GEN1[mon.status] or mon.status
      mon.statusTurns = nil
      mon.toxicCounter = nil
    end
  end

  local GENDER_TO_GEN2 = { M = "male", F = "female", U = "unknown" }
  local GENDER_TO_GEN3 = { male = "M", female = "F", unknown = "U" }

  local function reshapeGender(mon)
    if type(mon.gender) ~= "string" then return end
    local generation = GameVersion.generation()
    if generation == 3 then mon.gender = GENDER_TO_GEN3[mon.gender] or mon.gender
    elseif generation == 2 then mon.gender = GENDER_TO_GEN2[mon.gender] or mon.gender end
  end

  local function gen3Pokemon()
    local ok, module = pcall(require, "src.core.game3.pokemon")
    return ok and type(module) == "table" and module or nil
  end

  local META_LOCATION_UNKNOWN = 255

  local function backfillGen3Fields(mon)
    local isEgg = mon.isEgg == true
    if type(mon.dvs) == "table" then
      if mon.ivs == nil then mon.ivs = StatsValues.fromDVs(mon.dvs) end
      mon.dvs = nil
    end
    if type(mon.statExp) == "table" then
      if mon.evs == nil then mon.evs = StatsValues.fromStatExp(mon.statExp) end
      mon.statExp = nil
    end
    if mon.pokerus == nil then mon.pokerus = 0 end
    mon.friendship = mon.friendship or mon.happiness or (not isEgg and 70 or nil)
    if not isEgg then mon.happiness = mon.happiness or mon.friendship end
    if mon.metLevel == nil then mon.metLevel = isEgg and 0 or tonumber(mon.level) end
    if mon.pokeball == nil then mon.pokeball = 4 end
    if mon.metLocation == nil then mon.metLocation = META_LOCATION_UNKNOWN end
    if mon.fatefulEncounter == nil then mon.fatefulEncounter = false end
    local pid = mon.personality
    if type(pid) ~= "number" then return end
    if mon.nature == nil then mon.nature = Personality.nature(pid) end
    local species = Species.number(mon)
    local P = species and gen3Pokemon()
    if not P then return end
    if mon.abilityId == nil and P.abilityId then
      local ok, ability = pcall(P.abilityId, species, pid)
      if ok and ability then mon.ability, mon.abilityId = mon.ability or ability, ability end
    end
    if mon.gender == nil and P.gender then
      local ok, gender = pcall(P.gender, species, pid)
      if ok then mon.gender = gender end
    end
    if mon.growthRate == nil and P.speciesMeta then
      local ok, meta = pcall(P.speciesMeta, species)
      if ok and type(meta) == "table" then mon.growthRate = tonumber(meta.growthRate) end
    end
  end

  local FLAT_STAT_KEYS = { "maxHp", "attack", "defense", "speed", "spAtk", "spDef", "atk", "def", "spe", "spa", "spd" }

  local function hasFlatStats(mon) return type(mon.stats) ~= "table" and type(mon.attack) == "number" end

  local function hpShare(mon)
    local max = tonumber(mon.maxHp) or (type(mon.stats) == "table" and tonumber(mon.stats.hp))
    local hp = tonumber(mon.hp)
    if not (hp and max and max > 0) then return nil end
    return math.max(0, math.min(1, hp / max))
  end

  local function hpForShare(share, max)
    if share == nil then return max end
    if share <= 0 then return 0 end
    return math.min(max, math.max(1, math.floor(max * share + 0.5)))
  end

  local function recalcGen3Stats(mon)
    if type(mon.stats) ~= "table" and mon.maxHp ~= nil and mon.attack ~= nil then return end
    local P, species = gen3Pokemon(), Species.number(mon)
    if not (P and species and P.calcStats and type(mon.ivs) == "table") then return end
    local share = hpShare(mon)
    local calculated = P.calcStats(species, mon.level, mon.ivs, mon.evs, mon.personality)
    mon.stats = nil
    mon.hp = hpForShare(share, calculated.maxHp)
    if P.applyStats then P.applyStats(mon)
    else
      mon.maxHp, mon.attack, mon.defense, mon.speed = calculated.maxHp, calculated.attack, calculated.defense, calculated.speed
      mon.spAtk, mon.spDef = calculated.spAtk, calculated.spDef
    end
  end

  local function recalcGen12Stats(mon, def)
    if not hasFlatStats(mon) then return end
    local base = def and def.baseStats
    if not base then return end
    local share = hpShare(mon)
    local stats
    if GameVersion.generation() == 2 then stats = require("src.battle.gen2.Mon").stats(base, mon.dvs or {}, mon.level or 1, mon.statExp)
    else stats = Stats.calc(def, mon.level or 1, mon.dvs or {}, mon.statExp) end
    for _, key in ipairs(FLAT_STAT_KEYS) do mon[key] = nil end
    mon.stats = stats
    mon.hp = hpForShare(share, stats.hp)
  end

  local function stampTrainer(game, mon)
    if type(mon) ~= "table" then return end
    local trainer = Utils.currentTrainer(game)
    if not trainer.name then return end
    mon.ot = trainer.name
    mon.otId = trainer.tid
    mon.otName = trainer.name
    mon.otSecretId = trainer.sid
  end

  local function stampEggTrainer(game, mon) if mon and mon.isEgg then stampTrainer(game, mon) end end

  local function stampNewTrainer(game, mon)
    if mod.options:get("inherit_trainer_on_withdraw") then stampTrainer(game, mon) end
  end

  mod.events:on("pokemon.caught", function(ev)
    local mon = type(ev) == "table" and ev.mon
    if type(mon) ~= "table" or GameVersion.generation() > 2 then return end
    if mon.metLevel == nil then mon.metLevel = tonumber(mon.level) end
    if mon.metLocation == nil then mon.metLocation = META_LOCATION_UNKNOWN end
    if mon.pokeball == nil and ev.ball ~= nil then mon.pokeball = ev.ball end
    -- The red GYARADOS of the LAKE OF RAGE is an event shiny: a PID with no run of the generator behind it, marked as such.
    local map = ev.game and ev.game.save and ev.game.save.player and ev.game.save.player.map
    if GameVersion.generation() == 2 and Species.key(mon) == "GYARADOS" and map == "LAKE_OF_RAGE" and Legality.knownShiny(mod, mon) then mon.pidIvExempt = "event" end
  end)

  local moveId = core.moveEntryId

  local function fileAsideMoves(orphaned, mon, list)
    if type(mon.personality) ~= "number" or #list == 0 then return end
    local bucket = orphaned.boxes.moves[mon.personality]
    if not bucket then
      bucket = {}
      orphaned.boxes.moves[mon.personality] = bucket
    end
    for _, mv in ipairs(list) do
      local id = moveId(mv)
      local dup = false
      for _, existing in ipairs(bucket) do
        if moveId(existing) == id then dup = true break end
      end
      if not dup then bucket[#bucket + 1] = mv end
    end
  end

  local function setAsideMoves(mon, list)
    if #list == 0 or type(mon.personality) ~= "number" then return end
    fileAsideMoves(core.ensureOrphaned(loadStorage()), mon, list)
    markDirty()
  end
  
  local function reshapeBall(mon)
    local ball = mon.pokeball
    if ball == nil then return end
    if GameVersion.generation() == 3 then
      if type(ball) == "string" then
        mon.pokeball = POKE_BALL_BY_TEXT[ball] or POKE_BALL_BY_TEXT["POKE_BALL"]
        mon.pokeballAlt = ball
      end
    elseif type(ball) == "number" then
      local alt = mon.pokeballAlt
      local text = type(alt) == "string" and alt or POKE_BALL_BY_NUMBER[ball]
      if text then mon.pokeball, mon.pokeballAlt = text, ball end
    end
  end

  local function reshapeForActiveGame(game, mon)
    if type(mon) ~= "table" then return mon end
    Species.reshape(game, mon)
    local expValue = mon.exp or mon.experience
    if expValue ~= nil then
      if GameVersion.generation() == 2 then mon.experience, mon.exp = expValue, nil
      else mon.exp, mon.experience = expValue, nil end
    end
    reshapeStatus(mon)
    mirrorHeldItem(mon)
    mirrorEggFields(mon)
    stampEggTrainer(game, mon)
    setAsideMoves(mon, MoveSet.reshape(game, mon))
    reshapeMoves(game, mon)
    reshapeGender(mon)
    reshapeBall(mon)
    if GameVersion.generation() ~= 3 then
      if type(mon.ivs) == "table" then
        if mon.dvs == nil then mon.dvs = StatsValues.toDVs(mon.ivs) end
        mon.ivs = nil
      end
      if type(mon.evs) == "table" then
        if mon.statExp == nil then mon.statExp = StatsValues.toStatExp(mon.evs) end
        mon.evs = nil
      end
    end
    if GameVersion.generation() == 3 then
      backfillGen3Fields(mon)
      recalcGen3Stats(mon)
      return mon
    end
    local def = game and game.data and game.data.pokemon and game.data.pokemon[Species.key(mon)]
    recalcGen12Stats(mon, def)
    local baseStats = def and def.baseStats
    if not (baseStats and type(mon.stats) == "table") then return mon end
    if GameVersion.generation() == 2 then
      local Mon = require("src.battle.gen2.Mon")
      if baseStats.specialAttack and (mon.stats.specialAttack == nil or mon.stats.specialDefense == nil) then
        local computed = Mon.stats(baseStats, mon.dvs or {}, mon.level or 1, mon.statExp)
        mon.stats.specialAttack = mon.stats.specialAttack or computed.specialAttack
        mon.stats.specialDefense = mon.stats.specialDefense or computed.specialDefense
      end
      if mon.maxHp == nil then mon.maxHp = mon.stats.hp end
      if mon.types == nil then mon.types = def.types end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
      if mon.gender == nil then mon.gender = Mon.gender(def, mon.dvs or {}, { species = Species.key(mon), level = mon.level }) end
      if mon.happiness == nil then mon.happiness = 70 end
      if mon.pokerus == nil then mon.pokerus = 0 end
    else
      if mon.stats.special == nil and baseStats.special then mon.stats.special = Stats.calc(def, mon.level or 1, mon.dvs or {}, mon.statExp).special end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
      if mod.find("CRYSTAL_251") then
        if mon.happiness == nil then mon.happiness = 70 end
        if mon.pokerus == nil then mon.pokerus = 0 end
      end
    end
    return mon
  end

  local function registerDex(game, species)
    local dex = game and game.save and game.save.pokedex
    if not dex then return end
    if type(dex.seen) == "table" then dex.seen[species] = true end
    local owned = dex.owned or dex.caught
    if type(owned) == "table" then owned[species] = true end
  end

  local function stampOrigin(mon)
    if type(mon) ~= "table" then return end
    if mon.originGame == nil then mon.originGame = GameVersion.get() end
    if mon.originGeneration == nil then mon.originGeneration = GameVersion.generation() end
  end

  local function backfillOrigin(game, mon)
    if type(mon) ~= "table" then return false end
    if mon.originGame ~= nil and mon.originGeneration ~= nil then return false end
    local tid = Utils.currentTrainer(game).tid
    if not (tid ~= nil and mon.otId ~= nil and mon.otId == tid) then return false end
    local changed = false
    if mon.originGame == nil then
      mon.originGame = GameVersion.get()
      changed = true
    end
    if mon.originGeneration == nil then
      mon.originGeneration = GameVersion.generation()
      changed = true
    end
    return changed
  end

  function Pokemon.depositMon(mon, game)
    if type(mon) ~= "table" then return nil end
    stampOrigin(mon)
    Species.pair(game, mon)
    BagAccess.reshapeHeldItem(mon)
    if game then MoveSet.refresh(game, mon)
    else
      mon.movesAlt = nil
      mon.movesAltOf = nil
    end
    local s = loadStorage()
    local n = #s.entries.boxes
    local start = math.min(core.currentBox(), n)
    for off = 0, n - 1 do
      local i = ((start - 1 + off) % n) + 1
      local content = s.entries.boxes[i].content
      if #content < boxCapacity() then
        table.insert(content, mon)
        normalizeBoxes(s)
        markDirty()
        return i, #content
      end
    end
    return nil
  end

  local function isValidPokemon(mon, data)
    if type(mon) ~= "table" or type(data) ~= "table" then return false end
    local pokemon = data.pokemon
    if type(pokemon) ~= "table" then return false end
    local key = Species.key(mon)
    if not pokemon[key] then
      local translated = GenerationMap.translateSpeciesId(key)
      if not pokemon[translated] then return false end
      Species.setText(mon, translated)
    end
    if mon.isEgg and GameVersion.generation() == 1 and not (mod.find("CRYSTAL_251") or mod.find("Kanto-Reforged")) then return false end
    return true
  end

  local function checkHeldItem(game, mon, orphaned, lostItems)
    mirrorHeldItem(mon)
    local item = BagAccess.heldItemName(mon) or mon.item or mon.heldItem
    if not item then return false end
    local valid = mod.exports.isValidItem and mod.exports.isValidItem(item, game)
    if not valid and mod.exports.isValidItem then
      local translated = GenerationMap.translateItemId(item)
      if translated ~= item and mod.exports.isValidItem(translated, game) then
        item = translated
        BagAccess.setHeldItem(mon, item)
        valid = true
      end
    end
    local blacklisted = mod.exports.isBlacklisted and mod.exports.isBlacklisted(item, game)
    if valid and not blacklisted then return false end
    BagAccess.setHeldItem(mon, nil)
    core.bucketAdd(orphaned.items, item, 1)
    lostItems[#lostItems + 1] = { id = item, count = 1 }
    return true
  end

  local function forEachStoredMon(s, fn)
    for _, box in ipairs(s.entries.boxes) do
      for _, mon in ipairs(box.content) do fn(mon) end
    end
    for _, mon in ipairs(s.orphaned and s.orphaned.boxes.mons or {}) do fn(mon) end
    for _, mon in ipairs(s.entries.timeCapsule or {}) do fn(mon) end
  end

  local function personalityTaken(s, pid)
    local taken = false
    forEachStoredMon(s, function(mon) if mon.personality == pid then taken = true end end)
    local buckets = s.orphaned and s.orphaned.boxes.moves
    return taken or (buckets ~= nil and buckets[pid] ~= nil)
  end

  local function stampSecretId(game, mon)
    if type(mon.otSecretId) == "number" and mon.otSecretId ~= 0 then return false end
    local trainer = Utils.currentTrainer(game)
    local otName = mon.otName or mon.ot
    local own = trainer.sid ~= nil and mon.originGame ~= nil and mon.originGame == GameVersion.get()
      and otName ~= nil and otName == trainer.name
    local sid = own and trainer.sid or 0
    if mon.otSecretId == sid then return false end
    mon.otSecretId = sid
    return true
  end

  local function markUncorrelatedPid(mon)
    if mon.pidIvExempt ~= nil or type(mon.personality) ~= "number" then return false end
    local ivs = type(mon.ivs) == "table" and mon.ivs or (type(mon.dvs) == "table" and StatsValues.fromDVs(mon.dvs))
    local origin = tonumber(mon.originGeneration)
    local earlier = origin and origin < 3 or (origin == nil and type(mon.dvs) == "table")
    if not (ivs and earlier) or Personality.matchesIVs(mon.personality, ivs) then return false end
    local shiny = Personality.isShiny(mon.personality, tonumber(mon.otId) or 0, tonumber(mon.otSecretId) or 0)
    mon.pidIvExempt = shiny and "shiny" or "unmatched"
    return true
  end

  local function ensurePersonality(game, s, mon)
    local changed = false
    if type(mon.personality) ~= "number" then
      mon.personality = Personality.generate({
        ratio = Legality.genderRatio(mod, game, mon),
        gender = Legality.knownGender(mod, game, mon),
        shiny = Legality.knownShiny(mod, mon),
        unownForm = Legality.knownUnownForm(mod, mon),
        ivs = mon.ivs or (type(mon.dvs) == "table" and StatsValues.fromDVs(mon.dvs)) or nil,
        tid = mon.otId, sid = mon.otSecretId,
        taken = function(pid) return personalityTaken(s, pid) end,
      })
      changed = true
    end
    if markUncorrelatedPid(mon) then changed = true end
    -- Moves set aside under the bankId follow the mon to its PID.
    if mon.bankId ~= nil then
      local buckets = s.orphaned and s.orphaned.boxes.moves
      local old = buckets and buckets[mon.bankId]
      if old then
        buckets[mon.bankId] = nil
        local bucket = buckets[mon.personality] or {}
        for _, mv in ipairs(old) do bucket[#bucket + 1] = mv end
        buckets[mon.personality] = bucket
      end
      mon.bankId = nil
      changed = true
    end
    return changed
  end

  local function scrubInvalidMoves(s, mon, orphaned, data)
    if type(mon.personality) ~= "number" then return false end
    if type(mon.moves) ~= "table" or #mon.moves == 0 then return false end
    local keep, bad = {}, {}
    if MoveSet.form(mon.moves) == "number" then
      local pp, maxPp = {}, {}
      for i, n in ipairs(mon.moves) do
        if MoveSet.gen3Known(n) then
          keep[#keep + 1], pp[#pp + 1], maxPp[#maxPp + 1] = n, mon.pp and mon.pp[i], mon.maxPp and mon.maxPp[i]
        else bad[#bad + 1] = n end
      end
      if #bad == 0 then return false end
      fileAsideMoves(orphaned, mon, bad)
      mon.moves, mon.pp, mon.maxPp = keep, pp, maxPp
      return true
    end
    local renamed = false
    for _, mv in ipairs(mon.moves) do
      local id = moveId(mv)
      local here = id and GenerationMap.translateMoveId(id)
      if id and not data.moves[id] and here ~= id and data.moves[here] and type(mv) == "table" then
        mv.id = here
        renamed = true
      end
      if id and not data.moves[moveId(mv)] then bad[#bad + 1] = mv
      else keep[#keep + 1] = mv end
    end
    if #bad == 0 then return renamed end
    fileAsideMoves(orphaned, mon, bad)
    mon.moves = keep
    return true
  end

  function Pokemon.validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {}, lostItems = {} }
    end
    Utils.ensureTrainer(game, mod)
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local identityChanged = false
    forEachStoredMon(s, function(mon)
      if isValidPokemon(mon, data) and backfillOrigin(game, mon) then identityChanged = true end
      if stampSecretId(game, mon) then identityChanged = true end
      if ensurePersonality(game, s, mon) then identityChanged = true end
    end)
    local quarantined, restored = 0, 0
    local lostMons, restoredMons, lostItems = {}, {}, {}
    local originBackfilled = false
    for boxNum = 1, #s.entries.boxes do
      local content = s.entries.boxes[boxNum].content
      for idx = #content, 1, -1 do
        local mon = content[idx]
        if not isValidPokemon(mon, data) then
          table.remove(content, idx)
          orphaned.boxes.mons[#orphaned.boxes.mons + 1] = mon
          quarantined = quarantined + 1
          lostMons[#lostMons + 1] = { species = Species.key(mon), from = "BOX " .. boxNum }
        else
          reshapeForActiveGame(game, mon)
          checkHeldItem(game, mon, orphaned, lostItems)
          if backfillOrigin(game, mon) then originBackfilled = true end
          markDirty()
        end
      end
    end
    normalizeBoxes(s)
    local targetBoxNum = #s.entries.boxes
    local targetContent = s.entries.boxes[targetBoxNum].content
    for idx = #orphaned.boxes.mons, 1, -1 do
      local mon = orphaned.boxes.mons[idx]
      if isValidPokemon(mon, data) then
        table.remove(orphaned.boxes.mons, idx)
        reshapeForActiveGame(game, mon)
        checkHeldItem(game, mon, orphaned, lostItems)
        if backfillOrigin(game, mon) then originBackfilled = true end
        if #targetContent >= boxCapacity() then
          s.entries.boxes[#s.entries.boxes + 1] = core.newBox(s)
          targetBoxNum = #s.entries.boxes
          targetContent = s.entries.boxes[targetBoxNum].content
        end
        table.insert(targetContent, mon)
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = Species.key(mon), box = targetBoxNum }
      end
    end
    normalizeBoxes(s)
    local scrubbed = 0
    for _, box in ipairs(s.entries.boxes) do
      for _, mon in ipairs(box.content) do
        if scrubInvalidMoves(s, mon, orphaned, data) then scrubbed = scrubbed + 1 end
        if MoveSet.sync(game, mon) then scrubbed = scrubbed + 1; markDirty() end
      end
    end
    return {
      changed = quarantined > 0 or restored > 0 or #lostItems > 0 or identityChanged or scrubbed > 0 or originBackfilled,
      quarantined = quarantined,
      restored = restored,
      lostMons = lostMons,
      restoredMons = restoredMons,
      lostItems = lostItems,
    }
  end

  local function listInvalidMons()
    local out = {}
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.boxes.mons or {}
    for idx, mon in ipairs(orphaned) do
      out[#out + 1] = { index = idx, mon = mon }
    end
    return out
  end

  local function invalidMonCount()
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.boxes.mons or {}
    return #orphaned
  end

  function Pokemon.withdrawMon(boxNum, idx)
    local s = loadStorage()
    local box = s.entries.boxes[boxNum]
    local content = box and box.content
    local mon = content and content[idx]
    if not mon then return nil end
    table.remove(content, idx)
    normalizeBoxes(s)
    markDirty()
    return mon
  end

  local function peekMon(boxNum, idx)
    local box = loadStorage().entries.boxes[boxNum]
    return box and box.content[idx] or nil
  end

  local function isLegal(mon, game) return Legality.isLegal(mod, core, game, mon) end

  local function fixLegal(mon, game) return Legality.fix(mod, core, game, mon) end

  local function legalityMode()
    local v = mod.options:get("legality_checks")
    if v == true then return "reject" end
    if v == false then return "off" end
    return v
  end

  local function legalityCheckPasses(mon, game, allowFix)
    local mode = legalityMode()
    if mode == "off" then return true end
    if isLegal(mon, game) then return true end
    if mode == "force_fix" then return fixLegal(mon, game) end
    if mode == "fix" and allowFix then return fixLegal(mon, game) end
    return false
  end

  local function needsLegalityFix(mon, game) return legalityMode() == "fix" and not isLegal(mon, game) end

  local function meetsGenerationFloor(mon)
    if type(mon) ~= "table" then return true end
    return GameVersion.generation() >= (mon.minGeneration or 0)
  end

  local function withdrawEligible(mon, game, allowFix)
    if not meetsGenerationFloor(mon) then return false, "generation" end
    if not legalityCheckPasses(mon, game, allowFix) then return false, "illegal" end
    return true
  end

  local function moveMon(srcBox, srcIdx, destBox, destIdx)
    local s = loadStorage()
    local fromBox = s.entries.boxes[srcBox]
    local from = fromBox and fromBox.content
    local mon = from and from[srcIdx]
    if not mon then return false end
    if srcBox == destBox and destIdx == srcIdx then return false end
    local toBox = s.entries.boxes[destBox]
    local to = toBox and toBox.content
    if not to then return false end
    local destMon = to[destIdx]
    if destMon then
      from[srcIdx], to[destIdx] = destMon, mon
      normalizeBoxes(s)
      markDirty()
      return true
    end
    if #to >= boxCapacity() then return false, "full" end
    table.remove(from, srcIdx)
    table.insert(to, mon)
    normalizeBoxes(s)
    markDirty()
    return true
  end

  local function listMons()
    local out = {}
    local s = loadStorage()
    for boxNum, box in ipairs(s.entries.boxes) do
      for idx, mon in ipairs(box.content) do out[#out + 1] = { box = boxNum, index = idx, mon = mon } end
    end
    return out
  end

  local function countMons()
    local n = 0
    for _, box in ipairs(loadStorage().entries.boxes) do n = n + #box.content end
    return n
  end

  local function boxCount()
    return #loadStorage().entries.boxes
  end

  local function renameBox(game, view, boxNum, onDone)
    local current = view == "bank" and ((loadStorage().entries.boxes[boxNum] or {}).name or "") or (pcBoxName(game, boxNum) or "")
    local function apply(name)
      local value = (name and #name > 0) and name or nil
      if view == "bank" then
        local st = loadStorage()
        local box = st.entries.boxes[boxNum]
        if box then box.name = value end
        markDirty()
      else
        if BoxAccess.slotted() then BoxAccess.setNativeName(game, boxNum, value)
        else pcBoxNamesTable()[boxNum] = value
        end
        if GameVersion.generation() == 2 then require("src.core.gen2.Boxes").rename(game.save, boxNum, value) end
      end
      if onDone then onDone() end
    end
    if GameVersion.generation() == 2 then
      local Screens = require("src.ui.Screens")
      if not pcall(Screens.get, game, "Gen2NamingScreen") then return end
      Screens.push(game, "Gen2NamingScreen", {
        type = "box",
        initial = current,
        onDone = function(name) game.stack:pop(); apply(name) end,
        onCancel = function() game.stack:pop() end,
      })
      return
    end
    if GameVersion.generation() == 3 then
      local Naming = require("src.ui.game3.naming")
      Naming.open({
        title = "BOX NAME?", maxLen = 8, seed = current, template = Naming.TEMPLATE.BOX,
        onDone = apply,
      })
      return
    end
    game.stack:push(require("src.ui.NamingScreen").new(game, {
      title = "BOX NAME?", default = current, maxLen = 8,
      onDone = apply,
    }))
  end

  local function deleteBox(game, boxNum, onDone)
    local s = loadStorage()
    local box = s.entries.boxes[boxNum]
    if not box or #box.content > 0 then
      message(game, "That box still\nhas POKéMON\nin it!")
      if onDone then onDone() end
      return
    end
    table.remove(s.entries.boxes, boxNum)
    normalizeBoxes(s)
    markDirty()
    if onDone then onDone() end
  end

  local openTransferBoxList
  local openMoveList

  local function indexAfterMove(index, from, to)
    if index == from then return to end
    if from < to and index > from and index <= to then return index - 1 end
    if to < from and index >= to and index < from then return index + 1 end
    return index
  end

  local function moveBox(game, view, from, to)
    if from == to then return end
    if view == "bank" then
      local st = loadStorage()
      local box = table.remove(st.entries.boxes, from)
      table.insert(st.entries.boxes, to, box)
      core.setCurrentBox(indexAfterMove(core.currentBox(), from, to))
      normalizeBoxes(st)
      markDirty()
    else
      BoxAccess.moveBox(game, from, to)
      if not BoxAccess.slotted() then
        local names = pcBoxNamesTable()
        local moved = names[from]
        if from < to then
          for i = from, to - 1 do names[i] = names[i + 1] end
        else
          for i = from, to + 1, -1 do names[i] = names[i - 1] end
        end
        names[to] = moved
      end
      BoxAccess.setCurrentBox(game, indexAfterMove(BoxAccess.currentBox(game), from, to))
    end
    core.playSound(game, "Swap")
  end

  local boxListView = core.gridView("box_list_view", { columns = 6, default = "grid" })
  local function boxListFields(view)
    local actions = {
      { label = "TRANSFER", onSelect = function(game, boxNum, rebuild)
        openTransferBoxList(game, { view = view, box = boxNum }, function() rebuild() end)
      end },
      { label = "RENAME", onSelect = function(game, boxNum, rebuild) renameBox(game, view, boxNum, rebuild) end },
    }
    if view == "bank" then
      actions[#actions + 1] = { label = "DELETE", onSelect = function(game, boxNum, rebuild) deleteBox(game, boxNum, rebuild) end }
    end
    return {
      canListPages = true,
      listPagesLabel = "BOXES",
      listPagesActions = actions,
      listPagesColumns = boxListView.columns,
      listPagesOnStart = { boxListView.rows[1], boxListView.rows[2] },
      listPagesFooter = true,
      canRearrangePages = true,
      onMovePage = function(game, _, fromIndex, toIndex) moveBox(game, view, fromIndex, toIndex) end,
      canOverflow = true,
    }
  end

  local function transferBankBox(srcBoxNum, destBoxNum)
    local s = loadStorage()
    local srcBox = s.entries.boxes[srcBoxNum]
    local destBox = s.entries.boxes[destBoxNum]
    local src = srcBox and srcBox.content
    local dest = destBox and destBox.content
    if not src or #src == 0 or not dest then return 0, 0 end
    local mons = {}
    for i = 1, #src do mons[i] = src[i] end
    local leftover = {}
    local cap = boxCapacity()
    local moved = 0
    for _, mon in ipairs(mons) do
      if #dest < cap then
        table.insert(dest, mon)
        moved = moved + 1
      else
        leftover[#leftover + 1] = mon
      end
    end
    for i = #src, 1, -1 do table.remove(src, i) end
    for _, mon in ipairs(leftover) do table.insert(src, mon) end
    normalizeBoxes(s)
    markDirty()
    return moved, #leftover
  end

  local function transferPcBox(game, srcBoxNum, destBoxNum)
    local boxes = BoxAccess.boxes(game)
    local src = boxes[srcBoxNum]
    if not src or BoxAccess.total(src) == 0 then return 0, 0 end
    local mons = {}
    for _, mon in BoxAccess.each(src) do mons[#mons + 1] = mon end
    local leftover = {}
    local cursor = destBoxNum
    local moved = 0
    for _, mon in ipairs(mons) do
      local placed = false
      for off = 0, BoxAccess.count() - 1 do
        local boxNum = ((cursor - 1 + off) % BoxAccess.count()) + 1
        if boxNum ~= srcBoxNum and BoxAccess.insert(boxes[boxNum], mon) then
          cursor = boxNum
          moved = moved + 1
          placed = true
          break
        end
      end
      if not placed then leftover[#leftover + 1] = mon end
    end
    for i = 1, BoxAccess.capacity() do src[i] = nil end
    for _, mon in ipairs(leftover) do BoxAccess.insert(src, mon) end
    return moved, #leftover
  end

  openTransferBoxList = function(game, source, onTransferred)
    local handle

    local function labelOf(view, boxNum)
      return view == "bank" and boxLabel(loadStorage(), boxNum) or pcBoxLabel(game, boxNum)
    end

    local function performTransfer(destView, destBoxNum, fix)
      local destLabel = labelOf(destView, destBoxNum)
      local transferred, remaining
      if source.view == "bank" and destView == "bank" then
        transferred, remaining = transferBankBox(source.box, destBoxNum)
      elseif source.view == "bank" and destView == "pc" then
        local result = mod.exports.withdrawToBox(game, destBoxNum, { boxNum = source.box, indices = nil, fix = fix })
        transferred = result and #result.withdrawn or 0
        remaining = result and result.remaining or 0
      elseif source.view == "pc" and destView == "bank" then
        local result = mod.exports.depositBoxPokemon(game, source.box, { boxNum = destBoxNum, indices = nil })
        transferred, remaining = result and #result or 0, 0
      -- pc -> pc
      else transferred, remaining = transferPcBox(game, source.box, destBoxNum) end
      if transferred > 0 then
        local msg = Strings("Transferred %d\nPOKéMON to\n%s.", transferred, destLabel)
        if remaining > 0 then msg = msg .. Strings("\n%d remained.", remaining) end
        message(game, msg)
        if onTransferred then onTransferred() end
      else message(game, destView == "pc" and "No POKéMON\ntransferred.\nPC may be full." or "No POKéMON\ntransferred.") end
      handle.refresh()
    end

    local function confirmTransfer(destView, destBoxNum)
      local srcLabel = labelOf(source.view, source.box)
      local destLabel = labelOf(destView, destBoxNum)
      local function askTransfer(fix)
        core.confirm(game, Strings("Transfer %s\nto %s?", srcLabel, destLabel), function(yes)
          if yes then performTransfer(destView, destBoxNum, fix) end
        end, { defaultNo = true, noSound = true })
      end
      if source.view == "bank" and destView == "pc" then
        local needing = 0
        local sourceBox = loadStorage().entries.boxes[source.box]
        for _, mon in ipairs(sourceBox and sourceBox.content or {}) do
          if needsLegalityFix(mon, game) then needing = needing + 1 end
        end
        if needing > 0 then
          core.confirm(game, Strings("%d POKéMON need\nto be fixed. OK?", needing), function(yes) askTransfer(yes) end, { defaultNo = true, noSound = true })
          return
        end
      end
      askTransfer(false)
    end

    handle = Pickers.openBoxPicker(mod, core, game, {
      screenId = TRANSFER_BOX_SCREEN_ID,
      startView = source.view,
      initialBoxes = { [source.view] = source.box },
      requireNonEmpty = false,
      footer = function(view) return "A: CONFIRM\nSELECT: " .. (view == "bank" and "PC" or "BANK") end,
      onChoose = function(view, boxNum)
        if view == source.view and boxNum == source.box then
          message(game, "What? You can't\ntransfer a box\nto itself!")
          return
        end
        confirmTransfer(view, boxNum)
      end,
    })
  end

  local function pcToParty(game, pcBoxNum, index)
    if #game.save.party >= Party.MAX then return false end
    local box = BoxAccess.box(game, pcBoxNum)
    local mon = box and box[index]
    if not mon then return false end
    ensureStats(game, mon)
    BoxAccess.take(box, index)
    table.insert(game.save.party, mon)
    return true
  end

  local function partyToPc(game, index, startPcBoxNum)
    local mon = game.save.party[index]
    if not mon then return false end
    for off = 0, BoxAccess.count() - 1 do
      local i = ((startPcBoxNum - 1 + off) % BoxAccess.count()) + 1
      local box = BoxAccess.box(game, i)
      if not BoxAccess.isFull(box) then
        table.remove(game.save.party, index)
        BoxAccess.insert(box, mon)
        return true, i
      end
    end
    return false
  end

  local function performMove(game, env, srcView, srcBoxNum, destView, idx, fix)
    local bankPage, pcPage = env.pageOf("bank"), env.pageOf("pc")
    if destView == "party" and #game.save.party >= Party.MAX then
      return false, "The party is full!"
    end
    if destView == "bank" then
      if srcView == "party" then
        if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
        local deposited = mod.exports.depositPartyPokemon(game, { indices = { idx }, boxNum = bankPage })
        if not deposited or #deposited == 0 then return false, "It didn't work!" end
        return true, Strings("Stored in\n%s.", boxLabel(loadStorage(), deposited[1].box))
      elseif srcView == "pc" then
        local deposited = mod.exports.depositBoxPokemon(game, srcBoxNum, { indices = { idx }, boxNum = bankPage })
        if not deposited or #deposited == 0 then return false, "It didn't work!" end
        return true, Strings("Stored in\n%s.", boxLabel(loadStorage(), deposited[1].box))
      end
    elseif destView == "party" then
      if srcView == "bank" then
        local result = mod.exports.withdrawToParty(game, { boxNum = srcBoxNum, indices = { idx }, fix = fix })
        if not result or #result.withdrawn == 0 then return false, "It didn't work!" end
        return true, "Added to\nthe PARTY."
      elseif srcView == "pc" then
        if not pcToParty(game, srcBoxNum, idx) then return false, "It didn't work!" end
        return true, "Added to\nthe PARTY."
      end
    elseif destView == "pc" then
      if srcView == "bank" then
        local result = mod.exports.withdrawToBox(game, pcPage, { boxNum = srcBoxNum, indices = { idx }, fix = fix })
        if not result or #result.withdrawn == 0 then return false, "PC BOX is full!" end
        return true, Strings("Stored in\n%s.", pcBoxLabel(game, result.withdrawn[1].pcBox))
      elseif srcView == "party" then
        if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
        local ok, placedBox = partyToPc(game, idx, pcPage)
        if not ok then return false, "PC BOX is full!" end
        return true, Strings("Stored in\n%s.", pcBoxLabel(game, placedBox))
      end
    end
    return false, "It didn't work!"
  end

  local function releaseCurrent(game, view, boxNum, idx, mon, rebuild)
    if view == "party" and #game.save.party <= 1 then
      message(game, "You can't release\nyour last POKéMON!")
      return
    end
    local name = monName(game, mon)
    core.confirmRelease(game, name, function(yes)
      if not yes then return end
      local src = (view == "bank" and loadStorage().entries.boxes[boxNum].content)
        or (view == "party" and game.save.party)
        or BoxAccess.box(game, boxNum)
      if src[idx] ~= mon then
        message(game, "The selection changed.\nTry again.")
        return
      end
      if view == "pc" then BoxAccess.take(src, idx) else table.remove(src, idx) end
      if view == "bank" then
        local st = loadStorage()
        normalizeBoxes(st)
        markDirty()
        core.emitAction("boxes", "remove", "pokemon_released", { box = boxNum, index = idx, mon = mon })
      end
      core.playCry(game, Species.key(mon))
      message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
      rebuild(true)
    end)
  end

  local function transferRow(label, srcView, srcBoxNum, destView)
    return { label = label, onSelect = function(game, pageId, row, rebuild, list, env)
      local function commit(fix)
        local _, msg = performMove(game, env, srcView, srcBoxNum and srcBoxNum(pageId) or nil, destView, row, fix)
        rebuild(true)
        core.currentList(env, list).footer = msg
      end
      local mon = srcView == "bank" and loadStorage().entries.boxes[pageId].content[row]
        or srcView == "pc" and BoxAccess.box(game, pageId)[row]
        or game.save.party[row]
      if srcView == "bank" and needsLegalityFix(mon, game) then core.confirm(game, "This POKéMON\nneeds to be fixed.\nOK?", function(yes) commit(yes) end, { defaultNo = true, noSound = true })
      else commit(false) end
    end }
  end

  local function transferGroup(...) return core.transferGroup({ ... }) end

  local function statsRow(getMon)
    return { label = "STATS", keepOpen = true, onSelect = function(game, pageId, row)
      local mon = getMon(game, pageId, row)
      ensureStats(game, mon)
      core.openSummary(game, mon)
    end }
  end

  local function holdsItem(mon) return BagAccess.heldItemName(mon) ~= nil end

  local function storeHeldItem(game, view, mon, destView, playSound)
    local id = BagAccess.heldItemName(mon)
    if not id then return false end
    local ok, msg = core.storeHeldItem(game, destView, id, playSound)
    if ok then
      BagAccess.setHeldItem(mon, nil)
      if view ~= "bank" and GameVersion.generation() == 3 then mon.heldItem = 0 end
      if view == "bank" then markDirty() end
    end
    return ok, msg
  end

  local function itemDestinationMenu(game, storeTo)
    local rows = {}
    if core.bankTakesItems(game) then rows[#rows + 1] = { label = "TO BANK", onSelect = function() storeTo("bank") end } end
    rows[#rows + 1] = { label = "TO BAG", onSelect = function() storeTo("bag") end }
    rows[#rows + 1] = { label = "TO PC", onSelect = function() storeTo("pc") end }
    rows[#rows + 1] = { label = "CANCEL" }
    core.rowActionsMenu(game, rows)
  end

  local function heldItemRow(view, getMon)
    return { label = "ITEM", keepOpen = true,
      visible = function(game, pageId, row) return holdsItem(getMon(game, pageId, row)) end,
      onSelect = function(game, pageId, row, rebuild, list, env)
        itemDestinationMenu(game, function(destView)
          local _, msg = storeHeldItem(game, view, getMon(game, pageId, row), destView)
          rebuild(true)
          core.currentList(env, list).footer = msg
        end)
      end }
  end

  mod.events:on("mod.vrm_pokemon_bank.storage_action", function(ev)
    if not (type(ev) == "table" and ev.id == mod.id and ev.key == "boxes" and ev.action == "deposit") then return end
    local species = type(ev.value) == "table" and Species.key(ev.value)
    if not species then return end
    local id = tostring(species)
    mod.exports.updateCustomStorageStats(mod.id, "boxes", function(stats) stats.species[id] = (stats.species[id] or 0) + 1 end)
  end)

  local function relearnRow(getMon)
    return { label = "RELEARN", keepOpen = true,
      visible = function(game, pageId, row) return core.canRelearn ~= nil and core.canRelearn(game, getMon(game, pageId, row)) end,
      onSelect = function(game, pageId, row, rebuild)
        local mon = getMon(game, pageId, row)
        if not mon then return end
        core.openRelearn(game, mon, function()
          rebuild(true)
          -- the action menu underneath was built with RELEARN in it: with nothing left to relearn, close it too
          if not core.canRelearn(game, mon) then game.stack:pop() end
        end)
      end }
  end

  local function heldItemMons(pageMons)
    local out = {}
    for _, mon in pairs(pageMons or {}) do if type(mon) == "table" and holdsItem(mon) then out[#out + 1] = mon end end
    return out
  end

  local function heldItemsStartRow(view, getPageMons)
    return { label = "ITEMS", keepOpen = true,
      visible = function(game, pageId) return #heldItemMons(getPageMons(game, pageId)) > 0 end,
      onSelect = function(game, pageId, rebuild, list, env)
        itemDestinationMenu(game, function(destView)
          local mons = heldItemMons(getPageMons(game, pageId))
          core.confirmBulkMoveAll(game, {
            count = #mons,
            verb = "Store", resultVerb = "Stored", noun = "items",
            run = function()
              local moved, refused = 0, 0
              for _, mon in ipairs(mons) do
                if storeHeldItem(game, view, mon, destView, false) then moved = moved + 1 else refused = refused + 1 end
              end
              return moved, refused
            end,
            rebuild = function() rebuild(true) end,
            setFooter = function(msg) core.currentList(env, list).footer = msg end,
          })
        end)
      end }
  end

  local function releaseRow(view, getBoxNum, getMon)
    return { label = "RELEASE", onSelect = function(game, pageId, row, rebuild)
      releaseCurrent(game, view, getBoxNum(pageId), row, getMon(game, pageId, row), rebuild)
    end }
  end

  local boxView = core.gridView("box_view", { columns = 6, default = "grid" })
  local boxColumns = boxView.columns
  local function startRows(view, getPageMons)
    return { heldItemsStartRow(view, getPageMons), boxView.rows[1], boxView.rows[2] }
  end
  local gen2IconCache = {}
  local function monIcon(game, mon)
    if type(mon) ~= "table" then return nil end
    local generation = GameVersion.generation()
    if generation == 3 then
      local P = gen3Pokemon()
      local icon = P and P.monIcon(mon)
      if not (icon and icon.image) then return nil end
      return icon.image, icon.quads and icon.quads[0]
    end
    local function centered(draw) return function(x, y, size) local o = math.floor((size - 16) / 2); draw(x + o, y + o) end end
    if generation == 2 then
      local PartyMenu = require("src.ui.gen2.PartyMenu")
      local menu = setmetatable({ game = game, icons = game.data.gen2Icons, palettes = game.data.gen2Palettes, iconCache = gen2IconCache, clock = 0 }, { __index = PartyMenu })
      local shown = setmetatable({ item = 0 }, { __index = mon })
      if not menu:iconFor(shown) then return nil end
      return centered(function(x, y) menu:drawIcon(shown, x, y) end)
    end
    local PartyMenu = require("src.ui.PartyMenu")
    return centered(function(x, y) PartyMenu.drawIcon(game, mon, x, y, false, 0) end)
  end

  local function footerMonLine(game, mon)
    if not mon then return "" end
    local name = (boxColumns() > 1 and not mon.isEgg) and monName(game, mon) or Pokemon.speciesName(game, mon)
    local level = not mon.isEgg and tonumber(mon.level)
    return level and Strings("%s Lv%d", name, level) or name
  end

  local function bankBoxContent(_, pageId, row) return loadStorage().entries.boxes[pageId].content[row] end
  local function pcBoxContent(game, pageId, row) return BoxAccess.box(game, pageId)[row] end
  local function boxPageId(pageId) return pageId end
  local function partyContent(game, _, row) return game.save.party[row] end
  local function iconOf(getMon) return function(game, pageId, row) return monIcon(game, getMon(game, pageId, row)) end end

  local function bulkWithdraw(srcView)
    return function(game, pageId, row, destView, env)
      if srcView == "bank" then
        local mon = bankBoxContent(game, pageId, row)
        if mon and needsLegalityFix(mon, game) then return false end
      end
      return (performMove(game, env, srcView, pageId, destView, row, false))
    end
  end
  local function bulkDeposit() end

  local bankContainer = core.CustomStorage.MultiArray.subscreen({
    containerId = "bank", label = "BANK",
    getContainers = function() return loadStorage().entries.boxes end,
    pageIdBy = "index",
    pageLabel = function(_, _, i) return boxLabel(loadStorage(), i) end,
    getCurrent = function() return core.currentBox() end,
    setCurrent = function(_, boxNum) core.setCurrentBox(boxNum) end,
    autoRememberPage = false,
    slots = function() local cap = boxCapacity(); return cap ~= math.huge and cap or nil end,
    heldItemMarks = true,
    columns = boxColumns,
    onStart = startRows("bank", function(_, pageId) local box = loadStorage().entries.boxes[pageId]; return box and box.content end),
    icon = iconOf(bankBoxContent),
    renderRow = function(game, mon, i) return { label = monName(game, mon), value = i }, mon end,
    listOpts = { messageBox = true, noSound = true, wrap = true },
    canRearrange = true,
    canRearrangeBetweenPages = true,
    onMove = function(game, fromPageId, fromIndex, toPageId, toIndex)
      local s = loadStorage()
      local fromBox = s.entries.boxes[fromPageId]
      local mon = fromBox and fromBox.content[fromIndex]
      if not mon then return end
      if fromPageId == toPageId then
        table.remove(fromBox.content, fromIndex)
        table.insert(fromBox.content, toIndex, mon)
      else
        local toBox = s.entries.boxes[toPageId]
        if not toBox or #toBox.content >= boxCapacity() then
          message(game, "That box is full!")
          return
        end
        table.remove(fromBox.content, fromIndex)
        table.insert(toBox.content, math.min(toIndex, #toBox.content + 1), mon)
      end
      normalizeBoxes(s)
      markDirty()
      core.playSound(game, "Swap")
    end,
    dynamicFooter = function(game, pageId, row, nextLabel)
      local mon = loadStorage().entries.boxes[pageId].content[row]
      return Strings("%s\nSEL: %s ST: BOX", footerMonLine(game, mon), nextLabel)
    end,
    canTransfer = true,
    canWithdraw = false,
    withdraw = bulkWithdraw("bank"),
    deposit = bulkDeposit,
    onAction = {
      transferGroup(transferRow("TO PARTY", "bank", boxPageId, "party"), transferRow("TO PC", "bank", boxPageId, "pc")),
      statsRow(bankBoxContent),
      relearnRow(bankBoxContent),
      heldItemRow("bank", bankBoxContent),
      releaseRow("bank", boxPageId, bankBoxContent),
    },
  })[1]
  for k, v in pairs(boxListFields("bank")) do bankContainer[k] = v end

  local partyContainer = core.CustomStorage.MultiArray.subscreen({
    containerId = "party", label = "PARTY",
    getContainers = function(game) return { { id = "party", content = game.save.party } } end,
    slots = Party.MAX,
    heldItemMarks = true,
    columns = boxColumns,
    onStart = startRows("party", function(game) return game.save.party end),
    icon = iconOf(partyContent),
    renderRow = function(game, mon, i) return { label = monName(game, mon), value = i }, mon end,
    listOpts = { messageBox = true, noSound = true, wrap = true },
    canRearrange = true,
    onMove = function(game, _, fromIndex, _, toIndex)
      local party = game.save.party
      local mon = party[fromIndex]
      if not mon then return end
      table.remove(party, fromIndex)
      table.insert(party, toIndex, mon)
    end,
    dynamicFooter = function(game, _, row, nextLabel)
      local mon = game.save.party[row]
      return Strings("%s\nSELECT: %s", footerMonLine(game, mon), nextLabel)
    end,
    canTransfer = true,
    canWithdraw = false,
    withdraw = bulkWithdraw("party"),
    deposit = bulkDeposit,
    onAction = {
      transferGroup(transferRow("TO BANK", "party", nil, "bank"), transferRow("TO PC", "party", nil, "pc")),
      statsRow(partyContent),
      relearnRow(partyContent),
      heldItemRow("party", partyContent),
      releaseRow("party", function() return nil end, partyContent),
    },
  })[1]

  local pcContainer = {
    id = "pc", label = "PC",
    heldItemMarks = true,
    columns = boxColumns,
    onStart = startRows("pc", function(game, pageId) return BoxAccess.box(game, pageId) end),
    icon = iconOf(pcBoxContent),
    getPages = function(game)
      local pages = {}
      for i = 1, BoxAccess.count() do pages[i] = { id = i, label = pcBoxLabel(game, i) } end
      return pages
    end,
    getRememberedPage = function(game) return BoxAccess.currentBox(game) end,
    setRememberedPage = function(game, boxNum) BoxAccess.setCurrentBox(game, boxNum) end,
    autoRememberPage = false,
    build = function(game, pageId)
      local rows, mons = BoxAccess.rows(BoxAccess.box(game, pageId), function(mon, i)
        return { label = monName(game, mon), value = i }
      end)
      return rows, { messageBox = true, noSound = true, wrap = true }, mons
    end,
    canRearrange = true,
    canRearrangeBetweenPages = true,
    onMove = function(game, fromPageId, fromIndex, toPageId, toIndex)
      local from = BoxAccess.box(game, fromPageId)
      local mon = from and from[fromIndex]
      if fromPageId == toPageId then
        if not from or (mon == nil and not BoxAccess.slotted()) then return end
        BoxAccess.reorder(from, fromIndex, toIndex)
      else
        if not mon then return end
        local to = BoxAccess.box(game, toPageId)
        if not to or not BoxAccess.moveAcross(from, fromIndex, to, toIndex) then
          message(game, "That box is full!")
          return
        end
      end
      core.playSound(game, "Swap")
    end,
    dynamicFooter = function(game, pageId, row, nextLabel)
      local mon = BoxAccess.box(game, pageId)[row]
      return Strings("%s\nSEL: %s ST: BOX", footerMonLine(game, mon), nextLabel)
    end,
    slots = function() return BoxAccess.capacity() end,
    canTransfer = true,
    canWithdraw = false,
    withdraw = bulkWithdraw("pc"),
    deposit = bulkDeposit,
    onAction = {
      transferGroup(transferRow("TO BANK", "pc", boxPageId, "bank"), transferRow("TO PARTY", "pc", boxPageId, "party")),
      statsRow(pcBoxContent),
      relearnRow(pcBoxContent),
      heldItemRow("pc", pcBoxContent),
      releaseRow("pc", boxPageId, pcBoxContent),
    },
  }

  for k, v in pairs(boxListFields("pc")) do pcContainer[k] = v end

  Pokemon.containers = { bankContainer, partyContainer, pcContainer }

  openMoveList = function(game, opts)
    opts = opts or {}
    local screen = core.entryScreen(game, Pokemon.containers, {
      screenId = MOVE_SCREEN_ID,
      startView = opts.initialView,
      counter = true,
    })
    if opts.initialView and opts.initialBox then screen.jumpTo(opts.initialView, opts.initialBox) end
    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = openMoveList })

  local pokemonTab = core.entryTab("boxes", "show_pokemon_tab")
  Pokemon.tabEnabled = pokemonTab.shown

  mod.exports.boxCount = boxCount
  mod.exports.boxCapacity = boxCapacity
  mod.exports.depositPokemon = function(mon, opts)
    if type(mon) ~= "table" then return nil, "invalid pokemon" end
    opts = opts or {}
    if opts.game then
      ensureStats(opts.game, mon)
      autoHealMon("deposit", opts.game, mon)
    end
    local boxNum, slot = Pokemon.depositMon(mon, opts.game)
    core.emitAction("boxes", "deposit", "pokemon_deposited", { box = boxNum, index = slot, mon = mon })
    return boxNum, slot
  end
  mod.exports.withdrawPokemon = function(boxNum, index, game, fix)
    local ok, reason = withdrawEligible(peekMon(boxNum, index), game, fix)
    if not ok then return nil, reason end
    local mon = Pokemon.withdrawMon(boxNum, index)
    if mon then
      if game then
        stampNewTrainer(game, mon)
        autoHealMon("withdraw", game, mon)
      end
      registerDex(game, Species.key(mon))
      core.emitAction("boxes", "withdraw", "pokemon_withdrawn", { box = boxNum, index = index, mon = mon })
    end
    return mon
  end
  mod.exports.getPokemon = peekMon
  mod.exports.getBox = function(boxNum)
    local s = loadStorage()
    local box = s.entries.boxes[boxNum]
    if not box then return nil end
    local content = box.content
    local cap = boxCapacity()
    local slots = cap == math.huge and #content or cap
    local copy = {}
    for i = 1, slots do copy[i] = content[i] end
    return copy
  end
  mod.exports.movePokemon = moveMon
  mod.exports.releasePokemon = function(boxNum, index)
    local mon = Pokemon.withdrawMon(boxNum, index)
    if mon then core.emitAction("boxes", "remove", "pokemon_released", { box = boxNum, index = index, mon = mon }) end
    return mon ~= nil
  end
  mod.exports.listPokemon = listMons
  mod.exports.pokemonCount = countMons
  mod.exports.healBank = healBank
  mod.exports.isValidPokemon = function(mon, game) return isValidPokemon(mon, game and game.data) end
  mod.exports.validatePokemonStorage = Pokemon.validateStorage
  mod.exports.isLegal = isLegal
  mod.exports.tryFixLegality = fixLegal
  mod.exports.needsLegalityFix = needsLegalityFix
  mod.exports.reshapeForActiveGame = reshapeForActiveGame
  mod.exports.registerDex = registerDex
  mod.exports.reshapeMoves = reshapeMoves
  mod.exports.movesChanged = function(game, mon)
    local changed = MoveSet.sync(game, mon)
    if changed then markDirty() end
    return changed
  end
  mod.exports.reshapeStatus = reshapeStatus
  mod.exports.listInvalidPokemon = listInvalidMons
  mod.exports.invalidPokemonCount = invalidMonCount

  local function validIndices(indices, n)
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > n then return false end
    end
    return true
  end

  local function allIndices(n)
    local t = {}
    for i = 1, n do t[#t + 1] = i end
    return t
  end

  local function firstNonEmptyBox(s)
    local boxNum = 1
    while boxNum <= #s.entries.boxes and #s.entries.boxes[boxNum].content == 0 do boxNum = boxNum + 1 end
    return boxNum <= #s.entries.boxes and boxNum or nil
  end

  local function bulkTransfer(source, indices, place, take)
    local entries = {}
    for _, idx in ipairs(indices) do entries[#entries + 1] = { mon = source[idx], originalIdx = idx } end
    local results, removedIdx = {}, {}
    for _, entry in ipairs(entries) do
      local result = place(entry.mon, entry.originalIdx)
      if result then
        results[#results + 1] = result
        removedIdx[#removedIdx + 1] = entry.originalIdx
      end
    end
    table.sort(removedIdx, function(a, b) return a > b end)
    for _, idx in ipairs(removedIdx) do (take or table.remove)(source, idx) end
    return results, #entries - #results
  end

  local function depositPlacer(game, s, startBoxNum)
    local currentBoxNum = startBoxNum
    return function(mon)
      if game then ensureStats(game, mon) end
      autoHealMon("deposit", game, mon)
      stampOrigin(mon)
      Species.pair(game, mon)
      BagAccess.reshapeHeldItem(mon)
      if game then MoveSet.refresh(game, mon) else mon.movesAlt, mon.movesAltOf = nil, nil end
      local cap = boxCapacity()
      for off = 0, #s.entries.boxes - 1 do
        local boxNum = ((currentBoxNum - 1 + off) % #s.entries.boxes) + 1
        local content = s.entries.boxes[boxNum].content
        if #content < cap then
          table.insert(content, mon)
          currentBoxNum = boxNum
          return { box = boxNum, index = #content, mon = mon }
        end
      end
      s.entries.boxes[#s.entries.boxes + 1] = core.newBox(s)
      table.insert(s.entries.boxes[#s.entries.boxes].content, mon)
      currentBoxNum = #s.entries.boxes
      return { box = #s.entries.boxes, index = 1, mon = mon }
    end
  end

  mod.exports.depositPartyPokemon = function(game, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save or not game.save.party then return nil, "invalid game" end
    local party = game.save.party
    if #party < 2 then return nil, "need at least 2 pokemon in party" end
    if not indices then
      indices = {}
      for i = 2, #party do indices[#indices + 1] = i end
    end
    if not validIndices(indices, #party) then return nil, "invalid index" end
    if #party - #indices < 1 then return nil, "must keep at least 1 pokemon in party" end
    local s = loadStorage()
    local deposited = bulkTransfer(party, indices, depositPlacer(game, s, targetBoxNum or #s.entries.boxes))
    normalizeBoxes(s)
    markDirty()
    for _, entry in ipairs(deposited) do core.emitAction("boxes", "deposit", "pokemon_deposited", entry) end
    return deposited
  end
  mod.exports.depositBoxPokemon = function(game, pcBoxNum, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save then return nil, "invalid game" end
    local pcBox = BoxAccess.box(game, pcBoxNum)
    if not pcBox then return nil, "invalid pc box" end
    if BoxAccess.total(pcBox) == 0 then return nil, "pc box is empty" end
    indices = indices or BoxAccess.indices(pcBox)
    if not validIndices(indices, BoxAccess.capacity()) then return nil, "invalid index" end
    for _, idx in ipairs(indices) do
      if pcBox[idx] == nil then return nil, "invalid index" end
    end
    local s = loadStorage()
    local deposited = bulkTransfer(pcBox, indices, depositPlacer(game, s, targetBoxNum or #s.entries.boxes), BoxAccess.take)
    normalizeBoxes(s)
    markDirty()
    for _, entry in ipairs(deposited) do core.emitAction("boxes", "deposit", "pokemon_deposited", entry) end
    return deposited
  end
  mod.exports.withdrawToParty = function(game, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save or not game.save.party then return nil, "invalid game" end
    local party = game.save.party
    local s = loadStorage()
    sourceBoxNum = sourceBoxNum or firstNonEmptyBox(s)
    if not sourceBoxNum then return nil, "bank is empty" end
    local sourceBoxStruct = s.entries.boxes[sourceBoxNum]
    local sourceBox = sourceBoxStruct and sourceBoxStruct.content
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end
    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end
    if Party.MAX - #party <= 0 then return nil, "party is full" end
    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      if #party >= Party.MAX then return nil end
      if not withdrawEligible(mon, game, opts.fix) then return nil end
      stampNewTrainer(game, mon)
      autoHealMon("withdraw", game, mon)
      table.insert(party, mon)
      registerDex(game, Species.key(mon))
      core.emitAction("boxes", "withdraw", "pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
      return { mon = mon }
    end)
    normalizeBoxes(s)
    markDirty()
    return { withdrawn = withdrawn, remaining = remainingCount }
  end
  mod.exports.withdrawToBox = function(game, targetPcBoxNum, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save then
      return nil, "invalid game"
    end
    if not BoxAccess.box(game, targetPcBoxNum) then return nil, "invalid target pc box" end
    local s = loadStorage()
    sourceBoxNum = sourceBoxNum or firstNonEmptyBox(s)
    if not sourceBoxNum then return nil, "bank is empty" end
    local sourceBoxStruct = s.entries.boxes[sourceBoxNum]
    local sourceBox = sourceBoxStruct and sourceBoxStruct.content
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end
    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end
    local currentPcBoxNum = targetPcBoxNum
    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      if not withdrawEligible(mon, game, opts.fix) then return nil end
      for off = 0, BoxAccess.count() - 1 do
        local boxNum = ((currentPcBoxNum - 1 + off) % BoxAccess.count()) + 1
        local box = BoxAccess.box(game, boxNum)
        if box and not BoxAccess.isFull(box) then
          stampNewTrainer(game, mon)
          autoHealMon("withdraw", game, mon)
          BoxAccess.insert(box, mon)
          registerDex(game, Species.key(mon))
          core.emitAction("boxes", "withdraw", "pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
          currentPcBoxNum = boxNum
          return { mon = mon, pcBox = boxNum }
        end
      end
      return nil
    end)
    normalizeBoxes(s)
    markDirty()
    return { withdrawn = withdrawn, remaining = remainingCount }
  end
  mod.exports.pokemonScreenId = SCREEN_ID
  mod.exports.setPokemonTabEnabled = pokemonTab.setEnabled
  mod.exports.isPokemonTabEnabled = Pokemon.tabEnabled
  mod.log:info("Pokemon Bank: Pokemon tab ready")
  return Pokemon
end

return Module
