local V = ...

local Stats = require("src.pokemon.Stats")
local Party = require("src.pokemon.Party")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")

local BOX_CAPACITY = 20
local SCREEN_ID = "PokemonBankBox"

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
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  local function ensureStats(game, mon)
    local def = game.data.pokemon[mon.species]
    if def then Stats.ensure(def, mon) end
    return mon
  end

  -- Mirrors Evolution's own seen/owned write. Never called on release or on a move that stays inside the Bank -- see API.md's withdrawPokemon entry.
  local function registerDex(game, species)
    if game and game.save and game.save.pokedex then
      game.save.pokedex.seen[species] = true
      game.save.pokedex.owned[species] = true
    end
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

  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {} }
    end
    local s = loadStorage()
    local orphaned = ensureOrphaned(s)
    local quarantined, restored = 0, 0
    local lostMons, restoredMons = {}, {}
    for boxNum = 1, #s.boxes do
      local box = s.boxes[boxNum]
      for idx = #box, 1, -1 do
        local mon = box[idx]
        if not isValidPokemon(mon, data) then
          table.remove(box, idx)
          orphaned.mons[#orphaned.mons + 1] = mon
          quarantined = quarantined + 1
          lostMons[#lostMons + 1] = { species = mon.species, from = "BOX " .. boxNum }
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
      changed = quarantined > 0 or restored > 0,
      quarantined = quarantined,
      restored = restored,
      lostMons = lostMons,
      restoredMons = restoredMons,
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
    local def = game.data.pokemon[mon.species]
    return Strings("%s :L%d", mon.nickname or def.name, mon.level)
  end

  -- action + STATS + CANCEL, the vanilla PC's own per-mon submenu
  local function monSubmenu(game, action, mon, onAction)
    game.stack:push(Menu.new(game, {
      { label = action, onSelect = onAction },
      { label = "STATS", keepOpen = true, onSelect = function()
          ensureStats(game, mon)
          require("src.ui.Screens").push(game, "SummaryMenu", mon)
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
    list = ListMenu.new(game, ("BOX %d (WITHDRAW)"):format(boxNum), items, {
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
    local list
    list = ListMenu.new(game, "PARTY (DEPOSIT)", items, {
      noSound = true,
      onChoose = function(item)
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
    game.stack:push(ListMenu.new(game, ("BOX %d (RELEASE)"):format(boxNum), items, {
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
    }))
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

  -- WITHDRAW / DEPOSIT / RELEASE / CHANGE BOX / CANCEL, keepOpen so each sub-list leaves this menu underneath it.
  local function BankBoxMenu(game)
    local rows = {
      { label = Strings("WITHDRAW <PK><MN>"), keepOpen = true, onSelect = function() openWithdrawList(game) end },
      { label = Strings("DEPOSIT <PK><MN>"), keepOpen = true, onSelect = function() openDepositList(game) end },
      { label = "RELEASE", keepOpen = true, onSelect = function() openReleaseList(game) end },
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

  mod.exports.pokemonScreenId = SCREEN_ID

  mod.exports.setPokemonTabEnabled = function(enabled)
    tabEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.isPokemonTabEnabled = function() return tabEnabled() end

  mod.log:info("Pokemon Bank: Pokemon tab ready")

  return {
    screenId = SCREEN_ID,
    tabEnabled = tabEnabled,
    validateStorage = validateStorage,
  }
end

return Module
