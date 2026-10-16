--[[
  lib/screen_reader.lua  -- port of SF6Access ScreenReaderService
  ----------------------------------------------------------------------------
  Sends text to the in-process C++ Tolk speaker via the %TEMP% outbox.
  Carries over SF6Access's hard-won dedup logic:
    * drop identical announcements fired back-to-back (short 250ms window)
    * drop a line that is CONTAINED in what was just spoken (a menu says
      "Profile. <description>" and a guide watcher then re-emits <description>)
    * remember LastInterruptTick so low-priority readers can queue after the
      item name instead of cutting it off
]]

local Config = require("config")

local SR = {}

local last_text = nil
local last_tick = 0
SR.last_interrupt_tick = 0

local seq = 0
local function temp_base()
    return os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
end
local OUTBOX = temp_base() .. "\\TekkenA11y\\outbox"

local dir_ready = false
local function ensure_dir()
    if dir_ready then return end
    os.execute('if not exist "' .. OUTBOX .. '" mkdir "' .. OUTBOX .. '" >NUL 2>&1')
    dir_ready = true
end

local function now_ms()
    return math.floor((os.clock() or 0) * 1000)
end

local function write_outbox(interrupt, text)
    ensure_dir()
    seq = seq + 1
    local stem = OUTBOX .. "\\msg_" .. string.format("%08d", seq)
    local f = io.open(stem .. ".tmp", "w")
    if not f then return end
    f:write((interrupt and "1" or "0") .. "\n")
    f:write(text)
    f:close()
    os.rename(stem .. ".tmp", stem .. ".txt") -- atomic publish
end

-- text      : string
-- interrupt : cut current speech (default true)
function SR.speak(text, interrupt)
    if type(text) ~= "string" then return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    if interrupt == nil then interrupt = true end

    local now = now_ms()
    if last_text ~= nil and (now - last_tick) < Config.timing.dedupe_window_ms then
        -- identical, or fully contained in the line just spoken
        if text == last_text or last_text:find(text, 1, true) then
            return
        end
    end
    last_text = text
    last_tick = now
    if interrupt then SR.last_interrupt_tick = now end

    write_outbox(interrupt, text)
end

function SR.outbox_path() return OUTBOX end

return SR
