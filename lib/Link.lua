local V = ...

local Strings = require("src.core.Strings")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local Font = require("src.render.Font")
local Net = require("src.link.Net")
local Session = require("src.link.Session")
local CodeEntry = require("src.link.CodeEntry")

local SCREEN_ID = "PokemonBankLink"
local CURSOR = 0xED

-- Bumped only when the message shapes below change; a mismatch refuses the link.
local LINK_VERSION = 2

local Module = {}

-- POKéMON and MONEY are the two sibling tabs this module reaches into directly: withdrawMon/depositMon and AmountBox. ITEMS/MOVES have no such need -- mod.exports.withdrawItem/depositItem/withdrawMove/depositMove already do exactly the right thing for a cart move.
function Module.install(mod, core, Pokemon, Money)
  local loadStorage = core.loadStorage
  local message = core.message
  local playSound = core.playSound
  local truncateName = core.truncateName
  local attachLevelIcons = core.attachLevelIcons

  local function depositItemSafe(id, qty, game)
    local prevOverride = mod.exports.getTmItemDepositOverride and mod.exports.getTmItemDepositOverride()
    if mod.exports.setTmItemDepositAllowed then mod.exports.setTmItemDepositAllowed(true) end
    local ok = mod.exports.depositItem(id, qty, game)
    if mod.exports.setTmItemDepositAllowed then mod.exports.setTmItemDepositAllowed(prevOverride) end
    if ok then return end
    local orphaned = core.ensureOrphaned(loadStorage())
    orphaned.items[id] = (orphaned.items[id] or 0) + qty
    core.markDirty()
  end

  local function freshCart()
    return { mons = {}, items = {}, moves = {}, money = 0, orphaned = { mons = {}, items = {}, moves = {} } }
  end

  local function orphanedCount(orphaned)
    local n = #orphaned.mons
    for _, q in pairs(orphaned.items) do n = n + (q or 0) end
    for _, q in pairs(orphaned.moves) do n = n + (q or 0) end
    return n
  end

  -- Shared by cartSummaryLines below and applyReceived's own link_completed
  -- stats payload, so the two never sum items/moves differently.
  local function cartCounts(cart)
    local itemQty, moveQty = 0, 0
    for _, q in pairs(cart.items) do itemQty = itemQty + (q or 0) end
    for _, q in pairs(cart.moves) do moveQty = moveQty + (q or 0) end
    return { pokemon = #cart.mons, items = itemQty, moves = moveQty, money = cart.money }
  end

  local function cartSummaryLines(cart)
    local counts = cartCounts(cart)
    local lines = {
      Strings("%d POKéMON", counts.pokemon),
      Strings("%d items", counts.items),
      Strings("%d banked moves", counts.moves),
      Strings("¥%d", counts.money),
    }
    local lost = orphanedCount(cart.orphaned)
    if lost > 0 then lines[#lines + 1] = Strings("%d set aside (LOST)", lost) end
    return lines
  end

  local function confirmCancel(self, reopen)
    local game = self.game
    game.stack:push(TextBox.new(game, "Cancel the\ntransfer?", function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if yes then self:abort() else reopen() end
      end, { defaultNo = true }))
    end))
  end

  local function confirmCancelOrBack(self)
    local game = self.game
    game.stack:push(TextBox.new(game, "Cancel the\ntransfer?", function()
      local rows = {
        { label = "YES", onSelect = function() self:abort() end },
        { label = "GO BACK", onSelect = function() self:requestBack() end },
        { label = "NO", onSelect = function() self:openReceiveMenu() end },
      }
      game.stack:push(Menu.new(game, rows, {
        tx = 0, ty = 0, tw = 12, th = #rows * 2 + 2, noSound = true,
        onCancel = function() self:openReceiveMenu() end,
      }))
    end))
  end

  local function openConfirmScreen(self, opts)
    local game = self.game
    local screen = { isOpaque = true }
    function screen:update(dt)
      local input = game.input
      if input:wasPressed("a") then
        game.stack:pop()
        opts.onConfirm()
      elseif input:wasPressed("b") then
        game.stack:pop()
        if opts.onBack then opts.onBack() end
      end
    end
    function screen:draw()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(opts.title, 8, 6)
      for i, line in ipairs(opts.lines) do
        Font.draw(line, 8, 24 + (i - 1) * 12)
      end
      Font.draw(opts.footer or Strings("A: CONFIRM  B: BACK"), 8, 128)
      love.graphics.setColor(1, 1, 1, 1)
    end
    game.stack:push(screen)
  end

  local function openSendPokemonPicker(self)
    local game = self.game
    local cart = self.cart.send
    local state = { view = "bank", bankBox = loadStorage().currentBox }
    local screen = { isOpaque = true }
    local list

    local function clampBankBox()
      local n = #loadStorage().boxes
      state.bankBox = math.max(1, math.min(n, state.bankBox))
    end

    local function currentList()
      clampBankBox()
      return state.view == "bank" and loadStorage().boxes[state.bankBox] or cart.mons
    end

    local function viewTitle()
      return state.view == "bank" and Strings("BANK BOX %d", state.bankBox) or "SEND"
    end

    local rebuild
    rebuild = function()
      local src = currentList()
      local rows = {}
      for i, mon in ipairs(src) do
        rows[#rows + 1] = { label = core.monName(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, {
        noSound = true, rows = 6, wrap = true,
        -- A no longer moves the mon on the spot -- action + STATS + CANCEL,
        -- mirroring Pokemon.lua's own monSubmenu, so a highlighted mon can
        -- be checked before committing it either way.
        onChoose = function(item)
          local mon = src[item.value]
          if not mon then return end
          local action = state.view == "bank" and "SEND" or "TAKE BACK"
          game.stack:push(Menu.new(game, {
            { label = action, onSelect = function()
                if state.view == "bank" then
                  local moved = Pokemon.withdrawMon(state.bankBox, item.value)
                  if moved then
                    table.insert(cart.mons, moved)
                    playSound(game, "Withdraw_Deposit")
                  end
                else
                  local moved = table.remove(cart.mons, item.value)
                  if moved then
                    Pokemon.depositMon(moved)
                    playSound(game, "Withdraw_Deposit")
                  end
                end
                rebuild()
              end },
            { label = "STATS", keepOpen = true, onSelect = function() core.openSummary(game, mon) end },
            { label = "CANCEL" },
          }, { tx = 9, ty = 10, tw = 11, th = 8, noSound = true }))
        end,
      })
      attachLevelIcons(list, src, 0)
      list.footer = "SELECT: " .. (state.view == "bank" and "SEND" or "BANK")
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        state.view = state.view == "bank" and "cart" or "bank"
        rebuild()
        return
      elseif input:wasPressed("left") and state.view == "bank" then
        local n = #loadStorage().boxes
        state.bankBox = ((state.bankBox - 2) % n) + 1
        rebuild()
        return
      elseif input:wasPressed("right") and state.view == "bank" then
        local n = #loadStorage().boxes
        state.bankBox = (state.bankBox % n) + 1
        rebuild()
        return
      elseif input:wasPressed("b") then
        game.stack:pop()
        return
      end
      list:update(dt)
    end
    function screen:draw() list:draw() end

    rebuild()
    game.stack:push(screen)
  end

  local function openCartCountPicker(self, opts)
    local game = self.game
    local state = { view = "bank" }
    local screen = { isOpaque = true }
    local list

    local function counts()
      return state.view == "bank" and opts.getBankCounts() or opts.cartCounts
    end

    local rebuild
    rebuild = function()
      local c = counts()
      local rows = {}
      for _, id in ipairs(core.sortedIdsByName(opts.nameFn, c)) do
        local qty = c[id]
        if qty and qty > 0 then
          rows[#rows + 1] = { value = id, label = truncateName(opts.nameFn(id)), right = "x" .. qty }
        end
      end
      list = ListMenu.new(game, opts.title .. " (" .. (state.view == "bank" and "BANK" or "SEND") .. ")", rows, {
        noSound = true, wrap = true,
        onChoose = function(item)
          local have = counts()[item.value] or 0
          if have <= 0 then return end
          core.askQuantity(game, list, have, function(qty)
            if not qty then return end
            if state.view == "bank" then
              if opts.withdraw(item.value, qty) then
                opts.cartCounts[item.value] = (opts.cartCounts[item.value] or 0) + qty
                playSound(game, "Withdraw_Deposit")
                rebuild()
              end
            else
              local ok = opts.deposit(item.value, qty)
              if ok then
                opts.cartCounts[item.value] = opts.cartCounts[item.value] - qty
                if opts.cartCounts[item.value] <= 0 then opts.cartCounts[item.value] = nil end
                playSound(game, "Withdraw_Deposit")
                rebuild()
              else
                list.footer = "Can't take that\nback right now."
              end
            end
          end)
        end,
      })
      list.footer = "SELECT: " .. (state.view == "bank" and "SEND" or "BANK")
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        state.view = state.view == "bank" and "cart" or "bank"
        rebuild()
        return
      elseif input:wasPressed("b") then
        game.stack:pop()
        return
      end
      list:update(dt)
    end
    function screen:draw() list:draw() end

    rebuild()
    game.stack:push(screen)
  end

  local function openSendMoneyMenu(self)
    local game = self.game
    local cart = self.cart.send
    local rows = {
      { label = "SEND MONEY", keepOpen = true, onSelect = function()
          local have = mod.exports.bankMoney()
          if have <= 0 then message(game, "There's no\nmoney in the BANK!") return end
          game.stack:push(Money.AmountBox.new(game, {
            max = have, wallet = cart.money, bank = have,
            walletLabel = "SEND", bankLabel = "BANK", title = "SEND MONEY",
            onDone = function(amount)
              if not amount then return end
              mod.exports.withdrawMoney(amount)
              cart.money = cart.money + amount
              playSound(game, "Withdraw_Deposit")
            end,
          }))
        end },
      { label = "TAKE BACK", keepOpen = true, onSelect = function()
          local have = cart.money
          if have <= 0 then message(game, "You haven't set\nany money aside.") return end
          game.stack:push(Money.AmountBox.new(game, {
            max = have, wallet = have, bank = mod.exports.bankMoney(),
            walletLabel = "SEND", bankLabel = "BANK", title = "TAKE BACK",
            onDone = function(amount)
              if not amount then return end
              cart.money = cart.money - amount
              mod.exports.depositMoney(amount)
              playSound(game, "Withdraw_Deposit")
            end,
          }))
        end },
      { label = "CANCEL" },
    }
    game.stack:push(Menu.new(game, rows, { tx = 0, ty = 0, tw = 13, th = #rows * 2 + 2, noSound = true }))
  end

  local function openSendConfirm(self)
    openConfirmScreen(self, {
      title = "SENDING",
      lines = cartSummaryLines(self.cart.send),
      onConfirm = function() self:enterWaitReady() end,
      onBack = function() self:openSendMenu() end,
    })
  end

  local function openReceivePokemonList(self)
    local game = self.game
    local mons = self.cart.receive.mons
    local rows = {}
    for i, mon in ipairs(mons) do rows[#rows + 1] = { label = core.monName(game, mon), value = i } end
    local list = ListMenu.new(game, "RECEIVING", rows, {
      noSound = true, rows = 6, wrap = true,
      onChoose = function(item)
        local mon = mons[item.value]
        if mon then core.openSummary(game, mon) end
      end,
    })
    attachLevelIcons(list, mons, 0)
    game.stack:push(list)
  end

  local function openReadOnlyCounts(self, title, counts, nameFn)
    local game = self.game
    local rows = {}
    for _, id in ipairs(core.sortedIdsByName(nameFn, counts)) do
      local qty = counts[id]
      if qty and qty > 0 then
        rows[#rows + 1] = { value = id, label = truncateName(nameFn(id)), right = "x" .. qty }
      end
    end
    game.stack:push(ListMenu.new(game, title, rows, { noSound = true, wrap = true }))
  end

  -- Same idea as lib/Lost.lua's own VIEW LOST, reading the RECEIVE cart's own orphaned bucket (receiveOffer below) instead of the Bank's.
  local LOST_VIEWS = { "pokemon", "items", "moves" }
  local LOST_VIEW_TITLE = { pokemon = "LOST PKMN", items = "LOST ITEMS", moves = "LOST MOVES" }

  local function openReceiveLostScreen(self)
    local game = self.game
    local orphaned = self.cart.receive.orphaned
    local state = { view = "pokemon" }
    local screen = { isOpaque = true }
    local list

    local function nextView()
      local idx = 1
      for i, v in ipairs(LOST_VIEWS) do if v == state.view then idx = i break end end
      return LOST_VIEWS[(idx % #LOST_VIEWS) + 1]
    end

    local function idRows(map)
      local ids = {}
      for id in pairs(map) do ids[#ids + 1] = id end
      table.sort(ids)
      local rows = {}
      for _, id in ipairs(ids) do
        rows[#rows + 1] = { label = truncateName(id), right = "x" .. tostring(map[id]) }
      end
      return rows
    end

    local rebuild
    rebuild = function()
      if state.view == "pokemon" then
        local rows, mons = {}, {}
        for _, mon in ipairs(orphaned.mons) do
          rows[#rows + 1] = { label = monName(game, mon) }
          mons[#mons + 1] = mon
        end
        list = ListMenu.new(game, LOST_VIEW_TITLE.pokemon, rows, { noSound = true, wrap = true })
        attachLevelIcons(list, mons, 0)
      elseif state.view == "items" then
        list = ListMenu.new(game, LOST_VIEW_TITLE.items, idRows(orphaned.items), { noSound = true, wrap = true })
      else
        list = ListMenu.new(game, LOST_VIEW_TITLE.moves, idRows(orphaned.moves), { noSound = true, wrap = true })
      end
      list.footer = "SELECT: " .. LOST_VIEW_TITLE[nextView()]
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        state.view = nextView()
        rebuild()
        return
      elseif input:wasPressed("b") then
        game.stack:pop()
        return
      end
      list:update(dt)
    end
    function screen:draw() list:draw() end

    rebuild()
    game.stack:push(screen)
  end

  local function openReceiveConfirm(self)
    openConfirmScreen(self, {
      title = "RECEIVING",
      lines = cartSummaryLines(self.cart.receive),
      onConfirm = function() self:enterWaitCommit() end,
      onBack = function() self:openReceiveMenu() end,
    })
  end

  local BankLinkState = {}
  BankLinkState.__index = BankLinkState
  BankLinkState.isOpaque = true

  local function ipDigits(ip)
    local digits = {}
    local a, b, c, d = (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    local octets = { tonumber(a) or 192, tonumber(b) or 168, tonumber(c) or 0, tonumber(d) or 1 }
    for _, o in ipairs(octets) do
      o = math.min(255, o)
      table.insert(digits, math.floor(o / 100))
      table.insert(digits, math.floor(o / 10) % 10)
      table.insert(digits, o % 10)
    end
    return digits
  end

  local function openSession(role, connect)
    local transport = Net.new()
    if connect(transport) then
      return Session.new(transport, { role = role, kind = "bank_link" })
    end
    local detail = transport.error or "?"
    transport:close()
    return nil, detail
  end

  function BankLinkState.new(game)
    local self = setmetatable({}, BankLinkState)
    self.game = game
    self.stage = "mode"
    self.index = 1
    self.addr = ipDigits(Net.lanIP())
    self.addrPos = 12
    self.cart = { send = freshCart(), receive = freshCart() }
    self.readySent = false
    self.peerReady = false
    self.peerCommitted = false
    return self
  end

  function BankLinkState:refundSend()
    local game = self.game
    local send = self.cart.send
    for _, mon in ipairs(send.mons) do
      if type(mon) == "table" then Pokemon.depositMon(mon) end
    end
    for id, qty in pairs(send.items) do
      if type(qty) == "number" and qty > 0 then depositItemSafe(id, qty, game) end
    end
    for id, qty in pairs(send.moves) do
      if type(qty) == "number" and qty > 0 then mod.exports.depositMove(id, qty) end
    end
    if send.money and send.money > 0 then mod.exports.depositMoney(send.money) end
    self.cart.send = freshCart()
    self.cart.receive = freshCart()
  end

  function BankLinkState:finish(text)
    if self.net then
      pcall(function() self.net:send({ type = "bank_bye" }) end)
      self.net:close()
    end
    self.game.stack:pop()
    if text then message(self.game, text) end
  end

  function BankLinkState:abort(text)
    self:refundSend()
    mod.events:emit("mod.vrm_pokemon_bank.link_cancelled", {})
    self:finish(text or "The transfer was\ncancelled.")
  end

  function BankLinkState:enterHelloWait()
    self.net:send({ type = "bank_hello", version = LINK_VERSION, storageVersion = core.STORAGE_VERSION })
    self.stage = "helloWait"
    self.helloElapsed = 0
  end

  -- The mod's own manifest version isn't checked here: a change anywhere
  -- else in the mod (a different tab, an unrelated fix) bumps it too, and
  -- would refuse a link between two installs whose LINK code and storage
  -- shape actually agree. What a mismatch would actually break is either
  -- the message shapes on the wire (LINK_VERSION) or the mon/item/move
  -- shape a received parcel gets deposited in (STORAGE_VERSION, storage.lua
  -- -- see main.lua) -- those are the two things checked instead.
  function BankLinkState:checkHello()
    if tonumber(self.peerHello.version) ~= LINK_VERSION then
      self:abort("The other player's\nLINK version\ndoesn't match.")
    elseif tonumber(self.peerHello.storageVersion) ~= core.STORAGE_VERSION then
      self:abort("Both players need\nthe same BANK\ndata version.")
    else
      self.stage = "sendMenu"
      self:openSendMenu()
    end
  end

  function BankLinkState:openSendMenu()
    local rows = {
      { label = "POKéMON", keepOpen = true, onSelect = function() openSendPokemonPicker(self) end },
      { label = "ITEMS", keepOpen = true, onSelect = function()
          local game = self.game
          openCartCountPicker(self, {
            title = "ITEMS",
            getBankCounts = function() return loadStorage().items end,
            cartCounts = self.cart.send.items,
            withdraw = function(id, qty) return (mod.exports.withdrawItem(id, qty)) end,
            deposit = function(id, qty) return (mod.exports.depositItem(id, qty, game)) end,
            nameFn = function(id) return core.itemName(game, id) end,
          })
        end },
      { label = "MOVES", keepOpen = true, onSelect = function()
          local game = self.game
          openCartCountPicker(self, {
            title = "MOVES",
            getBankCounts = function() return loadStorage().moves end,
            cartCounts = self.cart.send.moves,
            withdraw = function(id, qty) return (mod.exports.withdrawMove(id, qty)) end,
            deposit = function(id, qty) return (mod.exports.depositMove(id, qty)) end,
            nameFn = function(id) return core.moveName(game, id) end,
          })
        end },
      { label = "MONEY", keepOpen = true, onSelect = function() openSendMoneyMenu(self) end },
      { label = "CONFIRM", onSelect = function() openSendConfirm(self) end },
      { label = "CANCEL", onSelect = function() confirmCancel(self, function() self:openSendMenu() end) end },
    }
    self.game.stack:push(Menu.new(self.game, rows, {
      tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true,
      onCancel = function() confirmCancel(self, function() self:openSendMenu() end) end,
    }))
  end

  function BankLinkState:enterWaitReady()
    self.readySent = true
    self.net:send({ type = "bank_ready" })
    self.stage = "waitReady"
  end

  function BankLinkState:sendOffer()
    local send = self.cart.send
    self.net:send({ type = "bank_offer", mons = send.mons, items = send.items, moves = send.moves, money = send.money })
    self.net:update()
    self.stage = "waitOffer"
  end

  function BankLinkState:receiveOffer(offer)
    local game = self.game
    local receive = freshCart()
    for _, mon in ipairs(type(offer.mons) == "table" and offer.mons or {}) do
      if type(mon) == "table" and mod.exports.isValidPokemon(mon, game) then
        table.insert(receive.mons, mon)
      elseif type(mon) == "table" then
        table.insert(receive.orphaned.mons, mon)
      end
    end
    for id, qty in pairs(type(offer.items) == "table" and offer.items or {}) do
      qty = math.floor(tonumber(qty) or 0)
      if qty > 0 then
        if mod.exports.isValidItem(id, game) and not mod.exports.isBlacklisted(id, game) then
          receive.items[id] = qty
        else
          receive.orphaned.items[id] = qty
        end
      end
    end
    for id, qty in pairs(type(offer.moves) == "table" and offer.moves or {}) do
      qty = math.floor(tonumber(qty) or 0)
      if qty > 0 then
        if game.data.moves and game.data.moves[id] then
          receive.moves[id] = qty
        else
          receive.orphaned.moves[id] = qty
        end
      end
    end
    receive.money = math.max(0, math.floor(tonumber(offer.money) or 0))
    self.cart.receive = receive
  end

  function BankLinkState:openReceiveMenu()
    local link = self
    local game = self.game
    local rows = {
      { label = "POKéMON", keepOpen = true, onSelect = function() openReceivePokemonList(link) end },
      { label = "ITEMS", keepOpen = true, onSelect = function()
          openReadOnlyCounts(link, "RECEIVING", link.cart.receive.items,
            function(id) return core.itemName(game, id) end)
        end },
      { label = "MOVES", keepOpen = true, onSelect = function()
          openReadOnlyCounts(link, "RECEIVING", link.cart.receive.moves,
            function(id) return core.moveName(game, id) end)
        end },
      { label = "MONEY", keepOpen = true, onSelect = function()
          message(game, Strings("You will receive\n¥%d.", link.cart.receive.money))
        end },
      { label = "LOST", keepOpen = true, onSelect = function() openReceiveLostScreen(link) end },
      { label = "CONFIRM", onSelect = function() openReceiveConfirm(link) end },
      { label = "CANCEL", onSelect = function() confirmCancelOrBack(link) end },
    }
    local menu = Menu.new(game, rows, {
      tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true,
      onCancel = function() confirmCancelOrBack(link) end,
    })
    local screen = {}
    screen.update = function(_, dt)
      if link:pollForPeerRestart() then return end
      menu:update(dt)
    end
    screen.draw = function() menu:draw() end
    game.stack:push(screen)
  end

  function BankLinkState:pollForPeerRestart()
    if not self.net then return false end
    self.net:update()
    self:pollNet()
    if self.peerRestart then
      self.peerRestart = false
      self.game.stack:pop()
      self:goBackToSend()
      return true
    end
    return false
  end

  function BankLinkState:goBackToSend()
    self.readySent = false
    self.peerReady = false
    self.peerOffer = nil
    self.peerCommitted = false
    self.cart.receive = freshCart()
    self.stage = "sendMenu"
    self:openSendMenu()
  end

  function BankLinkState:requestBack()
    self.net:send({ type = "bank_restart" })
    self.net:update()
    self:goBackToSend()
  end

  function BankLinkState:enterWaitCommit()
    self.net:send({ type = "bank_commit" })
    self.stage = "waitCommit"
  end

  function BankLinkState:applyReceived()
    local game = self.game
    local sent = self.cart.send
    local received = self.cart.receive
    -- Counted before the carts reset below -- link_completed's payload for Stats to tally without duplicating this summing.
    local sentCounts, receivedCounts = cartCounts(sent), cartCounts(received)
    for _, mon in ipairs(received.mons) do
      if type(mon) == "table" then Pokemon.depositMon(mon) end
    end
    for id, qty in pairs(received.items) do
      if type(qty) == "number" and qty > 0 then depositItemSafe(id, qty, game) end
    end
    for id, qty in pairs(received.moves) do
      if type(qty) == "number" and qty > 0 then mod.exports.depositMove(id, qty) end
    end
    if received.money and received.money > 0 then mod.exports.depositMoney(received.money) end
    if orphanedCount(received.orphaned) > 0 then
      local bankOrphaned = core.ensureOrphaned(loadStorage())
      for _, mon in ipairs(received.orphaned.mons) do
        table.insert(bankOrphaned.mons, mon)
      end
      for id, qty in pairs(received.orphaned.items) do
        bankOrphaned.items[id] = (bankOrphaned.items[id] or 0) + qty
      end
      for id, qty in pairs(received.orphaned.moves) do
        bankOrphaned.moves[id] = (bankOrphaned.moves[id] or 0) + qty
      end
      core.markDirty()
    end
    self.cart.send = freshCart()
    self.cart.receive = freshCart()
    if mod.exports.validateStorage then mod.exports.validateStorage(game) end
    if game.writeSave then game:writeSave() end
    core.playSaveSound(game)
    mod.events:emit("mod.vrm_pokemon_bank.link_completed", { sent = sentCounts, received = receivedCounts })
    self:finish("The transfer is\ncomplete!")
  end

  function BankLinkState:pollNet()
    for _, msg in ipairs(self.net:poll()) do
      if msg.type == "bank_bye" then
        self.peerBye = true
      elseif msg.type == "bank_hello" and not self.peerHello then
        self.peerHello = msg
      elseif msg.type == "bank_ready" then
        self.peerReady = true
      elseif msg.type == "bank_unready" then
        self.peerReady = false
      elseif msg.type == "bank_offer" and not self.peerOffer then
        self.peerOffer = msg
      elseif msg.type == "bank_commit" then
        self.peerCommitted = true
      elseif msg.type == "bank_uncommit" then
        self.peerCommitted = false
      elseif msg.type == "bank_restart" then
        self.peerRestart = true
      end
    end
  end

  function BankLinkState:update(dt)
    local input = self.game.input
    if self.net then
      self.net:update()
      self:pollNet()
      if self.stage == "helloWait" and self.peerHello then
        self:checkHello()
        return
      end
      if not self.peerCommitted then
        if self.peerRestart then
          self.peerRestart = false
          self:goBackToSend()
          return
        end
        if self.peerBye then
          self:abort("The other player\ndisconnected.")
          return
        end
        local status = self.net:getStatus()
        if status == "failed" then
          local _, detail = self.net:getFailure()
          self:abort(Strings("LINK error:\n%s", (detail or "?"):sub(1, 60)))
          return
        elseif status == "closed" then
          self:abort("The link was\nbroken.")
          return
        end
      end
    end

    if self.stage == "mode" then
      if input:wasPressed("up") or input:wasPressed("down") then
        self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      elseif input:wasPressed("a") then
        self.online = self.index ~= 1
        self.stage = self.index == 1 and "lanMenu" or "onlineMenu"
        self.index = 1
      end

    elseif self.stage == "lanMenu" then
      if input:wasPressed("up") or input:wasPressed("down") then
        self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then
        self.stage = "mode"
        self.index = 1
      elseif input:wasPressed("a") then
        if self.index == 1 then
          local net, detail = openSession("host", function(t) return t:host() end)
          if net then
            self.net = net
            self.stage = "hosting"
          else
            message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60)))
          end
        else
          self.stage = "addrEntry"
        end
      end

    elseif self.stage == "hosting" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      if self.net.paired then self:enterHelloWait() end

    elseif self.stage == "onlineMenu" then
      if input:wasPressed("up") or input:wasPressed("down") then
        self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then
        self.stage = "mode"
        self.index = 2
      elseif input:wasPressed("a") then
        if self.index == 1 then
          local net, detail = openSession("host", function(t) return t:hostOnline() end)
          if net then
            self.net = net
            self.stage = "onlineHosting"
          else
            message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60)))
          end
        else
          self.stage = "codeEntry"
          self.codeEntry = CodeEntry.new()
        end
      end

    elseif self.stage == "onlineHosting" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      if self.net.paired then self:enterHelloWait() end

    elseif self.stage == "codeEntry" then
      if input:wasPressed("b") then
        self.stage = "onlineMenu"
        self.index = 2
      elseif input:wasPressed("up") then
        CodeEntry.up(self.codeEntry)
      elseif input:wasPressed("down") then
        CodeEntry.down(self.codeEntry)
      elseif input:wasPressed("left") then
        CodeEntry.left(self.codeEntry)
      elseif input:wasPressed("right") then
        CodeEntry.right(self.codeEntry)
      elseif input:wasPressed("a") then
        local code = CodeEntry.text(self.codeEntry)
        local net, detail = openSession("guest", function(t) return t:joinOnline(nil, code) end)
        if net then
          self.net = net
          self.stage = "onlineJoining"
        else
          message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60)))
        end
      end

    elseif self.stage == "onlineJoining" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      if self.net.paired then self:enterHelloWait() end

    elseif self.stage == "addrEntry" then
      if input:wasPressed("b") then
        self.stage = "lanMenu"
      elseif input:wasPressed("up") then
        self.addr[self.addrPos] = (self.addr[self.addrPos] + 1) % 10
      elseif input:wasPressed("down") then
        self.addr[self.addrPos] = (self.addr[self.addrPos] - 1) % 10
      elseif input:wasPressed("left") then
        self.addrPos = math.max(1, self.addrPos - 1)
      elseif input:wasPressed("right") then
        self.addrPos = math.min(12, self.addrPos + 1)
      elseif input:wasPressed("a") then
        local octets = {}
        for i = 1, 4 do
          local base = (i - 1) * 3
          octets[i] = math.min(255, self.addr[base + 1] * 100
                                    + self.addr[base + 2] * 10 + self.addr[base + 3])
        end
        local address = table.concat(octets, ".")
        local net, detail = openSession("guest", function(t) return t:join(address) end)
        if net then
          self.net = net
          self.stage = "joining"
        else
          message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60)))
        end
      end

    elseif self.stage == "joining" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      if self.net.paired then self:enterHelloWait() end

    elseif self.stage == "helloWait" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      self.helloElapsed = self.helloElapsed + dt
      if self.helloElapsed > 4 then
        self:abort("The other player\ndoesn't have LINK\ninstalled.")
      end

    elseif self.stage == "waitReady" then
      if input:wasPressed("b") then
        self.net:send({ type = "bank_unready" })
        self.readySent = false
        self.stage = "sendMenu"
        self:openSendMenu()
        return
      end
      if self.readySent and self.peerReady then self:sendOffer() end
      if self.peerOffer then
        self:receiveOffer(self.peerOffer)
        self.peerOffer = nil
        self.stage = "receiveMenu"
        self:openReceiveMenu()
      end

    elseif self.stage == "waitOffer" then
      if input:wasPressed("b") then
        self:abort()
        return
      end
      if self.peerOffer then
        self:receiveOffer(self.peerOffer)
        self.peerOffer = nil
        self.stage = "receiveMenu"
        self:openReceiveMenu()
      end

    elseif self.stage == "waitCommit" then
      if self.peerCommitted then
        self:applyReceived()
      elseif input:wasPressed("b") then
        self.net:send({ type = "bank_uncommit" })
        self.stage = "receiveMenu"
        self:openReceiveMenu()
      end
    end
  end

  local function headerText(self)
    if self.stage == "mode" then return "LINK" end
    return self.online and "LINK (ONLINE)" or "LINK (LAN)"
  end

  function BankLinkState:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(headerText(self), 8, 6)

    if self.stage == "mode" then
      Font.draw(Strings("LAN"), 32, 44)
      Font.draw(Strings("ONLINE"), 32, 60)
      Font.drawCode(CURSOR, 24, 44 + (self.index - 1) * 16)
    elseif self.stage == "lanMenu" then
      Font.draw(Strings("HOST"), 32, 44)
      Font.draw(Strings("JOIN"), 32, 60)
      Font.drawCode(CURSOR, 24, 44 + (self.index - 1) * 16)
    elseif self.stage == "hosting" then
      Font.draw(Strings("Friend joins at:"), 8, 40)
      Font.draw(self.net.address or "?", 8, 52)
      Font.draw(Strings("Waiting for join..."), 8, 76)
    elseif self.stage == "addrEntry" then
      for i = 1, 12 do
        local octet = math.floor((i - 1) / 3)
        local x = 8 + (i - 1) * 8 + octet * 8
        Font.draw(tostring(self.addr[i]), x, 48)
        if i == self.addrPos then Font.drawCode(0xEE, x, 60) end
      end
      for octet = 1, 3 do Font.draw(".", 8 + octet * 32 - 8, 48) end
      Font.draw(Strings("Port: %s", Net.defaultPort()), 8, 76)
      Font.draw(Strings("A: connect  B: back"), 8, 128)
    elseif self.stage == "joining" then
      Font.draw(Strings("Calling..."), 8, 40)
      Font.draw(self.net.target or "", 8, 52)
    elseif self.stage == "onlineMenu" then
      Font.draw(Strings("HOST ONLINE"), 32, 44)
      Font.draw(Strings("JOIN ONLINE"), 32, 60)
      Font.drawCode(CURSOR, 24, 44 + (self.index - 1) * 16)
    elseif self.stage == "onlineHosting" then
      Font.draw(Strings("Tell your friend"), 8, 40)
      Font.draw(Strings("the code:"), 8, 52)
      Font.draw(self.net.code or "??????", 8, 68)
      Font.draw(Strings("Waiting for join..."), 8, 92)
    elseif self.stage == "codeEntry" then
      for i = 1, CodeEntry.LENGTH do
        local x = 8 + (i - 1) * 16
        local ch = CodeEntry.CHARSET:sub(self.codeEntry.chars[i], self.codeEntry.chars[i])
        Font.draw(ch, x, 48)
        if i == self.codeEntry.pos then Font.drawCode(0xEE, x, 60) end
      end
      Font.draw(Strings("A: connect  B: back"), 8, 128)
    elseif self.stage == "onlineJoining" then
      Font.draw(Strings("Calling..."), 8, 40)
      Font.draw(self.net.target or "", 8, 52)
    elseif self.stage == "helloWait" then
      Font.draw(Strings("Checking the"), 8, 40)
      Font.draw(Strings("other BANK..."), 8, 52)
    elseif self.stage == "sendMenu" then
      local sendText = Strings("STEP 2: SEND")
      Font.draw(sendText, 160 - 8 - Font.width(sendText), 20)
    elseif self.stage == "waitReady" then
      Font.draw(Strings("Waiting for the"), 8, 40)
      Font.draw(Strings("other player..."), 8, 52)
      Font.draw(Strings("B: edit again"), 8, 128)
    elseif self.stage == "waitOffer" then
      Font.draw(Strings("Exchanging data..."), 8, 40)
    elseif self.stage == "receiveMenu" then
      local receiveText = Strings("STEP 3: RECEIVE")
      Font.draw(receiveText, 160 - 8 - Font.width(receiveText), 20)
    elseif self.stage == "waitCommit" then
      Font.draw(Strings("Waiting for the"), 8, 40)
      Font.draw(Strings("other player..."), 8, 52)
      Font.draw(Strings("B: edit again"), 8, 128)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local linkTab = core.makeTabToggle("show_link_tab")

  local function open(game)
    if not game then return nil, "no game" end
    game.stack:push(BankLinkState.new(game))
    return true
  end

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.openLinkMenu = open
  mod.exports.linkScreenId = SCREEN_ID
  mod.exports.setLinkTabEnabled = linkTab.setEnabled
  mod.exports.isLinkTabEnabled = linkTab.enabled

  mod.log:info("Pokemon Bank: Link tab ready")

  return {
    screenId = SCREEN_ID,
    tabEnabled = linkTab.enabled,
    open = open,
  }
end

return Module
