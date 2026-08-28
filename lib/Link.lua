local V = ...

local Strings = require("src.core.Strings")
local Menu = require("src.ui.Menu")
local TextBox = require("src.render.TextBox")
local Font = require("src.render.Font")
local Net = require("src.link.Net")
local Session = require("src.link.Session")
local CodeEntry = require("src.link.CodeEntry")

local SCREEN_ID = "PokemonBankLink"
local CURSOR = 0xED

-- Bumped only when the message shapes below change; a mismatch refuses the link.
local LINK_VERSION = 5
-- How often the side that's just sitting on "Waiting for the other player..." pokes the connection
local WAIT_PING_INTERVAL = 2

local Module = {}

function Module.install(mod, core, Pokemon, Items, Money)
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

  local function depositItemSafe(id, qty, game)
    local prevOverride = Items.getTmItemDepositOverride()
    Items.setTmItemDepositAllowed(true)
    local ok = mod.exports.depositItem(id, qty, game)
    Items.setTmItemDepositAllowed(prevOverride)
    if ok then return end
    local orphaned = core.ensureOrphaned(loadStorage())
    core.bucketAdd(orphaned.items, id, qty)
    core.markDirty()
  end

  local function freshCart()
    return {
      mons = {},
      timeCapsuleMons = {},
      items = {},
      moves = {},
      money = 0,
      orphaned = {
        mons = {},
        items = {},
        moves = {}
      }
    }
  end

  local function orphanedCount(orphaned)
    local n = #orphaned.mons
    for _, q in pairs(orphaned.items) do n = n + (q or 0) end
    for _, q in pairs(orphaned.moves) do n = n + (q or 0) end
    return n
  end

  local function cartCounts(cart)
    local itemQty, moveQty = 0, 0
    for _, q in pairs(cart.items) do itemQty = itemQty + (q or 0) end
    for _, q in pairs(cart.moves) do moveQty = moveQty + (q or 0) end
    return {
      pokemon = #cart.mons, timeCapsule = #cart.timeCapsuleMons,
      items = itemQty, moves = moveQty, money = cart.money,
    }
  end

  local function cartSummaryLines(cart)
    local counts = cartCounts(cart)
    local lines = {
      Strings("%d POKéMON", counts.pokemon),
      Strings("%d TIME CAPSULE", counts.timeCapsule),
      Strings("%d items", counts.items),
      Strings("%d banked moves", counts.moves),
      Strings("¥%d", counts.money),
    }
    local lost = orphanedCount(cart.orphaned)
    if lost > 0 then lines[#lines + 1] = Strings("%d set aside (LOST)", lost) end
    return lines
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
    local state = { bankBox = loadStorage().currentBox }
    local group

    local function currentBox()
      state.bankBox = math.max(1, math.min(#loadStorage().boxes, state.bankBox))
      return loadStorage().boxes[state.bankBox]
    end

    local function cycleBankBox(delta)
      state.bankBox = core.cycleBoxNumber(state.bankBox, #loadStorage().boxes, delta)
      group.rebuild()
    end

    local function startTransferAll()
      local view = state.view
      local src = view == "bank" and currentBox() or cart.mons
      core.confirmBulkMoveAll(game, {
        count = #src,
        verb = view == "bank" and "Send" or "Take back",
        resultVerb = view == "bank" and "Sent" or "Took back",
        noun = "POKéMON",
        run = function()
          local moved = 0
          if view == "bank" then
            for i = #src, 1, -1 do
              local mon = Pokemon.withdrawMon(state.bankBox, i)
              if mon then
                table.insert(cart.mons, 1, mon)
                moved = moved + 1
              end
            end
          else
            for i = #cart.mons, 1, -1 do
              local mon = table.remove(cart.mons, i)
              if mon then
                Pokemon.depositMon(mon)
                moved = moved + 1
              end
            end
          end
          return moved, 0
        end,
        rebuild = function() group.rebuild(true) end,
        setFooter = function(msg) group.screen.list.footer = msg end,
      })
    end

    group = core.listGroup(game, {
      counter = true,
      views = { "bank", "cart" },
      state = state,
      title = function(view) return view == "bank" and core.boxLabel(loadStorage(), state.bankBox) or "SEND" end,
      label = function(view) return view == "bank" and "BANK" or "SEND" end,
      dynamicFooter = function(view, item, nextLabel)
        local src = view == "bank" and currentBox() or cart.mons
        local mon = item and src[item.value]
        local species = mon and Pokemon.speciesName(game, mon) or ""
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or ""
        return species .. "\n" .. selectLine
      end,
      build = function(view)
        local src = view == "bank" and currentBox() or cart.mons
        local rows = {}
        for i, mon in ipairs(src) do
          rows[#rows + 1] = { label = core.monName(game, mon), value = i }
        end
        return rows, {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            local mon = src[item.value]
            if not mon then return end
            local action = view == "bank" and "SEND" or "TAKE BACK"
            core.rowActionsMenu(game, {
              { label = action, onSelect = function()
                  if view == "bank" then
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
                  group.rebuild(true)
                end },
              { label = "STATS", keepOpen = true, onSelect = function() core.openSummary(game, mon) end },
              { label = "CANCEL" },
            })
          end,
        }, src, 0
      end,
      extraKeys = function(input)
        if state.view == "bank" then
          if input:wasPressed("left") then cycleBankBox(-1); return true end
          if input:wasPressed("right") then cycleBankBox(1); return true end
        end
        if input:wasPressed("start") then startTransferAll(); return true end
        return false
      end,
    })
    game.stack:push(group.screen)
  end

  local function openSendTimeCapsulePicker(self)
    local game = self.game
    local cart = self.cart.send
    local state = {}
    local group

    local function startTransferAll()
      local view = state.view
      local src = view == "timeCapsule" and loadStorage().timeCapsule or cart.timeCapsuleMons
      core.confirmBulkMoveAll(game, {
        count = #src,
        verb = view == "timeCapsule" and "Send" or "Take back",
        resultVerb = view == "timeCapsule" and "Sent" or "Took back",
        noun = "POKéMON",
        run = function()
          local moved = 0
          if view == "timeCapsule" then
            local capsule = loadStorage().timeCapsule
            for i = #capsule, 1, -1 do
              local mon = table.remove(capsule, i)
              if mon then
                table.insert(cart.timeCapsuleMons, 1, mon)
                moved = moved + 1
              end
            end
          else
            local capsule = loadStorage().timeCapsule
            for i = #cart.timeCapsuleMons, 1, -1 do
              local mon = table.remove(cart.timeCapsuleMons, i)
              if mon then
                table.insert(capsule, mon)
                moved = moved + 1
              end
            end
          end
          if moved > 0 then core.markDirty() end
          return moved, 0
        end,
        rebuild = function() group.rebuild(true) end,
        setFooter = function(msg) group.screen.list.footer = msg end,
      })
    end

    group = core.listGroup(game, {
      counter = true,
      views = { "timeCapsule", "cart" },
      state = state,
      title = function(view) return view == "timeCapsule" and "TIME CAPSULE" or "SEND" end,
      label = function(view) return view == "timeCapsule" and "CAPSULE" or "SEND" end,
      dynamicFooter = function(view, item, nextLabel)
        local src = view == "timeCapsule" and loadStorage().timeCapsule or cart.timeCapsuleMons
        local mon = item and src[item.value]
        local species = mon and Pokemon.speciesName(game, mon) or ""
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or ""
        return species .. "\n" .. selectLine
      end,
      build = function(view)
        local src = view == "timeCapsule" and loadStorage().timeCapsule or cart.timeCapsuleMons
        local rows = {}
        for i, mon in ipairs(src) do
          rows[#rows + 1] = { label = core.monName(game, mon), value = i }
        end
        return rows, {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            local mon = src[item.value]
            if not mon then return end
            local action = view == "timeCapsule" and "SEND" or "TAKE BACK"
            core.rowActionsMenu(game, {
              { label = action, onSelect = function()
                  if view == "timeCapsule" then
                    local moved = table.remove(loadStorage().timeCapsule, item.value)
                    if moved then
                      table.insert(cart.timeCapsuleMons, moved)
                      core.markDirty()
                      playSound(game, "Withdraw_Deposit")
                    end
                  else
                    local moved = table.remove(cart.timeCapsuleMons, item.value)
                    if moved then
                      table.insert(loadStorage().timeCapsule, moved)
                      core.markDirty()
                      playSound(game, "Withdraw_Deposit")
                    end
                  end
                  group.rebuild(true)
                end },
              { label = "STATS", keepOpen = true, onSelect = function() core.openSummary(game, mon) end },
              { label = "CANCEL" },
            })
          end,
        }, src, 0
      end,
      extraKeys = function(input)
        if input:wasPressed("start") then startTransferAll(); return true end
        return false
      end,
    })
    game.stack:push(group.screen)
  end

  local function openCartCountPicker(self, opts)
    local game = self.game
    local state = { category = "ALL" }
    local group
    local lastView

    local function currentCounts(view)
      return view == "bank" and opts.getBankCounts() or opts.cartCounts
    end

    local function startTransferAll()
      local view = state.view

      local function visibleIds()
        local c = currentCounts(view)
        local ids = {}
        for _, id in ipairs(core.sortedIdsByName(opts.nameFn, c)) do
          local qty = c[id]
          if qty and qty > 0 and (state.category == "ALL" or opts.categoryOf(game, id) == state.category) then
            ids[#ids + 1] = id
          end
        end
        return ids
      end
      
      local ids = visibleIds()
      core.confirmBulkMoveAll(game, {
        count = #ids,
        verb = view == "bank" and "Send" or "Take back",
        resultVerb = view == "bank" and "Sent" or "Took back",
        noun = opts.title:lower(),
        run = function()
          local moved, refused = 0, 0
          for _, id in ipairs(ids) do
            local qty = currentCounts(view)[id] or 0
            if qty > 0 then
              local ok
              if view == "bank" then
                ok = opts.withdraw(id, qty)
                if ok then core.bucketAdd(opts.cartCounts, id, qty) end
              else
                ok = opts.deposit(id, qty)
                if ok then core.bucketSub(opts.cartCounts, id, qty) end
              end
              if ok then moved = moved + 1 else refused = refused + 1 end
            end
          end
          return moved, refused
        end,
        rebuild = function() group.rebuild(true) end,
        setFooter = function(msg) group.screen.list.footer = msg end,
      })
    end

    group = core.listGroup(game, {
      counter = true,
      views = { "bank", "cart" },
      state = state,
      title = function(view)
        local base = view == "bank" and "BANK" or "SEND"
        if state.category == "ALL" then return base end
        return Strings("%s (%s)", base, opts.categoryLabel(state.category))
      end,
      label = function(view) return view == "bank" and "BANK" or "SEND" end,
      dynamicFooter = function(view, item, nextLabel)
        if opts.footer then return opts.footer(item and item.value, nextLabel) end
        local detail = item and opts.detail and opts.detail(item.value)
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or nil
        if not selectLine then return detail end
        return (detail or "") .. "\n" .. selectLine
      end,
      build = function(view)
        if view ~= lastView then
          state.category = "ALL"
          lastView = view
        end
        local c = currentCounts(view)
        local rows = {}
        for _, id in ipairs(core.sortedIdsByName(opts.nameFn, c)) do
          local qty = c[id]
          if qty and qty > 0 and (state.category == "ALL" or opts.categoryOf(game, id) == state.category) then
            rows[#rows + 1] = { value = id, label = core.truncateName(opts.nameFn(id)), right = "x" .. qty }
          end
        end
        return rows, {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            local c2 = currentCounts(view)
            local have = c2[item.value] or 0
            if have <= 0 then return end
            core.askQuantity(game, group.screen.list, have, function(qty)
              if not qty then return end
              if view == "bank" then
                if opts.withdraw(item.value, qty) then
                  core.bucketAdd(opts.cartCounts, item.value, qty)
                  playSound(game, "Withdraw_Deposit")
                  group.rebuild(true)
                end
              else
                local ok = opts.deposit(item.value, qty)
                if ok then
                  core.bucketSub(opts.cartCounts, item.value, qty)
                  playSound(game, "Withdraw_Deposit")
                  group.rebuild(true)
                else
                  group.screen.list.footer = "Can't take that\nback right now."
                end
              end
            end)
          end,
        }
      end,
      extraKeys = function(input)
        local function cycleCategory(delta)
          local avail = opts.availableCategories(game, currentCounts(state.view))
          local nextCategory = core.cycleCategory(state.category, avail, delta)
          if nextCategory == state.category then return end
          state.category = nextCategory
          group.rebuild()
        end

        if input:wasPressed("left") then cycleCategory(-1); return true end
        if input:wasPressed("right") then cycleCategory(1); return true end
        if input:wasPressed("start") then startTransferAll(); return true end
        return false
      end,
    })

    game.stack:push(group.screen)
  end

  local function availableMoveTypesForCounts(game, counts)
    return core.availableCategoriesSorted(counts, function(id) return core.moveTypeOf(game, id) end)
  end

  local function openSendLostPokemonPicker(self)
    local game = self.game
    local cart = self.cart.send
    local group
    group = core.listGroup(game, {
      counter = true,
      views = { "bank", "cart" },
      state = { view = "bank" },
      title = function(view) return view == "bank" and "LOST (BANK)" or "LOST (SEND)" end,
      label = function(view) return view == "bank" and "BANK" or "SEND" end,
      build = function(view)
        local src = view == "bank" and core.ensureOrphaned(loadStorage()).mons or cart.orphaned.mons
        local rows = {}
        for i, mon in ipairs(src) do
          rows[#rows + 1] = { label = core.monName(game, mon), value = i }
        end
        return rows, {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            if view == "bank" then
              local orphaned = core.ensureOrphaned(loadStorage())
              local mon = table.remove(orphaned.mons, item.value)
              if mon then
                table.insert(cart.orphaned.mons, mon)
                core.markDirty()
                playSound(game, "Withdraw_Deposit")
              end
            else
              local mon = table.remove(cart.orphaned.mons, item.value)
              if mon then
                table.insert(core.ensureOrphaned(loadStorage()).mons, mon)
                core.markDirty()
                playSound(game, "Withdraw_Deposit")
              end
            end
            group.rebuild(true)
          end,
        }
      end,
    })
    game.stack:push(group.screen)
  end

  local function openSendLostCountPicker(self, opts)
    local game = self.game
    local group
    group = core.listGroup(game, {
      counter = true,
      views = { "bank", "cart" },
      state = { view = "bank" },
      title = function(view) return Strings("%s (%s)", opts.title, view == "bank" and "BANK" or "SEND") end,
      label = function(view) return view == "bank" and "BANK" or "SEND" end,
      build = function(view)
        local map = view == "bank" and opts.getBankMap() or opts.cartMap
        local ids = {}
        for id in pairs(map) do ids[#ids + 1] = id end
        table.sort(ids)
        local rows = {}
        for _, id in ipairs(ids) do
          rows[#rows + 1] = { label = core.truncateName(id), right = "x" .. tostring(map[id]), value = id }
        end
        return rows, {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            local id = item.value
            local bankMap = opts.getBankMap()
            local from = view == "bank" and bankMap or opts.cartMap
            local to = view == "bank" and opts.cartMap or bankMap
            local have = from[id] or 0
            if have <= 0 then return end
            core.askQuantity(game, group.screen.list, have, function(qty)
              if not qty then return end
              core.bucketSub(from, id, qty)
              core.bucketAdd(to, id, qty)
              core.markDirty()
              playSound(game, "Withdraw_Deposit")
              group.rebuild(true)
            end)
          end,
        }
      end,
    })
    game.stack:push(group.screen)
  end

  local function openSendLostMenu(self)
    local game = self.game
    local cart = self.cart.send
    local rows = {
      { label = "POKéMON", keepOpen = true, onSelect = function() openSendLostPokemonPicker(self) end },
      { label = "ITEMS", keepOpen = true, onSelect = function()
          openSendLostCountPicker(self, {
            title = "ITEMS",
            getBankMap = function() return core.ensureOrphaned(loadStorage()).items end,
            cartMap = cart.orphaned.items,
          })
        end },
      { label = "MOVES", keepOpen = true, onSelect = function()
          openSendLostCountPicker(self, {
            title = "MOVES",
            getBankMap = function() return core.ensureOrphaned(loadStorage()).moves end,
            cartMap = cart.orphaned.moves,
          })
        end },
      { label = "CANCEL" },
    }
    game.stack:push(Menu.new(game, rows, { tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true }))
  end

  local function drawSendSummarySidebar(cart)
    local counts = cartCounts(cart)
    local rows = {
      { Strings("<PK><MN>"), tostring(counts.pokemon) },
      { Strings("CAPS"), tostring(counts.timeCapsule) },
      { Strings("ITEM"), tostring(counts.items) },
      { Strings("MOVE"), tostring(counts.moves) },
      { "", Strings("¥%d", counts.money) },
    }
    local lost = orphanedCount(cart.orphaned)
    if lost > 0 then rows[#rows + 1] = { Strings("LOST"), tostring(lost) } end
    love.graphics.setColor(0, 0, 0, 1)
    for i, row in ipairs(rows) do
      local label, value = row[1], row[2]
      local y = 32 + (i - 1) * 12
      Font.draw(label, 88, y)
      Font.draw(value, 160 - 8 - Font.width(value), y)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function drawSendBankBox(game, cart)
    local sendVal = ("¥%d"):format(cart.money)
    local bankVal = ("¥%d"):format(mod.exports.bankMoney())
    local tw, tx = Money.walletBankBoxWidth("SEND", sendVal, "BANK", bankVal)
    local ty = 9
    Font.drawBox(tx, ty, tw, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Money.drawWalletBankRows(tx, ty, "SEND", sendVal, "BANK", bankVal)
    love.graphics.setColor(1, 1, 1, 1)
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
    local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 13, th = #rows * 2 + 2, noSound = true })
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end
    function screen:draw()
      menu:draw()
      drawSendBankBox(game, cart)
    end
    game.stack:push(screen)
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
    local list = mod.ui.ListMenu.new(game, "RECEIVING", rows, {
      noSound = true, rows = 6, wrap = true,
      onChoose = function(item)
        local mon = mons[item.value]
        if mon then core.openSummary(game, mon) end
      end,
    })
    core.attachLevelIcons(list, mons)
    game.stack:push(withCounter(list))
  end

  local function openReceiveTimeCapsuleList(self)
    local game = self.game
    local mons = self.cart.receive.timeCapsuleMons
    local rows = {}
    for i, mon in ipairs(mons) do rows[#rows + 1] = { label = core.monName(game, mon), value = i } end
    local list = mod.ui.ListMenu.new(game, "RECEIVING", rows, {
      noSound = true, rows = 6, wrap = true,
      onChoose = function(item)
        local mon = mons[item.value]
        if mon then core.openSummary(game, mon) end
      end,
    })
    core.attachLevelIcons(list, mons)
    game.stack:push(withCounter(list))
  end

  local function openReadOnlyCounts(self, title, counts, nameFn)
    local game = self.game
    local rows = {}
    for _, id in ipairs(core.sortedIdsByName(nameFn, counts)) do
      local qty = counts[id]
      if qty and qty > 0 then
        rows[#rows + 1] = { value = id, label = core.truncateName(nameFn(id)), right = "x" .. qty }
      end
    end
    game.stack:push(withCounter(mod.ui.ListMenu.new(game, title, rows, { noSound = true, wrap = true })))
  end

  local function openReceiveLostScreen(self)
    local game = self.game
    local orphaned = self.cart.receive.orphaned
    game.stack:push(core.lostBrowser(game, {
      getMons = function() return orphaned.mons end,
      getItems = function() return orphaned.items end,
      getMoves = function() return orphaned.moves end,
    }))
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
    local game = self.game
    local send = self.cart.send
    for _, mon in ipairs(send.mons) do
      if type(mon) == "table" then Pokemon.depositMon(mon) end
    end
    if #send.timeCapsuleMons > 0 then
      local capsule = loadStorage().timeCapsule
      for _, mon in ipairs(send.timeCapsuleMons) do
        if type(mon) == "table" then table.insert(capsule, mon) end
      end
      core.markDirty()
    end
    for id, qty in pairs(send.items) do
      if type(qty) == "number" and qty > 0 then depositItemSafe(id, qty, game) end
    end
    for id, qty in pairs(send.moves) do
      if type(qty) == "number" and qty > 0 then mod.exports.depositMove(id, qty) end
    end
    if send.money and send.money > 0 then mod.exports.depositMoney(send.money) end
    if orphanedCount(send.orphaned) > 0 then
      local bankOrphaned = core.ensureOrphaned(loadStorage())
      for _, mon in ipairs(send.orphaned.mons) do table.insert(bankOrphaned.mons, mon) end
      for id, qty in pairs(send.orphaned.items) do core.bucketAdd(bankOrphaned.items, id, qty) end
      for id, qty in pairs(send.orphaned.moves) do core.bucketAdd(bankOrphaned.moves, id, qty) end
      core.markDirty()
    end
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
    self.net:send({
      type = "bank_hello",
      version = LINK_VERSION,
      storageVersion = core.STORAGE_VERSION,
      storageId = core.getStorageId(),
      trainerId = player and player.id,
      trainerName = player and player.name,
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

  function BankLinkState:checkHello()
    if tonumber(self.peerHello.version) ~= LINK_VERSION then
      self:abort("The other player's\nLINK version\ndoesn't match.")
    elseif tonumber(self.peerHello.storageVersion) ~= core.STORAGE_VERSION then
      self:abort("Both players need\nthe same BANK\ndata version.")
    elseif self:sameTrainerAsPeer() then
      self:abort("You can't LINK\nwith yourself!")
    elseif self:sameStorageAsPeer() then
      self:abort("You can't LINK\nwith your own\nBANK!")
    else
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

    local rows = {
      { label = "POKéMON", keepOpen = true, onSelect = function() openSendPokemonPicker(self) end },
      { label = "TIME CAPS.", keepOpen = true, onSelect = function() openSendTimeCapsulePicker(self) end },
      { label = "ITEMS", keepOpen = true, onSelect = function()
          local game = self.game
          openCartCountPicker(self, {
            title = "ITEMS",
            getBankCounts = function() return loadStorage().items end,
            cartCounts = self.cart.send.items,
            withdraw = function(id, qty) return (mod.exports.withdrawItem(id, qty)) end,
            deposit = function(id, qty) return (mod.exports.depositItem(id, qty, game)) end,
            nameFn = function(id) return core.itemName(game, id) end,
            categoryOf = core.pocketOf,
            availableCategories = core.availablePockets,
            categoryLabel = core.pocketLabel,
            detail = function(id) return core.itemDescriptionText(game, id) end,
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
            categoryOf = core.moveTypeOf,
            availableCategories = availableMoveTypesForCounts,
            categoryLabel = function(cat) return cat end,
            footer = function(id, nextLabel)
              local line1 = core.moveDetailLine(game, id)
              local pp = core.movePpText(game, id)
              local selectLine = nextLabel and ("SELECT: " .. nextLabel) or nil
              local line2 = (selectLine and pp) and core.padToRight(selectLine, pp) or (selectLine or pp)
              if not line2 then return line1 end
              return (line1 or "") .. "\n" .. line2
            end,
          })
        end },
      { label = "MONEY", keepOpen = true, onSelect = function() openSendMoneyMenu(self) end },
      { label = "LOST", keepOpen = true, onSelect = function() openSendLostMenu(self) end },
      { label = "CONFIRM", onSelect = function() openSendConfirm(self) end },
      { label = "CANCEL", onSelect = function() confirmCancel(function() self:openSendMenu() end) end },
    }
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

  function BankLinkState:sendOffer()
    local send = self.cart.send
    local mons = {}
    for _, mon in ipairs(send.mons) do mons[#mons + 1] = mon end
    for _, mon in ipairs(send.orphaned.mons) do mons[#mons + 1] = mon end
    local items = {}
    for id, qty in pairs(send.items) do items[id] = qty end
    for id, qty in pairs(send.orphaned.items) do core.bucketAdd(items, id, qty) end
    local moves = {}
    for id, qty in pairs(send.moves) do moves[id] = qty end
    for id, qty in pairs(send.orphaned.moves) do core.bucketAdd(moves, id, qty) end
    local timeCapsuleMons = {}
    for _, mon in ipairs(send.timeCapsuleMons) do timeCapsuleMons[#timeCapsuleMons + 1] = mon end
    self.net:send({
      type = "bank_offer", mons = mons, timeCapsuleMons = timeCapsuleMons,
      items = items, moves = moves, money = send.money,
    })
    self.net:update()
    self.stage = "waitOffer"
  end

  function BankLinkState:receiveOffer(offer)
    local game = self.game
    local receive = freshCart()
    local senderStorageId = self.peerHello and tonumber(self.peerHello.storageId)
    for _, mon in ipairs(type(offer.mons) == "table" and offer.mons or {}) do
      if type(mon) == "table" and mod.exports.isValidPokemon(mon, game) then
        if mon.originStorageId == nil then mon.originStorageId = senderStorageId end
        table.insert(receive.mons, mon)
      elseif type(mon) == "table" then
        table.insert(receive.orphaned.mons, mon)
      end
    end
    -- an unrecognized TIME CAPSULE mon has nowhere of its own to sit --
    -- same LOST bucket a regular unrecognized mon already falls into
    for _, mon in ipairs(type(offer.timeCapsuleMons) == "table" and offer.timeCapsuleMons or {}) do
      if type(mon) == "table" and mod.exports.isValidPokemon(mon, game) then
        if mon.originStorageId == nil then mon.originStorageId = senderStorageId end
        table.insert(receive.timeCapsuleMons, mon)
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

    local rows = {
      { label = "POKéMON", keepOpen = true, onSelect = function() openReceivePokemonList(link) end },
      { label = "TIME CAPS.", keepOpen = true, onSelect = function() openReceiveTimeCapsuleList(link) end },
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
      { label = "CANCEL", onSelect = function() confirmCancelOrBack() end },
    }
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
    local sent = self.cart.send
    local received = self.cart.receive
    local sentCounts, receivedCounts = cartCounts(sent), cartCounts(received)
    for _, mon in ipairs(received.mons) do
      if type(mon) == "table" then Pokemon.depositMon(mon) end
    end
    if #received.timeCapsuleMons > 0 then
      local capsule = loadStorage().timeCapsule
      for _, mon in ipairs(received.timeCapsuleMons) do
        if type(mon) == "table" then table.insert(capsule, mon) end
      end
      core.markDirty()
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
        core.bucketAdd(bankOrphaned.items, id, qty)
      end
      for id, qty in pairs(received.orphaned.moves) do
        core.bucketAdd(bankOrphaned.moves, id, qty)
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
          else message(self.game, Strings("LINK error:\n%s", (detail or "?"):sub(1, 60))) end
        else self.stage = "addrEntry" end
      end

    -- hosting/onlineHosting/onlineJoining/joining: all four just wait for the peer to pair (or B to bail), whichever transport/role got them there.
    elseif self.stage == "hosting" or self.stage == "onlineHosting"
        or self.stage == "onlineJoining" or self.stage == "joining" then
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
    elseif self.stage == "lanMenu" or self.stage == "onlineMenu" then
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
    elseif self.stage == "joining" or self.stage == "onlineJoining" then
      Font.draw(Strings("Calling..."), 8, 40)
      Font.draw(self.net.target or "", 8, 52)
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
    elseif self.stage == "helloWait" then
      Font.draw(Strings("Checking the"), 8, 40)
      Font.draw(Strings("other BANK..."), 8, 52)
    elseif self.stage == "sendMenu" then
      local sendText = Strings("SEND")
      Font.draw(sendText, 160 - 8 - Font.width(sendText), 20)
    elseif self.stage == "waitReady" or self.stage == "waitCommit" then
      Font.draw(Strings("Waiting for the"), 8, 40)
      Font.draw(Strings("other player..."), 8, 52)
      Font.draw(Strings("B: edit again"), 8, 128)
    elseif self.stage == "waitOffer" then
      Font.draw(Strings("Exchanging data..."), 8, 40)
    elseif self.stage == "receiveMenu" then
      local receiveText = Strings("RECEIVE")
      Font.draw(receiveText, 160 - 8 - Font.width(receiveText), 20)
    end
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

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.openLinkMenu = Link.open
  mod.exports.linkScreenId = SCREEN_ID
  mod.exports.setLinkTabEnabled = linkTab.setEnabled
  mod.exports.isLinkTabEnabled = linkTab.enabled
  mod.log:info("Pokemon Bank: Link tab ready")
  return Link
end

return Module
