local V = ...

local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local Menu = require("src.ui.Menu")
local QuantityBox = require("src.ui.QuantityBox")
local Sound = V.require("Sound")

local Actions = {}

function Actions.message(game, text) game.stack:push(TextBox.new(game, text)) end

function Actions.confirm(game, prompt, onChoose, opts)
  local options = function() game.stack:push(ChoiceBox.new(game, onChoose, opts)) end
  game.stack:push(TextBox.new(game, prompt, options))
end

function Actions.confirmRelease(game, name, onConfirmed)
  Actions.confirm(game, Strings("Once released,\n%s is\ngone forever. OK?", name), onConfirmed, { defaultNo = true, noSound = true })
end

function Actions.askQuantity(game, list, count, cb, text)
  if count == 1 then
    cb(1)
    return
  end
  list.footer = text or "How many?"
  game.stack:push(QuantityBox.new(game, {
    max = count,
    onDone = function(qty)
      if qty then cb(qty) else list.footer = nil end
    end,
  }))
end

function Actions.rowActionsMenu(game, rows)
  local th = #rows * 2 + 2
  game.stack:push(Menu.new(game, rows, { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th, noSound = true }))
end

function Actions.rowChooserScreen(game, rows, opts)
  if #rows == 0 then return nil end
  if #rows == 1 then return rows[1].build(game) end
  local menuRows = {}
  for _, row in ipairs(rows) do
    menuRows[#menuRows + 1] = { label = row.label, keepOpen = true, onSelect = function() game.stack:push(row.build(game)) end }
  end
  menuRows[#menuRows + 1] = { label = "CANCEL" }
  opts = opts or {}
  local th = #menuRows * 2 + 2
  return Menu.new(game, menuRows, { tx = opts.tx or 0, ty = opts.ty or 0, tw = opts.tw or 14, th = th, noSound = true })
end

function Actions.confirmBulkMoveAll(game, opts)
  if (opts.count or 0) == 0 then return end
  Actions.confirm(game, Strings("%s all\nvisible %s?", opts.verb, opts.noun), function(yes)
    if not yes then return end
    local moved, refused = opts.run()
    if moved > 0 and opts.playSound ~= false then Sound.playSound(game, "Withdraw_Deposit") end
    if opts.rebuild then opts.rebuild() end
    local msg = moved > 0 and Strings("%s %d %s.", opts.resultVerb, moved, opts.noun) or "Nothing moved."
    if refused and refused > 0 then msg = Strings("%s\n%d refused.", msg, refused) end
    opts.setFooter(msg)
  end, { defaultNo = true, noSound = true })
end

function Actions.confirmTossQuantity(game, list, opts)
  local count = opts.count
  if not count or count <= 0 then
    list.footer = opts.staleFooter or "The selection changed."
    return
  end
  Actions.askQuantity(game, list, count, function(qty)
    local prompt = opts.confirmPrompt or Strings("Toss %s?", opts.name)
    local function onYes()
      opts.onToss(qty)
      if opts.rebuild then opts.rebuild() end
      list.footer = opts.doneMessage or Strings("Threw away\n%s.", opts.name)
    end
    if opts.choice then
      opts.choice(prompt, onYes)
    else Actions.confirm(game, prompt, function(yes) if yes then onYes() end end, { noSound = true }) end
  end)
end

function Actions.pendingSwapBackHandler(state, rebuildFn, onClose)
  return function()
    if state.pendingSwap then
      state.pendingSwap = nil
      rebuildFn(true)
    else onClose() end
  end
end

function Actions.cancelHandler(game, opts)
  return function()
    game.stack:pop()
    if opts.onCancel then opts.onCancel() end
  end
end

function Actions.pickerHandle(game, group)
  return {
    refresh = function() group.rebuild(true) end,
    setFooter = function(msg) group.screen.list.footer = msg end,
    close = function() game.stack:pop() end,
  }
end

return Actions
