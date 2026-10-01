local V = ...

local Strings = require("src.core.Strings")
local Widgets = V.require("Widgets")
local TextBox, ChoiceBox, Menu, QuantityBox = Widgets.TextBox, Widgets.ChoiceBox, Widgets.Menu, Widgets.QuantityBox

local Actions = {}

function Actions.message(game, text, onClose) game.stack:push(TextBox.new(game, text, onClose)) end

function Actions.confirm(game, prompt, onChoose, opts)
  if Widgets.active() then
    game.stack:push(TextBox.new(game, prompt, nil, { choice = onChoose, defaultNo = opts and opts.defaultNo }))
    return
  end
  local options = function() game.stack:push(ChoiceBox.new(game, onChoose, opts)) end
  game.stack:push(TextBox.new(game, prompt, options))
end

function Actions.confirmRelease(game, name, onConfirmed) Actions.confirm(game, Strings("Once released,\n%s is\ngone forever. OK?", name), onConfirmed, { defaultNo = true, noSound = true }) end

function Actions.askQuantity(game, list, count, callback, text)
  if count > 1 then
    list.footer = text or "How many?"
    game.stack:push(QuantityBox.new(game, {
      max = count,
      onDone = function(qty)
        if qty then callback(qty) else list.footer = nil end
      end,
    }))
  else callback(1) end
end

local MAX_MENU_ROWS = 8

function Actions.rowActionsMenu(game, rows)
  local th = math.min(#rows, MAX_MENU_ROWS) * 2 + 2
  game.stack:push(Menu.new(game, rows, { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th, noSound = true, maxVisible = MAX_MENU_ROWS }))
end

function Actions.confirmBulkMoveAll(game, opts)
  if (opts.count or 0) == 0 then return end
  Actions.confirm(game, Strings("%s all\nvisible %s?", opts.verb, opts.noun), function(yes)
    if not yes then return end
    local moved, refused = opts.run()
    if moved > 0 and opts.playSound ~= false then V.require("Utils").playSound(game, "Withdraw_Deposit") end
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
      local live = opts.liveList and opts.liveList() or list
      live.footer = opts.doneMessage or Strings("Threw away\n%s.", opts.name)
    end
    if opts.choice then opts.choice(prompt, onYes)
    else Actions.confirm(game, prompt, function(yes) if yes then onYes() end end, { noSound = true }) end
  end)
end

function Actions.cancelHandler(game, opts)
  return function()
    game.stack:pop()
    if opts.onCancel then opts.onCancel() end
  end
end

function Actions.pickerHandle(game, screen)
  return {
    refresh = function() screen.refresh(true) end,
    setFooter = function(msg) screen.list.footer = msg end,
    close = function() game.stack:pop() end,
  }
end

return Actions
