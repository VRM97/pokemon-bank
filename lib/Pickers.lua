local V = ...

local Bag = V.require("BagAccess")
local PcItems = V.require("PcItemAccess")
local BoxAccess = V.require("BoxAccess")

local VIEW_LABELS = { bank = "BANK", party = "PARTY", pc = "PC", bag = "BAG" }

local Pickers = {
  MON_PICKER_SCREEN_ID = "PokemonBankMonPicker",
  ITEM_PICKER_SCREEN_ID = "PokemonBankItemPicker",
  BOX_PICKER_SCREEN_ID = "PokemonBankBoxPicker"
}


local function enabledViews(opts, order)
  local views = {}
  for _, view in ipairs(order) do
    local hidden = opts["hide" .. view:sub(1, 1):upper() .. view:sub(2)]
    if not hidden then views[#views + 1] = view end
  end
  return views
end

local function viewFooter(opts, view, nextLabel)
  if opts.footer then return opts.footer(view, nextLabel) end
  return nextLabel and ("SELECT: " .. nextLabel) or nil
end

local function modernSelect(core, getScreen, backHandler)
  return function(payload)
    local screen = getScreen()
    if payload then core.setListCursor(screen.list, payload) end
    core.chooseListCurrent(screen.list, backHandler)
  end
end

function Pickers.openMonPicker(mod, core, game, opts)
  opts = opts or {}
  local views = enabledViews(opts, { "bank", "party", "pc" })
  if #views == 0 then return nil, "no views enabled" end
  local loadStorage = core.loadStorage
  local initialPage = {
    bank = core.currentBox(),
    pc = BoxAccess.currentBox(game),
  }

  local function listOf(view, pageId)
    if view == "bank" then return loadStorage().entries.boxes[pageId].content
    elseif view == "party" then return game.save.party
    else return BoxAccess.box(game, pageId) end
  end

  local function boxOf(view, pageId) return view ~= "party" and pageId or nil end

  local function containerFor(view)
    local paged = view ~= "party"
    return {
      id = view, label = VIEW_LABELS[view],
      getPages = paged and function()
        local pages = {}
        if view == "bank" then
          for i = 1, #loadStorage().entries.boxes do pages[i] = { id = i, label = core.boxLabel(loadStorage(), i) } end
        else
          for i = 1, BoxAccess.count() do pages[i] = { id = i, label = core.pcBoxLabel(game, i) } end
        end
        return pages
      end or nil,
      getRememberedPage = paged and function() return initialPage[view] end or nil,
      title = function(_, pageId)
        if opts.title then return opts.title(view, boxOf(view, pageId)) end
        if view == "bank" then return core.boxLabel(loadStorage(), pageId)
        elseif view == "party" then return "PARTY" end
        return core.pcBoxLabel(game, pageId)
      end,
      build = function(_, pageId)
        local src = listOf(view, pageId)
        local function rowFor(mon, i)
          local sub = opts.rowRight and opts.rowRight(mon, view, boxOf(view, pageId), i)
          return { label = core.monName(game, mon), value = i, sub = sub }
        end
        local rows, mons = {}, src
        if view == "pc" then rows, mons = BoxAccess.rows(src, rowFor)
        else for i, mon in ipairs(src) do rows[i] = rowFor(mon, i) end end
        return rows, { messageBox = true, noSound = true, rows = opts.rows, wrap = true }, not opts.rowRight and mons or nil
      end,
      dynamicFooter = function(_, pageId, row, nextLabel)
        if opts.dynamicFooter then return opts.dynamicFooter(row and listOf(view, pageId)[row], view, nextLabel) end
        return viewFooter(opts, view, nextLabel)
      end,
    }
  end

  local containers = {}
  for i, view in ipairs(views) do containers[i] = containerFor(view) end

  local screen
  local backHandler = core.cancelHandler(game, opts)
  screen = core.pickerScreen(game, containers, {
    screenId = Pickers.MON_PICKER_SCREEN_ID,
    counter = true,
    startView = opts.startView,
    onClose = backHandler,
    onChoose = function(row, ctx)
      local mon = listOf(ctx.containerId, ctx.pageId)[row]
      if not mon then return end
      if opts.onChoose then opts.onChoose(mon, { view = ctx.containerId, box = boxOf(ctx.containerId, ctx.pageId), index = row }) end
    end,
    modernUi = { select = modernSelect(core, function() return screen end, backHandler) },
  })
  game.stack:push(screen)
  return core.pickerHandle(game, screen)
end

function Pickers.openMovePicker(mod, core, game, opts)
  opts = opts or {}
  if type(opts.compatible) ~= "function" then return nil, "opts.compatible required" end
  local wrapped = {}
  for k, v in pairs(opts) do wrapped[k] = v end
  wrapped.rowRight = function(mon) return opts.compatible(mon) and "ABLE" or "---" end
  return Pickers.openMonPicker(mod, core, game, wrapped)
end

function Pickers.openItemPicker(mod, core, game, opts)
  opts = opts or {}
  local views = enabledViews(opts, { "bank", "bag", "pc" })
  if #views == 0 then return nil, "no views enabled" end

  local loadStorage = core.loadStorage

  local function countsOf(view)
    if view == "bank" then return loadStorage().entries.items
    elseif view == "bag" then return Bag.counts(game)
    else return PcItems.counts(game) end
  end

  local function idsOf(view)
    if view == "bag" then return Bag.order(game.save) end
    return core.sortedItemIds(game, countsOf(view))
  end

  local function containerFor(view)
    return {
      id = view, label = VIEW_LABELS[view],
      title = function() return opts.title and opts.title(view) or VIEW_LABELS[view] end,
      build = function()
        local counts = countsOf(view)
        local rows = {}
        for _, id in ipairs(idsOf(view)) do
          local count = counts[id]
          if count and count > 0 then
            local right = opts.rowRight and opts.rowRight(id, count, view) or ("x" .. tostring(count))
            rows[#rows + 1] = { value = id, label = core.truncateName(core.itemName(game, id)), right = right }
          end
        end
        return rows, { messageBox = true, noSound = true, wrap = true }
      end,
      dynamicFooter = function(_, _, _, nextLabel) return viewFooter(opts, view, nextLabel) end,
    }
  end

  local containers = {}
  for i, view in ipairs(views) do containers[i] = containerFor(view) end

  local screen
  local backHandler = core.cancelHandler(game, opts)
  screen = core.pickerScreen(game, containers, {
    screenId = Pickers.ITEM_PICKER_SCREEN_ID,
    counter = true,
    startView = opts.startView,
    onClose = backHandler,
    onChoose = function(id, ctx)
      local count = countsOf(ctx.containerId)[id]
      if not count or count <= 0 then return end
      if opts.onChoose then opts.onChoose(id, count, ctx.containerId) end
    end,
    modernUi = { select = modernSelect(core, function() return screen end, backHandler) },
  })
  game.stack:push(screen)
  return core.pickerHandle(game, screen)
end

function Pickers.openBoxPicker(mod, core, game, opts)
  opts = opts or {}
  local views = enabledViews(opts, { "bank", "pc" })
  if #views == 0 then return nil, "no views enabled" end

  local loadStorage = core.loadStorage
  local initialBoxes = opts.initialBoxes or {}
  local initialPage = {
    bank = initialBoxes.bank or core.currentBox(),
    pc = initialBoxes.pc or BoxAccess.currentBox(game),
  }

  local function boxContent(view, pageId)
    if view == "bank" then return loadStorage().entries.boxes[pageId].content end
    return BoxAccess.box(game, pageId)
  end

  local function boxTotal(view, box) return view == "bank" and #box or BoxAccess.total(box) end

  local function containerFor(view)
    return {
      id = view, label = VIEW_LABELS[view],
      choosePage = true,
      getPages = function()
        local pages = {}
        if view == "bank" then
          for i = 1, #loadStorage().entries.boxes do pages[i] = { id = i, label = core.boxLabel(loadStorage(), i) } end
        else
          for i = 1, BoxAccess.count() do pages[i] = { id = i, label = core.pcBoxLabel(game, i) } end
        end
        return pages
      end,
      getRememberedPage = function() return initialPage[view] end,
      title = function(_, pageId)
        if opts.title then return opts.title(view, pageId) end
        return view == "bank" and core.boxLabel(loadStorage(), pageId) or core.pcBoxLabel(game, pageId)
      end,
      build = function(_, pageId)
        local box = boxContent(view, pageId)
        local function rowFor(mon, i) return { label = core.monName(game, mon), value = i } end
        local rows, mons = {}, box
        if view == "pc" then rows, mons = BoxAccess.rows(box, rowFor)
        else
          for i, mon in ipairs(box) do rows[i] = rowFor(mon, i) end
        end
        return rows, { messageBox = true, noSound = true, wrap = true }, mons
      end,
      dynamicFooter = function(_, pageId, _, nextLabel)
        if opts.footer then return opts.footer(view, pageId, nextLabel) end
        local hint = nextLabel and ("SELECT: " .. nextLabel .. "\n") or ""
        return hint .. "A: CONFIRM"
      end,
    }
  end

  local containers = {}
  for i, view in ipairs(views) do containers[i] = containerFor(view) end

  local screen
  local backHandler = core.cancelHandler(game, opts)
  screen = core.pickerScreen(game, containers, {
    screenId = opts.screenId or Pickers.BOX_PICKER_SCREEN_ID,
    counter = true,
    startView = opts.startView,
    onClose = backHandler,
    onChoose = function(_, ctx)
      if opts.requireNonEmpty ~= false and boxTotal(ctx.containerId, boxContent(ctx.containerId, ctx.pageId)) == 0 then
        screen.list.footer = opts.emptyMessage or "What? There are\nno POKéMON here!"
        return
      end
      if opts.onChoose then opts.onChoose(ctx.containerId, ctx.pageId) end
    end,
  })
  game.stack:push(screen)
  return core.pickerHandle(game, screen)
end

return Pickers
