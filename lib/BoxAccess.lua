local GameVersion = require("src.core.GameVersion")
local Boxes = require("src.pokemon.Boxes")

local BoxAccess = { EMPTY_LABEL = "<EMPTY SLOT>" }

function BoxAccess.slotted() return GameVersion.generation() == 3 end

function BoxAccess.count() return Boxes.COUNT end

function BoxAccess.capacity() return Boxes.CAPACITY end

function BoxAccess.boxes(game) return Boxes.ensure(game.save) end

function BoxAccess.box(game, boxNum) return BoxAccess.boxes(game)[boxNum] end

function BoxAccess.total(box)
  local n = 0
  for _ in pairs(box) do n = n + 1 end
  return n
end

function BoxAccess.isFull(box) return BoxAccess.total(box) >= BoxAccess.capacity() end

function BoxAccess.indices(box)
  local out = {}
  for i = 1, BoxAccess.capacity() do
    if box[i] ~= nil then out[#out + 1] = i end
  end
  return out
end

function BoxAccess.each(box)
  local indices, n = BoxAccess.indices(box), 0
  return function()
    n = n + 1
    local i = indices[n]
    if i then return i, box[i] end
  end
end

function BoxAccess.firstOpen(box)
  for i = 1, BoxAccess.capacity() do
    if box[i] == nil then return i end
  end
  return nil
end

function BoxAccess.insert(box, mon)
  local slot = BoxAccess.firstOpen(box)
  if slot then box[slot] = mon end
  return slot
end

function BoxAccess.take(box, index)
  local mon = box[index]
  if mon == nil then return nil end
  if BoxAccess.slotted() then box[index] = nil else table.remove(box, index) end
  return mon
end

-- On FireRed an empty slot moves like a mon (a grid MOVE's swap can displace one).
function BoxAccess.reorder(box, from, to)
  local mon = box[from]
  if from == to or (mon == nil and not BoxAccess.slotted()) then return end
  local step = from < to and 1 or -1
  for i = from, to - step, step do box[i] = box[i + step] end
  box[to] = mon
end

function BoxAccess.moveAcross(from, fromIndex, to, toIndex)
  local mon = from[fromIndex]
  if mon == nil or BoxAccess.isFull(to) then return false end
  local slot = (BoxAccess.slotted() and toIndex and toIndex <= BoxAccess.capacity() and to[toIndex] == nil) and toIndex or BoxAccess.firstOpen(to)
  if not slot then return false end
  BoxAccess.take(from, fromIndex)
  to[slot] = mon
  return true
end

function BoxAccess.rows(box, rowFor)
  local rows, mons = {}, {}
  local last = BoxAccess.slotted() and BoxAccess.capacity() or #box
  for i = 1, last do
    local mon = box[i]
    if mon ~= nil then
      rows[i], mons[i] = rowFor(mon, i), mon
    else
      rows[i], mons[i] = { label = BoxAccess.EMPTY_LABEL, value = i, inert = true }, false
    end
  end
  return rows, mons
end

function BoxAccess.moveBox(game, from, to)
  local list = BoxAccess.slotted() and game.save.gen3.storage.boxes or game.save.boxes
  local box = table.remove(list, from)
  table.insert(list, to, box)
end

function BoxAccess.nativeName(game, boxNum)
  if not BoxAccess.slotted() then return nil end
  local box = game.save.gen3 and game.save.gen3.storage and game.save.gen3.storage.boxes[boxNum]
  local name = box and box.name
  if type(name) ~= "string" or name == "" or name == ("BOX %d"):format(boxNum) then return nil end
  return name
end

function BoxAccess.setNativeName(game, boxNum, name)
  local box = game.save.gen3.storage.boxes[boxNum]
  if box then box.name = name or ("BOX %d"):format(boxNum) end
end

function BoxAccess.currentBox(game)
  local n
  if BoxAccess.slotted() then
    local s = game.save.gen3
    n = s and s.storage and s.storage.currentBox
  else n = game.save.currentBox end
  return math.max(1, math.min(BoxAccess.count(), tonumber(n) or 1))
end

function BoxAccess.setCurrentBox(game, boxNum)
  boxNum = math.max(1, math.min(BoxAccess.count(), boxNum))
  if BoxAccess.slotted() then
    if Boxes.setCurrent then Boxes.setCurrent(game.save, boxNum) end
  else game.save.currentBox = boxNum end
  return boxNum
end

return BoxAccess
