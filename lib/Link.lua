local V = ...

local Widgets = V.require("Widgets")
local Menu = Widgets.Menu
local TextBox = V.require("Widgets").TextBox
local Net = require("src.link.Net")
local Json = require("src.link.Json")
local Session = require("src.link.Session")
local CodeEntry = require("src.link.CodeEntry")

local SCREEN_ID = "PokemonBankLink"
local CURSOR = 0xED

-- Bumped when the wire message shapes change; a mismatch refuses the link outright.
local LINK_VERSION = 8
-- How often the side that's just sitting on "Waiting for the other player..." pokes the connection
local WAIT_PING_INTERVAL = 2
-- Gen 1/2's SEND sidebar fits 8 characters per row (label, a space and the value).
local SIDEBAR_CHARS = 8

local Module = {}

function Module.install(mod, core, Pokemon, Items, Money, Coins)
  local Link = { screenId = SCREEN_ID }
  local loadStorage = core.loadStorage
  local message = core.message
  local playSound = core.playSound
  local function withCounter(list)
    local origDraw = list.draw
    function list:draw()
      origDraw(self)
      core.drawListTitle(self)
      core.drawListCounter(self)
    end
    return list
  end

  local LE = core.LinkEntries

  local Strings = require("src.core.Strings")
  local Font = require("src.render.Font")

  do
    local hooks = core.storageHooks
    local function boxIndexOf(id)
      for i, box in ipairs(loadStorage().entries.boxes) do
        if box.id == id then return i end
      end
    end
    local function selectLine(nextLabel) return nextLabel and ("SELECT: " .. nextLabel) or nil end

    hooks["pokemon.isValid"] = function(game, mon) return type(mon) == "table" and mod.exports.isValidPokemon(mon, game) end

    hooks["pokemon.prepare"] = function(game, mon, sender)
      if mon.originStorageId == nil then mon.originStorageId = sender.storageId end
      mod.exports.reshapeForActiveGame(game, mon)
      return mon
    end

    hooks["boxes.poolLabel"] = function(_, _, index) return core.boxLabel(loadStorage(), index) end

    hooks["boxes.currentPool"] = function()
      local box = loadStorage().entries.boxes[core.currentBox()]
      return box and box.id
    end

    hooks["boxes.withdraw"] = function(_, poolId, index)
      local boxNum = boxIndexOf(poolId)
      return boxNum and Pokemon.withdrawMon(boxNum, index) or nil
    end

    hooks["boxes.deposit"] = function(game, _, _, mon) return Pokemon.depositMon(mon, game) ~= nil end

    hooks["items.isValid"] = function(game, id) return mod.exports.isValidItem(id, game) and not mod.exports.isBlacklisted(id, game) end

    hooks["items.nameOf"] = function(game, id) return core.itemName(game, id) end

    hooks["items.footer"] = function(game, id, nextLabel)
      local detail, line = core.itemDescriptionText(game, id), selectLine(nextLabel)
      if not line then return detail end
      return (detail or "") .. "\n" .. line
    end

    hooks["moves.isValid"] = function(game, id) return game.data.moves ~= nil and game.data.moves[id] ~= nil end

    hooks["moves.nameOf"] = function(game, id) return core.moveName(game, id) end

    hooks["moves.footer"] = function(game, id, nextLabel)
      local line1, pp, line = core.moveDetailLine(game, id), core.movePpText(game, id), selectLine(nextLabel)
      local line2 = (line and pp) and core.padToRight(line, pp) or (line or pp)
      if not line2 then return line1 end
      return (line1 or "") .. "\n" .. line2
    end
  end

  local function bankPool(d, poolId, game)
    for _, p in ipairs(LE.pools(d, game)) do
      if p.id == poolId then return p end
    end
  end

  local function bankPages(d, game)
    if not d.multi then return nil end
    local pages = {}
    for _, p in ipairs(LE.pools(d, game)) do pages[#pages + 1] = { id = p.id, label = p.label } end
    return pages
  end

  local function isPokemon(d) return d.link.pokemon == true end

  local function rowFooter(game, d, value, nextLabel)
    local text = value ~= nil and LE.footer(game, d, value, nextLabel)
    if text then return text end
    local line = nextLabel and ("SELECT: " .. nextLabel) or nil
    if isPokemon(d) and type(value) == "table" then return core.monName(game, value) .. "\n" .. (line or "") end
    return line
  end

  local function listRows(game, d, elements, valueOf)
    local rows, mons = {}, {}
    for i, element in ipairs(elements) do
      rows[#rows + 1] = { label = LE.labelOf(game, d, element), value = valueOf(i) }
      mons[#mons + 1] = element
    end
    return rows, isPokemon(d) and mons or nil
  end

  local function cartRows(game, d, cart)
    local rows, mons = {}, {}
    for _, pool in ipairs(LE.cartPools(cart, d)) do
      if d.kind == "list" then
        for i, element in ipairs(pool.data) do
          rows[#rows + 1] = { label = LE.labelOf(game, d, element), value = { poolId = pool.id, ref = i } }
          mons[#mons + 1] = element
        end
      else
        for _, id in ipairs(core.sortedIdsByName(function(x) return LE.nameOf(game, d, x) end, pool.data)) do
          rows[#rows + 1] = { label = core.truncateName(LE.nameOf(game, d, id)), right = "x" .. pool.data[id], value = { poolId = pool.id, ref = id } }
        end
      end
    end
    return rows, isPokemon(d) and mons or nil
  end

  local function bankRows(game, d, pool)
    if not pool then return {}, nil end
    if d.kind == "list" then return listRows(game, d, pool.data, function(i) return i end) end
    local rows = {}
    for _, id in ipairs(core.sortedIdsByName(function(x) return LE.nameOf(game, d, x) end, pool.data)) do
      rows[#rows + 1] = { label = core.truncateName(LE.nameOf(game, d, id)), right = "x" .. pool.data[id], value = id }
    end
    return rows
  end

  local LIST_OPTS = { messageBox = true, noSound = true, wrap = true }

  local function statsAction(elementOf)
    return { label = "STATS", keepOpen = true, onSelect = function(game, pageId, value)
      local mon = elementOf(game, pageId, value)
      if mon then core.openSummary(game, mon) end
    end }
  end

  local function listContainers(self, d)
    local game, cart = self.game, self.cart.send
    local pending
    local function bankElement(_, pageId, index)
      local pool = bankPool(d, pageId or LE.IMPLICIT, game)
      return pool and pool.data[index]
    end
    local function cartElement(_, _, row)
      local data = row and LE.cartPool(cart, d, row.poolId)
      return data and data[row.ref]
    end
    local bank = {
      id = "bank", label = "BANK", transferLabel = "SEND", canTransfer = true,
      getPages = d.multi and function(g) return bankPages(d, g) end or nil,
      getRememberedPage = d.multi and function(g) return LE.currentPool(d, g) end or nil,
      setRememberedPage = d.multi and function() end or nil,
      build = function(g, pageId)
        local rows, mons = bankRows(g, d, bankPool(d, pageId or LE.IMPLICIT, g))
        return rows, LIST_OPTS, mons
      end,
      dynamicFooter = function(g, pageId, index, nextLabel) return rowFooter(g, d, bankElement(g, pageId, index), nextLabel) end,
      withdraw = function(_, pageId, index)
        local element = LE.bankTake(game, d, pageId, index)
        if element == nil then return false end
        pending = { element = element, poolId = pageId or LE.IMPLICIT }
        return true
      end,
      deposit = function()
        if LE.bankPut(game, d, pending.poolId, nil, pending.element) then
          LE.pruneCart(cart, d)
          playSound(game, "Withdraw_Deposit")
        else
          LE.put("list", LE.cartPool(cart, d, pending.poolId, true), nil, pending.element)
          message(game, "It can't go back\nright now.")
        end
        pending = nil
      end,
      onAction = isPokemon(d) and { statsAction(bankElement) } or nil,
    }
    local send = {
      id = "send", label = "SEND", transferLabel = "TAKE BACK", canTransfer = true,
      build = function(g)
        local rows, mons = cartRows(g, d, cart)
        return rows, LIST_OPTS, mons
      end,
      dynamicFooter = function(g, pageId, row, nextLabel) return rowFooter(g, d, cartElement(g, pageId, row), nextLabel) end,
      withdraw = function(_, _, row)
        local data = LE.cartPool(cart, d, row.poolId)
        local element = data and LE.take("list", data, row.ref)
        if element == nil then return false end
        pending = { element = element, poolId = row.poolId }
        return true
      end,
      deposit = function()
        LE.put("list", LE.cartPool(cart, d, pending.poolId, true), nil, pending.element)
        pending = nil
        playSound(game, "Withdraw_Deposit")
      end,
      onAction = isPokemon(d) and { statsAction(cartElement) } or nil,
    }
    return { bank, send }
  end

  local function mapContainers(self, d)
    local game, cart = self.game, self.cart.send

    local function bankToCart(pageId, id, qty)
      local taken = LE.bankTake(game, d, pageId, id, qty)
      if not taken then return false end
      LE.put("map", LE.cartPool(cart, d, pageId or LE.IMPLICIT, true), id, taken)
      return true
    end

    local function cartToBank(poolId, id, qty)
      local data = LE.cartPool(cart, d, poolId)
      local taken = data and LE.take("map", data, id, qty)
      if not taken then return false end
      if LE.bankPut(game, d, poolId, id, taken) then
        LE.pruneCart(cart, d)
        return true
      end
      LE.put("map", data, id, taken)
      return false
    end

    local function moveToCart(pageId, id, qty, rebuild)
      if not bankToCart(pageId, id, qty) then return end
      playSound(game, "Withdraw_Deposit")
      rebuild(true)
    end

    local function moveToBank(poolId, id, qty, rebuild)
      if not cartToBank(poolId, id, qty) then
        message(game, "It can't go back\nright now.")
        return
      end
      playSound(game, "Withdraw_Deposit")
      rebuild(true)
    end

    local function bulk(rows, run, verb, resultVerb, rebuild, list)
      core.confirmBulkMoveAll(game, {
        count = #rows, verb = verb, resultVerb = resultVerb, noun = d.label:lower(),
        run = function()
          local moved, refused = 0, 0
          for i = #rows, 1, -1 do
            if run(rows[i].value) then moved = moved + 1 else refused = refused + 1 end
          end
          return moved, refused
        end,
        rebuild = function() rebuild(true) end,
        setFooter = function(msg) list.footer = msg end,
      })
    end

    local bank = {
      id = "bank", label = "BANK",
      getPages = d.multi and function(g) return bankPages(d, g) end or nil,
      getRememberedPage = d.multi and function(g) return LE.currentPool(d, g) end or nil,
      setRememberedPage = d.multi and function() end or nil,
      build = function(g, pageId) return bankRows(g, d, bankPool(d, pageId or LE.IMPLICIT, g)), LIST_OPTS end,
      dynamicFooter = function(g, _, id, nextLabel) return rowFooter(g, d, id, nextLabel) end,
      onAction = { { label = "SEND", keepOpen = true, onSelect = function(_, pageId, id, rebuild, list)
        local pool = bankPool(d, pageId or LE.IMPLICIT, game)
        local have = pool and pool.data[id] or 0
        if have <= 0 then return end
        core.askQuantity(game, list, have, function(qty) if qty then moveToCart(pageId, id, qty, rebuild) end end)
      end } },
      onStart = function(_, pageId, _, rebuild, list)
        local pool = bankPool(d, pageId or LE.IMPLICIT, game)
        bulk(bankRows(game, d, pool), function(id)
          local qty = pool.data[id] or 0
          return qty > 0 and bankToCart(pageId, id, qty)
        end, "Send", "Sent", rebuild, list)
      end,
    }
    local send = {
      id = "send", label = "SEND",
      build = function(g) return cartRows(g, d, cart), LIST_OPTS end,
      dynamicFooter = function(g, _, row, nextLabel) return rowFooter(g, d, row and row.ref, nextLabel) end,
      onAction = { { label = "TAKE BACK", keepOpen = true, onSelect = function(_, _, row, rebuild, list)
        local data = LE.cartPool(cart, d, row.poolId)
        local have = data and data[row.ref] or 0
        if have <= 0 then return end
        core.askQuantity(game, list, have, function(qty) if qty then moveToBank(row.poolId, row.ref, qty, rebuild) end end)
      end } },
      onStart = function(_, _, _, rebuild, list)
        bulk(cartRows(game, d, cart), function(row)
          local data = LE.cartPool(cart, d, row.poolId)
          local qty = data and data[row.ref] or 0
          return qty > 0 and cartToBank(row.poolId, row.ref, qty)
        end, "Take back", "Took back", rebuild, list)
      end,
    }
    return { bank, send }
  end

  local function openSendPicker(self, d)
    local containers = d.kind == "list" and listContainers(self, d) or mapContainers(self, d)
    self.game.stack:push(core.entryScreen(self.game, containers, { counter = true }))
  end

  local function singleText(d, n) return ("%s%d"):format(d.link.prefix or "", n) end

  local function openSingleMenu(self, d)
    local game, cart = self.game, self.cart.send
    local prefix = d.link.prefix or ""
    local label = tostring(d.label):upper()

    local rows = {
      { label = "SEND", keepOpen = true, onSelect = function()
          local have = LE.singleBank(d)
          if have <= 0 then message(game, Strings("There's no %s\nin the BANK!", label)) return end
          game.stack:push(Money.AmountBox.new(game, { max = have, wallet = LE.cartSingle(cart, d), bank = have, title = "SEND " .. label, prefix = prefix, walletLabel = "SEND", bankLabel = "BANK",
            onDone = function(amount)
              if not amount then return end
              local taken = LE.bankTakeSingle(game, d, amount)
              if not taken then return end
              LE.setCartSingle(cart, d, LE.cartSingle(cart, d) + taken)
              playSound(game, "Withdraw_Deposit")
            end }))
        end },
      { label = "TAKE BACK", keepOpen = true, onSelect = function()
          local have = LE.cartSingle(cart, d)
          if have <= 0 then message(game, Strings("You haven't set\nany %s aside.", label)) return end
          game.stack:push(Money.AmountBox.new(game, { max = have, wallet = have, bank = LE.singleBank(d), title = "TAKE BACK", prefix = prefix, walletLabel = "SEND", bankLabel = "BANK",
            onDone = function(amount)
              if not amount then return end
              if LE.bankPutSingle(game, d, amount) then
                LE.setCartSingle(cart, d, LE.cartSingle(cart, d) - amount)
                playSound(game, "Withdraw_Deposit")
              else
                message(game, "It can't go back\nright now.")
              end
            end }))
        end },
      { label = "CANCEL" },
    }
    local menu = Widgets.Menu.new(game, rows, { tx = 0, ty = 0, tw = 13, th = #rows * 2 + 2, noSound = true })
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end
    function screen:draw()
      menu:draw()
      local sendVal = singleText(d, LE.cartSingle(cart, d))
      local bankVal = singleText(d, LE.singleBank(d))
      if Widgets.active() then return Widgets.infoBox({ { "SEND", sendVal }, { "BANK", bankVal } }) end
      local tw, tx = Money.walletBankBoxWidth("SEND", sendVal, "BANK", bankVal)
      local ty = 9
      Font.drawBox(tx, ty, tw, 4)
      love.graphics.setColor(0, 0, 0, 1)
      Money.drawWalletBankRows(tx, ty, "SEND", sendVal, "BANK", bankVal)
      love.graphics.setColor(1, 1, 1, 1)
    end
    game.stack:push(screen)
  end

  local function openReceiveView(self, d)
    local game = self.game
    local received = self.cart.receive
    if d.kind == "single" then
      local n = LE.cartSingle(received, d)
      local text = d.link.prefix and singleText(d, n) or (tostring(n) .. " " .. tostring(d.label):lower())
      message(game, Strings("You will receive\n%s.", text))
      return
    end
    local flat = LE.cartPool(received, d, LE.IMPLICIT) or {}
    local rows, mons
    if d.kind == "list" then
      rows, mons = listRows(game, d, flat, function(i) return i end)
    else
      rows = {}
      for _, id in ipairs(core.sortedIdsByName(function(x) return LE.nameOf(game, d, x) end, flat)) do
        rows[#rows + 1] = { label = core.truncateName(LE.nameOf(game, d, id)), right = "x" .. flat[id], value = id }
      end
    end
    local list = Widgets.listMenu(mod.ui.ListMenu).new(game, "RECEIVING", rows, {
      noSound = true, rows = 6, wrap = true,
      onChoose = mons and function(item)
        local mon = flat[item.value]
        if mon then core.openSummary(game, mon) end
      end or nil,
    })
    if mons then core.attachLevelIcons(list, mons) end
    game.stack:push(withCounter(list))
  end

  local function freshCart() return { ext = {}, orphaned = { ext = {} } } end

  local function orphanedCount(orphaned)
    local n = 0
    for _, d in ipairs(LE.list()) do n = n + LE.cartCount(orphaned, d) end
    return n
  end

  local PUBLISHED_KEYS = { boxes = "pokemon", timeCapsule = "timeCapsule", items = "items", moves = "moves", money = "money", coins = "coins" }

  local function cartCounts(cart)
    local counts = { ext = {} }
    for _, name in pairs(PUBLISHED_KEYS) do counts[name] = 0 end
    for _, d in ipairs(LE.list()) do
      local n = LE.cartCount(cart, d)
      if d.storageId == mod.id and PUBLISHED_KEYS[d.key] then counts[PUBLISHED_KEYS[d.key]] = n
      elseif n > 0 then
        counts.ext[d.storageId] = counts.ext[d.storageId] or {}
        counts.ext[d.storageId][d.key] = n
      end
    end
    return counts
  end

  local function movedEntries(cart)
    local out = {}
    for _, d in ipairs(LE.list()) do
      local moved = LE.moved(cart, d)
      if moved then
        out[d.storageId] = out[d.storageId] or {}
        out[d.storageId][d.key] = moved
      end
    end
    return out
  end

  local function cartSummaryLines(cart)
    local lines = {}
    for _, d in ipairs(LE.list()) do
      local n = LE.cartCount(cart, d)
      if n > 0 then
        local label = tostring(d.label):upper()
        lines[#lines + 1] = (d.kind == "single" and d.link.prefix) and Strings("%s %s", singleText(d, n), label) or Strings("%d %s", n, label)
      end
    end
    local lost = orphanedCount(cart.orphaned)
    if lost > 0 then lines[#lines + 1] = Strings("%d set aside (LOST)", lost) end
    if #lines == 0 then lines[1] = Strings("Nothing.") end
    return lines
  end

  local CONFIRM_ROWS = 9

  local function openConfirmScreen(self, opts)
    local game = self.game
    local screen = { isOpaque = true, offset = 0 }

    local function panel() return { title = opts.title, lines = opts.lines, offset = screen.offset, hints = { opts.footer or Strings("A: CONFIRM  B: BACK") } } end

    local function visibleRows() return Widgets.active() and Widgets.panelRows(panel()) or CONFIRM_ROWS end

    function screen:update(dt)
      local input = game.input
      local maxOffset = math.max(0, #opts.lines - visibleRows())
      if input:wasPressed("a") then
        game.stack:pop()
        opts.onConfirm()
      elseif input:wasPressed("b") then
        game.stack:pop()
        if opts.onBack then opts.onBack() end
      elseif input:wasPressed("up") then
        screen.offset = math.max(0, screen.offset - 1)
      elseif input:wasPressed("down") then
        screen.offset = math.min(maxOffset, screen.offset + 1)
      end
    end

    function screen:draw()
      if Widgets.active() then return Widgets.drawPanel(panel()) end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(opts.title, 8, 6)
      for i = 1, CONFIRM_ROWS do
        local line = opts.lines[screen.offset + i]
        if line then Font.draw(line, 8, 24 + (i - 1) * 12) end
      end
      Font.draw(opts.footer or Strings("A: CONFIRM  B: BACK"), 8, 128)
      love.graphics.setColor(1, 1, 1, 1)
    end

    game.stack:push(screen)
  end

  local function lostRows(game, cartRoot, onlyStorage)
    local rows, mons = {}, {}
    for _, d in ipairs(LE.list()) do
      if d.kind ~= "single" and (onlyStorage == nil or d.storageId == onlyStorage) then
        local pools = cartRoot and LE.cartPools(cartRoot, d) or LE.orphanPools(d)
        local entryRows, entryMons = LE.lostRows(game, d, pools)
        for i, row in ipairs(entryRows) do
          rows[#rows + 1] = row
          mons[#mons + 1] = entryMons[i]
        end
      end
    end
    return rows, mons
  end

  local function lostPageChoices()
    local pages, seen = {}, {}
    for _, d in ipairs(LE.list()) do
      if d.kind ~= "single" and not seen[d.storageId] then
        seen[d.storageId] = true
        pages[#pages + 1] = { id = d.storageId, label = d.record.name }
      end
    end
    return pages
  end

  local function lostPageTitle(_, pageId)
    local record = pageId and core.CustomStorage.getCustomStorage(pageId)
    return record and core.truncateName(record.name:upper(), 16) or nil
  end

  local function openSendLostScreen(self)
    local game = self.game
    local cart = self.cart.send
    local pending

    local function withdrawRow(root, row)
      local d = LE.find(row.storageId, row.key)
      local taken = d and LE.lostWithdraw(d, root, row)
      if not taken then return false end
      pending = { d = d, poolId = row.poolId, taken = taken }
      return true
    end

    local function depositRow(root)
      LE.lostDeposit(pending.d, root, pending.poolId, pending.taken)
      pending = nil
      playSound(game, "Withdraw_Deposit")
    end

    local multiplePages = #lostPageChoices() > 1
    local containers = {
      {
        id = "bank", label = "BANK",
        getPages = multiplePages and lostPageChoices or nil,
        title = lostPageTitle,
        build = function(g, pageId)
          local rows, mons = lostRows(g, nil, pageId)
          return rows, LIST_OPTS, mons
        end,
        dynamicFooter = function(_, _, _, nextLabel) return nextLabel and ("SELECT: " .. nextLabel) or nil end,
        withdraw = function(_, _, row) return withdrawRow(nil, row) end,
        deposit = function() depositRow(nil) end,
      },
      {
        id = "send", label = "SEND",
        build = function(g)
          local rows, mons = lostRows(g, cart.orphaned, nil)
          return rows, LIST_OPTS, mons
        end,
        dynamicFooter = function(_, _, _, nextLabel) return nextLabel and ("SELECT: " .. nextLabel) or nil end,
        withdraw = function(_, _, row) return withdrawRow(cart.orphaned, row) end,
        deposit = function() depositRow(cart.orphaned) end,
      },
    }
    game.stack:push(core.entryScreen(game, containers, { counter = true }))
  end

  local function sidebarRow(d, n)
    local value = d.kind == "single" and singleText(d, n) or tostring(n)
    local label = tostring(d.shortLabel):upper()
    if not Widgets.active() and #Font.split(label) + 1 + #Font.split(value) > SIDEBAR_CHARS then label = "" end
    return { label, value }
  end

  local function drawSendSummarySidebar(cart)
    local rows = {}
    for _, d in ipairs(LE.list()) do
      local n = LE.cartCount(cart, d)
      if n > 0 then rows[#rows + 1] = sidebarRow(d, n) end
    end
    local lost = orphanedCount(cart.orphaned)
    if lost > 0 then rows[#rows + 1] = { Strings("LOST"), tostring(lost) } end
    if #rows == 0 then return end
    if Widgets.active() then return Widgets.infoBox(rows, { position = "topright" }) end
    love.graphics.setColor(0, 0, 0, 1)
    for i, row in ipairs(rows) do
      local label, value = row[1], row[2]
      local y = 32 + (i - 1) * 12
      Font.draw(label, 88, y)
      Font.draw(value, 160 - 8 - Font.width(value), y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function offerTooBig(self)
    local limit = (tonumber(Net.MAX_LINE) or (256 * 1024)) * 0.9
    local ok, encoded = pcall(Json.encode, self:buildOffer())
    return ok and type(encoded) == "string" and #encoded > limit
  end

  local function openSendConfirm(self)
    if offerTooBig(self) then
      message(self.game, "That's too much\nto send at once.\011Take some back.")
      return
    end
    openConfirmScreen(self, {
      title = "SENDING",
      lines = cartSummaryLines(self.cart.send),
      onConfirm = function() self:enterWaitReady() end,
      onBack = function() self:openSendMenu() end,
    })
  end

  local function openReceiveLostScreen(self)
    local game = self.game
    local orphaned = self.cart.receive.orphaned
    local containers = { {
      id = "receive", label = "LOST",
      build = function(g)
        local rows, mons = lostRows(g, orphaned, nil)
        return rows, LIST_OPTS, mons
      end,
    } }
    game.stack:push(core.entryScreen(game, containers, { readOnly = true, counter = true }))
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

  local activeLink

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
    activeLink = self
    return self
  end

  function BankLinkState:refundSend()
    local send = self.cart.send
    for _, d in ipairs(LE.list()) do LE.refund(d, send, self.game) end
    self.cart.send = freshCart()
    self.cart.receive = freshCart()
  end

  function BankLinkState:finish(text)
    if self.net then
      pcall(function() self.net:send({ type = "bank_bye" }) end)
      self.net:close()
    end
    activeLink = nil
    self.game.stack:pop()
    if text then message(self.game, text) end
  end

  function BankLinkState:abort(text)
    self:refundSend()
    mod.events:emit("mod.vrm_pokemon_bank.link_cancelled", {})
    self:finish(text or "The transfer was\ncancelled.")
  end

  function BankLinkState:shutdown()
    self:refundSend()
    mod.events:emit("mod.vrm_pokemon_bank.link_cancelled", {})
    core.flushStorage()
    if self.net then
      pcall(function() self.net:send({ type = "bank_bye" }) end)
      pcall(function() self.net:close() end)
    end
  end

  function BankLinkState:enterHelloWait()
    local player = self.game.save.player
    local customStorages = {}
    for _, record in ipairs(mod.exports.listCustomStorages()) do
      local keys = {}
      for _, entry in ipairs(record.entries) do
        if entry.linkEnabled ~= false then keys[#keys + 1] = entry.key end
      end
      if #keys > 0 then customStorages[#customStorages + 1] = { id = record.id, storageVersion = record.storageVersion, entries = keys } end
    end
    self.net:send({
      type = "bank_hello",
      version = LINK_VERSION,
      storageId = core.getStorageId(),
      trainerId = player and player.id,
      trainerName = player and player.name,
      customStorages = customStorages,
    })
    self.stage = "helloWait"
    self.helloElapsed = 0
  end

  function BankLinkState:sameTrainerAsPeer()
    local player = self.game.save.player
    local myId, myName = player and player.id, player and player.name
    local peerId, peerName = tonumber(self.peerHello.trainerId), self.peerHello.trainerName
    if myId == nil or myName == nil or peerId == nil or peerName == nil then return false end
    return myId == peerId and myName == peerName
  end

  function BankLinkState:sameStorageAsPeer()
    local myId = tonumber(core.getStorageId())
    local peerId = tonumber(self.peerHello.storageId)
    if myId == nil or peerId == nil then return false end
    return myId == peerId
  end

  function BankLinkState:computeCustomStorageAvailability()
    local peerStorages = {}
    for _, s in ipairs(type(self.peerHello.customStorages) == "table" and self.peerHello.customStorages or {}) do
      if type(s) == "table" and type(s.id) == "string" then peerStorages[s.id] = s end
    end
    local availability = {}
    for _, record in ipairs(mod.exports.listCustomStorages()) do
      local peer = peerStorages[record.id]
      local entries = {}
      for _, entry in ipairs(record.entries) do
        if entry.linkEnabled ~= false then
          local reason
          if not peer then
            reason = "The other player\ndoesn't have this\ndata."
          elseif tonumber(peer.storageVersion) ~= record.storageVersion then
            reason = "Both players need\nthe same data\nversion."
          else
            local found = false
            for _, key in ipairs(type(peer.entries) == "table" and peer.entries or {}) do
              if key == entry.key then found = true break end
            end
            if not found then reason = "The other player\ndoesn't have this\ndata." end
          end
          entries[entry.key] = { available = reason == nil, reason = reason }
        end
      end
      availability[record.id] = entries
    end
    self.customStorageAvailability = availability
  end

  local function entryAvailability(self, storageId, entryKey)
    local avail = self.customStorageAvailability and self.customStorageAvailability[storageId]
    local info = avail and avail[entryKey]
    if not info then return false, "That data isn't\navailable right\nnow." end
    return info.available, info.reason
  end

  function BankLinkState:checkHello()
    if tonumber(self.peerHello.version) ~= LINK_VERSION then self:abort("The other player's\nLINK version\ndoesn't match.")
    elseif self:sameTrainerAsPeer() then self:abort("You can't LINK\nwith yourself!")
    elseif self:sameStorageAsPeer() then self:abort("You can't LINK\nwith your own\nBANK!")
    else
      self:computeCustomStorageAvailability()
      self.stage = "sendMenu"
      self:openSendMenu()
    end
  end

  function BankLinkState:openSendMenu()
    local function confirmCancel(reopen)
      local game = self.game
      core.confirm(game, "Cancel the\ntransfer?", function(yes)
        if yes then self:abort() else reopen() end
      end, { defaultNo = true })
    end

    local function gated(storageId, entryKey, action)
      return function()
        local ok, reason = entryAvailability(self, storageId, entryKey)
        if not ok then message(self.game, reason) return end
        local liveGame = core.getLiveGame and core.getLiveGame() or self.game
        if not core.CustomStorage.isEntryUnlocked(storageId, entryKey, liveGame) then
          message(self.game, "You haven't\nunlocked this\nyet.")
          return
        end
        action()
      end
    end

    local rows = {}
    for _, d in ipairs(LE.list()) do
      rows[#rows + 1] = { label = core.truncateName(tostring(d.label):upper(), 9), keepOpen = true, onSelect = gated(d.storageId, d.key, function()
        if d.kind == "single" then openSingleMenu(self, d) else openSendPicker(self, d) end
      end) }
    end
    rows[#rows + 1] = { label = "LOST", keepOpen = true, onSelect = function() openSendLostScreen(self) end }
    rows[#rows + 1] = { label = "CONFIRM", onSelect = function() openSendConfirm(self) end }
    rows[#rows + 1] = { label = "CANCEL", onSelect = function() confirmCancel(function() self:openSendMenu() end) end }
    local menu = Menu.new(self.game, rows, {
      tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true,
      onCancel = function() confirmCancel(function() self:openSendMenu() end) end,
    })
    local cart = self.cart.send
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end
    function screen:draw()
      menu:draw()
      drawSendSummarySidebar(cart)
    end
    self.game.stack:push(screen)
  end

  function BankLinkState:enterWaitReady()
    self.readySent = true
    self.net:send({ type = "bank_ready" })
    self.stage = "waitReady"
  end

  function BankLinkState:buildOffer()
    local send = self.cart.send
    local offer = { type = "bank_offer", entries = {} }
    for _, d in ipairs(LE.list()) do
      local payload = LE.flatten(d, send)
      if payload ~= nil then
        offer.entries[d.storageId] = offer.entries[d.storageId] or {}
        offer.entries[d.storageId][d.key] = payload
      end
    end
    return offer
  end

  function BankLinkState:sendOffer()
    self.net:send(self:buildOffer())
    self.net:update()
    self.stage = "waitOffer"
  end

  function BankLinkState:receiveOffer(offer)
    local game = self.game
    local receive = freshCart()
    local sender = { storageId = self.peerHello and tonumber(self.peerHello.storageId) }
    local wireEntries = type(offer.entries) == "table" and offer.entries or {}
    for _, d in ipairs(LE.list()) do
      local perStorage = type(wireEntries[d.storageId]) == "table" and wireEntries[d.storageId] or {}
      local accepted, rejected = LE.receive(game, d, perStorage[d.key], sender)
      LE.store(receive, d, accepted)
      LE.store(receive.orphaned, d, rejected)
    end
    self.cart.receive = receive
  end

  function BankLinkState:openReceiveMenu()
    local link = self
    local game = self.game

    local function confirmCancelOrBack()
      game.stack:push(TextBox.new(game, "Cancel the\ntransfer?", function()
        local rows = {
          { label = "YES", onSelect = function() link:abort() end },
          { label = "GO BACK", onSelect = function() link:requestBack() end },
          { label = "NO", onSelect = function() link:openReceiveMenu() end },
        }
        game.stack:push(Menu.new(game, rows, {
          tx = 0, ty = 0, tw = 12, th = #rows * 2 + 2, noSound = true,
          onCancel = function() link:openReceiveMenu() end,
        }))
      end))
    end

    local rows = {}
    for _, d in ipairs(LE.list()) do
      rows[#rows + 1] = { label = core.truncateName(tostring(d.label):upper(), 9), keepOpen = true, onSelect = function() openReceiveView(link, d) end }
    end
    rows[#rows + 1] = { label = "LOST", keepOpen = true, onSelect = function() openReceiveLostScreen(link) end }
    rows[#rows + 1] = { label = "CONFIRM", onSelect = function() openReceiveConfirm(link) end }
    rows[#rows + 1] = { label = "CANCEL", onSelect = function() confirmCancelOrBack() end }
    local menu = Menu.new(game, rows, {
      tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true,
      onCancel = function() confirmCancelOrBack() end,
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
    local sent, received = self.cart.send, self.cart.receive
    local payload = {
      sent = cartCounts(sent), received = cartCounts(received),
      entries = { sent = movedEntries(sent), received = movedEntries(received) },
    }
    for _, d in ipairs(LE.list()) do LE.apply(d, received, game) end
    self.cart.send = freshCart()
    self.cart.receive = freshCart()
    if mod.exports.validateStorage then mod.exports.validateStorage(game) end
    if game.writeSave then game:writeSave() end
    core.playSaveSound(game)
    mod.events:emit("mod.vrm_pokemon_bank.link_completed", payload)
    self:finish("The transfer is\ncomplete!")
  end

  function BankLinkState:pollNet()
    for _, msg in ipairs(self.net:poll()) do
      if msg.type == "bank_bye" then self.peerBye = true
      elseif msg.type == "bank_hello" and not self.peerHello then self.peerHello = msg
      elseif msg.type == "bank_ready" then self.peerReady = true
      elseif msg.type == "bank_unready" then self.peerReady = false
      elseif msg.type == "bank_offer" and not self.peerOffer then self.peerOffer = msg
      elseif msg.type == "bank_commit" then self.peerCommitted = true
      elseif msg.type == "bank_uncommit" then self.peerCommitted = false
      elseif msg.type == "bank_restart" then self.peerRestart = true
      -- keepalive; just receiving it is proof the link isn't dead yet
      elseif msg.type == "bank_ping" then end
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
      if self.stage == "waitReady" or self.stage == "waitOffer" or self.stage == "waitCommit" then
        self.pingElapsed = (self.pingElapsed or 0) + dt
        if self.pingElapsed >= WAIT_PING_INTERVAL then
          self.pingElapsed = 0
          self.net:send({ type = "bank_ping" })
        end
      else self.pingElapsed = nil end
    end

    if self.stage == "mode" then
      if input:wasPressed("up") or input:wasPressed("down") then self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then self.game.stack:pop()
      elseif input:wasPressed("a") then
        self.online = self.index ~= 1
        self.stage = self.index == 1 and "lanMenu" or "onlineMenu"
        self.index = 1
      end
    elseif self.stage == "lanMenu" then
      if input:wasPressed("up") or input:wasPressed("down") then self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then
        self.stage = "mode"
        self.index = 1
      elseif input:wasPressed("a") then
        if self.index == 1 then
          local net, detail = openSession("host", function(t) return t:host() end)
          if net then
            self.net = net
            self.stage = "hosting"
          else message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60))) end
        else self.stage = "addrEntry" end
      end
    elseif self.stage == "hosting" or self.stage == "onlineHosting" or self.stage == "onlineJoining" or self.stage == "joining" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      if self.net.paired then self:enterHelloWait() end
    elseif self.stage == "onlineMenu" then
      if input:wasPressed("up") or input:wasPressed("down") then self.index = self.index == 1 and 2 or 1
      elseif input:wasPressed("b") then
        self.stage = "mode"
        self.index = 2
      elseif input:wasPressed("a") then
        if self.index == 1 then
          local net, detail = openSession("host", function(t) return t:hostOnline() end)
          if net then
            self.net = net
            self.stage = "onlineHosting"
          else message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60))) end
        else
          self.stage = "codeEntry"
          self.codeEntry = CodeEntry.new()
        end
      end
    elseif self.stage == "codeEntry" then
      if input:wasPressed("b") then
        self.stage = "onlineMenu"
        self.index = 2
      elseif input:wasPressed("up") then CodeEntry.up(self.codeEntry)
      elseif input:wasPressed("down") then CodeEntry.down(self.codeEntry)
      elseif input:wasPressed("left") then CodeEntry.left(self.codeEntry)
      elseif input:wasPressed("right") then CodeEntry.right(self.codeEntry)
      elseif input:wasPressed("a") then
        local code = CodeEntry.text(self.codeEntry)
        local net, detail = openSession("guest", function(t) return t:joinOnline(nil, code) end)
        if net then
          self.net = net
          self.stage = "onlineJoining"
        else message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60))) end
      end

    elseif self.stage == "addrEntry" then
      if input:wasPressed("b") then self.stage = "lanMenu"
      elseif input:wasPressed("up") then self.addr[self.addrPos] = (self.addr[self.addrPos] + 1) % 10
      elseif input:wasPressed("down") then self.addr[self.addrPos] = (self.addr[self.addrPos] - 1) % 10
      elseif input:wasPressed("left") then self.addrPos = math.max(1, self.addrPos - 1)
      elseif input:wasPressed("right") then self.addrPos = math.min(12, self.addrPos + 1)
      elseif input:wasPressed("a") then
        local octets = {}
        for i = 1, 4 do
          local base = (i - 1) * 3
          octets[i] = math.min(255, self.addr[base + 1] * 100 + self.addr[base + 2] * 10 + self.addr[base + 3])
        end
        local address = table.concat(octets, ".")
        local net, detail = openSession("guest", function(t) return t:join(address) end)
        if net then
          self.net = net
          self.stage = "joining"
        else message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60))) end
      end
    elseif self.stage == "helloWait" then
      if input:wasPressed("b") then
        self:abort("Connection\ncancelled.")
        return
      end
      self.helloElapsed = self.helloElapsed + dt
      if self.helloElapsed > 4 then self:abort("The other player\ndoesn't have LINK\ninstalled.") end
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
      if self.peerCommitted then self:applyReceived()
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

  local function panelOf(self)
    local panel = { title = headerText(self), lines = {}, hints = {} }
    local ys = {}
    local function line(text, y)
      panel.lines[#panel.lines + 1] = text
      ys[#ys + 1] = y
    end
    local stage = self.stage
    if stage == "mode" then panel.options, panel.cursor = { Strings("LAN"), Strings("ONLINE") }, self.index
    elseif stage == "lanMenu" or stage == "onlineMenu" then panel.options, panel.cursor = { Strings("HOST"), Strings("JOIN") }, self.index
    elseif stage == "hosting" then
      line(Strings("Friend joins at:"), 40)
      line(self.net.address or "?", 52)
      line(Strings("Waiting for join..."), 76)
    elseif stage == "addrEntry" then
      local cells = {}
      for i = 1, 12 do
        local octet = math.floor((i - 1) / 3)
        if i > 1 and (i - 1) % 3 == 0 then cells[#cells + 1] = { text = ".", x = 8 + octet * 32 - 8, sep = true } end
        cells[#cells + 1] = { text = tostring(self.addr[i]), x = 8 + (i - 1) * 8 + octet * 8, index = i }
      end
      panel.entry = { cells = cells, pos = self.addrPos }
      line(Strings("Port: %s", Net.defaultPort()), 76)
      panel.hints = { Strings("A: connect  B: back") }
    elseif stage == "joining" or stage == "onlineJoining" then
      line(Strings("Calling..."), 40)
      line(self.net.target or "", 52)
    elseif stage == "onlineHosting" then
      line(Strings("Tell your friend"), 40)
      line(Strings("the code:"), 52)
      line(self.net.code or "??????", 68)
      line(Strings("Waiting for join..."), 92)
    elseif stage == "codeEntry" then
      local cells = {}
      for i = 1, CodeEntry.LENGTH do cells[i] = { text = CodeEntry.CHARSET:sub(self.codeEntry.chars[i], self.codeEntry.chars[i]), x = 8 + (i - 1) * 16, index = i } end
      panel.entry = { cells = cells, pos = self.codeEntry.pos }
      panel.hints = { Strings("A: connect  B: back") }
    elseif stage == "helloWait" then
      line(Strings("Checking the"), 40)
      line(Strings("other BANK..."), 52)
    elseif stage == "sendMenu" then panel.right = Strings("SEND")
    elseif stage == "waitReady" or stage == "waitCommit" then
      line(Strings("Waiting for the"), 40)
      line(Strings("other player..."), 52)
      panel.hints = { Strings("B: edit again") }
    elseif stage == "waitOffer" then line(Strings("Exchanging data..."), 40)
    elseif stage == "receiveMenu" then panel.right = Strings("RECEIVE") end
    return panel, ys
  end
  Link.panelOf = panelOf

  function BankLinkState:draw()
    local panel, ys = panelOf(self)
    if Widgets.active() then return Widgets.drawPanel(panel) end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(panel.title, 8, 6)
    if panel.right then Font.draw(panel.right, 160 - 8 - Font.width(panel.right), 20) end
    for i, text in ipairs(panel.options or {}) do
      Font.draw(text, 32, 44 + (i - 1) * 16)
      if i == panel.cursor then Font.drawCode(CURSOR, 24, 44 + (i - 1) * 16) end
    end
    if panel.entry then
      for _, cell in ipairs(panel.entry.cells) do
        Font.draw(cell.text, cell.x, 48)
        if cell.index ~= nil and cell.index == panel.entry.pos then Font.drawCode(0xEE, cell.x, 60) end
      end
    end
    for i, text in ipairs(panel.lines) do Font.draw(text, 8, ys[i]) end
    if panel.hints[1] then Font.draw(panel.hints[1], 8, 128) end
    love.graphics.setColor(1, 1, 1, 1)
  end

  mod.hooks:wrap("core.quit_to_launcher", function(next_)
    if activeLink then activeLink:shutdown() end
    return next_()
  end)

  mod.hooks:wrap("core.update", function(next_, game, dt)
    if activeLink and activeLink.net then
      activeLink.net:update()
      activeLink:pollNet()
    end
    return next_(game, dt)
  end)

  local linkTab = core.makeTabToggle("show_link_tab")
  Link.tabEnabled = linkTab.enabled

  function Link.open(game)
    if not game then return nil, "no game" end
    game.stack:push(BankLinkState.new(game))
    return true
  end

  mod.exports.openLinkMenu = Link.open
  mod.exports.linkScreenId = SCREEN_ID
  mod.exports.setLinkTabEnabled = linkTab.setEnabled
  mod.exports.isLinkTabEnabled = linkTab.enabled
  mod.log:info("Pokemon Bank: Link tab ready")
  return Link
end

return Module
