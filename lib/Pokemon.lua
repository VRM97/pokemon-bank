local V = ...

local GameVersion = require("src.core.GameVersion")
local Stats = require("src.pokemon.Stats")
local Party = require("src.pokemon.Party")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")

local BOX_CAPACITY = 20
local SCREEN_ID = "PokemonBankBox"
local TRANSFER_BOX_SCREEN_ID = "PokemonBankTransferBox"
local MOVE_SCREEN_ID = "PokemonBankMovePkmn"

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local normalizeBoxes = core.normalizeBoxes

  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  local function playCry(game, species)
    pcall(function() require("src.core.Sound").playCry(game.data, species) end)
  end

  local function nameOf(game, mon)
    local def = game.data.pokemon[mon.species]
    return mon.nickname or mon.name or (def and def.name) or tostring(mon.species)
  end

  local function ensureStats(game, mon)
    local def = game.data.pokemon[mon.species]
    if def then Stats.ensure(def, mon) end
    return mon
  end

  -- CRYSTAL_251 gives a mon its own held item on mon.heldItem instead of Gold's mon.item. Mirrored both ways the same way exp/experience are, but only when that mod is actually installed and loaded.
  local function mirrorHeldItem(mon)
    local crystal251 = mod.find and mod.find("CRYSTAL_251")
    if not crystal251 then return end
    if mon.heldItem == nil then mon.heldItem = mon.item end
    if mon.item == nil then mon.item = mon.heldItem end
  end

  -- An Egg's remaining incubation is Gold's mon.eggSteps or CRYSTAL_251's mon.eggCycles. Cycles only ever fall, on either side, so whichever of the two is smaller is always the one that's actually current.
  -- CRYSTAL_251 also keeps the moves an Egg already inherited off mon.moves and stashes them on mon.eggMoves instead; Gold puts them straight on mon.moves from the moment the Egg is made and has no eggMoves field at all. Reshaped to whichever shape the destination expects, so a hatch on either side always finds the real moveset on mon.moves.
  local function mirrorEggFields(mon)
    if type(mon) ~= "table" or mon.isEgg ~= true then return end
    local crystal251 = mod.find and mod.find("CRYSTAL_251")
    if mon.eggSteps ~= nil or mon.eggCycles ~= nil then
      local cycles = math.min(mon.eggSteps or mon.eggCycles, mon.eggCycles or mon.eggSteps)
      mon.eggSteps, mon.eggCycles = cycles, cycles
    end
    if crystal251 and GameVersion.generation() == 1 then
      if type(mon.moves) == "table" and #mon.moves > 0 then
        mon.eggMoves = mon.eggMoves or mon.moves
        mon.moves = {}
      end
    elseif type(mon.eggMoves) == "table" and #mon.eggMoves > 0
        and (type(mon.moves) ~= "table" or #mon.moves == 0) then
      mon.moves = mon.eggMoves
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

  -- An Egg's OT is stamped once, at creation, and Gold's own hatch preserves whatever is already there rather than re-stamping.
  -- CRYSTAL_251's own hatch already re-stamps ot/otId at hatch time regardless of what the egg already carries, so this only changes behavior for Gold's own Day Care.
  local function stampEggTrainer(game, mon)
    if mon and mon.isEgg then stampTrainer(game, mon) end
  end

  -- When INHERIT TRAINER is enabled: the withdrawing trainer becomes any Pokémon's OT, not just an Egg's. Deliberately NOT part of reshapeForActiveGame.
  local function stampNewTrainer(game, mon)
    if mod.options:get("inherit_trainer_on_withdraw") then stampTrainer(game, mon) end
  end

  -- Reshaped here, once, right before a withdrawn mon actually enters the currently active game -- recomputed with the target generation's own formula over the target generation's own base stats.
  local function reshapeForActiveGame(game, mon)
    if type(mon) ~= "table" then return mon end
    if mon.exp == nil then mon.exp = mon.experience end
    if mon.experience == nil then mon.experience = mon.exp end
    mirrorHeldItem(mon)
    mirrorEggFields(mon)
    stampEggTrainer(game, mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local baseStats = def and def.baseStats
    if not (baseStats and type(mon.stats) == "table") then return mon end
    if GameVersion.generation() == 2 then
      if baseStats.specialAttack and (mon.stats.specialAttack == nil or mon.stats.specialDefense == nil) then
        local Mon = require("src.battle.gen2.Mon")
        local computed = Mon.stats(baseStats, mon.dvs or {}, mon.level or 1, mon.statExp)
        mon.stats.specialAttack = mon.stats.specialAttack or computed.specialAttack
        mon.stats.specialDefense = mon.stats.specialDefense or computed.specialDefense
      end
      if mon.maxHp == nil then mon.maxHp = mon.stats.hp end
      if mon.types == nil then mon.types = def.types end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
    else
      if mon.stats.special == nil and baseStats.special then
        mon.stats.special = Stats.calc(def, mon.level or 1, mon.dvs or {}, mon.statExp).special
      end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
    end
    return mon
  end

  -- Gold's builtins carry a "Gen2" prefix -- Screens.push does not translate a Gen 1 id on its own, so the STATS submenu below has to pick the right one itself.
  -- reshapeForActiveGame run here too so a look at STATS is never stale, whether or not the mon ends up actually leaving the Bank.
  local function openSummary(game, mon)
    reshapeForActiveGame(game, mon)
    local Screens = require("src.ui.Screens")
    if GameVersion.generation() == 2 then
      Screens.push(game, "Gen2SummaryMenu", {
        mon = mon,
        onClose = function() game.stack:pop() end,
      })
    else
      Screens.push(game, "SummaryMenu", mon)
    end
  end

  -- Mirrors Evolution's own seen/owned write. Never called on release or on a move that stays inside the Bank -- see API.md's withdrawPokemon entry.
  -- The "owned" field itself is named differently per generation -- owned on Red/Blue/Yellow, caught on Gold -- so this writes whichever one the active save actually has.
  local function registerDex(game, species)
    local dex = game and game.save and game.save.pokedex
    if not dex then return end
    if type(dex.seen) == "table" then dex.seen[species] = true end
    local owned = dex.owned or dex.caught
    if type(owned) == "table" then owned[species] = true end
  end

  -- ---------------------------------------------------------------------
  -- Pokémon storage
  -- ---------------------------------------------------------------------
  -- Never refuses: normalizeBoxes guarantees the last box is always empty, so the search below always finds room there even when every earlier box is full.
  local function depositMon(mon)
    if type(mon) ~= "table" then return nil end
    local s = loadStorage()
    local n = #s.boxes
    local start = math.min(s.currentBox, n)
    for off = 0, n - 1 do
      local i = ((start - 1 + off) % n) + 1
      if #s.boxes[i] < BOX_CAPACITY then
        table.insert(s.boxes[i], mon)
        normalizeBoxes(s)
        markDirty()
        return i, #s.boxes[i]
      end
    end
    return nil
  end

  local function moveId(mv)
    return type(mv) == "table" and mv.id or mv
  end

  local function isValidPokemon(mon, data)
    if type(mon) ~= "table" or type(data) ~= "table" then return false end
    local pokemon = data.pokemon
    if type(pokemon) ~= "table" or not pokemon[mon.species] then return false end
    if mon.isEgg and GameVersion.generation() == 1 and not (mod.find and mod.find("CRYSTAL_251")) then
      return false
    end
    local moves = data.moves
    if type(moves) ~= "table" then return false end
    if type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        local id = moveId(mv)
        if id and not moves[id] then return false end
      end
    end
    return true
  end

  local function ensureOrphaned(s)
    if not s.orphaned then
      s.orphaned = { mons = {}, items = {} }
    end
    s.orphaned.mons = s.orphaned.mons or {}
    s.orphaned.items = s.orphaned.items or {}
    return s.orphaned
  end

  -- A held item can go stale the same way a bank item can -- an id from an uninstalled mod, or one this game's item table simply doesn't carry.
  -- Checked on every mon that stays valid, and quarantined into the same table bank-item validation uses, rather than a separate list.
  -- Cleared off BOTH fields at once and quarantined once, not once per field, treating them as two held items would double-count the one Pokémon is actually holding.
  local function checkHeldItem(game, mon, orphaned, lostItems)
    mirrorHeldItem(mon)
    local item = mon.item or mon.heldItem
    if not item then return false end
    local valid = mod.exports.isValidItem and mod.exports.isValidItem(item, game)
    local blacklisted = mod.exports.isBlacklisted and mod.exports.isBlacklisted(item, game)
    if valid and not blacklisted then return false end
    mon.item = nil
    mon.heldItem = nil
    orphaned.items[item] = (orphaned.items[item] or 0) + 1
    lostItems[#lostItems + 1] = { id = item, count = 1 }
    return true
  end

  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {}, lostItems = {} }
    end
    local s = loadStorage()
    local orphaned = ensureOrphaned(s)
    local quarantined, restored = 0, 0
    local lostMons, restoredMons, lostItems = {}, {}, {}
    for boxNum = 1, #s.boxes do
      local box = s.boxes[boxNum]
      for idx = #box, 1, -1 do
        local mon = box[idx]
        if not isValidPokemon(mon, data) then
          table.remove(box, idx)
          orphaned.mons[#orphaned.mons + 1] = mon
          quarantined = quarantined + 1
          lostMons[#lostMons + 1] = { species = mon.species, from = "BOX " .. boxNum }
        elseif checkHeldItem(game, mon, orphaned, lostItems) then
          markDirty()
        end
      end
    end
    normalizeBoxes(s)
    local targetBoxNum = #s.boxes
    local targetBox = s.boxes[targetBoxNum]
    for idx = #orphaned.mons, 1, -1 do
      local mon = orphaned.mons[idx]
      if isValidPokemon(mon, data) then
        table.remove(orphaned.mons, idx)
        checkHeldItem(game, mon, orphaned, lostItems)
        -- Find space in current target box or create new if needed
        if #targetBox >= BOX_CAPACITY then
          s.boxes[#s.boxes + 1] = {}
          targetBoxNum = #s.boxes
          targetBox = s.boxes[targetBoxNum]
        end
        table.insert(targetBox, mon)
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = mon.species, box = targetBoxNum }
      end
    end
    normalizeBoxes(s)
    return {
      changed = quarantined > 0 or restored > 0 or #lostItems > 0,
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

  local function withdrawMon(boxNum, idx)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    local mon = box and box[idx]
    if not mon then return nil end
    table.remove(box, idx)
    normalizeBoxes(s)
    markDirty()
    return mon
  end

  local function peekMon(boxNum, idx)
    local box = loadStorage().boxes[boxNum]
    return box and box[idx] or nil
  end

  local function moveMon(srcBox, srcIdx, destBox, destIdx)
    local s = loadStorage()
    local from = s.boxes[srcBox]
    local mon = from and from[srcIdx]
    if not mon then return false end
    if srcBox == destBox and destIdx == srcIdx then return false end
    local to = s.boxes[destBox]
    if not to then return false end
    local destMon = to[destIdx]
    if destMon then
      from[srcIdx], to[destIdx] = destMon, mon
      normalizeBoxes(s)
      markDirty()
      return true
    end
    if #to >= BOX_CAPACITY then return false, "full" end
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
      for idx, mon in ipairs(box) do
        out[#out + 1] = { box = boxNum, index = idx, mon = mon }
      end
    end
    return out
  end

  local function countMons()
    local n = 0
    for _, box in ipairs(loadStorage().boxes) do n = n + #box end
    return n
  end

  local function boxCount()
    return #loadStorage().boxes
  end

  -- =========================================================================
  -- Pokémon UI
  -- =========================================================================
  local function monLabel(game, mon)
    return Strings("%s :L%d", nameOf(game, mon), mon.level)
  end

  -- action + STATS + CANCEL, the vanilla PC's own per-mon submenu
  local function monSubmenu(game, action, mon, onAction)
    game.stack:push(Menu.new(game, {
      { label = action, onSelect = onAction },
      { label = "STATS", keepOpen = true, onSelect = function()
          ensureStats(game, mon)
          openSummary(game, mon)
        end },
      { label = "CANCEL" },
    }, { tx = 9, ty = 10, tw = 11, th = 8, noSound = true }))
  end

  local function openWithdrawList(game)
    local s = loadStorage()
    local boxNum = s.currentBox
    local box = s.boxes[boxNum]
    if #box == 0 then
      message(game, "What? There are\nno POKéMON here!")
      return
    end
    if #game.save.party >= Party.MAX then
      message(game, "You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst.")
      return
    end
    local items = {}
    for i, mon in ipairs(box) do
      items[#items + 1] = { label = monLabel(game, mon), value = i }
    end
    local list
    list = ListMenu.new(game, Strings("BOX %d (WITHDRAW)", boxNum), items, {
      noSound = true,
      onChoose = function(item)
        local mon = box[item.value]
        if not mon then return end
        monSubmenu(game, "WITHDRAW", mon, function()
          if #game.save.party >= Party.MAX then
            list.footer = "The party is full!"
            return
          end
          table.remove(box, item.value)
          normalizeBoxes(s)
          markDirty()
          reshapeForActiveGame(game, mon)
          stampNewTrainer(game, mon)
          table.insert(game.save.party, mon)
          registerDex(game, mon.species)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn",
            { box = boxNum, index = item.value, mon = mon })
          local name = nameOf(game, mon)
          list:close()
          message(game, ("%s is\ntaken out.\vGot %s."):format(name, name))
        end)
      end,
    })
    game.stack:push(list)
  end

  local function openDepositList(game)
    if #game.save.party <= 1 then
      message(game, "You can't deposit\nthe last Pokemon!")
      return
    end
    local items = {}
    for i, mon in ipairs(game.save.party) do
      items[#items + 1] = { label = monLabel(game, mon), value = i }
    end
    local list = ListMenu.new(game, "PARTY (DEPOSIT)", items, {
      noSound = true,
      onChoose = function(item, list)
        local mon = game.save.party[item.value]
        if not mon then return end
        monSubmenu(game, "DEPOSIT", mon, function()
          if #game.save.party <= 1 then
            list.footer = "You need at least\none POKéMON!"
            return
          end
          table.remove(game.save.party, item.value)
          ensureStats(game, mon)
          local boxNum, slot = depositMon(mon)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited",
            { box = boxNum, index = slot, mon = mon })
          local name = nameOf(game, mon)
          list:close()
          message(game, ("%s was\nstored in BANK BOX %d."):format(name, boxNum))
        end)
      end,
    })
    game.stack:push(list)
  end

  local function openReleaseList(game)
    local s = loadStorage()
    local boxNum = s.currentBox
    local box = s.boxes[boxNum]
    if #box == 0 then
      message(game, "What? There are\nno POKéMON here!")
      return
    end
    local items = {}
    for i, mon in ipairs(box) do
      items[#items + 1] = { label = monLabel(game, mon), value = i }
    end
    local list = ListMenu.new(game, ("BOX %d (RELEASE)"):format(boxNum), items, {
      noSound = true,
      onChoose = function(_, list)
        local mon = box[list.index]
        if not mon then return end
        local name = nameOf(game, mon)
        game.stack:push(TextBox.new(game,
          Strings("Once released,\n%s is\ngone forever. OK?", name), function()
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then return end
            local current = box[list.index]
            if current ~= mon then
              message(game, "The selection changed.\nTry again.")
              return
            end
            table.remove(box, list.index)
            normalizeBoxes(s)
            markDirty()
            playCry(game, mon.species)
            mod.events:emit("mod.vrm_pokemon_bank.pokemon_released",
              { box = boxNum, index = list.index, mon = mon })
            message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
            list:removeCurrent()
          end, { defaultNo = true, noSound = true }))
        end))
      end,
    })
    game.stack:push(list)
  end

  local function openChangeBoxList(game)
    local s = loadStorage()
    local items = {}
    for i = 1, #s.boxes do
      local mark = i == s.currentBox and "*" or " "
      items[#items + 1] = {
        label = ("%sBOX %d"):format(mark, i),
        right = ("%d/%d"):format(#s.boxes[i], BOX_CAPACITY),
        value = i,
      }
    end
    game.stack:push(ListMenu.new(game, "CHANGE BOX", items, {
      noSound = true,
      onChoose = function(item, list)
        local st = loadStorage()
        st.currentBox = math.max(1, math.min(#st.boxes, item.value))
        markDirty()
        list:close()
      end,
    }))
  end

  -- TRANSFER BOX: a two-step box picker.
  -- It commits the WHOLE box currently on screen as either the source or the destination, since this moves every Pokémon in a box in one go.
  -- Stage 1 ("source"): SELECT still alternates BANK/PC, and A on a non-empty box locks it in as the source and flips to the other storage.
  -- Stage 2 ("destination"): SELECT is locked out (the whole point is the other storage), A asks to confirm before calling the bulk exports.
  local function openTransferBoxList(game)
    Boxes.ensure(game.save)
    local state = {
      stage = "source",
      view = "bank",
      bankBox = loadStorage().currentBox,
      pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
      source = nil,
    }

    local screen = { isOpaque = true }
    local list
    local rebuild, backHandler

    local function clampState()
      local st = loadStorage()
      state.bankBox = math.max(1, math.min(#st.boxes, state.bankBox))
      state.pcBox = math.max(1, math.min(Boxes.COUNT, state.pcBox))
    end

    local function currentBoxNum()
      return state.view == "bank" and state.bankBox or state.pcBox
    end

    local function currentBox()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox]
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return Strings("BANK BOX %d", state.bankBox)
      else return Strings("PC BOX %d", state.pcBox) end
    end

    local function cycleView()
      if state.stage == "destination" then return end -- locked to the other storage
      state.view = (state.view == "bank") and "pc" or "bank"
      rebuild()
    end

    local function cycleBox(delta)
      if state.view == "bank" then
        local n = #loadStorage().boxes
        if n <= 1 then return end
        state.bankBox = ((state.bankBox - 1 + delta) % n) + 1
      else
        state.pcBox = ((state.pcBox - 1 + delta) % Boxes.COUNT) + 1
      end
      rebuild()
    end

    local function performTransfer()
      local src = state.source
      local destBoxNum = currentBoxNum()
      state.stage = "source"
      state.source = nil
      if src.view == "bank" then
        local result = mod.exports.withdrawToBox(game, destBoxNum, { boxNum = src.box, indices = nil })
        local transferred = result and #result.withdrawn or 0
        if transferred > 0 then
          local msg = Strings("Transferred %d\nPOKéMON to\nPC BOX %d.", transferred, destBoxNum)
          if result.remaining > 0 then msg = msg .. Strings("\n%d remained.", result.remaining) end
          message(game, msg)
        else
          message(game, "No POKéMON\ntransferred.\nPC may be full.")
        end
      else
        local result = mod.exports.depositBoxPokemon(game, src.box, { boxNum = destBoxNum, indices = nil })
        local transferred = result and #result or 0
        if transferred > 0 then
          message(game, Strings("Transferred %d\nPOKéMON to\nthe BANK.", transferred))
        else
          message(game, "No POKéMON\ntransferred.")
        end
      end
      rebuild()
    end

    local function confirmTransfer()
      local src = state.source
      local srcLabel = src.view == "bank" and Strings("BANK BOX %d", src.box) or Strings("PC BOX %d", src.box)
      local destLabel = viewTitle()
      game.stack:push(TextBox.new(game,
        Strings("Transfer %s\nto %s?", srcLabel, destLabel), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if yes then performTransfer() end
        end, { defaultNo = true, noSound = true }))
      end))
    end

    local function chooseThisBox()
      if state.stage == "source" then
        if #currentBox() == 0 then
          message(game, "What? There are\nno POKéMON here!")
          return
        end
        state.source = { view = state.view, box = currentBoxNum() }
        state.stage = "destination"
        state.view = (state.view == "bank") and "pc" or "bank"
        rebuild()
      else
        confirmTransfer()
      end
    end

    -- Shared by screen:update's own "b" handling and the Gen1 Modern UI adapter's "back" action below, so a touch/mouse BACK does exactly what the B button does.
    backHandler = function()
      if state.stage == "destination" then
        state.view = state.source.view
        state.stage = "source"
        state.source = nil
        rebuild()
      else
        game.stack:pop()
      end
    end

    rebuild = function()
      clampState()
      local box = currentBox()
      local rows = {}
      for i, mon in ipairs(box) do
        rows[#rows + 1] = { label = monLabel(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, { noSound = true, rows = 6 })
      list.footer = state.stage == "source"
        and ("A: PICK BOX\nSELECT: " .. (state.view == "bank" and "PC" or "BANK"))
        or "A: CONFIRM"
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
      local total = #list.items
      local text = Strings("%d/%d", total > 0 and list.index or 0, total)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, 160 - 8 - Font.width(text), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Gen1 Modern UI compatibility surface: read-only accessors plus semantic actions so the presenter can paint this screen, and a touch/mouse user can drive it
    screen.screenId = TRANSFER_BOX_SCREEN_ID
    screen.gen1ModernUi = {
      title = function() return viewTitle() end,
      rows = function() return core.publicRows(list) end,
      index = function() return list.index end,
      scroll = function() return list.scroll end,
      footer = function() return list.footer end,
      up = function() core.moveListCursor(list, -1) end,
      down = function() core.moveListCursor(list, 1) end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseThisBox()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
      hover = function(payload) core.setListCursor(list, payload) end,
    }

    rebuild()
    game.stack:push(screen)
  end

  -- Direct PARTY <-> PC moves bypass the Bank entirely (nothing here ever touches loadStorage()/markDirty) -- only reachable from the MOVE screen below, so these stay local instead of joining the exports table.
  local function pcToParty(game, pcBoxNum, index)
    Boxes.ensure(game.save)
    if #game.save.party >= Party.MAX then return false end
    local box = game.save.boxes[pcBoxNum]
    local mon = box and box[index]
    if not mon then return false end
    -- mirrors BoxMenu.withdraw's own Stats.ensure: a box mon carries no stat block on some imported .sav files
    Stats.ensure(game.data.pokemon[mon.species], mon)
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

  -- MOVE <PK><MN>: SELECT cycles BANK > PARTY > PC, on BANK/PC, Left/Right cycles boxes. A on a Pokémon opens TO <other two storages>/SWITCH/STATS/RELEASE/CANCEL.
  -- SWITCH pins the source slot and stays armed while Left/Right keeps browsing boxes, so the target can be anywhere in the same storage.
  local function openMoveList(game)
    Boxes.ensure(game.save)
    local state = {
      view = "bank",
      bankBox = loadStorage().currentBox,
      pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
      pendingSwap = nil,
    }

    local screen = { isOpaque = true }
    local list -- current ListMenu; rebuilt on every view/box/data change

    local rebuild, performMove, releaseCurrent, completeSwitch, openMonActions, backHandler, chooseCurrent

    local function clampState()
      local st = loadStorage()
      state.bankBox = math.max(1, math.min(#st.boxes, state.bankBox))
      state.pcBox = math.max(1, math.min(Boxes.COUNT, state.pcBox))
    end

    local function currentList()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox]
      elseif state.view == "party" then return game.save.party
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return Strings("BANK BOX %d", state.bankBox)
      elseif state.view == "party" then return "PARTY"
      else return Strings("PC BOX %d", state.pcBox) end
    end

    -- BANK > PARTY > PC > BANK, matching cycleView below -- what SELECT switches TO from the current view, for the footer hint.
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
        local n = #loadStorage().boxes
        if n <= 1 then return end
        state.bankBox = ((state.bankBox - 1 + delta) % n) + 1
        rebuild()
      elseif state.view == "pc" then
        state.pcBox = ((state.pcBox - 1 + delta) % Boxes.COUNT) + 1
        rebuild()
      end
    end

    performMove = function(destView, idx)
      local srcView = state.view
      if destView == "party" and #game.save.party >= Party.MAX then
        return false, "The party is full!"
      end
      if destView == "bank" then
        if srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local deposited = mod.exports.depositPartyPokemon(game, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\nBANK BOX %d.", deposited[1].box)
        elseif srcView == "pc" then
          local deposited = mod.exports.depositBoxPokemon(game, state.pcBox, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\nBANK BOX %d.", deposited[1].box)
        end
      elseif destView == "party" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToParty(game, { boxNum = state.bankBox, indices = { idx } })
          if not result or #result.withdrawn == 0 then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        elseif srcView == "pc" then
          if not pcToParty(game, state.pcBox, idx) then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        end
      elseif destView == "pc" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToBox(game, state.pcBox, { boxNum = state.bankBox, indices = { idx } })
          if not result or #result.withdrawn == 0 then return false, "PC BOX is full!" end
          return true, Strings("Stored in\nPC BOX %d.", result.withdrawn[1].pcBox)
        elseif srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local ok, placedBox = partyToPc(game, idx, state.pcBox)
          if not ok then return false, "PC BOX is full!" end
          return true, Strings("Stored in\nPC BOX %d.", placedBox)
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
      rebuild()
    end

    releaseCurrent = function(idx, mon)
      if state.view == "party" and #game.save.party <= 1 then
        message(game, "You can't release\nyour last POKéMON!")
        return
      end
      local name = nameOf(game, mon)
      game.stack:push(TextBox.new(game,
        Strings("Once released,\n%s is\ngone forever. OK?", name), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
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
          playCry(game, mon.species)
          message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
          rebuild()
        end, { defaultNo = true, noSound = true }))
      end))
    end

    openMonActions = function(mon, idx)
      local view = state.view
      local rows = {}
      local function addTo(label, destView)
        rows[#rows + 1] = { label = label, onSelect = function()
          local _, msg = performMove(destView, idx)
          rebuild()
          list.footer = msg
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
        rebuild()
      end }
      rows[#rows + 1] = { label = "STATS", keepOpen = true, onSelect = function()
        ensureStats(game, mon)
        openSummary(game, mon)
      end }
      rows[#rows + 1] = { label = "RELEASE", onSelect = function() releaseCurrent(idx, mon) end }
      rows[#rows + 1] = { label = "CANCEL" }
      local th = #rows * 2 + 2
      game.stack:push(Menu.new(game, rows, { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th, noSound = true }))
    end

    rebuild = function()
      clampState()
      local src = currentList()
      local rows = {}
      for i, mon in ipairs(src) do
        rows[#rows + 1] = { label = monLabel(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, {
        noSound = true,
        rows = 6,
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
      list.footer = "\nSELECT: " .. nextViewName()
      local pending = state.pendingSwap
      if pending and pending.view == state.view then
        local sameBox = state.view == "party"
          or (state.view == "bank" and pending.box == state.bankBox)
          or (state.view == "pc" and pending.box == state.pcBox)
        if sameBox then list.swapIndex = pending.index end
        list.footer = "Choose a POKéMON\nto switch with."
      end
    end

    -- Shared by screen:update's own "b" handling and the Gen1 Modern UI adapter's "back" action below.
    backHandler = function()
      if state.pendingSwap then
        state.pendingSwap = nil
        rebuild()
      else
        game.stack:pop()
      end
    end

    -- Whatever pressing A on the highlighted row would do -- list.onChoose already branches on state.pendingSwap itself, so this is the one thing the Gen1 Modern UI "select" action needs to reuse.
    -- An empty list mirrors ListMenu:update's own empty-list branch, where A closes the screen exactly like B does.
    chooseCurrent = function()
      if #list.items == 0 then
        game.stack:pop()
        return
      end
      local item = list.items[list.index]
      if item and list.onChoose then list.onChoose(item, list) end
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
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      local total = #list.items
      local text = Strings("%d/%d", total > 0 and list.index or 0, total)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, 160 - 8 - Font.width(text), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Gen1 Modern UI compatibility surface -- see the TRANSFER BOX screen above (openTransferBoxList) for the full explanation.
    screen.screenId = MOVE_SCREEN_ID
    screen.gen1ModernUi = {
      title = function() return viewTitle() end,
      rows = function() return core.publicRows(list) end,
      index = function() return list.index end,
      scroll = function() return list.scroll end,
      footer = function() return list.footer end,
      up = function() core.moveListCursor(list, -1) end,
      down = function() core.moveListCursor(list, 1) end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseCurrent()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
      hover = function(payload) core.setListCursor(list, payload) end,
    }

    rebuild()
    game.stack:push(screen)
  end

  -- WITHDRAW / DEPOSIT / RELEASE / MOVE / TRANSFER BOX / CHANGE BOX / CANCEL, keepOpen so each sub-list leaves this menu underneath it.
  local function BankBoxMenu(game)
    local rows = {
      { label = "MOVE <PK><MN>", keepOpen = true, onSelect = function() openMoveList(game) end },
      { label = "WITHDRAW <PK><MN>", keepOpen = true, onSelect = function() openWithdrawList(game) end },
      { label = "DEPOSIT <PK><MN>", keepOpen = true, onSelect = function() openDepositList(game) end },
      { label = "RELEASE <PK><MN>", keepOpen = true, onSelect = function() openReleaseList(game) end },
      { label = "TRANSFER BOX", keepOpen = true, onSelect = function() openTransferBoxList(game) end },
      { label = "CHANGE BOX", keepOpen = true, onSelect = function() openChangeBoxList(game) end },
      { label = "CANCEL" },
    }
    local th = #rows * 2 + 2
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 14, th = th, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankBoxMenu })

  -- Tab visibility: POKéMON MENU option AND setPokemonTabEnabled override.
  local tabEnabledByOthers = true

  local function tabEnabled()
    return tabEnabledByOthers and mod.options:get("show_pokemon_tab") == true
  end

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.boxCount = function() return boxCount() end
  mod.exports.boxCapacity = function() return BOX_CAPACITY end

  mod.exports.depositPokemon = function(mon, opts)
    if type(mon) ~= "table" then return nil, "invalid pokemon" end
    opts = opts or {}
    if opts.game then ensureStats(opts.game, mon) end
    local boxNum, slot = depositMon(mon)
    mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", { box = boxNum, index = slot, mon = mon })
    return boxNum, slot
  end

  mod.exports.withdrawPokemon = function(boxNum, index, game)
    local mon = withdrawMon(boxNum, index)
    if mon then
      if game then
        reshapeForActiveGame(game, mon)
        stampNewTrainer(game, mon)
      end
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = boxNum, index = index, mon = mon })
    end
    return mon
  end

  mod.exports.getPokemon = function(boxNum, index) return peekMon(boxNum, index) end

  mod.exports.getBox = function(boxNum)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    if not box then return nil end
    local copy = {}
    for i = 1, BOX_CAPACITY do copy[i] = box[i] end
    return copy
  end

  mod.exports.movePokemon = function(srcBox, srcIdx, destBox, destIdx)
    return moveMon(srcBox, srcIdx, destBox, destIdx)
  end

  mod.exports.releasePokemon = function(boxNum, index)
    local mon = withdrawMon(boxNum, index)
    if mon then
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_released", { box = boxNum, index = index, mon = mon })
    end
    return mon ~= nil
  end

  mod.exports.listPokemon = function() return listMons() end
  mod.exports.pokemonCount = function() return countMons() end

  mod.exports.isValidPokemon = function(mon, game)
    return isValidPokemon(mon, game and game.data)
  end
  mod.exports.validatePokemonStorage = function(game) return validateStorage(game) end
  mod.exports.listInvalidPokemon = function() return listInvalidMons() end
  mod.exports.invalidPokemonCount = function() return invalidMonCount() end

  -- Bulk deposit from party
  mod.exports.depositPartyPokemon = function(game, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum -- nil = last box
    local indices = opts.indices -- nil = 2..last (keep first)
    
    if not game or not game.save or not game.save.party then
      return nil, "invalid game"
    end
    
    local party = game.save.party
    if #party < 2 then
      return nil, "need at least 2 pokemon in party"
    end
    
    -- Default indices: keep first, deposit rest
    if not indices then
      indices = {}
      for i = 2, #party do
        indices[#indices + 1] = i
      end
    end
    
    -- Validate indices
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > #party then
        return nil, "invalid index"
      end
    end
    
    -- Ensure at least one remains after removal
    local remainingCount = #party - #indices
    if remainingCount < 1 then
      return nil, "must keep at least 1 pokemon in party"
    end
    
    local s = loadStorage()
    local startBox = targetBoxNum or #s.boxes -- default to last box
    
    -- Collect mons to deposit, in the caller's own indices order -- removal
    -- below sorts its own descending list, so this one is free to preserve
    -- the order mons actually land in the destination box.
    local toDeposit = {}
    for _, idx in ipairs(indices) do
      toDeposit[#toDeposit + 1] = { mon = party[idx], originalIdx = idx }
    end
    
    -- Deposit each mon
    local deposited = {}
    local currentBox = startBox
    local currentBoxNum = currentBox
    
    for _, entry in ipairs(toDeposit) do
      local mon = entry.mon
      if game then ensureStats(game, mon) end
      
      -- Find space starting from current box
      local placed = false
      for off = 0, #s.boxes - 1 do
        local boxNum = ((currentBoxNum - 1 + off) % #s.boxes) + 1
        if #s.boxes[boxNum] < BOX_CAPACITY then
          table.insert(s.boxes[boxNum], mon)
          deposited[#deposited + 1] = { box = boxNum, index = #s.boxes[boxNum], mon = mon }
          currentBoxNum = boxNum
          placed = true
          break
        end
      end
      
      if not placed then
        -- Should not happen due to normalizeBoxes guarantee, but handle gracefully
        s.boxes[#s.boxes + 1] = {}
        table.insert(s.boxes[#s.boxes], mon)
        deposited[#deposited + 1] = { box = #s.boxes, index = 1, mon = mon }
        currentBoxNum = #s.boxes
      end
    end

    -- Remove from party (in reverse index order to preserve positions)
    local sortedIndices = {}
    for _, idx in ipairs(indices) do
      sortedIndices[#sortedIndices + 1] = idx
    end
    table.sort(sortedIndices, function(a, b) return a > b end)
    
    for _, idx in ipairs(sortedIndices) do
      table.remove(party, idx)
    end
    
    normalizeBoxes(s)
    markDirty()
    
    -- Emit events for each deposited mon
    for _, entry in ipairs(deposited) do
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry)
    end
    
    return deposited
  end

  -- Bulk deposit from PC box
  mod.exports.depositBoxPokemon = function(game, pcBoxNum, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum -- nil = last box
    local indices = opts.indices -- nil = all
    
    if not game or not game.save or not game.save.boxes then
      return nil, "invalid game"
    end
    
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)

    local pcBox = game.save.boxes[pcBoxNum]
    if not pcBox then
      return nil, "invalid pc box"
    end
    
    if #pcBox == 0 then
      return nil, "pc box is empty"
    end
    
    -- Default indices: all
    if not indices then
      indices = {}
      for i = 1, #pcBox do
        indices[#indices + 1] = i
      end
    end
    
    -- Validate indices
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > #pcBox then
        return nil, "invalid index"
      end
    end
    
    local s = loadStorage()
    local startBox = targetBoxNum or #s.boxes -- default to last box
    
    -- Collect mons to deposit, in the caller's own indices order -- removal
    -- below sorts its own descending list, so this one is free to preserve
    -- the order mons actually land in the destination box.
    local toDeposit = {}
    for _, idx in ipairs(indices) do
      toDeposit[#toDeposit + 1] = { mon = pcBox[idx], originalIdx = idx }
    end
    
    -- Deposit each mon
    local deposited = {}
    local currentBoxNum = startBox
    
    for _, entry in ipairs(toDeposit) do
      local mon = entry.mon
      if game then ensureStats(game, mon) end
      
      -- Find space starting from current box
      local placed = false
      for off = 0, #s.boxes - 1 do
        local boxNum = ((currentBoxNum - 1 + off) % #s.boxes) + 1
        if #s.boxes[boxNum] < BOX_CAPACITY then
          table.insert(s.boxes[boxNum], mon)
          deposited[#deposited + 1] = { box = boxNum, index = #s.boxes[boxNum], mon = mon }
          currentBoxNum = boxNum
          placed = true
          break
        end
      end
      
      if not placed then
        s.boxes[#s.boxes + 1] = {}
        table.insert(s.boxes[#s.boxes], mon)
        deposited[#deposited + 1] = { box = #s.boxes, index = 1, mon = mon }
        currentBoxNum = #s.boxes
      end
    end

    -- Remove from PC box (in reverse index order)
    local sortedIndices = {}
    for _, idx in ipairs(indices) do
      sortedIndices[#sortedIndices + 1] = idx
    end
    table.sort(sortedIndices, function(a, b) return a > b end)
    
    for _, idx in ipairs(sortedIndices) do
      table.remove(pcBox, idx)
    end
    
    normalizeBoxes(s)
    markDirty()
    
    -- Emit events for each deposited mon
    for _, entry in ipairs(deposited) do
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry)
    end
    
    return deposited
  end

  -- Bulk withdraw to party
  mod.exports.withdrawToParty = function(game, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum -- nil = first non-empty box
    local indices = opts.indices -- nil = all
    
    if not game or not game.save or not game.save.party then
      return nil, "invalid game"
    end
    
    local party = game.save.party
    local s = loadStorage()
    
    -- Default source box: first non-empty box
    if not sourceBoxNum then
      sourceBoxNum = 1
      while sourceBoxNum <= #s.boxes and #s.boxes[sourceBoxNum] == 0 do
        sourceBoxNum = sourceBoxNum + 1
      end
      if sourceBoxNum > #s.boxes then
        return nil, "bank is empty"
      end
    end
    
    local sourceBox = s.boxes[sourceBoxNum]
    if not sourceBox then
      return nil, "invalid bank box"
    end
    
    if #sourceBox == 0 then
      return nil, "bank box is empty"
    end
    
    -- Default indices: all
    if not indices then
      indices = {}
      for i = 1, #sourceBox do
        indices[#indices + 1] = i
      end
    end
    
    -- Validate indices
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > #sourceBox then
        return nil, "invalid index"
      end
    end
    
    -- Calculate how many can fit in party
    local partySpace = Party.MAX - #party
    if partySpace <= 0 then
      return nil, "party is full"
    end
    
    -- Collect mons to withdraw, in the caller's own indices order -- removal
    -- below sorts its own descending list, so this one is free to preserve
    -- the order mons actually land in the party.
    local toWithdraw = {}
    for _, idx in ipairs(indices) do
      toWithdraw[#toWithdraw + 1] = { mon = sourceBox[idx], originalIdx = idx }
    end

    -- Withdraw up to party capacity
    local withdrawn = {}
    local remaining = {}
    
    for _, entry in ipairs(toWithdraw) do
      if #withdrawn < partySpace then
        local mon = entry.mon
        reshapeForActiveGame(game, mon)
        stampNewTrainer(game, mon)
        table.insert(party, mon)
        registerDex(game, mon.species)
        withdrawn[#withdrawn + 1] = { mon = mon }
        mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = entry.originalIdx, mon = mon })
      else
        remaining[#remaining + 1] = entry
      end
    end
    
    -- Remove withdrawn mons from bank (in reverse index order)
    local sortedIndices = {}
    for _, entry in ipairs(withdrawn) do
      -- Need to find the original index from toWithdraw
      for _, origEntry in ipairs(toWithdraw) do
        if origEntry.mon == entry.mon then
          sortedIndices[#sortedIndices + 1] = origEntry.originalIdx
          break
        end
      end
    end
    table.sort(sortedIndices, function(a, b) return a > b end)
    
    for _, idx in ipairs(sortedIndices) do
      table.remove(sourceBox, idx)
    end
    
    normalizeBoxes(s)
    markDirty()
    
    return { withdrawn = withdrawn, remaining = #remaining }
  end

  -- Bulk withdraw to PC box
  mod.exports.withdrawToBox = function(game, targetPcBoxNum, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum -- nil = first non-empty box
    local indices = opts.indices -- nil = all
    if not game or not game.save or not game.save.boxes then
      return nil, "invalid game"
    end
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)
    local targetBox = game.save.boxes[targetPcBoxNum]
    if not targetBox then
      return nil, "invalid target pc box"
    end
    local s = loadStorage()
    -- Default source box: first non-empty box
    if not sourceBoxNum then
      sourceBoxNum = 1
      while sourceBoxNum <= #s.boxes and #s.boxes[sourceBoxNum] == 0 do
        sourceBoxNum = sourceBoxNum + 1
      end
      if sourceBoxNum > #s.boxes then
        return nil, "bank is empty"
      end
    end
    local sourceBox = s.boxes[sourceBoxNum]
    if not sourceBox then
      return nil, "invalid bank box"
    end
    if #sourceBox == 0 then
      return nil, "bank box is empty"
    end
    -- Default indices: all
    if not indices then
      indices = {}
      for i = 1, #sourceBox do
        indices[#indices + 1] = i
      end
    end
    -- Validate indices
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > #sourceBox then
        return nil, "invalid index"
      end
    end
    -- Collect mons to withdraw, in the caller's own indices order -- removal
    -- below sorts its own descending list, so this one is free to preserve
    -- the order mons actually land in the destination PC box.
    local toWithdraw = {}
    for _, idx in ipairs(indices) do
      toWithdraw[#toWithdraw + 1] = { mon = sourceBox[idx], originalIdx = idx }
    end
    -- Withdraw mons, filling target box then overflowing to next boxes
    local withdrawn = {}
    local remaining = {}
    local currentPcBoxNum = targetPcBoxNum
    for _, entry in ipairs(toWithdraw) do
      local mon = entry.mon
      local placed = false
      -- Try to place in current or subsequent PC boxes
      for off = 0, Boxes.COUNT - 1 do
        local boxNum = ((currentPcBoxNum - 1 + off) % Boxes.COUNT) + 1
        local box = game.save.boxes[boxNum]
        if box and #box < Boxes.CAPACITY then
          reshapeForActiveGame(game, mon)
          stampNewTrainer(game, mon)
          table.insert(box, mon)
          registerDex(game, mon.species)
          withdrawn[#withdrawn + 1] = { mon = mon, pcBox = boxNum }
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = entry.originalIdx, mon = mon })
          currentPcBoxNum = boxNum
          placed = true
          break
        end
      end
      if not placed then
        remaining[#remaining + 1] = entry
      end
    end
    -- Remove withdrawn mons from bank (in reverse index order)
    local sortedIndices = {}
    for _, entry in ipairs(withdrawn) do
      for _, origEntry in ipairs(toWithdraw) do
        if origEntry.mon == entry.mon then
          sortedIndices[#sortedIndices + 1] = origEntry.originalIdx
          break
        end
      end
    end
    table.sort(sortedIndices, function(a, b) return a > b end)
    for _, idx in ipairs(sortedIndices) do
      table.remove(sourceBox, idx)
    end
    normalizeBoxes(s)
    markDirty()
    return { withdrawn = withdrawn, remaining = #remaining }
  end

  mod.exports.pokemonScreenId = SCREEN_ID

  mod.exports.setPokemonTabEnabled = function(enabled)
    tabEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.isPokemonTabEnabled = function() return tabEnabled() end

  mod.log:info("Pokemon Bank: Pokemon tab ready")

  return {
    screenId = SCREEN_ID,
    transferBoxScreenId = TRANSFER_BOX_SCREEN_ID,
    moveScreenId = MOVE_SCREEN_ID,
    tabEnabled = tabEnabled,
    validateStorage = validateStorage,
  }
end

return Module
