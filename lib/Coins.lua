local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local Widgets = V.require("Widgets")
local Menu = Widgets.Menu

local SCREEN_ID = "PokemonBankCoins"
local MAX_COINS = 9999

local Module = {}

local function clampCoins(amount) return math.min(math.max(0, math.floor(tonumber(amount) or 0)), MAX_COINS) end

local function gen3Coins()
  local okRuntime, runtime = pcall(require, "src.core.game3.runtime")
  local okBag, bag = pcall(require, "src.core.game3.bag")
  if not (okRuntime and okBag and type(runtime) == "table" and type(bag) == "table" and bag.Coins) then return nil end
  local session = runtime.getSession and runtime.getSession()
  if not session then return nil end
  return bag.Coins, session
end

local function walletCoins(game)
  local generation = GameVersion.generation()
  if generation == 1 then return game.save.coins or 0 end
  if generation == 2 then return game.save.player and game.save.player.coins or 0 end
  local Case, session = gen3Coins()
  return Case and Case.get(session) or 0
end

local function setWalletCoins(game, amount)
  local generation = GameVersion.generation()
  if generation == 1 then game.save.coins = clampCoins(amount)
  elseif generation == 2 then
    if not game.save.player then return false end
    game.save.player.coins = clampCoins(amount)
  else
    local Case, session = gen3Coins()
    if not Case then return false end
    Case.set(session, amount)
  end
  return true
end

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local message = core.message

  local AmountBox = Widgets.AmountBox

  local Coins = { screenId = SCREEN_ID, maxCoins = MAX_COINS }

  local function bankCoins() return loadStorage().entries.coins or 0 end

  local function depositCoins(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad request" end
    local s = loadStorage()
    s.entries.coins = (s.entries.coins or 0) + amount
    core.markDirty()
    return true
  end

  local function withdrawCoins(amount)
    amount = math.floor(tonumber(amount) or 0)
    local s = loadStorage()
    local have = s.entries.coins or 0
    if amount <= 0 or amount > have then return false, "not enough" end
    s.entries.coins = have - amount
    core.markDirty()
    return true
  end

  local function openDepositCoins(game)
    local have = walletCoins(game)
    if have <= 0 then
      message(game, "You have no\ncoins to deposit!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = have,
      wallet = have,
      bank = bankCoins(),
      title = "DEPOSIT COINS",
      onDone = function(amount)
        if not amount then return end
        setWalletCoins(game, have - amount)
        depositCoins(amount)
        core.emitAction("coins", "deposit", "coins_deposited", { amount = amount })
        core.playSound(game, "Withdraw_Deposit")
        message(game, Strings("%d coins were\nstored in BANK.", amount))
      end,
    }))
  end

  local function openWithdrawCoins(game)
    local have = bankCoins()
    if have <= 0 then
      message(game, "There's no\ncoins in the BANK!")
      return
    end
    local wallet = walletCoins(game)
    local room = MAX_COINS - wallet
    if room <= 0 then
      message(game, "Your coin case\nis full!")
      return
    end
    game.stack:push(AmountBox.new(game, {
      max = math.min(have, room),
      wallet = wallet,
      bank = have,
      title = "WITHDRAW COINS",
      onDone = function(amount)
        if not amount then return end
        withdrawCoins(amount)
        setWalletCoins(game, walletCoins(game) + amount)
        core.emitAction("coins", "withdraw", "coins_withdrawn", { amount = amount })
        core.playSound(game, "Withdraw_Deposit")
        message(game, Strings("Withdrew\n%d coins.", amount))
      end,
    }))
  end

  local function drawCoinsBankBox(game)
    local coinsVal = ("%d"):format(walletCoins(game))
    local bankVal = ("%d"):format(bankCoins())
    local coinsLabel, bankLabel = "COINS", "BANK"
    if Widgets.active() then return Widgets.infoBox({ { coinsLabel, coinsVal }, { bankLabel, bankVal } }) end
    local tw, tx = Widgets.walletBankBoxWidth(coinsLabel, coinsVal, bankLabel, bankVal)
    local ty = 9
    Font.drawBox(tx, ty, tw, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Widgets.drawWalletBankRows(tx, ty, coinsLabel, coinsVal, bankLabel, bankVal)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function BankCoinsMenu(game)
    local rows = {
      { label = "DEPOSIT COINS",  keepOpen = true, onSelect = function() openDepositCoins(game) end },
      { label = "WITHDRAW COINS", keepOpen = true, onSelect = function() openWithdrawCoins(game) end },
      { label = "CANCEL" },
    }
    local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end

    function screen:draw()
      menu:draw()
      drawCoinsBankBox(game)
    end

    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = BankCoinsMenu })

  local coinsTab = core.entryTab("coins", "show_coins_tab")
  Coins.tabEnabled = coinsTab.shown

  local function amountPayload(amount) return { amount = amount } end

  mod.exports.bankCoins = bankCoins
  mod.exports.depositCoins = core.emitOnSuccess(depositCoins, "coins", "deposit", "coins_deposited", amountPayload)
  mod.exports.withdrawCoins = core.emitOnSuccess(withdrawCoins, "coins", "withdraw", "coins_withdrawn", amountPayload)
  mod.exports.maxCoins = MAX_COINS
  mod.exports.coinsScreenId = SCREEN_ID
  mod.exports.setCoinsTabEnabled = coinsTab.setEnabled
  mod.exports.isCoinsTabEnabled = Coins.tabEnabled
  mod.log:info("Pokemon Bank: Coins tab ready")
  return Coins
end

return Module
