local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local Widgets = V.require("Widgets")
local Menu = Widgets.Menu

local SCREEN_ID = "PokemonBankMoney"
local AMOUNT_SCREEN_ID = "PokemonBankMoneyAmount"
local MAX_MONEY = 999999

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local message = core.message

  local AmountBox = Widgets.AmountBox

  local Money = {
    screenId = SCREEN_ID,
    amountScreenId = AMOUNT_SCREEN_ID,
    AmountBox = AmountBox,
    walletBankBoxWidth = Widgets.walletBankBoxWidth,
    drawWalletBankRows = Widgets.drawWalletBankRows,
  }

  local function bankMoney() return loadStorage().entries.money or 0 end

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
    s.entries.money = (s.entries.money or 0) + amount
    core.markDirty()
    return true
  end

  local function withdrawMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local s = loadStorage()
    local have = s.entries.money or 0
    if amount <= 0 or amount > have then return false, "not enough" end
    s.entries.money = have - amount
    core.markDirty()
    return true
  end

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
      prefix = "¥",
      title = "DEPOSIT MONEY",
      onDone = function(amount)
        if not amount then return end
        setWalletMoney(game, have - amount)
        depositMoney(amount)
        core.emitAction("money", "deposit", "money_deposited", { amount = amount })
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
      prefix = "¥",
      title = "WITHDRAW MONEY",
      onDone = function(amount)
        if not amount then return end
        withdrawMoney(amount)
        setWalletMoney(game, walletMoney(game) + amount)
        core.emitAction("money", "withdraw", "money_withdrawn", { amount = amount })
        core.playSound(game, "Withdraw_Deposit")
        message(game, Strings("Withdrew\n¥%d.", amount))
      end,
    }))
  end

  local function drawWalletBankBox(game)
    local moneyVal = ("¥%d"):format(walletMoney(game))
    local bankVal = ("¥%d"):format(bankMoney())
    local moneyLabel, bankLabel = "MONEY", "BANK"
    if Widgets.active() then return Widgets.infoBox({ { moneyLabel, moneyVal }, { bankLabel, bankVal } }) end
    local tw, tx = Widgets.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal)
    local ty = 9
    Font.drawBox(tx, ty, tw, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Widgets.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
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

  -- Its BANK menu row: shown while its toggle is on and the entry is unlocked.
  local moneyTab = core.entryTab("money", "show_money_tab")
  Money.tabEnabled = moneyTab.shown

  local function amountPayload(amount) return { amount = amount } end

  mod.exports.bankMoney = bankMoney
  mod.exports.depositMoney = core.emitOnSuccess(depositMoney, "money", "deposit", "money_deposited", amountPayload)
  mod.exports.withdrawMoney = core.emitOnSuccess(withdrawMoney, "money", "withdraw", "money_withdrawn", amountPayload)
  mod.exports.maxMoney = MAX_MONEY
  mod.exports.moneyScreenId = SCREEN_ID
  mod.exports.setMoneyTabEnabled = moneyTab.setEnabled
  mod.exports.isMoneyTabEnabled = Money.tabEnabled
  mod.log:info("Pokemon Bank: Money tab ready")
  return Money
end

return Module
