local GameVersion = require("src.core.GameVersion")
local Font = require("src.render.Font")
local FOOTER_COLUMNS = 18

local SECRET_ID_KEY = "secret_id"

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

function Utils.sortedItemIds(game, counts) return Utils.sortedIdsByName(function(id) return Utils.itemName(game, id) end, counts) end

function Utils.padToRight(left, right)
  local pad = FOOTER_COLUMNS - #left - #right
  if pad < 1 then pad = 1 end
  return left .. string.rep(" ", pad) .. right
end

function Utils.bucketAdd(bucket, id, qty) bucket[id] = (bucket[id] or 0) + qty end

function Utils.bucketSub(bucket, id, qty)
  local have = bucket[id] or 0
  if qty <= 0 or qty > have then return false end
  bucket[id] = have - qty
  if bucket[id] <= 0 then bucket[id] = nil end
  return true
end

function Utils.idQtyPayload(id, qty) return { id = id, qty = qty } end

function Utils.generateId(taken)
  local id
  repeat id = love.math.random(1, 999999999) until not taken or not taken(id)
  return id
end

function Utils.playSound(game, name) pcall(function() require("src.core.Sound").play(game.data, name) end) end

function Utils.playSaveSound(game) Utils.playSound(game, GameVersion.generation() == 2 and "Sfx_Save" or "Save") end

function Utils.playCry(game, species) pcall(function() require("src.core.Sound").playCry(game.data, species) end) end

local function isId(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 65535 end

local function holder(game)
  local save = game and game.save
  if not save then return nil end
  if GameVersion.generation() == 3 then return save.gen3 or game.session, { tid = "trainerId", sid = "secretId", name = "name" } end
  return save.player, { tid = "id", sid = "secretId", name = "name" }
end

function Utils.ensureTrainer(game, mod)
  local h, keys = holder(game)
  if type(h) ~= "table" or not keys then return false end
  local changed = false
  if not isId(h[keys.sid]) then
    local saved = mod.save:get(SECRET_ID_KEY)
    h[keys.sid] = isId(saved) and saved or love.math.random(0, 65535)
    changed = true
  end
  if mod.save:get(SECRET_ID_KEY) ~= h[keys.sid] then mod.save:set(SECRET_ID_KEY, h[keys.sid]) end
  return changed
end

function Utils.currentTrainer(game)
  local h, keys = holder(game)
  if type(h) ~= "table" or not keys then return { } end
  return { tid = h[keys.tid], sid = h[keys.sid], name = h[keys.name] }
end

return Utils
