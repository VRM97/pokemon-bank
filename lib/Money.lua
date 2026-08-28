local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local Menu = require("src.ui.Menu")
local Theme = require("src.ui.Theme")

local SCREEN_ID = "PokemonBankMoney"
local AMOUNT_SCREEN_ID = "PokemonBankMoneyAmount"
local MAX_MONEY = 999999

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local message = core.message

  local Money = {
    screenId = SCREEN_ID,
    amountScreenId = AMOUNT_SCREEN_ID
  }

  local function bankMoney()
    return loadStorage().money or 0
  end

  local function walletMoney(game)
    if GameVersion.generation() == 2 then return (game.save.player and game.save.player.money) or 0 end
    return game.save.money or 0
  end

  local function setWalletMoney(game, amount)
    if GameVersion.generation() == 2 then
      game.save.player = game.save.player or {}
      game.save.player.money = amount
    else game.save.money = amount end
  end

  local function depositMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad request" end
    local s = loadStorage()
    s.money = (s.money or 0) + amount
    core.markDirty()
    return true
  end

  local function withdrawMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local s = loadStorage()
    local have = s.money or 0
    if amount <= 0 or amount > have then return false, "not enough" end
    s.money = have - amount
    core.markDirty()
    return true
  end

  local AmountBox = {}
  AmountBox.__index = AmountBox
  AmountBox.isOpaque = false

  function AmountBox.new(game, opts)
    local self = setmetatable({}, AmountBox)
    self.game = game
    self.max = math.max(1, math.floor(opts.max or 1))
    self.digitCount = #tostring(self.max)
    self.wallet = math.floor(opts.wallet or 0)
    self.bank = math.floor(opts.bank or 0)
    self.walletLabel = opts.walletLabel or "MONEY"
    self.bankLabel = opts.bankLabel or "BANK"
    self.onDone = opts.onDone
    self.title = opts.title
    self:setAmount(opts.start or 1)
    self.pos = self.digitCount

    self.screenId = AMOUNT_SCREEN_ID
    self.gen1ModernUi = {
      title = function() return self.title or "AMOUNT" end,
      rows = function()
        return {
          { label = self.walletLabel, value = ("¥%d"):format(self.wallet), enabled = false },
          { label = self.bankLabel, value = ("¥%d"):format(self.bank), enabled = false },
          { label = "AMOUNT", value = ("¥%d"):format(self.amount) },
        }
      end,
      index = function() return 3 end,
      scroll = function() return 0 end,
      footer = function() return "A OK   B CANCEL" end,
      up = function() self:stepDigit(1) end,
      down = function() self:stepDigit(-1) end,
      left = function() self:moveCursor(-1) end,
      right = function() self:moveCursor(1) end,
      select = function() self:confirm() end,
      back = function() self:cancel() end,
      start = function() self:jumpMax() end,
    }
    return self
  end

  local function composeDigits(digits, digitCount)
    local n = 0
    for i = 1, digitCount do n = n * 10 + digits[i] end
    return n
  end

  function AmountBox:setAmount(amount)
    amount = math.min(self.max, math.max(1, math.floor(amount)))
    self.amount = amount
    local digits = {}
    for i = self.digitCount, 1, -1 do
      digits[i] = amount % 10
      amount = math.floor(amount / 10)
    end
    self.digits = digits
  end

  function AmountBox:stepDigit(delta)
    self.digits[self.pos] = (self.digits[self.pos] + delta) % 10
    self:setAmount(composeDigits(self.digits, self.digitCount))
  end

  function AmountBox:moveCursor(delta)
    self.pos = ((self.pos - 1 + delta) % self.digitCount) + 1
  end

  function AmountBox:jumpMax() self:setAmount(self.max) end

  function AmountBox:confirm()
    self.game.stack:pop()
    if self.onDone then self.onDone(self.amount) end
  end

  function AmountBox:cancel()
    self.game.stack:pop()
    if self.onDone then self.onDone(nil) end
  end

  function AmountBox:update(dt)
    local input = self.game.input
    if input:wasPressed("up") then
      self:stepDigit(1)
    elseif input:wasPressed("down") then
      self:stepDigit(-1)
    elseif input:wasPressed("right") then
      self:moveCursor(1)
    elseif input:wasPressed("left") then
      self:moveCursor(-1)
    elseif input:wasPressed("start") then
      self:jumpMax()
    elseif input:wasPressed("a") then
      self:confirm()
    elseif input:wasPressed("b") then
      self:cancel()
    end
  end

  function Money.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal, extra)
    local gap = 1
    local interior = math.max(#moneyLabel + gap + #moneyVal, #bankLabel + gap + #bankVal, extra or 0)
    local tw = interior + 2
    return tw, math.max(0, 20 - tw)
  end

  function Money.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
    Font.draw(moneyLabel, (tx + 1) * 8, (ty + 1) * 8)
    Font.draw(bankLabel, (tx + 1) * 8, (ty + 2) * 8)
    Font.draw(moneyVal, 160 - 8 - Font.width(moneyVal), (ty + 1) * 8)
    Font.draw(bankVal, 160 - 8 - Font.width(bankVal), (ty + 2) * 8)
  end

  function AmountBox:draw()
    local moneyVal = ("¥%d"):format(self.wallet)
    local bankVal = ("¥%d"):format(self.bank)
    local digitsStr = table.concat(self.digits)
    local amountVal = "¥" .. digitsStr
    local moneyLabel, bankLabel = self.walletLabel, self.bankLabel
    local tw, tx = Money.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal, #amountVal)
    local ty = 9
    Font.drawBox(tx, ty, tw, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Money.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
    local amountX = 160 - 8 - Font.width(amountVal)
    Font.draw(amountVal, amountX, (ty + 3) * 8)
    local cursorX = amountX + Font.width("¥" .. digitsStr:sub(1, self.pos - 1))
    Font.drawCode(Theme.moreArrow, cursorX, (ty + 4) * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end

  Money.AmountBox = AmountBox

  -- =========================================================================
  -- Money UI
  -- =========================================================================
  local function openDepositMoney(game)
    local have = walletMoney(game)
    if have <= 0 then
      message(game, "You have no\nmoney to deposit!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = have,
      wallet = have,
      bank = bankMoney(),
      title = "DEPOSIT MONEY",
      onDone = function(amount)
        if not amount then return end
        setWalletMoney(game, have - amount)
        depositMoney(amount)
        mod.events:emit("mod.vrm_pokemon_bank.money_deposited", { amount = amount })
        core.playSound(game, "Withdraw_Deposit")
        message(game, Strings("¥%d was\nstored in BANK.", amount))
      end,
    }))
  end

  local function openWithdrawMoney(game)
    local have = bankMoney()
    if have <= 0 then
      message(game, "There's no\nmoney in the BANK!")
      return
    end
    local wallet = walletMoney(game)
    local room = MAX_MONEY - wallet
    if room <= 0 then
      message(game, "Your money is\nfull!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = math.min(have, room),
      wallet = wallet,
      bank = have,
      title = "WITHDRAW MONEY",
      onDone = function(amount)
        if not amount then return end
        withdrawMoney(amount)
        setWalletMoney(game, walletMoney(game) + amount)
        mod.events:emit("mod.vrm_pokemon_bank.money_withdrawn", { amount = amount })
        core.playSound(game, "Withdraw_Deposit")
        message(game, Strings("Withdrew\n¥%d.", amount))
      end,
    }))
  end

  local function drawWalletBankBox(game)
    local moneyVal = ("¥%d"):format(walletMoney(game))
    local bankVal = ("¥%d"):format(bankMoney())
    local moneyLabel, bankLabel = "MONEY", "BANK"
    local tw, tx = Money.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal)
    local ty = 9
    Font.drawBox(tx, ty, tw, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Money.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function BankMoneyMenu(game)
    local rows = {
      { label = "DEPOSIT MONEY", keepOpen = true, onSelect = function() openDepositMoney(game) end },
      { label = "WITHDRAW MONEY", keepOpen = true, onSelect = function() openWithdrawMoney(game) end },
      { label = "CANCEL" },
    }
    local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end
    function screen:draw()
      menu:draw()
      drawWalletBankBox(game)
    end
    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = BankMoneyMenu })

  local moneyTab = core.makeTabToggle("show_money_tab")
  Money.tabEnabled = moneyTab.enabled

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  local function amountPayload(amount) return { amount = amount } end

  mod.exports.bankMoney = bankMoney
  mod.exports.depositMoney = core.emitOnSuccess(depositMoney, "mod.vrm_pokemon_bank.money_deposited", amountPayload)
  mod.exports.withdrawMoney = core.emitOnSuccess(withdrawMoney, "mod.vrm_pokemon_bank.money_withdrawn", amountPayload)
  mod.exports.maxMoney = MAX_MONEY
  mod.exports.moneyScreenId = SCREEN_ID
  mod.exports.setMoneyTabEnabled = moneyTab.setEnabled
  mod.exports.isMoneyTabEnabled = Money.tabEnabled
  mod.log:info("Pokemon Bank: Money tab ready")
  return Money
end

return Module
