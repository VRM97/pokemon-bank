local V = ...
local Utils = V.require("Utils")

local KIND = { single = "single", map = "map", ["multi-map"] = "map", array = "list", ["multi-array"] = "list" }
local MULTI = { ["multi-map"] = true, ["multi-array"] = true }
local IMPLICIT = "_"

local Module = {}

function Module.install(mod, CustomStorage, core)
  local LE = { IMPLICIT = IMPLICIT }

  local function describe(record, entry)
    return {
      record = record, entry = entry, storageId = record.id, key = entry.key, label = entry.label,
      shortLabel = entry.shortLabel or entry.label,
      format = entry.storageFormat, kind = KIND[entry.storageFormat], multi = MULTI[entry.storageFormat] or false,
      link = type(entry.link) == "table" and entry.link or {},
    }
  end

  function LE.list()
    local out = {}
    for _, record in ipairs(CustomStorage.listCustomStorages()) do
      for _, entry in ipairs(record.entries) do
        if entry.linkEnabled ~= false then out[#out + 1] = describe(record, entry) end
      end
    end
    return out
  end

  function LE.listAll(storageId)
    local record = CustomStorage.getCustomStorage(storageId)
    local out = {}
    for _, entry in ipairs(record and record.entries or {}) do out[#out + 1] = describe(record, entry) end
    return out
  end

  function LE.find(storageId, key)
    for _, d in ipairs(LE.list()) do
      if d.storageId == storageId and d.key == key then return d end
    end
  end

  local function callHook(d, name, ...)
    local fn = d.link[name]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    if not ok then
      mod.log:warn("custom storage %s: link.%s failed: %s", d.storageId, name, tostring(result))
      return false, nil
    end
    return true, result
  end

  function LE.nameOf(game, d, id)
    local called, name = callHook(d, "nameOf", game, id)
    if called and type(name) == "string" and name ~= "" then return name end
    return tostring(id)
  end

  function LE.labelOf(game, d, element)
    local called, text = callHook(d, "labelOf", game, element)
    if called and type(text) == "string" and text ~= "" then return text end
    if d.link.pokemon == true and type(element) == "table" then return core.monName(game, element) end
    if type(element) == "table" then
      local name = element.nickname or element.name or element.species or element.id
      if name ~= nil then return tostring(name) end
    end
    return tostring(element)
  end

  function LE.footer(game, d, value, nextLabel)
    local called, text = callHook(d, "footer", game, value, nextLabel)
    if called and type(text) == "string" then return text end
  end

  local function isValid(game, d, value)
    local fn = d.link.isValid
    if type(fn) ~= "function" then return true end
    local ok, result = pcall(fn, game, value)
    if not ok then
      mod.log:warn("custom storage %s: link.isValid failed: %s", d.storageId, tostring(result))
      return false
    end
    return result ~= false
  end

  local function file(d) return d.record.file.loadFile() end

  function LE.value(d) return file(d).entries[d.key] end
  
  function LE.orphans(d)
    local bucket = file(d).orphaned[d.key]
    if type(d.entry.orphanList) ~= "function" or type(bucket) ~= "table" then return bucket end
    local ok, list = pcall(d.entry.orphanList, bucket)
    if ok and type(list) == "table" then return list end
    if not ok then mod.log:warn("custom storage %s: orphanList failed: %s", d.storageId, tostring(list)) end
    return nil
  end

  function LE.markDirty(d) d.record.file.markDirty() end

  local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) and type(a) ~= "boolean" then return a < b end
      return tostring(a) < tostring(b)
    end)
    return keys
  end

  local function containerLabel(d, container, index, game)
    local called, label = callHook(d, "poolLabel", game, container, index)
    if called and type(label) == "string" and label ~= "" then return label end
    return container.name or ("#" .. tostring(index))
  end

  function LE.pools(d, game)
    if d.kind == "single" then return {} end
    local value = LE.value(d)
    if not d.multi then return { { id = IMPLICIT, label = d.label, data = value } } end
    local out = {}
    for i, c in ipairs(value) do out[i] = { id = c.id, label = containerLabel(d, c, i, game), data = c.content } end
    return out
  end

  function LE.currentPool(d, game)
    local called, poolId = callHook(d, "currentPool", game)
    if called then return poolId end
  end

  function LE.orphanPools(d)
    local orphan = d.kind ~= "single" and LE.orphans(d) or nil
    if type(orphan) ~= "table" then return {} end
    if d.format ~= "multi-map" then return { { id = IMPLICIT, label = d.label, data = orphan } } end
    local names = {}
    for i, c in ipairs(LE.value(d)) do names[c.id] = containerLabel(d, c, i) end
    local out = {}
    for _, cid in ipairs(sortedKeys(orphan)) do
      if type(orphan[cid]) == "table" then out[#out + 1] = { id = cid, label = names[cid] or ("#" .. tostring(cid)), data = orphan[cid] } end
    end
    return out
  end

  function LE.poolCount(kind, data)
    if kind == "list" then return #data end
    local n = 0
    for _, qty in pairs(data) do n = n + (tonumber(qty) or 0) end
    return n
  end

  function LE.take(kind, data, ref, qty)
    if kind == "list" then return table.remove(data, ref) end
    local have = data[ref] or 0
    qty = qty or have
    if qty <= 0 or qty > have then return nil end
    data[ref] = have > qty and have - qty or nil
    return qty
  end

  function LE.put(kind, data, ref, value)
    if kind == "list" then
      data[#data + 1] = value
    else
      data[ref] = (data[ref] or 0) + value
    end
  end

  function LE.cartSingle(root, d)
    local s = root.ext[d.storageId]
    return s and tonumber(s[d.key]) or 0
  end

  function LE.setCartSingle(root, d, n)
    local s = root.ext[d.storageId]
    if not s and n <= 0 then return end
    s = s or {}
    root.ext[d.storageId] = s
    s[d.key] = n > 0 and n or nil
    if next(s) == nil then root.ext[d.storageId] = nil end
  end

  function LE.cartPool(root, d, poolId, create)
    local s = root.ext[d.storageId]
    if not s then
      if not create then return nil end
      s = {}
      root.ext[d.storageId] = s
    end
    local e = s[d.key]
    if type(e) ~= "table" then
      if not create then return nil end
      e = {}
      s[d.key] = e
    end
    local data = e[poolId]
    if not data and create then
      data = {}
      e[poolId] = data
    end
    return data
  end

  function LE.cartPools(root, d)
    local s = root.ext[d.storageId]
    local e = s and s[d.key]
    local out = {}
    if type(e) ~= "table" then return out end
    for _, poolId in ipairs(sortedKeys(e)) do out[#out + 1] = { id = poolId, data = e[poolId] } end
    return out
  end

  function LE.cartCount(root, d)
    if d.kind == "single" then return LE.cartSingle(root, d) end
    local n = 0
    for _, pool in ipairs(LE.cartPools(root, d)) do n = n + LE.poolCount(d.kind, pool.data) end
    return n
  end

  function LE.pruneCart(root, d)
    local s = root.ext[d.storageId]
    local e = s and s[d.key]
    if type(e) ~= "table" then return end
    for poolId, data in pairs(e) do
      if LE.poolCount(d.kind, data) == 0 then e[poolId] = nil end
    end
    if next(e) == nil then s[d.key] = nil end
    if next(s) == nil then root.ext[d.storageId] = nil end
  end

  function LE.moved(root, d)
    if d.kind == "single" then
      local n = LE.cartSingle(root, d)
      return n > 0 and { count = 1, qty = n } or nil
    end
    local count, qty = 0, 0
    for _, r in ipairs({ root, root.orphaned }) do
      for _, pool in ipairs(r and LE.cartPools(r, d) or {}) do
        if d.kind == "list" then
          count = count + #pool.data
        else
          for _, n in pairs(pool.data) do
            count, qty = count + 1, qty + (tonumber(n) or 0)
          end
        end
      end
    end
    if d.kind == "list" then qty = count end
    return count > 0 and { count = count, qty = qty } or nil
  end

  function LE.countAll(root)
    local out = {}
    for _, d in ipairs(LE.list()) do
      local n = LE.cartCount(root, d)
      if n > 0 then
        out[d.storageId] = out[d.storageId] or {}
        out[d.storageId][d.key] = n
      end
    end
    return out
  end

  function LE.flatten(d, cart)
    if d.kind == "single" then
      local n = LE.cartSingle(cart, d)
      return n > 0 and n or nil
    end
    local out = {}
    for _, root in ipairs({ cart, cart.orphaned }) do
      for _, pool in ipairs(LE.cartPools(root, d)) do
        if d.kind == "list" then
          for _, element in ipairs(pool.data) do out[#out + 1] = element end
        else
          for id, qty in pairs(pool.data) do out[id] = (out[id] or 0) + qty end
        end
      end
    end
    if d.kind == "list" then return #out > 0 and out or nil end
    return next(out) ~= nil and out or nil
  end

  local function prepare(game, d, element, sender)
    local fn = d.link.prepare
    if type(fn) ~= "function" then return element end
    local ok, result = pcall(fn, game, element, sender)
    if not ok then
      mod.log:warn("custom storage %s: link.prepare failed: %s", d.storageId, tostring(result))
      return element
    end
    return result ~= nil and result or element
  end

  function LE.receive(game, d, wire, sender)
    if d.kind == "single" then
      local n = math.floor(tonumber(wire) or 0)
      return n > 0 and n or 0, nil
    end
    local accepted, rejected = {}, {}
    if type(wire) ~= "table" then return accepted, rejected end
    if d.kind == "list" then
      for _, element in ipairs(wire) do
        if element ~= nil then
          if isValid(game, d, element) then
            accepted[#accepted + 1] = prepare(game, d, element, sender or {})
          else
            rejected[#rejected + 1] = element
          end
        end
      end
    else
      for id, qty in pairs(wire) do
        qty = math.floor(tonumber(qty) or 0)
        if type(id) == "string" and id ~= "" and qty > 0 then
          local bucket = isValid(game, d, id) and accepted or rejected
          bucket[id] = (bucket[id] or 0) + qty
        end
      end
    end
    return accepted, rejected
  end

  local function firstPool(d)
    local pools = LE.pools(d)
    if pools[1] then return pools[1] end
    if d.multi then
      -- an empty multi-array has no container yet: make one to land in
      local value = LE.value(d)
      value[#value + 1] = { id = Utils.generateId(function(id)
        for _, c in ipairs(value) do if c.id == id then return true end end
        return false
      end), content = {} }
      return LE.pools(d)[1]
    end
  end

  local function putAll(d, data, payload)
    if d.kind == "list" then
      for _, element in ipairs(payload) do LE.put("list", data, nil, element) end
    else
      for id, qty in pairs(payload) do LE.put("map", data, id, qty) end
    end
  end

  local function isEmpty(d, payload)
    if type(payload) == "number" then return payload <= 0 end
    if d.kind == "list" then return #payload == 0 end
    return next(payload) == nil
  end

  local function transferHook(d, name, ...)
    local fn = d.entry[name]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    if not ok then
      mod.log:warn("custom storage %s: %s failed: %s", d.storageId, name, tostring(result))
      return true, false
    end
    return true, true, result
  end

  local function hasDepositHook(d) return type(d.entry.deposit) == "function" end

  local function poolById(d, poolId)
    local wanted = d.multi and poolId or IMPLICIT
    for _, p in ipairs(LE.pools(d)) do
      if p.id == wanted then return p end
    end
  end

  function LE.bankTake(game, d, poolId, ref, qty)
    local has, ok, result = transferHook(d, "withdraw", game, d.multi and poolId or nil, ref, qty)
    if has then
      if not ok or result == nil or result == false then return nil end
      LE.markDirty(d)
      return result
    end
    local pool = poolById(d, poolId)
    local taken = pool and LE.take(d.kind, pool.data, ref, qty)
    if taken ~= nil then LE.markDirty(d) end
    return taken
  end

  function LE.bankPut(game, d, poolId, ref, value)
    local has, ok, result = transferHook(d, "deposit", game, d.multi and poolId or nil, ref, value)
    if has then
      if not ok or result == false then return false end
      LE.markDirty(d)
      return true
    end
    local pool = poolById(d, poolId) or firstPool(d)
    if not pool then return false end
    LE.put(d.kind, pool.data, ref, value)
    LE.markDirty(d)
    return true
  end

  function LE.singleBank(d) return math.max(0, math.floor(tonumber(LE.value(d)) or 0)) end

  function LE.setSingleBank(d, n)
    file(d).entries[d.key] = math.max(0, math.floor(n))
    LE.markDirty(d)
  end

  function LE.bankTakeSingle(game, d, amount)
    local has, ok, result = transferHook(d, "withdraw", game, nil, nil, amount)
    if has then
      result = ok and tonumber(result) or nil
      if not result or result <= 0 then return nil end
      LE.markDirty(d)
      return math.floor(result)
    end
    local have = LE.singleBank(d)
    if amount <= 0 or amount > have then return nil end
    LE.setSingleBank(d, have - amount)
    return amount
  end

  function LE.bankPutSingle(game, d, amount, force)
    if amount <= 0 then return true end
    if not force then
      local has, ok, result = transferHook(d, "deposit", game, nil, nil, amount)
      if has then
        if ok and result ~= false then LE.markDirty(d) return true end
        return false
      end
    end
    LE.setSingleBank(d, LE.singleBank(d) + amount)
    return true
  end

  local function depositEach(game, d, poolId, payload)
    local refused = {}
    local any = false
    if d.kind == "list" then
      for _, element in ipairs(payload) do
        if not LE.bankPut(game, d, poolId, nil, element) then refused[#refused + 1] = element; any = true end
      end
    else
      for id, qty in pairs(payload) do
        if not LE.bankPut(game, d, poolId, id, qty) then refused[id] = qty; any = true end
      end
    end
    return any and refused or nil
  end

  function LE.commit(d, accepted, game)
    if d.kind == "single" then
      if accepted > 0 and not LE.bankPutSingle(game, d, accepted) then LE.bankPutSingle(game, d, accepted, true) end
      return
    end
    if isEmpty(d, accepted) then return end
    local called, handled = callHook(d, "commit", LE.value(d), accepted)
    if called and handled ~= false then
      LE.markDirty(d)
      return
    end
    if hasDepositHook(d) then
      local first = firstPool(d)
      LE.commitOrphans(d, depositEach(game, d, first and first.id, accepted))
      return
    end
    local pool = firstPool(d)
    if pool then putAll(d, pool.data, accepted) end
    LE.markDirty(d)
  end

  function LE.commitOrphans(d, rejected)
    if d.kind == "single" or rejected == nil or isEmpty(d, rejected) then return end
    local f = file(d)
    if d.format == "multi-map" then
      local first = firstPool(d)
      local cid = first and first.id or IMPLICIT
      f.orphaned[d.key][cid] = f.orphaned[d.key][cid] or {}
      putAll(d, f.orphaned[d.key][cid], rejected)
    else
      local orphan = LE.orphans(d)
      if not orphan then return end
      putAll(d, orphan, rejected)
    end
    LE.markDirty(d)
  end

  function LE.refund(d, cart, game)
    if d.kind == "single" then
      local n = LE.cartSingle(cart, d)
      if n > 0 then LE.commit(d, n, game) end
      LE.setCartSingle(cart, d, 0)
      return
    end
    local pools = LE.pools(d)
    local byId = {}
    for _, p in ipairs(pools) do byId[p.id] = p end
    for _, pool in ipairs(LE.cartPools(cart, d)) do
      if hasDepositHook(d) then
        local refused = depositEach(game, d, pool.id, pool.data)
        if refused then
          if d.kind == "list" then
            for _, element in ipairs(refused) do LE.lostDeposit(d, nil, pool.id, { element = element }) end
          else
            for id, qty in pairs(refused) do LE.lostDeposit(d, nil, pool.id, { id = id, qty = qty }) end
          end
        end
      else
        local target = byId[pool.id] or firstPool(d)
        if target then putAll(d, target.data, pool.data) end
      end
    end
    local orphan = d.format ~= "multi-map" and LE.orphans(d) or nil
    for _, pool in ipairs(LE.cartPools(cart.orphaned, d)) do
      if d.format == "multi-map" then
        local f = file(d)
        f.orphaned[d.key][pool.id] = f.orphaned[d.key][pool.id] or {}
        putAll(d, f.orphaned[d.key][pool.id], pool.data)
      elseif orphan then
        putAll(d, orphan, pool.data)
      end
    end
    for _, root in ipairs({ cart, cart.orphaned }) do
      local perStorage = root.ext[d.storageId]
      if perStorage then
        perStorage[d.key] = nil
        if next(perStorage) == nil then root.ext[d.storageId] = nil end
      end
    end
    LE.markDirty(d)
  end

  function LE.store(root, d, flat)
    if d.kind == "single" then
      LE.setCartSingle(root, d, flat or 0)
    elseif flat ~= nil and not isEmpty(d, flat) then
      local pool = LE.cartPool(root, d, IMPLICIT, true)
      for k, v in pairs(flat) do pool[k] = v end
    end
  end

  function LE.apply(d, received, game)
    if d.kind == "single" then
      LE.commit(d, LE.cartSingle(received, d), game)
      return
    end
    local accepted = LE.cartPool(received, d, IMPLICIT)
    if accepted then LE.commit(d, accepted, game) end
    local rejected = LE.cartPool(received.orphaned, d, IMPLICIT)
    if rejected then LE.commitOrphans(d, rejected) end
  end

  function LE.lostRows(game, d, pools)
    local rows, mons = {}, {}
    local prefix = Utils.truncateName(tostring(d.shortLabel):upper())
    for _, pool in ipairs(pools) do
      if d.kind == "list" then
        for i, element in ipairs(pool.data) do
          rows[#rows + 1] = {
            label = prefix .. ": " .. LE.labelOf(game, d, element),
            value = { kind = "ext", storageId = d.storageId, key = d.key, poolId = pool.id, index = i },
          }
          mons[#mons + 1] = d.link.pokemon == true and type(element) == "table" and element or false
        end
      else
        for _, id in ipairs(sortedKeys(pool.data)) do
          rows[#rows + 1] = {
            label = prefix .. ": " .. Utils.truncateName(LE.nameOf(game, d, id)),
            right = "x" .. tostring(pool.data[id]),
            value = { kind = "ext", storageId = d.storageId, key = d.key, poolId = pool.id, id = id },
          }
          mons[#mons + 1] = false
        end
      end
    end
    return rows, mons
  end

  function LE.orphanPool(d, poolId, create)
    local orphan = d.kind ~= "single" and LE.orphans(d) or nil
    if type(orphan) ~= "table" then return nil end
    if d.format ~= "multi-map" then return orphan end
    if not orphan[poolId] and create then orphan[poolId] = {} end
    return orphan[poolId]
  end

  function LE.lostWithdraw(d, root, row)
    local data = root and LE.cartPool(root, d, row.poolId) or (not root and LE.orphanPool(d, row.poolId)) or nil
    if not data then return nil end
    local taken
    if d.kind == "list" then
      local element = table.remove(data, row.index)
      taken = element ~= nil and { element = element } or nil
    else
      local qty = data[row.id]
      if qty and qty > 0 then
        data[row.id] = nil
        taken = { id = row.id, qty = qty }
      end
    end
    if taken and not root then LE.markDirty(d) end
    return taken
  end

  function LE.lostDeposit(d, root, poolId, taken)
    local data = root and LE.cartPool(root, d, poolId, true) or (not root and LE.orphanPool(d, poolId, true)) or nil
    if not data then return false end
    if d.kind == "list" then
      data[#data + 1] = taken.element
    else
      data[taken.id] = (data[taken.id] or 0) + taken.qty
    end
    if not root then LE.markDirty(d) end
    return true
  end

  return LE
end

return Module
