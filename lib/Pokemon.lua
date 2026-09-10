local V = ...

local GameVersion = require("src.core.GameVersion")
local Stats = require("src.pokemon.Stats")
local Party = require("src.pokemon.Party")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local Boxes = require("src.pokemon.Boxes")

local SCREEN_ID = "PokemonBankBox"
local TRANSFER_BOX_SCREEN_ID = "PokemonBankTransferBox"
local MOVE_SCREEN_ID = "PokemonBankMovePkmn"

local Module = {}

function Module.install(mod, core)
  local ListMenu = mod.ui.ListMenu
  local GenerationMap = V.require("GenerationMap")
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
    local def = game.data.pokemon[mon.species]
    return (def and def.name) or tostring(mon.species)
  end

  local function gen2StatsComplete(stats)
    return stats and type(stats.hp) == "number" and type(stats.attack) == "number" and type(stats.defense) == "number" and type(stats.speed) == "number" and type(stats.specialAttack) == "number" and type(stats.specialDefense) == "number"
  end

  local function ensureStats(game, mon)
    if type(mon) ~= "table" then return mon end
    if GameVersion.generation() == 2 then
      if gen2StatsComplete(mon.stats) then return mon end
      local def = game.data.pokemon[mon.species]
      if not (def and def.baseStats) then return mon end
      local stats = require("src.battle.gen2.Mon").stats(def.baseStats, mon.dvs or {}, mon.level or 1, mon.statExp)
      mon.stats = stats
      mon.hp = math.max(0, math.min(tonumber(mon.hp) or stats.hp, stats.hp))
      return mon
    end
    local def = game.data.pokemon[mon.species]
    if def then Stats.ensure(def, mon) end
    return mon
  end

  local function healMon(game, mon)
    if type(mon) ~= "table" then return mon end
    if type(mon.stats) == "table" and mon.stats.hp then mon.hp = mon.stats.hp end
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    local movesData = game and game.data and game.data.moves
    if movesData and type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        if type(mv) == "table" and mv.id then
          local def = movesData[mv.id]
          if def then
            if GameVersion.generation() == 2 then
              mv.pp = mv.maxPp or def.pp
            else
              mv.pp = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)
            end
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
    for _, box in ipairs(s.boxes) do
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

  local function mirrorHeldItem(mon)
    if type(mon) ~= "table" then return end
    local value = mon.item or mon.heldItem
    if value == nil then return end
    if GameVersion.generation() == 2 then
      mon.item, mon.heldItem = value, nil
    else
      mon.heldItem, mon.item = value, nil
    end
  end

  local function mirrorEggFields(mon)
    if type(mon) ~= "table" or mon.isEgg ~= true then return end
    local crystal251 = mod.find("CRYSTAL_251")
    if mon.eggSteps ~= nil or mon.eggCycles ~= nil then
      local cycles = math.min(mon.eggSteps or mon.eggCycles, mon.eggCycles or mon.eggSteps)
      if GameVersion.generation() == 2 then
        mon.eggSteps, mon.eggCycles = cycles, nil
      else
        mon.eggCycles, mon.eggSteps = cycles, nil
      end
    end
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
            if mv.maxPp == nil then
              mv.maxPp = def.pp + (mv.ppUps or 0) * step
            end
          elseif mv.ppUps == nil and mv.maxPp then
            mv.ppUps = step > 0 and math.max(0, math.min(3, math.floor((mv.maxPp - def.pp) / step + 0.5))) or 0
          end
        end
      end
    end
  end

  local STATUS_TO_GEN2 = { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze" }
  local STATUS_TO_GEN1 = { sleep = "SLP", poison = "PSN", toxic = "PSN", burn = "BRN", freeze = "FRZ", paralyze = "PAR" }

  local function reshapeStatus(mon)
    if type(mon) ~= "table" or mon.status == nil then return end
    if GameVersion.generation() == 2 then
      mon.status = STATUS_TO_GEN2[mon.status] or mon.status
    else
      mon.status = STATUS_TO_GEN1[mon.status] or mon.status
      mon.statusTurns = nil
      mon.toxicCounter = nil
    end
  end

  local function stampTrainer(game, mon)
    if type(mon) ~= "table" then return end
    local player = game and game.save and game.save.player
    if not player then return end
    mon.ot = player.name
    mon.otId = player.id
    mon.otName = player.name
  end

  local function stampEggTrainer(game, mon) if mon and mon.isEgg then stampTrainer(game, mon) end end

  local function stampNewTrainer(game, mon)
    if mod.options:get("inherit_trainer_on_withdraw") then stampTrainer(game, mon) end
  end

  local function reshapeForActiveGame(game, mon)
    if type(mon) ~= "table" then return mon end
    local expValue = mon.exp or mon.experience
    if expValue ~= nil then
      if GameVersion.generation() == 2 then
        mon.experience, mon.exp = expValue, nil
      else
        mon.exp, mon.experience = expValue, nil
      end
    end
    reshapeStatus(mon)
    mirrorHeldItem(mon)
    mirrorEggFields(mon)
    stampEggTrainer(game, mon)
    reshapeMoves(game, mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
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
      if mon.gender == nil then mon.gender = Mon.gender(def, mon.dvs or {}, { species = mon.species, level = mon.level }) end
      if mon.happiness == nil then mon.happiness = 70 end
      if mon.pokerus == nil then mon.pokerus = 0 end
    else
      if mon.stats.special == nil and baseStats.special then
        mon.stats.special = Stats.calc(def, mon.level or 1, mon.dvs or {}, mon.statExp).special
      end
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
    local player = game and game.save and game.save.player
    if not (player and mon.otId ~= nil and mon.otId == player.id) then return false end
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

  function Pokemon.depositMon(mon)
    if type(mon) ~= "table" then return nil end
    stampOrigin(mon)
    local s = loadStorage()
    local n = #s.boxes
    local start = math.min(s.currentBox, n)
    for off = 0, n - 1 do
      local i = ((start - 1 + off) % n) + 1
      local content = s.boxes[i].content
      if #content < boxCapacity() then
        table.insert(content, mon)
        normalizeBoxes(s)
        markDirty()
        return i, #content
      end
    end
    return nil
  end

  local moveId = core.moveEntryId

  local function isValidPokemon(mon, data)
    if type(mon) ~= "table" or type(data) ~= "table" then return false end
    local pokemon = data.pokemon
    if type(pokemon) ~= "table" then return false end
    if not pokemon[mon.species] then
      local translated = GenerationMap.translateSpeciesId(mon.species)
      if not pokemon[translated] then return false end
      mon.species = translated
    end
    if mon.isEgg and GameVersion.generation() == 1 and not mod.find("CRYSTAL_251") then
      return false
    end
    return true
  end

  local function checkHeldItem(game, mon, orphaned, lostItems)
    mirrorHeldItem(mon)
    local item = mon.item or mon.heldItem
    if not item then return false end
    local valid = mod.exports.isValidItem and mod.exports.isValidItem(item, game)
    if not valid and mod.exports.isValidItem then
      local translated = GenerationMap.translateItemId(item)
      if translated ~= item and mod.exports.isValidItem(translated, game) then
        item = translated
        if GameVersion.generation() == 2 then mon.item = item else mon.heldItem = item end
        valid = true
      end
    end
    local blacklisted = mod.exports.isBlacklisted and mod.exports.isBlacklisted(item, game)
    if valid and not blacklisted then return false end
    mon.item = nil
    mon.heldItem = nil
    core.bucketAdd(orphaned.items, item, 1)
    lostItems[#lostItems + 1] = { id = item, count = 1 }
    return true
  end

  local function bankIdTaken(s, id)
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box.content) do
        if mon.bankId == id then return true end
      end
    end
    local orphaned = s.orphaned
    if orphaned then
      for _, mon in ipairs(orphaned.mons or {}) do
        if mon.bankId == id then return true end
      end
      if orphaned.monMoves and orphaned.monMoves[id] then return true end
    end
    return false
  end

  local function assignBankId(s, mon)
    if type(mon) ~= "table" or mon.bankId ~= nil then return false end
    mon.bankId = Utils.generateId(function(id) return bankIdTaken(s, id) end)
    return true
  end

  local function scrubInvalidMoves(s, mon, orphaned, data)
    if type(mon.moves) ~= "table" or #mon.moves == 0 then return false end
    local keep, bad = {}, {}
    for _, mv in ipairs(mon.moves) do
      local id = moveId(mv)
      if id and not data.moves[id] then
        bad[#bad + 1] = mv
      else
        keep[#keep + 1] = mv
      end
    end
    if #bad == 0 then return false end
    assignBankId(s, mon)
    local bucket = orphaned.monMoves[mon.bankId]
    if not bucket then
      bucket = {}
      orphaned.monMoves[mon.bankId] = bucket
    end
    for _, mv in ipairs(bad) do
      local id = moveId(mv)
      local dup = false
      for _, existing in ipairs(bucket) do
        if moveId(existing) == id then dup = true break end
      end
      if not dup then bucket[#bucket + 1] = mv end
    end
    mon.moves = keep
    return true
  end

  function Pokemon.validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {}, lostItems = {} }
    end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local bankIdAssigned = false
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box.content) do
        if assignBankId(s, mon) then bankIdAssigned = true end
      end
    end
    for _, mon in ipairs(orphaned.mons) do
      if assignBankId(s, mon) then bankIdAssigned = true end
    end
    local quarantined, restored = 0, 0
    local lostMons, restoredMons, lostItems = {}, {}, {}
    local originBackfilled = false
    for boxNum = 1, #s.boxes do
      local content = s.boxes[boxNum].content
      for idx = #content, 1, -1 do
        local mon = content[idx]
        if not isValidPokemon(mon, data) then
          table.remove(content, idx)
          orphaned.mons[#orphaned.mons + 1] = mon
          quarantined = quarantined + 1
          lostMons[#lostMons + 1] = { species = mon.species, from = "BOX " .. boxNum }
        else
          local heldChanged = checkHeldItem(game, mon, orphaned, lostItems)
          if backfillOrigin(game, mon) then originBackfilled = true end
          if heldChanged then markDirty() end
        end
      end
    end
    normalizeBoxes(s)
    local targetBoxNum = #s.boxes
    local targetContent = s.boxes[targetBoxNum].content
    for idx = #orphaned.mons, 1, -1 do
      local mon = orphaned.mons[idx]
      if isValidPokemon(mon, data) then
        table.remove(orphaned.mons, idx)
        checkHeldItem(game, mon, orphaned, lostItems)
        if backfillOrigin(game, mon) then originBackfilled = true end
        -- Find space in current target box or create new if needed
        if #targetContent >= boxCapacity() then
          s.boxes[#s.boxes + 1] = core.newBox(s)
          targetBoxNum = #s.boxes
          targetContent = s.boxes[targetBoxNum].content
        end
        table.insert(targetContent, mon)
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = mon.species, box = targetBoxNum }
      end
    end
    normalizeBoxes(s)
    local scrubbed = 0
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box.content) do
        if scrubInvalidMoves(s, mon, orphaned, data) then scrubbed = scrubbed + 1 end
      end
    end
    return {
      changed = quarantined > 0 or restored > 0 or #lostItems > 0 or bankIdAssigned or scrubbed > 0 or originBackfilled,
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
    local orphaned = s.orphaned and s.orphaned.mons or {}
    for idx, mon in ipairs(orphaned) do
      out[#out + 1] = { index = idx, mon = mon }
    end
    return out
  end

  local function invalidMonCount()
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.mons or {}
    return #orphaned
  end

  function Pokemon.withdrawMon(boxNum, idx)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    local content = box and box.content
    local mon = content and content[idx]
    if not mon then return nil end
    table.remove(content, idx)
    normalizeBoxes(s)
    markDirty()
    return mon
  end

  local function peekMon(boxNum, idx)
    local box = loadStorage().boxes[boxNum]
    return box and box.content[idx] or nil
  end

  local Legality = V.require("Legality")
  local function isLegal(mon, game)
    reshapeForActiveGame(game, mon)
    return Legality.isLegal(mod, core, game, mon)
  end

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
    local fromBox = s.boxes[srcBox]
    local from = fromBox and fromBox.content
    local mon = from and from[srcIdx]
    if not mon then return false end
    if srcBox == destBox and destIdx == srcIdx then return false end
    local toBox = s.boxes[destBox]
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
    for boxNum, box in ipairs(s.boxes) do
      for idx, mon in ipairs(box.content) do out[#out + 1] = { box = boxNum, index = idx, mon = mon } end
    end
    return out
  end

  local function countMons()
    local n = 0
    for _, box in ipairs(loadStorage().boxes) do n = n + #box.content end
    return n
  end

  local function boxCount()
    return #loadStorage().boxes
  end

  -- =========================================================================
  -- Pokémon UI
  -- =========================================================================
  local function buildBoxRows(s)
    local cap = boxCapacity()
    local items = {}
    for i = 1, #s.boxes do
      local content = s.boxes[i].content
      items[#items + 1] = {
        label = boxLabel(s, i),
        sub = cap == math.huge and tostring(#content) or ("%d/%d"):format(#content, cap),
        value = i,
      }
    end
    return items
  end

  local function attachCurrentBoxMark(list, currentBoxNumFn)
    local origDraw = list.draw
    function list:draw()
      origDraw(self)
      love.graphics.setColor(0, 0, 0, 1)
      local current = currentBoxNumFn()
      for row = 1, self.rows do
        local item = self.items[self.scroll + row]
        if item and item.value == current then
          local y = self.itemBox and (32 + (row - 1) * 16) or (8 + row * 16)
          local x0 = self.itemBox and 48 or 16
          local x = x0 + Font.width(item.label) + 6
          love.graphics.rectangle("fill", x, y + 2, 4, 4)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local function drawCurrentBoxTitleMark(list)
    love.graphics.setColor(0, 0, 0, 1)
    local x = 8 + Font.width(Strings(list.title)) + 6
    love.graphics.rectangle("fill", x, 4 + 2, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function renameBox(game, view, boxNum, onDone)
    local current = view == "bank" and ((loadStorage().boxes[boxNum] or {}).name or "") or (pcBoxName(game, boxNum) or "")
    local function apply(name)
      local value = (name and #name > 0) and name or nil
      if view == "bank" then
        local st = loadStorage()
        local box = st.boxes[boxNum]
        if box then box.name = value end
        markDirty()
      else
        pcBoxNamesTable()[boxNum] = value
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
    game.stack:push(require("src.ui.NamingScreen").new(game, {
      title = "BOX NAME?", default = current, maxLen = 8,
      onDone = apply,
    }))
  end

  local function deleteBox(game, boxNum, onDone)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    if not box or #box.content > 0 then
      message(game, "That box still\nhas POKéMON\nin it!")
      if onDone then onDone() end
      return
    end
    table.remove(s.boxes, boxNum)
    normalizeBoxes(s)
    markDirty()
    if onDone then onDone() end
  end

  local openTransferBoxList
  local openMoveList

  local function openBoxActionsPopup(game, view, boxNum, callbacks)
    local rows = {}
    local function appendRow(label, onSelect) rows[#rows + 1] = { label = label, onSelect = onSelect }  end
    if callbacks.onView then appendRow("VIEW", callbacks.onView) end
    appendRow("CHANGE", function()
      if view == "bank" then
        local st = loadStorage()
        st.currentBox = math.max(1, math.min(#st.boxes, boxNum))
        markDirty()
      else
        game.save.currentBox = math.max(1, math.min(Boxes.COUNT, boxNum))
      end
      callbacks.afterAction()
    end)
    appendRow("SWITCH", function() callbacks.onSwitch(boxNum) end)
    appendRow("TRANSFER", function() openTransferBoxList(game, { view = view, box = boxNum }, callbacks.afterAction) end)
    appendRow("RENAME", function() renameBox(game, view, boxNum, callbacks.afterAction) end)
    if view == "bank" then appendRow("DELETE", function() deleteBox(game, boxNum, callbacks.afterAction) end) end
    appendRow("CANCEL")
    core.rowActionsMenu(game, rows)
  end

  local function openManageBoxList(game, opts)
    opts = opts or {}
    Boxes.ensure(game.save)
    local state = { view = opts.initialView or "bank", pendingSwap = nil }
    local screen = { isOpaque = true }
    local list
    local refresh, openBoxActionsMenu, cycleView, backHandler, closeList

    local function boxesOf() return state.view == "bank" and loadStorage().boxes or game.save.boxes end

    local function currentBoxNumOf() return state.view == "bank" and loadStorage().currentBox or game.save.currentBox end

    local function viewTitle() return state.view == "bank" and "BANK" or "PC" end

    local function rowsForView()
      if state.view == "bank" then return buildBoxRows(loadStorage()) end
      local pcNames = pcBoxNamesTable()
      local boxes = game.save.boxes
      local items = {}
      for i = 1, Boxes.COUNT do
        local name = pcNames[i]
        local label = (type(name) == "string" and name ~= "") and name or Strings("BOX %d", i)
        items[#items + 1] = { label = label, sub = ("%d/%d"):format(#boxes[i], Boxes.CAPACITY), value = i }
      end
      return items
    end

    refresh = function(preserveCursor)
      local oldIndex = preserveCursor and list.index
      list.items = rowsForView()
      list.title = viewTitle()
      core.setListCursor(list, oldIndex or 1)
      list.footer = state.pendingSwap and "Choose a box\nto switch with." or nil
      list.swapIndex = state.pendingSwap
    end

    cycleView = function()
      if state.pendingSwap then return end
      state.view = state.view == "bank" and "pc" or "bank"
      refresh()
    end

    closeList = function(navigateTo)
      if opts.onClose then opts.onClose(navigateTo) end
      game.stack:pop()
    end

    openBoxActionsMenu = function(boxNum)
      openBoxActionsPopup(game, state.view, boxNum, {
        onView = function()
          if opts.onClose then
            closeList({ view = state.view, box = boxNum })
          else
            closeList(nil)
            game.stack:push(openMoveList(game, { initialView = state.view, initialBox = boxNum }))
          end
        end,
        onSwitch = function(bn)
          state.pendingSwap = bn
          refresh(true)
        end,
        afterAction = function() refresh(true) end,
      })
    end

    backHandler = core.pendingSwapBackHandler(state, refresh, function() closeList(nil) end)

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      core.drawListTitle(list)
      core.drawListCounter(list)
    end

    list = ListMenu.new(game, viewTitle(), rowsForView(), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item)
        if state.pendingSwap then
          local boxes = boxesOf()
          local a, b = state.pendingSwap, item.value
          state.pendingSwap = nil
          if a ~= b then
            boxes[a], boxes[b] = boxes[b], boxes[a]
            if state.view == "bank" then
              local st = loadStorage()
              if st.currentBox == a then st.currentBox = b
              elseif st.currentBox == b then st.currentBox = a end
              normalizeBoxes(st)
              markDirty()
            else
              local pcNames = pcBoxNamesTable()
              pcNames[a], pcNames[b] = pcNames[b], pcNames[a]
              if game.save.currentBox == a then game.save.currentBox = b
              elseif game.save.currentBox == b then game.save.currentBox = a end
            end
            core.playSound(game, "Swap")
          end
          refresh(true)
          return
        end
        openBoxActionsMenu(item.value)
      end,
    })
    attachCurrentBoxMark(list, currentBoxNumOf)
    if opts.initialBox then core.setListCursor(list, opts.initialBox) end
    return screen
  end

  local function transferBankBox(srcBoxNum, destBoxNum)
    local s = loadStorage()
    local srcBox = s.boxes[srcBoxNum]
    local destBox = s.boxes[destBoxNum]
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
    Boxes.ensure(game.save)
    local boxes = game.save.boxes
    local src = boxes[srcBoxNum]
    if not src or #src == 0 then return 0, 0 end
    local mons = {}
    for i = 1, #src do mons[i] = src[i] end
    local leftover = {}
    local cursor = destBoxNum
    local moved = 0
    for _, mon in ipairs(mons) do
      local placed = false
      for off = 0, Boxes.COUNT - 1 do
        local boxNum = ((cursor - 1 + off) % Boxes.COUNT) + 1
        if boxNum ~= srcBoxNum and #boxes[boxNum] < Boxes.CAPACITY then
          table.insert(boxes[boxNum], mon)
          cursor = boxNum
          moved = moved + 1
          placed = true
          break
        end
      end
      if not placed then leftover[#leftover + 1] = mon end
    end
    for i = #src, 1, -1 do table.remove(src, i) end
    for _, mon in ipairs(leftover) do table.insert(src, mon) end
    return moved, #leftover
  end

  openTransferBoxList = function(game, source, onTransferred)
    Boxes.ensure(game.save)
    local state = {
      view = source.view,
      bankBox = source.view == "bank" and source.box or loadStorage().currentBox,
      pcBox = source.view == "pc" and source.box or math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
    }

    local screen = { isOpaque = true }
    local list
    local rebuild, backHandler

    local function currentBoxNum() return state.view == "bank" and state.bankBox or state.pcBox end

    local function currentBox()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox].content
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return boxLabel(loadStorage(), state.bankBox)
      else return pcBoxLabel(game, state.pcBox) end
    end

    local function isSourceBox() return state.view == source.view and currentBoxNum() == source.box end

    local function cycleView()
      state.view = (state.view == "bank") and "pc" or "bank"
      rebuild()
    end

    local function cycleBox(delta)
      if state.view == "bank" then
        state.bankBox = core.cycleBoxNumber(state.bankBox, #loadStorage().boxes, delta)
      else state.pcBox = core.cycleBoxNumber(state.pcBox, Boxes.COUNT, delta) end
      rebuild()
    end

    local function performTransfer(fix)
      local destView = state.view
      local destBoxNum = currentBoxNum()
      local destLabel = viewTitle()
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
      else -- pc -> pc
        transferred, remaining = transferPcBox(game, source.box, destBoxNum)
      end
      if transferred > 0 then
        local msg = Strings("Transferred %d\nPOKéMON to\n%s.", transferred, destLabel)
        if remaining > 0 then msg = msg .. Strings("\n%d remained.", remaining) end
        message(game, msg)
        if onTransferred then onTransferred() end
      else
        message(game, destView == "pc" and "No POKéMON\ntransferred.\nPC may be full." or "No POKéMON\ntransferred.")
      end
      rebuild()
    end

    local function confirmTransfer()
      local srcLabel = source.view == "bank" and boxLabel(loadStorage(), source.box) or pcBoxLabel(game, source.box)
      local destLabel = viewTitle()
      local function askTransfer(fix)
        core.confirm(game, Strings("Transfer %s\nto %s?", srcLabel, destLabel), function(yes)
          if yes then performTransfer(fix) end
        end, { defaultNo = true, noSound = true })
      end
      if source.view == "bank" and state.view == "pc" then
        local needing = 0
        local sourceBox = loadStorage().boxes[source.box]
        for _, mon in ipairs(sourceBox and sourceBox.content or {}) do
          if needsLegalityFix(mon, game) then needing = needing + 1 end
        end
        if needing > 0 then
          core.confirm(game, Strings("%d POKéMON need\nto be fixed. OK?", needing), function(yes)
            askTransfer(yes)
          end, { defaultNo = true, noSound = true })
          return
        end
      end
      askTransfer(false)
    end

    local function chooseThisBox()
      if isSourceBox() then
        message(game, "What? You can't\ntransfer a box\nto itself!")
        return
      end
      confirmTransfer()
    end

    backHandler = function() game.stack:pop() end

    rebuild = function()
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local box = currentBox()
      local rows = {}
      for i, mon in ipairs(box) do
        rows[#rows + 1] = { label = monName(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, { messageBox = true, noSound = true, wrap = true })
      core.attachLevelIcons(list, box)
      list.footer = "A: CONFIRM\nSELECT: " .. (state.view == "bank" and "PC" or "BANK")
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("left") then
        cycleBox(-1)
        return
      elseif input:wasPressed("right") then
        cycleBox(1)
        return
      elseif input:wasPressed("a") then
        chooseThisBox()
        return
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      core.drawListTitle(list)
      core.drawListCounter(list)
    end

    screen.screenId = TRANSFER_BOX_SCREEN_ID
    screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
      title = function() return viewTitle() end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseThisBox()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
    })

    rebuild()
    game.stack:push(screen)
  end

  local function pcToParty(game, pcBoxNum, index)
    Boxes.ensure(game.save)
    if #game.save.party >= Party.MAX then return false end
    local box = game.save.boxes[pcBoxNum]
    local mon = box and box[index]
    if not mon then return false end
    ensureStats(game, mon)
    table.remove(box, index)
    table.insert(game.save.party, mon)
    return true
  end

  local function partyToPc(game, index, startPcBoxNum)
    Boxes.ensure(game.save)
    local mon = game.save.party[index]
    if not mon then return false end
    for off = 0, Boxes.COUNT - 1 do
      local i = ((startPcBoxNum - 1 + off) % Boxes.COUNT) + 1
      local box = game.save.boxes[i]
      if #box < Boxes.CAPACITY then
        table.remove(game.save.party, index)
        table.insert(box, mon)
        return true, i
      end
    end
    return false
  end

  openMoveList = function(game, opts)
    opts = opts or {}
    Boxes.ensure(game.save)
    local state = {
      view = opts.initialView or "bank",
      bankBox = (opts.initialView == "bank" and opts.initialBox) or loadStorage().currentBox,
      pcBox = (opts.initialView == "pc" and opts.initialBox) or math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
      pendingSwap = nil,
    }

    local screen = { isOpaque = true }
    local list

    local rebuild, performMove, releaseCurrent, completeSwitch, openMonActions, backHandler, chooseCurrent

    local function currentList()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox].content
      elseif state.view == "party" then return game.save.party
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return boxLabel(loadStorage(), state.bankBox)
      elseif state.view == "party" then return "PARTY"
      else return pcBoxLabel(game, state.pcBox) end
    end

    local function nextViewName()
      if state.view == "bank" then return "PARTY"
      elseif state.view == "party" then return "PC"
      else return "BANK" end
    end

    local function cycleView()
      if state.pendingSwap then return end
      if state.view == "bank" then state.view = "party"
      elseif state.view == "party" then state.view = "pc"
      else state.view = "bank" end
      rebuild()
    end

    local function cycleBox(delta)
      if state.view == "bank" then
        state.bankBox = core.cycleBoxNumber(state.bankBox, #loadStorage().boxes, delta)
        rebuild()
      elseif state.view == "pc" then
        state.pcBox = core.cycleBoxNumber(state.pcBox, Boxes.COUNT, delta)
        rebuild()
      end
    end

    local function currentBoxNumForView()
      if state.view == "bank" then return state.bankBox
      elseif state.view == "pc" then return state.pcBox end
      return nil
    end

    local function openBoxOptionsMenu()
      if state.view == "party" then return end
      local boxNum = currentBoxNumForView()
      game.stack:push(openManageBoxList(game, {
        initialView = state.view,
        initialBox = boxNum,
        onClose = function(navigateTo)
          if navigateTo then
            state.view = navigateTo.view
            if navigateTo.view == "bank" then state.bankBox = navigateTo.box
            else state.pcBox = navigateTo.box end
            rebuild()
          else
            rebuild(true)
          end
        end,
      }))
    end

    performMove = function(destView, idx, fix)
      local srcView = state.view
      if destView == "party" and #game.save.party >= Party.MAX then
        return false, "The party is full!"
      end
      if destView == "bank" then
        if srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local deposited = mod.exports.depositPartyPokemon(game, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\n%s.", boxLabel(loadStorage(), deposited[1].box))
        elseif srcView == "pc" then
          local deposited = mod.exports.depositBoxPokemon(game, state.pcBox, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\n%s.", boxLabel(loadStorage(), deposited[1].box))
        end
      elseif destView == "party" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToParty(game, { boxNum = state.bankBox, indices = { idx }, fix = fix })
          if not result or #result.withdrawn == 0 then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        elseif srcView == "pc" then
          if not pcToParty(game, state.pcBox, idx) then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        end
      elseif destView == "pc" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToBox(game, state.pcBox, { boxNum = state.bankBox, indices = { idx }, fix = fix })
          if not result or #result.withdrawn == 0 then return false, "PC BOX is full!" end
          return true, Strings("Stored in\n%s.", pcBoxLabel(game, result.withdrawn[1].pcBox))
        elseif srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local ok, placedBox = partyToPc(game, idx, state.pcBox)
          if not ok then return false, "PC BOX is full!" end
          return true, Strings("Stored in\n%s.", pcBoxLabel(game, placedBox))
        end
      end
      return false, "It didn't work!"
    end

    completeSwitch = function(targetIdx)
      local pending = state.pendingSwap
      state.pendingSwap = nil
      if pending and pending.view == state.view then
        if state.view == "party" then
          if pending.index ~= targetIdx then
            local party = game.save.party
            party[pending.index], party[targetIdx] = party[targetIdx], party[pending.index]
          end
        elseif state.view == "bank" then
          if not (pending.box == state.bankBox and pending.index == targetIdx) then
            mod.exports.movePokemon(pending.box, pending.index, state.bankBox, targetIdx)
          end
        else -- pc
          if not (pending.box == state.pcBox and pending.index == targetIdx) then
            local from = game.save.boxes[pending.box]
            local to = game.save.boxes[state.pcBox]
            if pending.box == state.pcBox then
              from[pending.index], from[targetIdx] = from[targetIdx], from[pending.index]
            else
              from[pending.index], to[targetIdx] = to[targetIdx], from[pending.index]
            end
          end
        end
      end
      rebuild(true)
    end

    releaseCurrent = function(idx, mon)
      if state.view == "party" and #game.save.party <= 1 then
        message(game, "You can't release\nyour last POKéMON!")
        return
      end
      local name = monName(game, mon)
      core.confirmRelease(game, name, function(yes)
        if not yes then return end
        local src = currentList()
        local current = src[idx]
        if current ~= mon then
          message(game, "The selection changed.\nTry again.")
          return
        end
        table.remove(src, idx)
        if state.view == "bank" then
          local st = loadStorage()
          normalizeBoxes(st)
          markDirty()
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_released",
            { box = state.bankBox, index = idx, mon = mon })
        end
        core.playCry(game, mon.species)
        message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
        rebuild(true)
      end)
    end

    openMonActions = function(mon, idx)
      local view = state.view
      local rows = {}
      local function addTo(label, destView)
        rows[#rows + 1] = { label = label, onSelect = function()
          local function commit(fix)
            local _, msg = performMove(destView, idx, fix)
            rebuild(true)
            list.footer = msg
          end
          if view == "bank" and (destView == "party" or destView == "pc") and needsLegalityFix(mon, game) then
            core.confirm(game, "This POKéMON\nneeds to be fixed.\nOK?", function(yes) commit(yes) end, { defaultNo = true, noSound = true })
          else commit(false) end
        end }
      end
      if view ~= "bank" then addTo("TO BANK", "bank") end
      if view ~= "party" then addTo("TO PARTY", "party") end
      if view ~= "pc" then addTo("TO PC", "pc") end
      rows[#rows + 1] = { label = "SWITCH", onSelect = function()
        state.pendingSwap = {
          view = view,
          box = (view == "bank" and state.bankBox) or (view == "pc" and state.pcBox) or nil,
          index = idx,
        }
        rebuild(true)
      end }
      rows[#rows + 1] = { label = "STATS", keepOpen = true, onSelect = function()
        ensureStats(game, mon)
        core.openSummary(game, mon)
      end }
      rows[#rows + 1] = { label = "RELEASE", onSelect = function() releaseCurrent(idx, mon) end }
      rows[#rows + 1] = { label = "CANCEL" }
      core.rowActionsMenu(game, rows)
    end

    rebuild = function(preserveCursor)
      local oldIndex = preserveCursor and list and list.index
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local src = currentList()
      local rows = {}
      for i, mon in ipairs(src) do rows[#rows + 1] = { label = monName(game, mon), value = i } end
      list = ListMenu.new(game, viewTitle(), rows, {
        noSound = true,
        messageBox = true,
        wrap = true,
        onChoose = function(item)
          if state.pendingSwap then
            completeSwitch(item.value)
            return
          end
          local mon = src[item.value]
          if not mon then return end
          openMonActions(mon, item.value)
        end,
      })
      if oldIndex then core.setListCursor(list, oldIndex) end
      core.attachLevelIcons(list, src)
      local pending = state.pendingSwap
      if pending and pending.view == state.view then
        local sameBox = state.view == "party" or (state.view == "bank" and pending.box == state.bankBox) or (state.view == "pc" and pending.box == state.pcBox)
        if sameBox then list.swapIndex = pending.index end
        list.footer = "Choose a POKéMON\nto switch with."
      else
        core.attachDynamicFooter(list, function(l)
          local mon = src[l.index]
          local str = state.view == "party" and "%s\nSELECT: %s" or "%s\nSEL: %s ST: BOX"
          return Strings(str, mon and Pokemon.speciesName(game, mon) or "", nextViewName())
        end)
      end
    end

    backHandler = core.pendingSwapBackHandler(state, rebuild, function() game.stack:pop() end)

    chooseCurrent = function() core.chooseListCurrent(list, function() game.stack:pop() end) end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("start") then
        if not state.pendingSwap then openBoxOptionsMenu() end
        return
      elseif input:wasPressed("left") then
        cycleBox(-1)
        return
      elseif input:wasPressed("right") then
        cycleBox(1)
        return
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      core.drawListTitle(list)
      if state.view ~= "party" then
        local current = state.view == "bank" and loadStorage().currentBox or (game.save.currentBox or 1)
        if current == currentBoxNumForView() then drawCurrentBoxTitleMark(list) end
      end
      core.drawListCounter(list)
    end

    screen.screenId = MOVE_SCREEN_ID
    screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
      title = function() return viewTitle() end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseCurrent()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
    })

    rebuild()
    return screen
  end

  local TimeCapsuleScreenId = V.require("TimeCapsule").screenId

  local function BankPokemonMenu(game)
    local rows = {}
    local function addRow(label, build) rows[#rows + 1] = { label = label, build = build } end
    local mode = mod.options:get("storage_mode")
    if mode ~= "time_capsule" then addRow("MANAGE <PK><MN>", openMoveList) end
    if mode == "both" then addRow("MANAGE BOX", openManageBoxList) end
    if mode ~= "bank" then addRow("TIME CAPSULE", function(g) return require("src.ui.Screens").build(g, TimeCapsuleScreenId) end) end
    return core.rowChooserScreen(game, rows, { tw = 14 })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankPokemonMenu })

  local pokemonTab = core.makeTabToggle("show_pokemon_tab")
  Pokemon.tabEnabled = pokemonTab.enabled

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.boxCount = boxCount
  mod.exports.boxCapacity = boxCapacity
  mod.exports.depositPokemon = function(mon, opts)
    if type(mon) ~= "table" then return nil, "invalid pokemon" end
    opts = opts or {}
    if opts.game then
      ensureStats(opts.game, mon)
      autoHealMon("deposit", opts.game, mon)
    end
    local boxNum, slot = Pokemon.depositMon(mon)
    mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", { box = boxNum, index = slot, mon = mon })
    return boxNum, slot
  end
  mod.exports.withdrawPokemon = function(boxNum, index, game, fix)
    local ok, reason = withdrawEligible(peekMon(boxNum, index), game, fix)
    if not ok then return nil, reason end
    local mon = Pokemon.withdrawMon(boxNum, index)
    if mon then
      if game then
        reshapeForActiveGame(game, mon)
        stampNewTrainer(game, mon)
        autoHealMon("withdraw", game, mon)
      end
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = boxNum, index = index, mon = mon })
    end
    return mon
  end
  mod.exports.getPokemon = peekMon
  mod.exports.getBox = function(boxNum)
    local s = loadStorage()
    local box = s.boxes[boxNum]
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
    if mon then mod.events:emit("mod.vrm_pokemon_bank.pokemon_released", { box = boxNum, index = index, mon = mon }) end
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
    while boxNum <= #s.boxes and #s.boxes[boxNum].content == 0 do boxNum = boxNum + 1 end
    return boxNum <= #s.boxes and boxNum or nil
  end

  local function bulkTransfer(source, indices, place)
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
    for _, idx in ipairs(removedIdx) do table.remove(source, idx) end
    return results, #entries - #results
  end

  local function depositPlacer(game, s, startBoxNum)
    local currentBoxNum = startBoxNum
    return function(mon)
      if game then ensureStats(game, mon) end
      autoHealMon("deposit", game, mon)
      stampOrigin(mon)
      local cap = boxCapacity()
      for off = 0, #s.boxes - 1 do
        local boxNum = ((currentBoxNum - 1 + off) % #s.boxes) + 1
        local content = s.boxes[boxNum].content
        if #content < cap then
          table.insert(content, mon)
          currentBoxNum = boxNum
          return { box = boxNum, index = #content, mon = mon }
        end
      end
      s.boxes[#s.boxes + 1] = core.newBox(s)
      table.insert(s.boxes[#s.boxes].content, mon)
      currentBoxNum = #s.boxes
      return { box = #s.boxes, index = 1, mon = mon }
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
    local deposited = bulkTransfer(party, indices, depositPlacer(game, s, targetBoxNum or #s.boxes))
    normalizeBoxes(s)
    markDirty()
    for _, entry in ipairs(deposited) do mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry) end
    return deposited
  end
  mod.exports.depositBoxPokemon = function(game, pcBoxNum, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save or not game.save.boxes then return nil, "invalid game" end
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)
    local pcBox = game.save.boxes[pcBoxNum]
    if not pcBox then return nil, "invalid pc box" end
    if #pcBox == 0 then return nil, "pc box is empty" end
    indices = indices or allIndices(#pcBox)
    if not validIndices(indices, #pcBox) then return nil, "invalid index" end
    local s = loadStorage()
    local deposited = bulkTransfer(pcBox, indices, depositPlacer(game, s, targetBoxNum or #s.boxes))
    normalizeBoxes(s)
    markDirty()
    for _, entry in ipairs(deposited) do mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry) end
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
    local sourceBoxStruct = s.boxes[sourceBoxNum]
    local sourceBox = sourceBoxStruct and sourceBoxStruct.content
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end
    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end
    if Party.MAX - #party <= 0 then return nil, "party is full" end
    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      if #party >= Party.MAX then return nil end
      if not withdrawEligible(mon, game, opts.fix) then return nil end
      reshapeForActiveGame(game, mon)
      stampNewTrainer(game, mon)
      autoHealMon("withdraw", game, mon)
      table.insert(party, mon)
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
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
    if not game or not game.save or not game.save.boxes then
      return nil, "invalid game"
    end
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)
    if not game.save.boxes[targetPcBoxNum] then return nil, "invalid target pc box" end
    local s = loadStorage()
    sourceBoxNum = sourceBoxNum or firstNonEmptyBox(s)
    if not sourceBoxNum then return nil, "bank is empty" end
    local sourceBoxStruct = s.boxes[sourceBoxNum]
    local sourceBox = sourceBoxStruct and sourceBoxStruct.content
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end
    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end
    local currentPcBoxNum = targetPcBoxNum
    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      if not withdrawEligible(mon, game, opts.fix) then return nil end
      for off = 0, Boxes.COUNT - 1 do
        local boxNum = ((currentPcBoxNum - 1 + off) % Boxes.COUNT) + 1
        local box = game.save.boxes[boxNum]
        if box and #box < Boxes.CAPACITY then
          reshapeForActiveGame(game, mon)
          stampNewTrainer(game, mon)
          autoHealMon("withdraw", game, mon)
          table.insert(box, mon)
          registerDex(game, mon.species)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
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
