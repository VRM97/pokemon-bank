local V = ...

local Font = require("src.render.Font")
local FOOTER_COLUMNS = 18

local Utils = {}

function Utils.truncateName(name, maxLen)
  maxLen = maxLen or 12
  name = tostring(name)
  local spans = Font.split(name)
  if #spans <= maxLen then return name end
  local cut = name:sub(1, spans[maxLen - 1].to):gsub("%s+$", "")
  return cut .. "…"
end

function Utils.itemName(game, id)
  local def = game.data.items[id]
  return def and def.name or id
end

function Utils.sortedIdsByName(nameFn, counts, filter)
  local ids = {}
  for id, count in pairs(counts) do
    if count and count > 0 and (not filter or filter(id)) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return nameFn(a) < nameFn(b) end)
  return ids
end

function Utils.sortedItemIds(game, counts)
  return Utils.sortedIdsByName(function(id) return Utils.itemName(game, id) end, counts)
end

function Utils.padToRight(left, right)
  local pad = FOOTER_COLUMNS - #left - #right
  if pad < 1 then pad = 1 end
  return left .. string.rep(" ", pad) .. right
end

function Utils.bucketAdd(bucket, id, qty)
  bucket[id] = (bucket[id] or 0) + qty
end

function Utils.bucketSub(bucket, id, qty)
  local have = bucket[id] or 0
  if qty <= 0 or qty > have then return false end
  bucket[id] = have - qty
  if bucket[id] <= 0 then bucket[id] = nil end
  return true
end

function Utils.idQtyPayload(id, qty) return { id = id, qty = qty } end

return Utils
