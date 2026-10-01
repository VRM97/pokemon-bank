local V = ...
local File = V.require("File")
local Utils = V.require("Utils")
local Screen = V.require("Screen")

local FORMATS = {
  single = true,
  array = true,
  map = true,
  ["multi-array"] = true,
  ["multi-map"] = true,
}

local function defaultFreshStats() return {} end

local BASIC_FIELDS = { "transactions", "deposited", "withdrawn", "links", "sent", "received" }
local QTY_FIELDS = { "depositedQty", "withdrawnQty", "sentQty", "receivedQty" }
local REMOVED_FIELDS = { "removed", "removedQty" }
local QTY_FORMATS = { map = true, ["multi-map"] = true, single = true }

local function whole(v) return math.max(0, math.floor(tonumber(v) or 0)) end

local function migrateCounters(old, format)
  local qty = QTY_FORMATS[format]
  local out = { transactions = old.transactions }
  if old.depositedOps ~= nil or old.withdrawnOps ~= nil then
    out.deposited, out.withdrawn, out.removed = old.depositedOps, old.withdrawnOps, old.tossedOps
    out.depositedQty = old.depositedQty or old.depositedTotal
    out.withdrawnQty = old.withdrawnQty or old.withdrawnTotal
    out.removedQty = old.tossedQty
    out.sentQty, out.receivedQty = old.linkSentQty or old.linkSent, old.linkReceivedQty or old.linkReceived
    out.peak = old.peak
  elseif qty then
    out.depositedQty, out.withdrawnQty = old.deposited, old.withdrawn
    out.sentQty, out.receivedQty = old.linkSent, old.linkReceived
  else
    out.deposited, out.withdrawn, out.removed = old.deposited, old.withdrawn, old.released
    out.sent, out.received = old.linkSent, old.linkReceived
  end
  return out
end

local function isOldCounters(v) return v.linkSent ~= nil or v.linkReceived ~= nil or v.depositedOps ~= nil end

local function normalizeBasic(v, legacy, format)
  local changed = false
  if type(v) ~= "table" then
    v = type(legacy) == "table" and migrateCounters(legacy, format) or {}
    changed = true
  elseif isOldCounters(v) then
    v = migrateCounters(v, format)
    changed = true
  end
  if format == "single" and changed and v.peak == nil and type(legacy) == "table" then v.peak = legacy.peak end
  local fields = { BASIC_FIELDS, QTY_FORMATS[format] and QTY_FIELDS or {}, format == "single" and { "peak" } or {} }
  local keep = {}
  for _, list in ipairs(fields) do
    for _, k in ipairs(list) do
      keep[k] = true
      local n = whole(v[k])
      if n ~= v[k] then v[k] = n; changed = true end
    end
  end
  for _, k in ipairs(REMOVED_FIELDS) do
    if k ~= "removedQty" or QTY_FORMATS[format] then
      keep[k] = true
      if v[k] ~= nil then
        local n = whole(v[k])
        if n == 0 then n = nil end
        if n ~= v[k] then v[k] = n; changed = true end
      end
    end
  end
  for k in pairs(v) do
    if not keep[k] then v[k] = nil; changed = true end
  end
  return v, changed
end

local MultiMap = {}

local function idTaken(containers, id)
  for _, c in ipairs(containers) do
    if type(c) == "table" and c.id == id then return true end
  end
  return false
end

function MultiMap.newContainer(containers, name)
  return {
    id = Utils.generateId(function(id) return idTaken(containers, id) end),
    name = (type(name) == "string" and name ~= "") and name or nil,
    content = {},
  }
end

function MultiMap.fresh()
  local containers = {}
  containers[1] = MultiMap.newContainer(containers)
  return containers
end

