local V = ...

local Species = V.require("Species")
local MoveSet = V.require("MoveSet")
local GenerationMap = V.require("GenerationMap")
local BoxAccess = V.require("BoxAccess")

local GameVersion = require("src.core.GameVersion")
local Bag = V.require("BagAccess")
local PcItems = V.require("PcItemAccess")
local Strings = require("src.core.Strings")
local Pickers = V.require("Pickers")

local SCREEN_ID = "PokemonBankMoves"

local Module = {}

function Module.install(mod, core)
  local Moves = { screenId = SCREEN_ID }
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local autoFillRecoveredMoves
  local playSound = core.playSound
  local askQuantity = core.askQuantity

  local function isHmItem(id)
    if type(id) ~= "string" then return false end
    id = id:upper()
    return id:sub(1, 3) == "HM_" or id:find("^HM%d") ~= nil
  end

  local FIRST_TM_ITEM, TM_COUNT = 288, 50

  local function gen3Machines()
    local ok, P = pcall(require, "src.core.game3.pokemon")
    if not (ok and type(P) == "table") then return nil end
    if not P._tmhm and P.install then pcall(P.install, P._cache) end
    return P._tmhm and P._tmhm.machines
  end

  local function gen3TmForMove(moveId)
    local machines, number = gen3Machines(), MoveSet.toNumber(nil, moveId)
    if not (machines and number) then return nil end
    for tm = 1, TM_COUNT do
      if tonumber(machines[tm - 1]) == number then return Bag.itemName(FIRST_TM_ITEM + tm) end
    end
    return nil
  end

  local function gen3MoveOfTm(id)
    local item, machines = Bag.itemNumber(id), gen3Machines()
    local tm = item and item - FIRST_TM_ITEM
    if not (machines and tm and tm >= 1 and tm <= TM_COUNT) then return nil end
    local number = tonumber(machines[tm - 1])
    return number and MoveSet.toText(nil, number)
  end

  local function tmMoveId(id, def)
    if GameVersion.generation() == 3 then return gen3MoveOfTm(id) end
    if type(def) ~= "table" or isHmItem(id) then return nil end
    if def.machine and def.machine.kind == "TM" and def.machine.move then return def.machine.move end
    if def.teaches then return def.teaches end
    return nil
  end

  local tmItemIndex
  local function tmItemId(moveId)
    if GameVersion.generation() == 3 then return gen3TmForMove(moveId) or ("TM_" .. moveId) end
    if not tmItemIndex then
      tmItemIndex = {}
      for id, def in mod.content.items:each() do
        local move = tmMoveId(id, def)
        if move and not tmItemIndex[move] then tmItemIndex[move] = id end
      end
    end
    return tmItemIndex[moveId] or ("TM_" .. moveId)
  end

  local function isValidMachine(id, data)
    if type(id) ~= "string" or id == "" then return false end
    if not (data and data.moves and data.moves[id]) then return false end
    if GameVersion.generation() == 3 then return gen3TmForMove(id) ~= nil end
    local itemDef = data.items and data.items[tmItemId(id)]
    return itemDef ~= nil and tmMoveId(tmItemId(id), itemDef) == id
  end

  local function isValidMove(id, data) return type(id) == "string" and id ~= "" and data and data.moves and data.moves[id] ~= nil end

  local function moveCount(id) return loadStorage().entries.moves[id] or 0 end

  local function depositMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    core.bucketAdd(loadStorage().entries.moves, id, qty)
    markDirty()
    return true
  end

  local function withdrawMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if not core.bucketSub(loadStorage().entries.moves, id, qty) then return false, "not enough" end
    markDirty()
    return true
  end

  local function listMoves()
    local out = {}
    for id, count in pairs(loadStorage().entries.moves) do out[id] = count end
    return out
  end

  function Moves.validateStorage(game)
    local data = game and game.data
    if not data then return { changed = false, quarantined = 0, restored = 0, lostItems = {}, restoredItems = {}, monMovesRestored = 0 } end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local result = core.reconcileCountBucket(s.entries.moves, orphaned.moves, function(id) return isValidMove(id, data) end, "POKéMON BANK MOVES")
    result.monMovesRestored = autoFillRecoveredMoves(game)
    result.changed = result.quarantined > 0 or result.restored > 0 or result.monMovesRestored > 0
    return result
  end

  local function listInvalidMoves() return core.listOrphaned("moves") end

  local function invalidMoveCount(id) return core.orphanedCount("moves", id) end

  local function sortedMoveIds(game, counts, filter) return core.sortedIdsByName(function(id) return core.moveName(game, id) end, counts, filter) end

  local function tmRowsForBank(game, counts)
    local rows = {}
    for id, count in pairs(counts) do
      if count and count > 0 then
        local moveId = tmMoveId(id, game.data.items[id])
        if moveId and game.data.moves[moveId] then
          rows[#rows + 1] = { value = id, moveId = moveId, label = core.truncateName(core.moveName(game, moveId)), right = "x" .. tostring(count) }
        end
      end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
  end

  local GEN3_TYPES = {
    [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL", "UNKNOWN",
    "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK",
  }

  local function typeDisplayName(game, typeId)
    if type(typeId) == "number" then return GEN3_TYPES[typeId] or "UNKNOWN" end
    local types = game.data.type_chart and game.data.type_chart.types
    local record = types and types[typeId]
    local name = record and record.name or typeId or "UNKNOWN"
    if name == "PSYCHIC_TYPE" then name = "PSYCHIC" end
    return tostring(name)
  end

  local TYPE_ABBR = {
    NORMAL = "NOR", FIGHTING = "FIG", FLYING = "FLY", POISON = "POI", GROUND = "GRD",
    ROCK = "ROK", BUG = "BUG", GHOST = "GHO", FIRE = "FIR", WATER = "WTR", GRASS = "GRS",
    ELECTRIC = "ELC", PSYCHIC = "PSY", ICE = "ICE", DRAGON = "DRG", DARK = "DRK",
    STEEL = "STL", FAIRY = "FRY", UNKNOWN = "UNK",
  }

  local function typeAbbr(name) return TYPE_ABBR[tostring(name):upper()] or "UNK" end

  function Moves.moveDetailLine(game, id)
    local def = id and game.data.moves[id]
    if not def then return nil end
    local power = (tonumber(def.power) or 0) > 0 and tostring(math.floor(def.power)) or "--"
    local accuracy = (tonumber(def.accuracy) or 0) > 0 and tostring(math.floor(def.accuracy)) or "--"
    return Strings("%s PWR%s ACC%s", typeAbbr(typeDisplayName(game, def.type)), power, accuracy)
  end

  function Moves.movePpText(game, id)
    local def = id and game.data.moves[id]
    return def and ("PP" .. tostring(math.floor(tonumber(def.pp) or 0))) or nil
  end

  function Moves.moveTypeOf(game, id)
    local def = id and game.data.moves[id]
    return def and typeDisplayName(game, def.type)
  end

  local function moveMoveRows(game, view)
    if view == "bag" then return tmRowsForBank(game, Bag.counts(game)) end
    if view == "pc" then return tmRowsForBank(game, PcItems.counts(game)) end
    local counts = loadStorage().entries.moves
    local rows = {}
    for _, id in ipairs(sortedMoveIds(game, counts)) do
      rows[#rows + 1] = { value = id, label = core.truncateName(core.moveName(game, id)), right = "x" .. tostring(counts[id]) }
    end
    return rows
  end

  local function moveMoveIdOf(view, item)
    if not item then return nil end
    return (view == "bag" or view == "pc") and item.moveId or item.value
  end

  local function availableMoveTypes(game, view)
    local ids = {}
    for _, row in ipairs(moveMoveRows(game, view)) do
      local id = moveMoveIdOf(view, row)
      if id then ids[id] = 1 end
    end
    return core.availableCategoriesSorted(ids, function(id) return Moves.moveTypeOf(game, id) end)
  end

  local function pageLabel(view)
    if view == "bank" then return "BANK" end
    if view == "pc" then return "PC" end
    return "BAG"
  end

  local function speciesKnowsMove(def, moveId)
    if not def then return false end
    for _, m in ipairs(def.tmhm or {}) do
      if m == moveId then return true end
    end
    if GameVersion.generation() == 2 then
      for _, entry in ipairs(def.levelMoves or {}) do
        if entry.move == moveId then return true end
      end
      for _, m in ipairs(def.eggMoves or {}) do
        if m == moveId then return true end
      end
    else
      for _, m in ipairs(def.level1Moves or {}) do
        if m == moveId then return true end
      end
      for _, entry in ipairs(def.learnset or {}) do
        if entry.move == moveId then return true end
      end
    end
    return false
  end

  local function evolvesInto(evo) return evo and (evo.into or evo.species) end

  local prevolutionCache = {}
  local function prevolutionOf(game, species)
    local cached = prevolutionCache[species]
    if cached ~= nil then return cached or nil end
    local prev
    for id, def in pairs(game.data.pokemon) do
      if type(def) == "table" and type(def.evolutions) == "table" then
        for _, evo in ipairs(def.evolutions) do
          if evolvesInto(evo) == species then
            prev = id
            break
          end
        end
      end
      if prev then break end
    end
    prevolutionCache[species] = prev or false
    return prev
  end

  local function gen3Engine()
    local ok, module = pcall(require, "src.core.game3.pokemon")
    return ok and type(module) == "table" and module or nil
  end

  local gen3Prevolutions

  local function gen3Prevolution(P, species)
    if not gen3Prevolutions or gen3Prevolutions.engine ~= P then
      if not P._names and P.install then pcall(P.install, P._cache) end
      local reverse = {}
      for sp in pairs(P._names or {}) do
        for _, evo in ipairs(P.evolutions(sp)) do
          local target = tonumber(evo.target or evo[3])
          if target and target > 0 and reverse[target] == nil then reverse[target] = sp end
        end
      end
      gen3Prevolutions = { engine = P, reverse = reverse }
    end
    return gen3Prevolutions.reverse[species]
  end

  local function gen3SpeciesKnows(P, species, number)
    for _, entry in ipairs(P.learnset(species)) do
      if tonumber(entry[2] or entry.move) == number then return true end
    end
    if not P._tmhm and P.install then pcall(P.install, P._cache) end
    local machines = P._tmhm and P._tmhm.machines
    for index = 0, 57 do
      if machines and tonumber(machines[index]) == number and P.canLearnTmIndex(species, index) then return true end
    end
    return false
  end

  local function gen3CanLearn(game, mon, moveId)
    local P, number, species = gen3Engine(), MoveSet.toNumber(game, moveId), Species.number(mon)
    if not (P and number and species) then return false end
    local seen = {}
    while species and not seen[species] do
      seen[species] = true
      if gen3SpeciesKnows(P, species, number) then return true end
      species = gen3Prevolution(P, species)
    end
    return false
  end

  local function moveDef(game, id)
    local moves = game.data.moves
    local def = moves[id]
    if def == nil and GameVersion.generation() == 3 then def = moves[GenerationMap.translateMoveId(id, 3)] end
    return def
  end

  local function canLearn(game, mon, moveId)
    if type(mon) ~= "table" or mon.isEgg then return false end
    if GameVersion.generation() == 3 then return gen3CanLearn(game, mon, moveId) end
    local species = Species.key(mon)
    local seen = { [species] = true }
    while species do
      if speciesKnowsMove(game.data.pokemon[species], moveId) then return true end
      local prev = prevolutionOf(game, species)
      if not prev or seen[prev] then break end
      seen[prev] = true
      species = prev
    end
    return false
  end

  local function moveTeachContext(game, mon, id)
    local mdef = moveDef(game, id)
    local moveLabel = mdef and mdef.name or id
    local speciesDef = game.data.pokemon[Species.key(mon)]
    local nickname = mon.nickname ~= "" and mon.nickname or nil
    local name = nickname or mon.name or (speciesDef and speciesDef.name) or tostring(Species.key(mon))
    return mdef, moveLabel, name
  end

  local function usesNumbers(mon) return GameVersion.generation() == 3 or MoveSet.form(mon.moves) == "number" end

  local function knowsMove(game, mon, id)
    if usesNumbers(mon) then
      local number = MoveSet.toNumber(game, id)
      for _, mv in ipairs(mon.moves or {}) do
        if mv == number then return true end
      end
      return false
    end
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == id then return true end
    end
    return false
  end

  local function gen3Teach(mon, number)
    local P = gen3Engine()
    if not (P and P.teachMove) then return false end
    local ok, taught = pcall(P.teachMove, mon, number)
    return ok and taught == true
  end

  local function openGen3ForgetMenu(game, mon, number, name, moveLabel, onDone)
    core.confirm(game, Strings("%s wants to\nlearn %s. Forget\na move?", name, moveLabel), function(yes)
      if not yes then return onDone(false) end
      local rows = {}
      for slot = 1, #mon.moves do
        local known = MoveSet.toText(game, mon.moves[slot]) or tostring(mon.moves[slot])
        rows[#rows + 1] = { label = core.truncateName(core.moveName(game, known)), onSelect = function()
          local P = gen3Engine()
          local old, why = P.replaceMove(mon, slot, number)
          if old == nil then
            core.message(game, why == "hm" and "HM moves can't be\nforgotten." or "It didn't work!")
            return onDone(false)
          end
          onDone(true, Strings("%s learned\n%s!", name, moveLabel))
        end }
      end
      rows[#rows + 1] = { label = "CANCEL", onSelect = function() onDone(false) end }
      core.rowActionsMenu(game, rows)
    end, { defaultNo = true, noSound = true })
  end

  -- The engine's own learn flow (Gen 3): its texts, the yes/no prompts and the summary's "pick the move to forget" mode.
  local function openGen3EngineLearn(game, mon, number, name, onDone)
    local okL, LearnMove = pcall(require, "src.core.game3.battle.learn_move")
    local okS, SummaryMenu = pcall(require, "src.ui.game3.summary_menu")
    if not (okL and type(LearnMove) == "table" and LearnMove.begin and okS and type(SummaryMenu) == "table" and SummaryMenu.openMenu) then return false end
    LearnMove.begin({
      mon = mon, moveId = number, displayName = name,
      pushMsg = function(text, cb) core.message(game, text, cb) end,
      askYesNo = function(text, cb) core.confirm(game, text, cb, { noSound = true }) end,
      askForget = function(_, cb, ctx)
        local opened = pcall(SummaryMenu.openMenu, { mon }, 1, {
          mode = "select_move", moveToLearn = ctx and ctx.moveId or number,
          onSelectMove = function(slotIdx) cb(slotIdx) end,
        })
        if not opened then cb(nil) end
      end,
      onDone = function(learned) onDone(learned) end,
    })
    return true
  end

  local function insertOrOverflowMove(game, mon, moveId, entry, successMsg, onDone, afterLearn)
    if usesNumbers(mon) then
      local number = MoveSet.toNumber(game, moveId)
      if not number then return onDone(false, "It can't be\nlearned here.") end
      if #mon.moves < 4 and gen3Teach(mon, number) then
        playSound(game, "Get_Item1")
        if afterLearn then afterLearn() end
        return onDone(true, successMsg)
      end
      local _, moveLabel, name = moveTeachContext(game, mon, moveId)
      if openGen3EngineLearn(game, mon, number, name, function(learned)
        if learned and afterLearn then afterLearn() end
        onDone(learned)
      end) then return end
      return openGen3ForgetMenu(game, mon, number, name, moveLabel, function(learned, msg)
        if learned and afterLearn then afterLearn() end
        onDone(learned, msg)
      end)
    end
    if #mon.moves < 4 then
      table.insert(mon.moves, entry)
      playSound(game, "Get_Item1")
      if afterLearn then afterLearn() end
      onDone(true, successMsg)
    else
      require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId, function(learned)
        if learned and afterLearn then afterLearn() end
        onDone(learned)
      end)
    end
  end

  local function syncedOnDone(game, mon, onDone)
    return function(learned, ...)
      if learned and MoveSet.sync(game, mon) then core.markDirty() end
      return onDone(learned, ...)
    end
  end

  local function attemptTeach(game, mon, moveId, onDone)
    onDone = syncedOnDone(game, mon, onDone)
    mon.moves = mon.moves or {}
    local mdef, moveLabel, name = moveTeachContext(game, mon, moveId)
    if not canLearn(game, mon, moveId) then
      return onDone(false, Strings("%s can't\nlearn %s!", name, moveLabel))
    end
    if knowsMove(game, mon, moveId) then
      return onDone(false, Strings("%s already\nknows %s!", name, moveLabel))
    end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, moveId, function(learned)
        if learned then pcall(function() require("src.core.gen2.Happiness").change(mon, "LEARNMOVE") end) end
        onDone(learned)
      end)
      return
    end
    insertOrOverflowMove(game, mon, moveId, { id = moveId, pp = mdef and mdef.pp },
      Strings("%s learned\n%s!", name, moveLabel), onDone, function()
        pcall(function()
          local follower = require("src.world.PikachuFollower")
          local _ = follower.modifyHappiness and follower.modifyHappiness(game.save, "USEDTMHM", mon)
        end)
      end)
  end

  local function spendMoveUses()
    local INFITE_TM_MODS = { "infinite_tms", "reusable_machines", "reusable_machines_gen2", "reusable_machines_gen3" }
    for _, modId in ipairs(INFITE_TM_MODS) do
      if mod.find(modId) then return false end
    end
    return true
  end

  local function openTeachTargetList(game, moveId, onTaught)
    local handle
    local function doTeach(mon)
      if moveCount(moveId) <= 0 then
        handle.refresh()
        handle.setFooter("No uses left.")
        return
      end
      attemptTeach(game, mon, moveId, function(learned, msg)
        if not learned then
          handle.refresh()
          handle.setFooter(msg)
          return
        end
        if spendMoveUses() then
          core.bucketSub(loadStorage().entries.moves, moveId, 1)
          markDirty()
        end
        core.emitAction("moves", "use", "move_taught", { id = moveId, mon = mon })
        mod.exports.updateCustomStorageStats(mod.id, "moves", function(stats) stats.taught = stats.taught + 1 end)
        if onTaught then onTaught() end
        if moveCount(moveId) <= 0 then
          handle.close()
          if msg then core.message(game, msg) end
        else
          handle.refresh()
          handle.setFooter(msg)
        end
      end)
    end
    handle = Pickers.openMovePicker(mod, core, game, {
      compatible = function(mon) return canLearn(game, mon, moveId) end,
      onChoose = function(mon) doTeach(mon) end,
    })
  end

  local entryMoveId = core.moveEntryId

  local function recoverableMoves(game, personality)
    if personality == nil then return {} end
    local s = loadStorage()
    local bucket = s.orphaned and s.orphaned.boxes and s.orphaned.boxes.moves and s.orphaned.boxes.moves[personality]
    if type(bucket) ~= "table" then return {} end
    local out = {}
    for _, mv in ipairs(bucket) do
      local id = entryMoveId(mv)
      if id and moveDef(game, id) then out[#out + 1] = mv end
    end
    return out
  end

  local function canRelearn(game, mon)
    if type(mon) ~= "table" or mon.personality == nil then return false end
    return #recoverableMoves(game, mon.personality) > 0
  end

  local function consumeRecoveredMove(personality, id)
    local s = loadStorage()
    local bucket = s.orphaned and s.orphaned.boxes and s.orphaned.boxes.moves and s.orphaned.boxes.moves[personality]
    if type(bucket) ~= "table" then return end
    for i, mv in ipairs(bucket) do
      if entryMoveId(mv) == id then table.remove(bucket, i) break end
    end
    core.normalizeBoxes(s)
    markDirty()
  end

  local function scanMons(game, fn)
    local s = loadStorage()
    for _, box in ipairs(s.entries.boxes) do
      for _, mon in ipairs(box.content) do
        if fn(mon) then return true end
      end
    end
    for _, mon in ipairs(game.save.party or {}) do
      if fn(mon) then return true end
    end
    for _, box in ipairs(BoxAccess.boxes(game)) do
      for _, mon in BoxAccess.each(box) do
        if fn(mon) then return true end
      end
    end
    return false
  end

  local function recoveredMoveEntry(mvEntry, id, mdef)
    local entry = {}
    if type(mvEntry) == "table" then
      for k, v in pairs(mvEntry) do entry[k] = v end
    else entry.id, entry.pp = id, (mdef and mdef.pp or 0) end
    return entry
  end

  local function fillMonSlots(game, mon)
    if type(mon) ~= "table" or mon.personality == nil then return 0 end
    mon.moves = mon.moves or {}
    local filled = 0
    while #mon.moves < 4 do
      local moves = recoverableMoves(game, mon.personality)
      if #moves == 0 then break end
      local mvEntry = moves[1]
      local id = entryMoveId(mvEntry)
      if knowsMove(game, mon, id) then
        consumeRecoveredMove(mon.personality, id)
      elseif usesNumbers(mon) then
        local number = MoveSet.toNumber(game, id)
        if not (number and gen3Teach(mon, number)) then break end
        consumeRecoveredMove(mon.personality, id)
        filled = filled + 1
      else
        table.insert(mon.moves, recoveredMoveEntry(mvEntry, id, game.data.moves[id]))
        consumeRecoveredMove(mon.personality, id)
        filled = filled + 1
      end
    end
    if filled > 0 and MoveSet.sync(game, mon) then core.markDirty() end
    return filled
  end

  function autoFillRecoveredMoves(game)
    local filled = 0
    scanMons(game, function(mon)
      filled = filled + fillMonSlots(game, mon)
      return false
    end)
    return filled
  end

  local function attemptRelearn(game, mon, mvEntry, onDone)
    onDone = syncedOnDone(game, mon, onDone)
    mon.moves = mon.moves or {}
    local id = entryMoveId(mvEntry)
    local mdef, moveLabel, name = moveTeachContext(game, mon, id)
    if knowsMove(game, mon, id) then return onDone(false, Strings("%s already\nknows %s!", name, moveLabel)) end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, id, function(learned) onDone(learned) end)
      return
    end
    insertOrOverflowMove(game, mon, id, recoveredMoveEntry(mvEntry, id, mdef), Strings("%s remembered\n%s!", name, moveLabel), onDone)
  end

  local function openRelearnMovesList(game, mon, onClose)
    local function rebuildRows()
      local moves = recoverableMoves(game, mon.personality)
      local rows = {}
      for _, mv in ipairs(moves) do
        rows[#rows + 1] = { value = mv, label = core.truncateName(core.moveName(game, entryMoveId(mv))) }
      end
      return rows
    end
    local function closeScreen()
      game.stack:pop()
      if onClose then onClose() end
    end
    local screen = core.listScreen(game, { counter = true, onClose = closeScreen })
    screen:rebuild("RELEARN MOVE", rebuildRows(), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item, list)
        attemptRelearn(game, mon, item.value, function(learned, msg)
          if not learned then
            list.footer = msg
            return
          end
          consumeRecoveredMove(mon.personality, entryMoveId(item.value))
          list.items = rebuildRows()
          list.index = math.min(list.index, math.max(1, #list.items))
          list.footer = msg
          if #list.items == 0 then closeScreen() end
        end)
      end,
    })
    game.stack:push(screen)
  end

  Moves.canRelearn = canRelearn
  Moves.openRelearn = openRelearnMovesList

  local ALL_TYPES = "ALL"

  local function bagStore(game, view) return view == "pc" and PcItems.counts(game) or Bag.counts(game) end

  local function rowMoveId(game, view, row)
    if row == nil then return nil end
    if view == "bank" then return row end
    return tmMoveId(row, game.data.items[row])
  end

  local function rowsForType(game, view, pageId)
    local rows = moveMoveRows(game, view)
    if pageId == nil or pageId == ALL_TYPES then return rows end
    local filtered = {}
    for _, row in ipairs(rows) do
      if Moves.moveTypeOf(game, moveMoveIdOf(view, row)) == pageId then filtered[#filtered + 1] = row end
    end
    return filtered
  end

  local function startTeach(game, moveId, rebuild, list, env)
    if moveCount(moveId) <= 0 then
      core.currentList(env, list).footer = "The selection changed."
      return
    end
    openTeachTargetList(game, moveId, function() rebuild(true) end)
  end

  local function startToss(game, view, row, moveId, rebuild, list, env)
    local name = core.moveName(game, moveId)
    local function liveList() return core.currentList(env, list) end
    if view == "bank" then
      core.confirmTossQuantity(game, list, {
        liveList = liveList,
        count = moveCount(moveId),
        name = name,
        onToss = function(qty)
          withdrawMove(moveId, qty)
          core.emitAction("moves", "remove", "move_tossed", { id = moveId, qty = qty })
        end,
        rebuild = function() rebuild(true) end,
      })
    else
      local store = bagStore(game, view)
      core.confirmTossQuantity(game, list, {
        liveList = liveList,
        count = store[row],
        name = name,
        onToss = function(qty)
          if view == "pc" then
            core.bucketSub(store, row, qty)
          else Bag.remove(game.save, row, qty) end
        end,
        rebuild = function() rebuild(true) end,
      })
    end
  end

  local function transferMove(game, srcView, destView, row, qty)
    local itemId, moveId, count
    if srcView == "bank" then
      moveId, count = row, moveCount(row)
      if count > 0 and not isValidMachine(moveId, game.data) then return false, "There's no TM\nfor that move!" end
      itemId = tmItemId(moveId)
    else
      itemId, moveId, count = row, rowMoveId(game, srcView, row), bagStore(game, srcView)[row]
    end
    if not (moveId and count and count > 0) then return false, "The selection changed." end
    qty = math.min(qty or count, count)
    if destView == "bag" then
      if not Bag.add(game.save, itemId, qty, game.data) then return false, "You can't carry\nany more items." end
    elseif destView == "pc" then
      if PcItems.full(game, itemId, qty) then return false, "No room left to\nstore items." end
      PcItems.add(game, itemId, qty)
    end
    if srcView == "bank" then
      withdrawMove(moveId, qty)
      core.emitAction("moves", "withdraw", "move_withdrawn", { id = moveId, qty = qty })
    elseif srcView == "pc" then
      PcItems.remove(game, itemId, qty)
    else
      Bag.remove(game.save, itemId, qty)
    end
    if destView == "bank" then
      depositMove(moveId, qty)
      core.emitAction("moves", "deposit", "move_deposited", { id = moveId, qty = qty })
    end
    local msg
    if destView == "bank" then msg = Strings("%s was\nstored in BANK.", core.moveName(game, moveId))
    else msg = Strings("Withdrew\n%s.", core.itemName(game, itemId)) end
    return true, msg
  end

  local function startTransfer(game, srcView, destView, row, rebuild, list, env)
    local count = srcView == "bank" and moveCount(row) or bagStore(game, srcView)[row]
    if not (count and count > 0) then
      core.currentList(env, list).footer = "The selection changed."
      return
    end
    askQuantity(game, list, count, function(qty)
      local ok, msg = transferMove(game, srcView, destView, row, qty)
      if ok then playSound(game, "Withdraw_Deposit") end
      rebuild(true)
      core.currentList(env, list).footer = msg
    end)
  end

  local VIEW_LABEL = { bank = "BANK", bag = "BAG", pc = "PC" }

  local function transferRow(view)
    local targets = {}
    for _, dest in ipairs({ "bank", "bag", "pc" }) do
      if dest ~= view then
        targets[#targets + 1] = { label = "TO " .. VIEW_LABEL[dest], onSelect = function(game, _, row, rebuild, list, env) startTransfer(game, view, dest, row, rebuild, list, env) end }
      end
    end
    return core.transferGroup(targets)
  end

  local function makeMoveContainer(view)
    local label = pageLabel(view)
    local container = {
      id = view, label = label,
      getPages = function(game)
        local types = availableMoveTypes(game, view)
        local pages = { { id = ALL_TYPES, label = ALL_TYPES } }
        if #types - 1 >= 2 then
          for i = 2, #types do pages[#pages + 1] = { id = types[i], label = types[i] } end
        end
        return pages
      end,
      title = function(_, pageId)
        if pageId == nil or pageId == ALL_TYPES then return label end
        return Strings("%s (%s)", label, pageId)
      end,
      build = function(game, pageId)
        return rowsForType(game, view, pageId), { messageBox = true, noSound = true, wrap = true }
      end,
      dynamicFooter = function(game, _, row, nextLabel)
        local id = rowMoveId(game, view, row)
        local detail = Moves.moveDetailLine(game, id)
        local pp = Moves.movePpText(game, id)
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or nil
        local line2 = (selectLine and pp) and core.padToRight(selectLine, pp) or (selectLine or pp)
        if not line2 then return detail end
        return (detail or "") .. "\n" .. line2
      end,
      canTransfer = true,
      canListPages = true,
      listPagesLabel = "TYPES",
      canWithdraw = false,
      withdraw = function(game, _, row, destView) return (transferMove(game, view, destView, row)) end,
      deposit = function() end,
      onAction = {
        { label = "TEACH",
          visible = function(game, _, row) return moveCount(rowMoveId(game, view, row)) > 0 end,
          onSelect = function(game, _, row, rebuild, list, env) startTeach(game, rowMoveId(game, view, row), rebuild, list, env) end },
        transferRow(view),
        { label = "TOSS", onSelect = function(game, _, row, rebuild, list, env)
          startToss(game, view, row, rowMoveId(game, view, row), rebuild, list, env)
        end },
      },
    }
    return container
  end

  Moves.containers = { makeMoveContainer("bank"), makeMoveContainer("bag"), makeMoveContainer("pc") }

  local function buildManageMovesScreen(game)
    return core.entryScreen(game, Moves.containers, { counter = true })
  end

  local function BankMoveMenu(game) return buildManageMovesScreen(game) end

  mod.content.screens:register(SCREEN_ID, { new = BankMoveMenu })

  local movesTab = core.entryTab("moves", "show_moves_tab")
  Moves.tabEnabled = movesTab.shown

  mod.exports.depositMove = core.emitOnSuccess(depositMove, "moves", "deposit", "move_deposited", core.idQtyPayload)
  mod.exports.withdrawMove = core.emitOnSuccess(withdrawMove, "moves", "withdraw", "move_withdrawn", core.idQtyPayload)
  mod.exports.tossMove = core.emitOnSuccess(withdrawMove, "moves", "remove", "move_tossed", core.idQtyPayload)
  mod.exports.moveCount = moveCount
  mod.exports.listMoves = listMoves
  mod.exports.isValidMachine = function(id, game) return isValidMachine(id, game and game.data) end
  mod.exports.validateMovesStorage = Moves.validateStorage
  mod.exports.listInvalidMoves = listInvalidMoves
  mod.exports.invalidMoveCount = invalidMoveCount
  mod.exports.tmItemForMove = tmItemId
  mod.exports.canLearn = canLearn
  mod.exports.speciesKnowsMove = speciesKnowsMove
  mod.exports.prevolutionOf = prevolutionOf
  mod.exports.movesScreenId = SCREEN_ID
  mod.exports.setMovesTabEnabled = movesTab.setEnabled
  mod.exports.isMovesTabEnabled = Moves.tabEnabled
  mod.log:info("Pokemon Bank: Moves tab ready")
  return Moves
end

return Module
