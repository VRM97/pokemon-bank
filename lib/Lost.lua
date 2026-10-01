local SCREEN_ID = "PokemonBankLost"

local Module = {}

function Module.install(mod, core)
  local LE = core.LinkEntries

  local function storageRows(game, storageId)
    local rows, mons = {}, {}
    for _, d in ipairs(LE.listAll(storageId)) do
      local entryRows, entryMons = LE.lostRows(game, d, LE.orphanPools(d))
      for i, row in ipairs(entryRows) do
        rows[#rows + 1] = row
        mons[#mons + 1] = entryMons[i]
      end
    end
    return rows, mons
  end

  local function pageChoices()
    local pages = {}
    for _, record in ipairs(core.CustomStorage.listCustomStorages()) do pages[#pages + 1] = { id = record.id, label = record.name } end
    return pages
  end

  local function bankContainer()
    return {
      id = "bank", label = "BANK",
      getPages = #core.CustomStorage.listCustomStorages() > 1 and pageChoices or nil,
      title = function(_, pageId)
        local record = pageId and core.CustomStorage.getCustomStorage(pageId)
        return record and core.truncateName(record.name:upper(), 16) or nil
      end,
      build = function(game, pageId)
        local rows, mons = storageRows(game, pageId or mod.id)
        return rows, { messageBox = true, noSound = true, wrap = true }, mons
      end,
    }
  end

  local function buildLostScreen(game) return core.entryScreen(game, { bankContainer() }, { screenId = SCREEN_ID, readOnly = true, counter = true }) end

  mod.content.screens:register(SCREEN_ID, { new = buildLostScreen })
  mod.exports.lostScreenId = SCREEN_ID
  mod.log:info("Pokemon Bank: Lost viewer ready")
  return { screenId = SCREEN_ID }
end

return Module
