local V = ...

local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")

local SCREEN_ID = "PokemonBankMoney"

-- Withdrawals are capped so save.money can never cross it, matching what happens to any amount over it anyway the next time GenSave writes the save (setBcd clamps with math.min(save.money, MAX_MONEY), silently dropping the excess). See API.md's maxMoney entry for why the Bank's own balance isn't capped by this itself.
local MAX_MONEY = 999999

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty

  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  local function playSound(game, name)
    pcall(function() require("src.core.Sound").play(game.data, name) end)
  end

  local function bankMoney()
    return loadStorage().money or 0
  end

  local function depositMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad request" end
    local s = loadStorage()
    s.money = (s.money or 0) + amount
    markDirty()
    return true
  end

  local function withdrawMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local s = loadStorage()
    local have = s.money or 0
    if amount <= 0 or amount > have then return false, "not enough" end
    s.money = have - amount
    markDirty()
    return true
  end

  -- QuantityBox (source/src/ui/QuantityBox.lua) is built for item stacks,
  -- its box fixed at 2 digits (interior 3 tiles: "×02") -- too narrow for a
  -- money amount, which can run into six digits. Sized to the amount's own
  -- digit count instead, right edge pinned at column 20 like QuantityBox's
  -- own two variants (15+5 unpriced, 7+13 priced) so it lines up with them.
  -- The wallet/bank balance shown above the amount (opts.wallet/opts.bank)
  -- is a static snapshot from when the box opened, not a live read, since
  -- neither actually changes until A confirms.
  local AmountBox = {}
  AmountBox.__index = AmountBox
  AmountBox.isOpaque = false

  function AmountBox.new(game, opts)
    local self = setmetatable({}, AmountBox)
    self.game = game
    self.max = math.max(1, math.floor(opts.max or 1))
    self.amount = math.min(math.max(1, math.floor(opts.start or 1)), self.max)
    self.wallet = math.floor(opts.wallet or 0)
    self.bank = math.floor(opts.bank or 0)
    self.onDone = opts.onDone -- onDone(amount | nil on cancel)
    return self
  end

  local function wrapAmount(v, max)
    if v < 1 then return max end
    if v > max then return 1 end
    return v
  end

  function AmountBox:update(dt)
    local input = self.game.input
    if input:wasPressed("up") then
      self.amount = wrapAmount(self.amount + 1, self.max)
    elseif input:wasPressed("down") then
      self.amount = wrapAmount(self.amount - 1, self.max)
    elseif input:wasPressed("right") then
      self.amount = math.min(self.max, self.amount + 100)
    elseif input:wasPressed("left") then
      self.amount = math.max(1, self.amount - 100)
    elseif input:wasPressed("start") then
      self.amount = self.max
    elseif input:wasPressed("a") then
      self.game.stack:pop()
      if self.onDone then self.onDone(self.amount) end
    elseif input:wasPressed("b") then
      self.game.stack:pop()
      if self.onDone then self.onDone(nil) end
    end
  end

  function AmountBox:draw()
    local moneyVal = ("¥%d"):format(self.wallet)
    local bankVal = ("¥%d"):format(self.bank)
    local amountVal = ("¥%d"):format(self.amount)
    local moneyLabel, bankLabel = "MONEY", "BANK"
    local gap = 1 -- min blank column between a left label and its right-aligned value
    local interior = math.max(
      #moneyLabel + gap + #moneyVal,
      #bankLabel + gap + #bankVal,
      #amountVal
    )
    local tw = interior + 2
    local tx = math.max(0, 20 - tw)
    local ty = 9
    Font.drawBox(tx, ty, tw, 5)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(moneyLabel, (tx + 1) * 8, (ty + 1) * 8)
    Font.draw(bankLabel, (tx + 1) * 8, (ty + 2) * 8)
    Font.draw(moneyVal, 160 - 8 - Font.width(moneyVal), (ty + 1) * 8)
    Font.draw(bankVal, 160 - 8 - Font.width(bankVal), (ty + 2) * 8)
    Font.draw(amountVal, 160 - 8 - Font.width(amountVal), (ty + 3) * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- =========================================================================
  -- Money UI
  -- =========================================================================
  local function openDepositMoney(game)
    local have = game.save.money or 0
    if have <= 0 then
      message(game, "You have no\nmoney to deposit!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = have,
      wallet = have,
      bank = bankMoney(),
      onDone = function(amount)
        if not amount then return end
        game.save.money = have - amount
        depositMoney(amount)
        mod.events:emit("mod.vrm_pokemon_bank.money_deposited", { amount = amount })
        playSound(game, "Withdraw_Deposit")
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
    local room = MAX_MONEY - (game.save.money or 0)
    if room <= 0 then
      message(game, "Your money is\nfull!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = math.min(have, room),
      wallet = game.save.money or 0,
      bank = have,
      onDone = function(amount)
        if not amount then return end
        withdrawMoney(amount)
        game.save.money = (game.save.money or 0) + amount
        mod.events:emit("mod.vrm_pokemon_bank.money_withdrawn", { amount = amount })
        playSound(game, "Withdraw_Deposit")
        message(game, Strings("Withdrew\n¥%d.", amount))
      end,
    }))
  end

  -- No vanilla equivalent to mirror instead: DEPOSIT MONEY / WITHDRAW MONEY / CANCEL, each opening AmountBox above for the amount.
  local function BankMoneyMenu(game)
    local rows = {
      { label = "DEPOSIT MONEY", keepOpen = true, onSelect = function() openDepositMoney(game) end },
      { label = "WITHDRAW MONEY", keepOpen = true, onSelect = function() openWithdrawMoney(game) end },
      { label = "CANCEL" },
    }
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankMoneyMenu })

  -- Tab visibility: MONEY MENU option AND setMoneyTabEnabled override.
  local tabEnabledByOthers = true

  local function tabEnabled()
    return tabEnabledByOthers and mod.options:get("show_money_tab") == true
  end

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.bankMoney = function() return bankMoney() end

  mod.exports.depositMoney = function(amount)
    local ok, err = depositMoney(amount)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.money_deposited", { amount = amount })
    end
    return ok, err
  end

  mod.exports.withdrawMoney = function(amount)
    local ok, err = withdrawMoney(amount)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.money_withdrawn", { amount = amount })
    end
    return ok, err
  end

  mod.exports.maxMoney = MAX_MONEY
  mod.exports.moneyScreenId = SCREEN_ID

  mod.exports.setMoneyTabEnabled = function(enabled)
    tabEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.isMoneyTabEnabled = function() return tabEnabled() end

  mod.log:info("Pokemon Bank: Money tab ready")

  return { screenId = SCREEN_ID, tabEnabled = tabEnabled }
end

return Module
