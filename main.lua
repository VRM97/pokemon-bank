local BOX_CAPACITY = 20
local STORAGE_DIR = "bank"
local STORAGE_FILE = STORAGE_DIR .. "/storage.lua"
local STORAGE_BACKUP = STORAGE_FILE .. ".bak"
local STORAGE_TMP = STORAGE_FILE .. ".tmp"
local SCREEN_POKEMON = "PokemonBankBox"
local SCREEN_ITEMS = "PokemonBankItems"
local PC_MENU_LABEL = "POKéMON BANK"

return function(mod)
  mod.options:define({
    { key = "pc_menu_entry", label = "SHOW IN PC MENU", type = "toggle", default = true },
    { key = "show_pokemon_tab", label = "SHOW POKéMON", type = "toggle", default = true },
    { key = "show_items_tab", label = "SHOW ITEMS", type = "toggle", default = true },
  })

  local SaveSerializer = require("src.core.SaveSerializer")
  local SaveData = require("src.core.SaveData")
  local Stats = require("src.pokemon.Stats")
  local Party = require("src.pokemon.Party")
  local Bag = require("src.inventory.Bag")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local QuantityBox = require("src.ui.QuantityBox")

  -- -----------------------------------------------------------------------
  -- Persistence
  -- -----------------------------------------------------------------------
  local function fs()
    return SaveData.portableFs() or love.filesystem
  end

  local function fileExists(name)
    local ok, info = pcall(function() return fs().getInfo(name) end)
    return ok and info ~= nil
  end

  local function tryRead(name)
    local ok, result = pcall(function() return fs().read(name) end)
    if ok and type(result) == "string" then return result end
    return nil
  end

  -- fs().write returns true, or false + an error message, but never
  -- throws under normal conditions; the pcall is only there for whatever
  -- an injected/headless fs might do differently.
  local function tryWrite(name, data)
    local ok, result = pcall(function() return fs().write(name, data) end)
    return ok and result ~= false
  end

  local function tryRemove(name)
    pcall(function()
      local f = fs()
      if f.remove then f.remove(name) end
    end)
  end

  local function readStorageFile(name)
    if not fileExists(name) then return nil end
    local raw = tryRead(name)
    if not raw then return nil end
    local decoded = SaveSerializer.decode(raw)
    if type(decoded) ~= "table" then return nil end
    return decoded
  end

  local function freshStorage()
    return { version = 1, boxes = { {} }, currentBox = 1, items = {} }
  end

  -- Maintains the box array's one invariant after every mutation: no empty
  -- box ever sticks around except exactly one, always last -- a spare to
  -- grow into, so a deposit or a MOVE into "the next box" never has to ask
  -- permission. A box left empty by a withdrawal/release/move is dropped
  -- outright rather than kept as a hole, so #s.boxes (boxCount(), below) is
  -- always "occupied boxes + 1", and it shrinks back down on its own as the
  -- bank empties out instead of growing forever. The trade-off: a box's
  -- NUMBER is only a snapshot, not a stable id -- any other box elsewhere
  -- emptying out shifts every later box's number down by one. Every mutator
  -- below re-checks the mon/count it expects to find at a given box+index
  -- before touching it, and callers of the exported API should do the same
  -- (see API.md).
  local function normalizeBoxes(s)
    local boxes = type(s.boxes) == "table" and s.boxes or {}
    local compact = {}
    for _, box in ipairs(boxes) do
      if type(box) == "table" and #box > 0 then
        compact[#compact + 1] = box
      end
    end
    compact[#compact + 1] = {} -- the one spare box, always last
    s.boxes = compact
    s.currentBox = math.max(1, math.min(#s.boxes, math.floor(tonumber(s.currentBox) or 1)))
    s.items = type(s.items) == "table" and s.items or {}
  end

  local storage -- in-memory cache; loaded lazily on first touch
  local dirty = false -- true when storage has mutations not yet flushed to disk

  -- Mirrors SaveData.load's own recovery order (source/src/core/SaveData.lua):
  -- the main file wins; a missing or corrupt one (e.g. the process died
  -- mid-write) falls back to the .tmp staging witness, then the rolling
  -- .bak. A recovered copy is only promoted back to the main filename the
  -- next time something actually flushes, not eagerly here.
  local function loadStorage()
    if storage then return storage end
    local out = readStorageFile(STORAGE_FILE)
      or readStorageFile(STORAGE_TMP)
      or readStorageFile(STORAGE_BACKUP)
    if not out then out = freshStorage() end
    normalizeBoxes(out)
    storage = out
    return storage
  end

  -- Every mutator calls this instead of writing to disk directly -- see
  -- the header comment above for why the actual write waits for the
  -- game's own save.
  local function markDirty()
    dirty = true
  end

  -- The actual disk write, only ever called from the save.write hook
  -- below (never after a single deposit/withdraw). Mirrors SaveData.save's
  -- own backup-then-tmp-witness-then-swap discipline: the last good file
  -- rolls into .bak, the new bytes stage as a .tmp witness, then main is
  -- removed and rewritten -- so a crash mid-write leaves a recoverable
  -- .tmp or .bak instead of a half-written storage.lua.
  local function flushStorage()
    if not (dirty and storage) then return end
    pcall(function() fs().createDirectory(STORAGE_DIR) end)
    local ok, encoded = pcall(SaveSerializer.encode, storage)
    if not ok then
      mod.log:warn("could not encode bank storage: %s", tostring(encoded))
      return
    end
    if fileExists(STORAGE_FILE) then
      local prev = tryRead(STORAGE_FILE)
      if prev then tryWrite(STORAGE_BACKUP, prev) end
    end
    if not tryWrite(STORAGE_TMP, encoded) then
      mod.log:warn("could not stage %s", STORAGE_TMP)
      return
    end
    tryRemove(STORAGE_FILE)
    if not tryWrite(STORAGE_FILE, encoded) then
      mod.log:warn("could not write %s", STORAGE_FILE)
      return
    end
    tryRemove(STORAGE_TMP)
    dirty = false
  end

  -- Ties the Bank's own disk write to the game's: whenever a save is about
  -- to go through (a manual SAVE, an autosave mod, anything that reaches
  -- Game:writeSave), flush right alongside it. A veto earlier in the
  -- save.write chain (an ephemeral tool session, source/docs/modding.md)
  -- means the save itself won't happen, so the Bank doesn't flush either
  -- -- staying dirty is correct, not a bug, when nothing was actually saved.
  mod.hooks:wrap("save.write", function(next_, game)
    local proceed = next_(game)
    if proceed ~= false then
      flushStorage()
    end
    return proceed
  end)

  -- -----------------------------------------------------------------------
  -- Item blacklist: HMs and key items can never enter the Bank -- a hard
  -- rule, not a preference, so there is no way to lift it for either. A
  -- mod may only ADD to it (blacklistItem), for items it knows are
  -- progression-critical but that don't set keyItem = true (extraBlacklist
  -- lives only in memory, so it's re-declared by that mod every load).
  -- -----------------------------------------------------------------------
  local extraBlacklist = {}

  local function isHM(id)
    return type(id) == "string" and id:find("^HM_") ~= nil
  end

  local function isBlacklisted(id, def)
    if extraBlacklist[id] then return true end
    if isHM(id) then return true end
    if def and def.keyItem then return true end
    return false
  end

  -- -----------------------------------------------------------------------
  -- Pokémon storage
  -- -----------------------------------------------------------------------
  -- Never refuses: normalizeBoxes guarantees the last box is always
  -- empty, so the search below always finds room there even when every
  -- earlier box is full.
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

  -- -----------------------------------------------------------------------
  -- Item storage: a flat { id = count } table, no manual ordering to
  -- maintain -- the UI below always lists it sorted by display name.
  -- -----------------------------------------------------------------------
  local function itemCount(id)
    return loadStorage().items[id] or 0
  end

  local function depositItem(id, qty, def)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    if isBlacklisted(id, def) then return false, "blacklisted" end
    local s = loadStorage()
    s.items[id] = (s.items[id] or 0) + qty
    markDirty()
    return true
  end

  local function withdrawItem(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    local s = loadStorage()
    local have = s.items[id] or 0
    if qty <= 0 or qty > have then return false, "not enough" end
    s.items[id] = have - qty
    if s.items[id] <= 0 then s.items[id] = nil end
    markDirty()
    return true
  end

  local function listItems()
    local out = {}
    for id, count in pairs(loadStorage().items) do out[id] = count end
    return out
  end

  -- -----------------------------------------------------------------------
  -- UI helpers
  -- -----------------------------------------------------------------------
  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
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

  -- Withdrawing a mon out of the Bank -- into the party or a PC box, the
  -- only two places a withdrawal can land -- catches it in the Pokédex if
  -- it wasn't already, mirroring Evolution.lua's own seen/owned write.
  -- Never called on release or on a move that stays inside the Bank.
  local function registerDex(game, species)
    if game and game.save and game.save.pokedex then
      game.save.pokedex.seen[species] = true
      game.save.pokedex.owned[species] = true
    end
  end

  local function playSound(game, name)
    pcall(function() require("src.core.Sound").play(game.data, name) end)
  end

  local function playCry(game, species)
    pcall(function() require("src.core.Sound").playCry(game.data, species) end)
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

  -- bills_pc.asm BillsPCMenu: WITHDRAW/DEPOSIT/RELEASE/CHANGE BOX/CANCEL,
  -- keepOpen so each sub-list leaves this menu underneath it. The WITHDRAW
  -- and DEPOSIT labels use the same "<PK><MN>" macro
  -- (source/src/render/Font.lua's multi-character charmap sequences) the
  -- vanilla PC menu itself uses, rather than spelling out "POKéMON" --
  -- Menu.new grows tw to fit the widest label, and the two-tile macro is
  -- what keeps this box the same compact width as the vanilla one.
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

  mod.content.screens:register(SCREEN_POKEMON, { new = BankBoxMenu })

  -- =========================================================================
  -- Item UI
  -- =========================================================================
  local function itemName(game, id)
    local def = game.data.items[id]
    return def and def.name or id
  end

  local function sortedItemIds(game, counts)
    local ids = {}
    for id, count in pairs(counts) do
      if count and count > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return itemName(game, a) < itemName(game, b) end)
    return ids
  end

  local function bankItemRows(game)
    local s = loadStorage()
    local rows = {}
    for _, id in ipairs(sortedItemIds(game, s.items)) do
      rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(s.items[id]) }
    end
    return rows
  end

  local function bagItemRowsForBank(game)
    local inv = game.save.inventory
    local counts = {}
    for _, id in ipairs(Bag.order(game.save)) do counts[id] = inv[id] end
    local rows = {}
    for _, id in ipairs(sortedItemIds(game, counts)) do
      rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(inv[id]) }
    end
    return rows
  end

  -- Updates or drops `id`'s row after its count changed, keeping the list
  -- open and the cursor valid (vanilla PlayerPC's own refreshRow).
  local function refreshItemRow(list, count, id)
    for i, row in ipairs(list.items) do
      if row.value == id then
        if count and count > 0 then
          row.right = "x" .. tostring(count)
        else
          table.remove(list.items, i)
        end
        break
      end
    end
    list.index = math.max(1, math.min(list.index, #list.items))
  end

  local function askItemQuantity(game, list, count, cb)
    list.footer = "How many?"
    game.stack:push(QuantityBox.new(game, {
      max = count,
      onDone = function(qty)
        if qty then cb(qty) else list.footer = nil end
      end,
    }))
  end

  local function openWithdrawItemsList(game)
    local list
    list = ListMenu.new(game, "WITHDRAW ITEM", bankItemRows(game), {
      messageBox = true, noSound = true,
      onChoose = function(item)
        local count = itemCount(item.value)
        if count <= 0 then
          list.footer = "The selection changed."
          return
        end
        askItemQuantity(game, list, count, function(qty)
          if not Bag.add(game.save, item.value, qty, game.data) then
            list.footer = "You can't carry\nany more items."
            return
          end
          withdrawItem(item.value, qty)
          mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = item.value, qty = qty })
          refreshItemRow(list, itemCount(item.value), item.value)
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("Withdrew\n%s.", itemName(game, item.value))
        end)
      end,
    })
    game.stack:push(list)
  end

  local function openDepositItemsList(game)
    local list
    list = ListMenu.new(game, "DEPOSIT ITEM", bagItemRowsForBank(game), {
      messageBox = true, noSound = true,
      onChoose = function(item)
        local def = game.data.items[item.value]
        if isBlacklisted(item.value, def) then
          list.footer = "That can't be\nstored in BANK!"
          return
        end
        local count = game.save.inventory[item.value]
        if not count then
          list.footer = "The selection changed."
          return
        end
        askItemQuantity(game, list, count, function(qty)
          Bag.remove(game.save, item.value, qty)
          depositItem(item.value, qty, def)
          mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = item.value, qty = qty })
          refreshItemRow(list, game.save.inventory[item.value], item.value)
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("%s was\nstored in BANK.", itemName(game, item.value))
        end)
      end,
    })
    game.stack:push(list)
  end

  -- players_pc.asm PlayerPCMenu: WITHDRAW ITEM / DEPOSIT ITEM / CANCEL --
  -- vanilla also has TOSS ITEM, but tossing isn't the Bank's job (the real
  -- Bag/PC already do it); keepOpen so each list leaves this menu
  -- underneath it.
  local function BankItemMenu(game)
    -- matches vanilla PlayerPC's own box exactly (16x10 for its 4 rows;
    -- 16 wide is what "WITHDRAW ITEM"/"DEPOSIT ITEM" need without growing)
    local rows = {
      { label = "WITHDRAW ITEM", keepOpen = true, onSelect = function() openWithdrawItemsList(game) end },
      { label = "DEPOSIT ITEM", keepOpen = true, onSelect = function() openDepositItemsList(game) end },
      { label = "CANCEL" },
    }
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
  end

  mod.content.screens:register(SCREEN_ITEMS, { new = BankItemMenu })

  -- =========================================================================
  -- Entry point: a row on the PC's own main menu (BILL's PC / Player's PC /
  -- PROF.OAK's PC / LOG OFF -- OverworldState:openPC, the ui.pc.items hook)
  -- opening a small POKéMON / ITEMS chooser. Deliberately not a START menu
  -- row: the Bank is another PC service, so it lives where the other ones
  -- do.
  -- =========================================================================
  -- Another mod can veto either tab outright through setPokemonTabEnabled/
  -- setItemsTabEnabled(false) (see exports below) -- each checked
  -- independently of, and in addition to, the player's own SHOW POKéMON /
  -- SHOW ITEMS options. Mirrors pcEntryEnabledByOthers/pc_menu_entry below,
  -- one level down.
  local pokemonTabEnabledByOthers = true
  local itemsTabEnabledByOthers = true

  local function pokemonTabEnabled()
    return pokemonTabEnabledByOthers and mod.options:get("show_pokemon_tab") == true
  end

  local function itemsTabEnabled()
    return itemsTabEnabledByOthers and mod.options:get("show_items_tab") == true
  end

  -- With both tabs enabled, opens the usual POKéMON/ITEMS chooser. With
  -- only one enabled, skips the chooser and opens that tab directly --
  -- there is nothing left to choose between. Never called with neither
  -- enabled: the ui.pc.items hook below drops the PC row entirely in that
  -- case, and setPokemonTabEnabled/setItemsTabEnabled don't reach into an
  -- already-open chooser.
  local function openBankMenu(game)
    local pokeOn, itemsOn = pokemonTabEnabled(), itemsTabEnabled()
    if pokeOn and itemsOn then
      game.stack:push(Menu.new(game, {
        { label = "POKéMON", onSelect = function() mod.ui.push(game, SCREEN_POKEMON) end },
        { label = "ITEMS", onSelect = function() mod.ui.push(game, SCREEN_ITEMS) end },
        { label = "CANCEL" },
      }, { tx = 8, ty = 10, tw = 12, th = 8 }))
    elseif pokeOn then
      mod.ui.push(game, SCREEN_POKEMON)
    elseif itemsOn then
      mod.ui.push(game, SCREEN_ITEMS)
    end
  end

  -- Another mod can veto the row outright through setPcEntryEnabled(false)
  -- (see exports below) -- checked independently of, and in addition to,
  -- the player's own SHOW IN PC MENU option.
  local pcEntryEnabledByOthers = true

  mod.hooks:wrap("ui.pc.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    if not pcEntryEnabledByOthers then return out end
    if mod.options:get("pc_menu_entry") ~= true then return out end
    -- Nothing to open with both tabs off -- drop the row instead of
    -- showing an empty chooser (or a chooser with nothing behind it).
    if not (pokemonTabEnabled() or itemsTabEnabled()) then return out end
    -- Right before PROF.OAK's PC -- which, in the menu's normal order
    -- (BILL's PC / Player's PC / PROF.OAK's PC / LOG OFF), lands this row
    -- right after the player's own item-storage PC too, without having to
    -- match that row's dynamic (player name).."'s PC" label. insertBefore
    -- falls back to appending when the anchor isn't found, so this still
    -- lands correctly even if some other mod's hook removed or renamed
    -- that row. keepOpen mirrors every other row already on this menu, so
    -- B in the chooser above returns to the PC menu instead of logging off.
    return mod.ui.insertBefore(out, "PROF.OAK's PC", {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function() openBankMenu(game) end,
    })
  end)

  -- =========================================================================
  -- Public API for other mods.
  -- =========================================================================
  -- boxCount(): how many boxes currently exist -- always (occupied boxes)
  -- + 1, since an emptied-out box is deleted rather than kept as a gap
  -- (normalizeBoxes above); there is no cap, so this grows on its own as
  -- the Bank fills up. See API.md for the box-number-is-not-a-stable-id
  -- caveat that follows from boxes being deleted this way.
  mod.exports.boxCount = function() return boxCount() end
  mod.exports.boxCapacity = function() return BOX_CAPACITY end

  -- depositPokemon(mon, opts): opts.game, when given, is used to calculate
  -- and freeze the mon's stats block before storage (mirrors what every
  -- deposit path in this mod's own UI does). Never refuses -- the Bank has
  -- no box limit -- so boxNum is always returned; the only failure is a
  -- malformed mon.
  mod.exports.depositPokemon = function(mon, opts)
    if type(mon) ~= "table" then return nil, "invalid pokemon" end
    opts = opts or {}
    if opts.game then ensureStats(opts.game, mon) end
    local boxNum, slot = depositMon(mon)
    mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", { box = boxNum, index = slot, mon = mon })
    return boxNum, slot
  end

  -- withdrawPokemon(boxNum, index, game): removes and returns the mon
  -- table, or nil if that slot is empty. game is optional but strongly
  -- recommended -- when given, catches the mon in the Pokédex (seen +
  -- owned) if it wasn't already, the same way this mod's own WITHDRAW
  -- POKéMON list does. Without it, the withdrawal still happens; only the
  -- Pokédex write is skipped.
  mod.exports.withdrawPokemon = function(boxNum, index, game)
    local mon = withdrawMon(boxNum, index)
    if mon then
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = boxNum, index = index, mon = mon })
    end
    return mon
  end

  -- getPokemon(boxNum, index): read-only peek, does not remove.
  mod.exports.getPokemon = function(boxNum, index) return peekMon(boxNum, index) end

  -- getBox(boxNum): a snapshot copy of one box's slots, indexed
  -- 1..boxCapacity() (nil for an empty slot), for a mod that wants to
  -- render the Bank as a grid instead of walking listPokemon() itself
  -- (e.g. vrm_unified_pc_system's own box-grid style). A copy, not a live
  -- reference -- mutating it does nothing to the Bank; call it again
  -- after any mutation (deposit/withdraw/move/release) to see the result.
  -- nil for a boxNum outside 1..boxCount() (see the box-numbering caveat
  -- in API.md).
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

  -- releasePokemon(boxNum, index): removes it for good, no confirmation
  -- (this mod's own RELEASE action asks first; the export does not).
  -- Returns whether anything was actually there to remove.
  mod.exports.releasePokemon = function(boxNum, index)
    local mon = withdrawMon(boxNum, index)
    if mon then
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_released", { box = boxNum, index = index, mon = mon })
    end
    return mon ~= nil
  end

  -- listPokemon(): flat array of { box, index, mon }, every stored mon.
  mod.exports.listPokemon = function() return listMons() end
  mod.exports.pokemonCount = function() return countMons() end

  -- depositItem(id, qty, game): game is optional but strongly recommended
  -- -- without it, only the id-prefix HM check and any extraBlacklist
  -- entries apply (no game.data.items lookup means the keyItem flag can't
  -- be checked). Returns true, or false, "blacklisted"/"bad request".
  mod.exports.depositItem = function(id, qty, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    local ok, err = depositItem(id, qty, def)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = id, qty = qty })
    end
    return ok, err
  end

  -- withdrawItem(id, qty): decrements the Bank's own count. Does NOT touch
  -- any bag -- callers add it to whatever inventory they mean with their
  -- own Bag.add (mirrors this mod's own UI, which checks capacity first).
  mod.exports.withdrawItem = function(id, qty)
    local ok, err = withdrawItem(id, qty)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = id, qty = qty })
    end
    return ok, err
  end

  mod.exports.itemCount = function(id) return itemCount(id) end
  mod.exports.listItems = function() return listItems() end

  mod.exports.isBlacklisted = function(id, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    return isBlacklisted(id, def)
  end

  -- blacklistItem(id): permanently (for this session) refuses id from
  -- depositItem, on top of the built-in HM/keyItem rule. Additive only.
  mod.exports.blacklistItem = function(id)
    if type(id) ~= "string" or id == "" then return false end
    extraBlacklist[id] = true
    return true
  end

  -- open(game, tab): pushes the Bank UI directly ("pokemon" or "items",
  -- default "pokemon"), the same screens the PC's own POKéMON BANK row opens.
  mod.exports.open = function(game, tab)
    if not game then return nil, "no game" end
    if tab == "items" then return mod.ui.push(game, SCREEN_ITEMS) end
    return mod.ui.push(game, SCREEN_POKEMON)
  end

  -- setPcEntryEnabled(enabled): lets another mod hide the POKéMON BANK row
  -- from the PC's main menu outright (pass false), or restore it (true) --
  -- independent of the player's own SHOW IN PC MENU option, and without
  -- having to guess this mod's hook priority to out-order it. Also exported
  -- as pcMenuLabel below for a mod that would rather do it itself with
  -- ModUI.removeLabel inside its own ui.pc.items hook.
  mod.exports.setPcEntryEnabled = function(enabled)
    pcEntryEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.pcMenuLabel = PC_MENU_LABEL

  -- setPokemonTabEnabled(enabled) / setItemsTabEnabled(enabled): same idea
  -- as setPcEntryEnabled, one level down -- hide (pass false) or restore
  -- (true, or call again) just the POKéMON or just the ITEMS side of the
  -- Bank, independent of the player's own SHOW POKéMON / SHOW ITEMS
  -- options. With only one side enabled (by option or by another mod),
  -- the POKéMON BANK row skips the chooser and opens that side directly;
  -- with neither enabled, the row itself doesn't appear (see the
  -- ui.pc.items hook above). Does not affect open(game, tab) or the
  -- registered screen ids below -- those stay available for a mod that
  -- wants to reach a tab directly regardless of this setting, the same
  -- way open() already bypasses SHOW IN PC MENU/setPcEntryEnabled.
  mod.exports.setPokemonTabEnabled = function(enabled)
    pokemonTabEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.setItemsTabEnabled = function(enabled)
    itemsTabEnabledByOthers = enabled ~= false
    return true
  end

  mod.exports.pokemonScreenId = SCREEN_POKEMON
  mod.exports.itemsScreenId = SCREEN_ITEMS

  -- flush(): forces the pending write early instead of waiting for the
  -- game's own save. Normally unnecessary -- see the persistence header
  -- comment at the top of this file for why waiting is the safer default
  -- -- but available for a mod that has its own reason to make a Bank
  -- change durable right away (e.g. right before doing something that
  -- risks the process, like a native file-picker call). Returns whether
  -- anything was actually pending.
  mod.exports.flush = function()
    local was = dirty
    flushStorage()
    return was
  end

  mod.log:info("Pokemon Bank loaded")
end