function MultiMap.normalize(value)
  local changed = type(value) ~= "table"
  local out = {}
  for _, c in ipairs(changed and {} or value) do
    if type(c) ~= "table" then
      changed = true
    else
      local content = {}
      if type(c.content) ~= "table" then changed = true end
      for id, qty in pairs(type(c.content) == "table" and c.content or {}) do
        local n = math.floor(tonumber(qty) or 0)
        if type(id) == "string" and id ~= "" and n > 0 then
          content[id] = n
          if n ~= qty then changed = true end
        else changed = true end
      end
      local id = c.id
      if (type(id) ~= "number" and type(id) ~= "string") or idTaken(out, id) then id = nil; changed = true end
      local name = (type(c.name) == "string" and c.name ~= "") and c.name or nil
      if name ~= c.name then changed = true end
      local container = { id = id, name = name, content = content }
      out[#out + 1] = container
      if id == nil then container.id = Utils.generateId(function(candidate) return idTaken(out, candidate) end) end
    end
  end
  if #out == 0 then
    out[1] = MultiMap.newContainer(out)
    changed = true
  end
  return out, changed
end

function MultiMap.validate(_, orphaned)
  local changed = false
  for containerId, bucket in pairs(orphaned) do
    if type(bucket) ~= "table" then
      orphaned[containerId] = nil
      changed = true
    else
      for id, qty in pairs(bucket) do
        if type(qty) ~= "number" or qty <= 0 then bucket[id] = nil; changed = true end
      end
      if next(bucket) == nil then orphaned[containerId] = nil; changed = true end
    end
  end
  return changed
end

function MultiMap.container(containers, containerId)
  for index, c in ipairs(containers) do
    if c.id == containerId then return c, index end
  end
  return nil
end

function MultiMap.add(container, id, qty)
  qty = math.floor(tonumber(qty) or 0)
  if type(id) ~= "string" or id == "" or qty <= 0 then return false end
  container.content[id] = (container.content[id] or 0) + qty
  return true
end

function MultiMap.remove(container, id, qty)
  qty = math.floor(tonumber(qty) or 0)
  local have = container.content[id] or 0
  if qty <= 0 or qty > have then return false end
  container.content[id] = have > qty and have - qty or nil
  return true
end

function MultiMap.total(containers, id)
  local n = 0
  for _, c in ipairs(containers) do n = n + (c.content[id] or 0) end
  return n
end

function MultiMap.reconcile(containers, orphaned, isValid)
  local result = { quarantined = 0, restored = 0, lostItems = {}, restoredItems = {} }
  for _, c in ipairs(containers) do
    local bad = {}
    for id in pairs(c.content) do
      if not isValid(id) then bad[#bad + 1] = id end
    end
    for _, id in ipairs(bad) do
      local qty = c.content[id]
      c.content[id] = nil
      orphaned[c.id] = orphaned[c.id] or {}
      orphaned[c.id][id] = (orphaned[c.id][id] or 0) + qty
      result.quarantined = result.quarantined + qty
      result.lostItems[#result.lostItems + 1] = { id = id, count = qty, from = c.name or tostring(c.id) }
    end
  end
  local buckets = {}
  for containerId in pairs(orphaned) do buckets[#buckets + 1] = containerId end
  for _, containerId in ipairs(buckets) do
    local bucket = orphaned[containerId]
    local target = MultiMap.container(containers, containerId) or containers[1]
    local good = {}
    for id in pairs(bucket) do
      if isValid(id) then good[#good + 1] = id end
    end
    for _, id in ipairs(good) do
      local qty = bucket[id]
      bucket[id] = nil
      target.content[id] = (target.content[id] or 0) + qty
      result.restored = result.restored + qty
      result.restoredItems[#result.restoredItems + 1] = { id = id, count = qty }
    end
    if next(bucket) == nil then orphaned[containerId] = nil end
  end
  return result
end

local MultiArray = {}

function MultiArray.newContainer(containers, name)
  return {
    id = Utils.generateId(function(id) return idTaken(containers, id) end),
    name = (type(name) == "string" and name ~= "") and name or nil,
    content = {},
  }
end

function MultiArray.fresh()
  local containers = {}
  containers[1] = MultiArray.newContainer(containers)
  return containers
end

function MultiArray.normalize(value)
  local changed = type(value) ~= "table"
  local out = {}
  for _, c in ipairs(changed and {} or value) do
    if type(c) == "table" then
      local content = c.content
      if type(content) ~= "table" then content = {}; changed = true end
      local id = c.id
      if (type(id) ~= "number" and type(id) ~= "string") or idTaken(out, id) then id = nil; changed = true end
      local name = (type(c.name) == "string" and c.name ~= "") and c.name or nil
      if name ~= c.name then changed = true end
      local container = { id = id, name = name, content = content }
      out[#out + 1] = container
      if id == nil then container.id = Utils.generateId(function(candidate) return idTaken(out, candidate) end) end
    else changed = true end
  end
  if #out == 0 then
    out[1] = MultiArray.newContainer(out)
    changed = true
  end
  return out, changed
end

function MultiArray.validate(_, _orphaned) return false end

function MultiArray.container(containers, containerId)
  for index, c in ipairs(containers) do
    if c.id == containerId then return c, index end
  end
  return nil
end

function MultiArray.insert(container, element)
  if element == nil then return false end
  container.content[#container.content + 1] = element
  return true
end

function MultiArray.removeAt(container, index) return table.remove(container.content, index) end

function MultiArray.total(containers)
  local n = 0
  for _, c in ipairs(containers) do n = n + #c.content end
  return n
end

function MultiArray.reconcile(containers, orphaned, isValid)
  local result = { quarantined = 0, restored = 0, lostItems = {}, restoredItems = {} }
  for _, c in ipairs(containers) do
    local bad = {}
    for i, element in ipairs(c.content) do
      if not isValid(element) then bad[#bad + 1] = i end
    end
    for i = #bad, 1, -1 do
      local element = table.remove(c.content, bad[i])
      orphaned[#orphaned + 1] = element
      result.quarantined = result.quarantined + 1
      result.lostItems[#result.lostItems + 1] = { element = element, from = c.name or tostring(c.id) }
    end
  end
  local kept = {}
  for _, element in ipairs(orphaned) do
    if isValid(element) then
      local target = containers[1]
      target.content[#target.content + 1] = element
      result.restored = result.restored + 1
      result.restoredItems[#result.restoredItems + 1] = { element = element }
    else kept[#kept + 1] = element end
  end
  for i = #orphaned, 1, -1 do orphaned[i] = nil end
  for i, element in ipairs(kept) do orphaned[i] = element end
  return result
end

local function containerLabelOf(game, config, c, i)
  if config.pageLabel then
    local label = config.pageLabel(game, c, i)
    if label then return label end
  end
  if type(c.name) == "string" and c.name ~= "" then return c.name end
  return (config.label or "LIST") .. " " .. i
end

local function pageIdOf(config, c, i)
  if config.pageIdBy == "index" then return i end
  return c.id
end

local function containerOfPage(config, dataModule, containers, pageId)
  if pageId == nil then return containers[1] end
  if config.pageIdBy == "index" then return containers[pageId] or containers[1] end
  return (dataModule.container(containers, pageId)) or containers[1]
end

local function containerNavFields(config)
  local canListPages = config.canListPages
  if canListPages == nil then canListPages = true end
  return {
    id = config.containerId or "content",
    label = config.label,
    getPages = function(game)
      local containers = config.getContainers(game)
      if #containers <= 1 then return nil end
      local pages = {}
      for i, c in ipairs(containers) do pages[i] = { id = pageIdOf(config, c, i), label = containerLabelOf(game, config, c, i) } end
      return pages
    end,
    getRememberedPage = function(game, env) return config.getCurrent and config.getCurrent(game, env) end,
    setRememberedPage = config.setCurrent,
    autoRememberPage = config.autoRememberPage,
    rememberPageLabel = config.rememberPageLabel,
    canListPages = canListPages,
    listPagesLabel = config.listPagesLabel,
    listPagesActions = config.listPagesActions,
    listPagesColumns = config.listPagesColumns,
    listPagesIcon = config.listPagesIcon,
    listPagesOnStart = config.listPagesOnStart,
    listPagesFooter = config.listPagesFooter,
    canRearrangePages = config.canRearrangePages,
    onMovePage = config.onMovePage,
    slots = config.slots,
    canOverflow = config.canOverflow,
    emptySlots = config.emptySlots,
    emptySlotLabel = config.emptySlotLabel,
    title = config.title,
    emptyMessage = config.emptyMessage,
    heldItemMarks = config.heldItemMarks,
    columns = config.columns,
    icon = config.icon,
    dynamicFooter = config.dynamicFooter,
    draw = config.draw,
    onAction = config.onAction,
    onStart = config.onStart,
    withdraw = config.withdraw,
    deposit = config.deposit,
    canWithdraw = config.canWithdraw,
    canDeposit = config.canDeposit,
    transferLabel = config.transferLabel,
    canTransfer = config.canTransfer,
  }
end

local function copyListOpts(listOpts)
  local out = {}
  for k, v in pairs(type(listOpts) == "table" and listOpts or {}) do out[k] = v end
  return out
end

local function defaultArraySubscreen(config, dataModule)
  local renderRow = config.renderRow or function(_, element, _, _) return { label = tostring(element), value = element } end
  local content = containerNavFields(config)
  content.build = function(game, pageId, env)
    local c = containerOfPage(config, dataModule, config.getContainers(game), pageId)
    local rows, mons = {}, {}
    for i, element in ipairs(c.content) do rows[i], mons[i] = renderRow(game, element, i, env) end
    return rows, copyListOpts(config.listOpts), config.heldItemMarks and mons or nil
  end
  content.canRearrange, content.canRearrangeBetweenPages = config.canRearrange, config.canRearrangeBetweenPages
  content.onMove = config.onMove
  return { content }
end

local function defaultMapSubscreen(config, dataModule)
  local content = containerNavFields(config)
  content.heldItemMarks = nil
  content.build = function(game, pageId, env)
    local c = containerOfPage(config, dataModule, config.getContainers(game), pageId)
    local ids = {}
    for id in pairs(c.content) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    local rows = {}
    for i, id in ipairs(ids) do
      rows[i] = config.renderRow and config.renderRow(game, id, c.content[id], env) or { label = tostring(id), right = tostring(c.content[id]), value = id }
    end
    return rows, copyListOpts(config.listOpts)
  end
  return { content }
end

function MultiArray.subscreen(config)
  assert(type(config) == "table" and type(config.getContainers) == "function", "subscreen: config.getContainers(game) is required")
  return defaultArraySubscreen(config, MultiArray)
end

function MultiMap.subscreen(config)
  assert(type(config) == "table" and type(config.getContainers) == "function", "subscreen: config.getContainers(game) is required")
  return defaultMapSubscreen(config, MultiMap)
end

local function buildMultiEntry(format, dataModule, config)
  assert(type(config) == "table", "entry: config must be a table")
  assert(type(config.key) == "string" and config.key ~= "", "entry: config.key is required")
  assert(type(config.label) == "string" and config.label ~= "", "entry: config.label is required")
  assert(type(config.getContainers) == "function", "entry: config.getContainers(game) is required")

  local subscreen = config.subscreen
  if subscreen == nil then
    if format == "multi-array" then subscreen = defaultArraySubscreen(config, dataModule) else subscreen = defaultMapSubscreen(config, dataModule) end
  end

  local screen = config.screen
  if screen == nil then
    screen = function(game)
      if type(subscreen) == "function" then
        local containers = config.getContainers(game)
        assert(type(containers) == "table" and #containers > 0, "entry.screen: getContainers() must return a non-empty array")
        local current = config.getCurrent and containerOfPage(config, dataModule, containers, config.getCurrent(game))
        subscreen(game, current or containers[1])
        return
      end
      game.stack:push(Screen.entryScreen(game, subscreen, { screenId = config.contentScreenId }))
    end
  end

  return {
    key = config.key,
    label = config.label,
    shortLabel = config.shortLabel,
    description = config.description,
    menuScreen = config.menuScreen,
    storageFormat = format,
    freshStorage = config.fresh or dataModule.fresh,
    normalizeStorage = config.normalize or dataModule.normalize,
    validate = config.validate or dataModule.validate,
    orphanList = config.orphanList,
    freshStats = config.freshStats,
    normalizeStats = config.normalizeStats or function(v) return v, false end,
    stats = config.stats,
    deposit = config.linkDeposit,
    withdraw = config.linkWithdraw,
    linkEnabled = config.linkEnabled,
    link = config.link,
    isUnlocked = config.isUnlocked,
    screen = screen,
    subscreen = subscreen,
  }
end

function MultiArray.entry(config) return buildMultiEntry("multi-array", MultiArray, config) end

function MultiMap.entry(config) return buildMultiEntry("multi-map", MultiMap, config) end

local Map = {}

function Map.fresh() return {} end

function Map.normalize(value)
  if type(value) == "table" then return value, false end
  return {}, true
end

function Map.validate(_, orphaned)
  local changed = false
  for id, qty in pairs(orphaned) do
    if type(qty) ~= "number" or qty <= 0 then orphaned[id] = nil; changed = true end
  end
  return changed
end

function Map.add(store, id, qty)
  qty = math.floor(tonumber(qty) or 0)
  if type(id) ~= "string" or id == "" or qty <= 0 then return false end
  store[id] = (store[id] or 0) + qty
  return true
end

function Map.remove(store, id, qty)
  qty = math.floor(tonumber(qty) or 0)
  local have = store[id] or 0
  if qty <= 0 or qty > have then return false end
  store[id] = have > qty and have - qty or nil
  return true
end

function Map.total(store, id) return store[id] or 0 end

local Array = {}

function Array.fresh() return {} end

function Array.normalize(value)
  if type(value) == "table" then return value, false end
  return {}, true
end

function Array.validate(_, _orphaned) return false end

function Array.insert(store, element)
  if element == nil then return false end
  store[#store + 1] = element
  return true
end

function Array.removeAt(store, index) return table.remove(store, index) end

function Array.total(store) return #store end

local Single = {}

function Single.fresh() return 0 end

function Single.normalize(value, max)
  local n = math.max(0, math.floor(tonumber(value) or 0))
  if max then n = math.min(n, max) end
  return n, n ~= value
end

function Single.entry(config)
  assert(type(config) == "table", "entry: config must be a table")
  assert(type(config.key) == "string" and config.key ~= "", "entry: config.key is required")
  assert(type(config.label) == "string" and config.label ~= "", "entry: config.label is required")

  return {
    key = config.key,
    label = config.label,
    shortLabel = config.shortLabel,
    description = config.description,
    menuScreen = config.menuScreen,
    storageFormat = "single",
    freshStorage = config.fresh or Single.fresh,
    normalizeStorage = config.normalize or function(value) return Single.normalize(value, config.max) end,
    freshStats = config.freshStats,
    normalizeStats = config.normalizeStats or function(v) return v, false end,
    stats = config.stats,
    deposit = config.linkDeposit,
    withdraw = config.linkWithdraw,
    linkEnabled = config.linkEnabled,
    link = config.link,
    isUnlocked = config.isUnlocked,
    screen = config.screen,
  }
end

local function categoryPages(config, game, idsOrElements)
  if type(config.categoryOrder) == "function" then return config.categoryOrder(game, idsOrElements) end
  local present = {}
  for _, v in ipairs(idsOrElements) do
    local cat = config.categoryOf(game, v)
    if cat then present[cat] = true end
  end
  local pages = {}
  if type(config.categoryOrder) == "table" then
    for _, entry in ipairs(config.categoryOrder) do
      local id = type(entry) == "table" and entry.id or entry
      local label = type(entry) == "table" and entry.label or entry
      if present[id] then pages[#pages + 1] = { id = id, label = label } end
    end
  else
    local names = {}
    for cat in pairs(present) do names[#names + 1] = cat end
    table.sort(names)
    for _, cat in ipairs(names) do pages[#pages + 1] = { id = cat, label = cat } end
  end
  return pages
end

local FLAT_ALL_PAGE = {}

local function setCategoryNavFields(content, config)
  content.includeAllPage = not config.globalAllPage and config.includeAllPage ~= false
  content.canListPages = config.canListPages
  content.listPagesLabel = config.listPagesLabel
  content.listPagesActions = config.listPagesActions
  content.listPagesColumns, content.listPagesIcon = config.listPagesColumns, config.listPagesIcon
  content.listPagesOnStart, content.listPagesFooter = config.listPagesOnStart, config.listPagesFooter
  content.getRememberedPage = config.getRememberedPage
  content.onPageChange = config.onPageChange
  content.setRememberedPage = config.setRememberedPage
  content.autoRememberPage = config.autoRememberPage
  content.rememberPageLabel = config.rememberPageLabel
end

local function pagesWithFlatAll(config, pages)
  if not config.globalAllPage then return pages end
  local out = { { id = FLAT_ALL_PAGE, label = "ALL" } }
  for _, p in ipairs(pages) do out[#out + 1] = p end
  return out
end

local function passesCategory(config, game, v, pageId) return pageId == nil or Screen.isAllPage(pageId) or pageId == FLAT_ALL_PAGE or config.categoryOf(game, v) == pageId end

local function defaultMapContent(config)
  local content = { id = "content", label = config.label }
  content.build = function(game, pageId, env)
    local store = config.getStore(game)
    local rows = {}
    for id, qty in pairs(store) do
      if qty and qty > 0 and passesCategory(config, game, id, pageId) then
        rows[#rows + 1] = config.renderRow and config.renderRow(game, id, qty, env) or { label = tostring(id), right = tostring(qty), value = id }
      end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows, config.listOpts
  end
  if config.categoryOf then
    setCategoryNavFields(content, config)
    content.getPages = function(game)
      local store = config.getStore(game)
      local ids = {}
      for id, qty in pairs(store) do if qty and qty > 0 then ids[#ids + 1] = id end end
      return pagesWithFlatAll(config, categoryPages(config, game, ids))
    end
  end
  content.title, content.emptyMessage = config.title, config.emptyMessage
  content.columns, content.icon = config.columns, config.icon
  content.dynamicFooter, content.draw, content.onAction = config.dynamicFooter, config.draw, config.onAction
  content.withdraw, content.deposit = config.withdraw, config.deposit
  content.canWithdraw, content.canDeposit = config.canWithdraw, config.canDeposit
  content.transferLabel, content.canTransfer = config.transferLabel, config.canTransfer
  return { content }
end

local function defaultArrayContent(config)
  local renderRow = config.renderRow or function(_, element, _, _) return { label = tostring(element), value = element } end
  local content = { id = "content", label = config.label, heldItemMarks = config.heldItemMarks }
  content.build = function(game, pageId, env)
    local store = config.getStore(game)
    local rows, mons = {}, {}
    for i, element in ipairs(store) do
      if passesCategory(config, game, element, pageId) then
        local row, mon = renderRow(game, element, i, env)
        rows[#rows + 1], mons[#mons + 1] = row, mon
      end
    end
    return rows, config.listOpts, config.heldItemMarks and mons or nil
  end
  if config.categoryOf then
    setCategoryNavFields(content, config)
    content.getPages = function(game) return pagesWithFlatAll(config, categoryPages(config, game, config.getStore(game))) end
  end
  content.title, content.emptyMessage = config.title, config.emptyMessage
  content.columns, content.icon = config.columns, config.icon
  content.dynamicFooter, content.draw, content.onAction = config.dynamicFooter, config.draw, config.onAction
  content.canRearrange, content.onMove = config.canRearrange, config.onMove
  content.withdraw, content.deposit = config.withdraw, config.deposit
  content.canWithdraw, content.canDeposit = config.canWithdraw, config.canDeposit
  content.transferLabel, content.canTransfer = config.transferLabel, config.canTransfer
  return { content }
end

local function buildFlatEntry(format, dataModule, defaultContent, config)
  assert(type(config) == "table", "entry: config must be a table")
  assert(type(config.key) == "string" and config.key ~= "", "entry: config.key is required")
  assert(type(config.label) == "string" and config.label ~= "", "entry: config.label is required")
  assert(type(config.getStore) == "function", "entry: config.getStore(game) is required")
  local subscreen = config.subscreen or defaultContent(config)
  local screen = config.screen
  if screen == nil then
    screen = function(game)
      if type(subscreen) == "function" then
        subscreen(game, config.getStore(game))
        return
      end
      game.stack:push(Screen.entryScreen(game, subscreen, { screenId = config.contentScreenId }))
    end
  end
  return {
    key = config.key,
    label = config.label,
    shortLabel = config.shortLabel,
    description = config.description,
    menuScreen = config.menuScreen,
    storageFormat = format,
    freshStorage = config.fresh or dataModule.fresh,
    normalizeStorage = config.normalize or dataModule.normalize,
    validate = config.validate or dataModule.validate,
    orphanList = config.orphanList,
    freshStats = config.freshStats,
    normalizeStats = config.normalizeStats or function(v) return v, false end,
    stats = config.stats,
    deposit = config.linkDeposit,
    withdraw = config.linkWithdraw,
    linkEnabled = config.linkEnabled,
    link = config.link,
    isUnlocked = config.isUnlocked,
    screen = screen,
    subscreen = subscreen,
  }
end

function Map.entry(config) return buildFlatEntry("map", Map, defaultMapContent, config) end

function Array.entry(config) return buildFlatEntry("array", Array, defaultArrayContent, config) end

local Module = {}

function Module.install(mod)
  local CustomStorage = {}
  local registry = {}
  local registryIndex = {}

  local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then
      mod.log:warn("custom storage: %s", tostring(a))
      return nil
    end
    return a, b
  end

  local function fileNamesFor(id)
    if id == mod.id then return "storage.lua", "stats.lua" end
    return id .. "_storage.lua", id .. "_stats.lua"
  end

  local function validateEntry(entry, seen)
    if type(entry) ~= "table" then return nil, "entry must be a table" end
    if type(entry.key) ~= "string" or entry.key == "" then return nil, "entry.key is required" end
    if seen[entry.key] then return nil, ("duplicate entry key: %s"):format(entry.key) end
    if type(entry.label) ~= "string" or entry.label == "" then return nil, "entry.label is required" end
    if entry.shortLabel ~= nil and type(entry.shortLabel) ~= "string" then return nil, "entry.shortLabel must be a string" end
    if not FORMATS[entry.storageFormat] then return nil, "entry.storageFormat is invalid" end
    if entry.orphanList ~= nil and type(entry.orphanList) ~= "function" then return nil, "entry.orphanList must be a function" end
    if entry.link ~= nil and type(entry.link) ~= "table" then return nil, "entry.link must be a table" end
    if type(entry.normalizeStorage) ~= "function" then return nil, "entry.normalizeStorage is required" end
    if type(entry.normalizeStats) ~= "function" then return nil, "entry.normalizeStats is required" end
    if type(entry.freshStorage) ~= "function" then return nil, "entry.freshStorage is required" end
    if entry.storageFormat ~= "single" and type(entry.validate) ~= "function" then return nil, "entry.validate is required unless storageFormat is \"single\"" end
    if entry.stats ~= nil then
      if type(entry.stats) ~= "table" then return nil, "entry.stats must be a table of rows" end
      for _, row in ipairs(entry.stats) do
        if type(row) ~= "table" or type(row.label) ~= "string" or type(row.value) ~= "function" then return nil, "entry.stats rows need a label and a value function" end
        if row.description ~= nil and type(row.description) ~= "string" then return nil, "entry.stats row description must be a string" end
      end
      if type(entry.freshStats) ~= "function" then return nil, "entry.freshStats is required when entry.stats is provided" end
    end
    if entry.screen ~= nil and type(entry.screen) ~= "function" and type(entry.screen) ~= "table" then return nil, "entry.screen must be a function or a table" end
    if entry.menuScreen ~= nil and type(entry.menuScreen) ~= "function" and type(entry.menuScreen) ~= "table" then return nil, "entry.menuScreen must be a function or a table" end
    if entry.description ~= nil and type(entry.description) ~= "string" then return nil, "entry.description must be a string" end
    if entry.isUnlocked ~= nil and type(entry.isUnlocked) ~= "function" then return nil, "entry.isUnlocked must be a function" end
    return true
  end

  local function freshStorageFile(record)
    return function()
      local entries = {}
      for _, entry in ipairs(record.entries) do entries[entry.key] = safeCall(entry.freshStorage) end
      return { version = record.storageVersion, entries = entries, orphaned = {} }
    end
  end

  local function normalizeStorageFile(record)
    return function(decoded)
      local changed = false
      if record.migrate and safeCall(record.migrate, decoded) then changed = true end
      if type(decoded.entries) ~= "table" then decoded.entries = {}; changed = true end
      if type(decoded.orphaned) ~= "table" then decoded.orphaned = {}; changed = true end
      for _, entry in ipairs(record.entries) do
        if decoded.entries[entry.key] == nil then
          decoded.entries[entry.key] = safeCall(entry.freshStorage)
          changed = true
        end
        local value, entryChanged = safeCall(entry.normalizeStorage, decoded.entries[entry.key])
        if value ~= nil then decoded.entries[entry.key] = value end
        if entryChanged then changed = true end
        if entry.storageFormat ~= "single" then
          if type(decoded.orphaned[entry.key]) ~= "table" then decoded.orphaned[entry.key] = {}; changed = true end
          if safeCall(entry.validate, decoded.entries[entry.key], decoded.orphaned[entry.key]) then changed = true end
        end
      end
      decoded.version = record.storageVersion
      return changed
    end
  end

  local function freshStatsFile(record)
    return function()
      local entries, basic = {}, {}
      for _, entry in ipairs(record.entries) do
        entries[entry.key] = safeCall(entry.freshStats or defaultFreshStats)
        basic[entry.key] = normalizeBasic(nil, nil, entry.storageFormat)
      end
      return { version = record.statsVersion, entries = entries, basic = basic }
    end
  end

  local function normalizeStatsFile(record)
    return function(decoded)
      local changed = false
      if type(decoded.entries) ~= "table" then decoded.entries = {}; changed = true end
      if type(decoded.basic) ~= "table" then decoded.basic = {}; changed = true end
      for _, entry in ipairs(record.entries) do
        local value, basicChanged = normalizeBasic(decoded.basic[entry.key], decoded.entries[entry.key], entry.storageFormat)
        decoded.basic[entry.key] = value
        if basicChanged then changed = true end
        local freshStats = entry.freshStats or defaultFreshStats
        if decoded.entries[entry.key] == nil then
          decoded.entries[entry.key] = safeCall(freshStats)
          changed = true
        end
        local value, entryChanged = safeCall(entry.normalizeStats, decoded.entries[entry.key])
        if value ~= nil then decoded.entries[entry.key] = value end
        if entryChanged then changed = true end
      end
      decoded.version = record.statsVersion
      return changed
    end
  end

  function CustomStorage.registerCustomStorage(config)
    if type(config) ~= "table" then return false, "config must be a table" end
    if type(config.id) ~= "string" or config.id == "" then return false, "config.id is required" end
    if not mod.find(config.id) then return false, "config.id does not match any active mod" end
    if registryIndex[config.id] then return false, "config.id is already registered" end
    if type(config.name) ~= "string" or config.name == "" then return false, "config.name is required" end
    if type(config.entries) ~= "table" or #config.entries == 0 then return false, "config.entries is required" end
    if config.migrate ~= nil and type(config.migrate) ~= "function" then return false, "config.migrate must be a function" end
    if config.description ~= nil and type(config.description) ~= "string" then return false, "config.description must be a string" end
    if config.menu ~= nil and config.menu ~= "storage" and config.menu ~= "entries" then return false, "config.menu must be \"storage\" or \"entries\"" end
    local entries, seen = {}, {}
    for _, entry in ipairs(config.entries) do
      local ok, err = validateEntry(entry, seen)
      if not ok then return false, err end
      seen[entry.key] = true
      entries[#entries + 1] = entry
    end
    local id = config.id
    local record = {
      id = id,
      name = config.name,
      description = config.description,
      storageVersion = tonumber(config.storageVersion) or 1,
      statsVersion = tonumber(config.statsVersion) or 1,
      entries = entries,
      migrate = config.migrate,
      menu = config.menu or "storage",
    }
    record.entryIndex = {}
    for i, entry in ipairs(entries) do record.entryIndex[entry.key] = i end
    record.storageFilename, record.statsFilename = fileNamesFor(id)
    record.freshStorage = freshStorageFile(record)
    record.normalizeStorage = normalizeStorageFile(record)
    record.freshStats = freshStatsFile(record)
    record.normalizeStats = normalizeStatsFile(record)
    record.file = File.new(mod, record.storageFilename, record.freshStorage, record.normalizeStorage)
    record.statsFile = File.new(mod, record.statsFilename, record.freshStats, record.normalizeStats)
    record.flush = function()
      local storageWasDirty = record.file.flushFile()
      local statsWasDirty = record.statsFile.flushFile()
      return storageWasDirty or statsWasDirty
    end
    record.isDirty = function() return record.file.isDirty() or record.statsFile.isDirty() end
    registry[#registry + 1] = record
    registryIndex[id] = #registry
    return true
  end

  function CustomStorage.listCustomStorages()
    local out = {}
    for i, record in ipairs(registry) do out[i] = record end
    return out
  end

  function CustomStorage.getCustomStorage(id)
    local index = registryIndex[id]
    return index and registry[index] or nil
  end

  function CustomStorage.getCustomStorageEntry(id, key)
    local record = CustomStorage.getCustomStorage(id)
    if not record or not record.entryIndex[key] then return nil end
    return record.file.loadFile().entries[key]
  end

  function CustomStorage.setCustomStorageEntry(id, key, value)
    local record = CustomStorage.getCustomStorage(id)
    if not record then return false, "unknown custom storage" end
    if not record.entryIndex[key] then return false, "unknown entry" end
    record.file.loadFile().entries[key] = value
    record.file.markDirty()
    return true
  end

  function CustomStorage.getCustomStorageOrphaned(id)
    local record = CustomStorage.getCustomStorage(id)
    if not record then return nil end
    return record.file.loadFile().orphaned
  end

  function CustomStorage.getBasicStats(id, key)
    local record = CustomStorage.getCustomStorage(id)
    if not record or not record.entryIndex[key] then return nil end
    return record.statsFile.loadFile().basic[key]
  end

  function CustomStorage.validateAll(game)
    local results, anyChanged = {}, false
    for _, record in ipairs(registry) do
      local decoded = record.file.loadFile()
      local changed = false
      results[record.id] = {}
      for _, entry in ipairs(record.entries) do
        if entry.storageFormat ~= "single" then
          if type(decoded.orphaned[entry.key]) ~= "table" then decoded.orphaned[entry.key] = {} end
          local entryChanged, detail = safeCall(entry.validate, decoded.entries[entry.key], decoded.orphaned[entry.key], game)
          if entryChanged then changed = true end
          results[record.id][entry.key] = detail
        end
      end
      if changed then
        record.file.markDirty()
        anyChanged = true
      end
    end
    return results, anyChanged
  end

  local ACTIONS = { deposit = true, withdraw = true, remove = true, use = true }

  function CustomStorage.reportAction(id, key, action, amount, value)
    if not ACTIONS[action] then return false, "unknown action" end
    local record = CustomStorage.getCustomStorage(id)
    if not record or not record.entryIndex[key] then return false, "unknown entry" end
    mod.events:emit("mod.vrm_pokemon_bank.storage_action", { id = id, key = key, action = action, amount = amount, value = value })
    return true
  end

  function CustomStorage.isEntryUnlocked(id, key, game)
    local record = CustomStorage.getCustomStorage(id)
    if not record or not record.entryIndex[key] then return false end
    local entry = record.entries[record.entryIndex[key]]
    if entry.isUnlocked == nil then return true end
    return safeCall(entry.isUnlocked, game) and true or false
  end

  CustomStorage.QTY_FORMATS = QTY_FORMATS
  CustomStorage.normalizeBasic = normalizeBasic

  function CustomStorage.listCustomStorageFiles()
    local out = {}
    for _, record in ipairs(registry) do out[#out + 1] = { id = record.id, storageFile = record.storageFilename, statsFile = record.statsFilename } end
    return out
  end

  CustomStorage.safeCall = safeCall
  CustomStorage.MultiMap = MultiMap
  CustomStorage.MultiArray = MultiArray
  CustomStorage.Map = Map
  CustomStorage.Array = Array
  CustomStorage.Single = Single

  return CustomStorage
end

return Module
