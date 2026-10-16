--[[
  lib/state_tracker.lua  -- port of SF6Access GameStateTracker
  ----------------------------------------------------------------------------
  has_changed(key, value) returns true only when `value` differs from the last
  value stored under `key`, OR the stored value has gone stale. The expiry is
  what lets a single-option menu re-announce when you leave and come back
  (otherwise it would be silent on every visit after the first).
]]

local Config = require("config")

local ST = {}
local tracked = {} -- key -> { value=, tick= }

local function now_ms()
    return math.floor((os.clock() or 0) * 1000)
end

function ST.has_changed(key, value)
    local prev = tracked[key]
    if prev and prev.value == value then
        return false
    end
    tracked[key] = { value = value }
    return true
end

function ST.clear() tracked = {} end
function ST.remove(key) tracked[key] = nil end

return ST
