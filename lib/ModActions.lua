local V = ...

local GameVersion = require("src.core.GameVersion")

local Module = {}

function Module.install(mod)
  local ModActions = {
    openSummary = function(game, mon)
      mod.exports.reshapeForActiveGame(game, mon)
      local Screens = require("src.ui.Screens")
      if GameVersion.generation() == 2 then
        Screens.push(game, "Gen2SummaryMenu", { mon = mon, onClose = function() game.stack:pop() end })
      else Screens.push(game, "SummaryMenu", mon) end
    end,
    emitOnSuccess = function(fn, eventName, payloadFn)
      return function(...)
        local ok, err = fn(...)
        if ok then mod.events:emit(eventName, payloadFn(...)) end
        return ok, err
      end
    end,
    makeTabToggle = function(optionKey)
      local enabledByOthers = true
      return {
        enabled = function() return enabledByOthers and mod.options:get(optionKey) == true end,
        setEnabled = function(value)
          enabledByOthers = value ~= false
          return true
        end
      }
    end
  }
  return ModActions
end

return Module
