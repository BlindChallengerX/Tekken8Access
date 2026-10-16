--[[
  TekkenA11y v0.6 - main.lua  (event-driven, no-lag model, matching SF6Access)
  ----------------------------------------------------------------------------
  The lag came from polling the whole UI several times a second. SF6Access never
  does that -- it hooks the game's navigation function and reads the item the
  game hands it. So this version does NO UI scanning in its loop:

    * the loop only writes a heartbeat (keeps the speaker alive). Near-zero cost.
    * menu reading comes from selection hooks (config.tekken.selection_hooks),
      registered once and fired by the game -- added after the dump.
    * subtitles are the one optional poll (a single widget), OFF by default,
      toggled with F10. Even that is one lookup, not a full scan.

  Manual keys (F8 read focused, F9 read screen, F11 dump) always work.
]]

local Config = require("config")
local SR     = require("lib/screen_reader")
local Nav    = require("hooks/navigation")
local Subs   = require("hooks/subtitles")
local Dumper = require("lib/dumper")

print("[A11y] TekkenA11y v0.6 loading...")

local function temp_dir()
    return (os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp") .. "\\TekkenA11y"
end
local HEARTBEAT = temp_dir() .. "\\heartbeat"

-- master on/off for automatic reading (F6). Declared here so the keybind
-- closure below captures this exact local.
local master_enabled = true

-- deferred speaker launch (never blocks startup)
local launched = false
local function launch_speaker_once()
    if launched then return end
    launched = true
    local mod_dir
    for entry in package.path:gmatch("[^;]+") do
        local d = entry:match("(.-[\\/]Mods[\\/]TekkenA11y)[\\/]Scripts")
        if d then mod_dir = d break end
    end
    if not mod_dir then return end
    pcall(function() os.execute('start "" "' .. mod_dir .. '\\speaker\\TekkenA11ySpeech.exe"') end)
end

-- ---- hotkeys --------------------------------------------------------------
local function bind(key_name, fn)
    local key = Key[key_name]
    if not key then return end
    RegisterKeyBind(key, function()
        local ok, err = pcall(fn)
        if not ok then print("[A11y] keybind error: " .. tostring(err)) end
    end)
end

bind(Config.keys.read_focused,     function() Nav.read_focused() end)
bind(Config.keys.read_screen,      function() Nav.read_screen() end)
bind(Config.keys.toggle_subs,      function() Subs.toggle() end)
bind(Config.keys.dump,             function() Dumper.dump() end)
bind(Config.keys.toggle_auto_dump, function() Dumper.toggle_auto() end)
bind(Config.keys.toggle_auto,      function()
    master_enabled = not master_enabled
    SR.speak(master_enabled and "Automatic reading on" or "Automatic reading off", true)
end)

local function reg(name, fn)
    RegisterConsoleCommandHandler(name, function()
        pcall(function() ExecuteInGameThread(fn) end) return true
    end)
end
reg("a11y_focus",    function() Nav.read_focused() end)
reg("a11y_screen",   function() Nav.read_screen() end)
reg("a11y_subs",     function() Subs.toggle() end)
reg("a11y_dump",     function() Dumper.dump() end)
reg("a11y_autodump", function() Dumper.toggle_auto() end)
reg("a11y_auto",     function()
    master_enabled = not master_enabled
    SR.speak(master_enabled and "Automatic reading on" or "Automatic reading off", true)
end)

-- register selection hooks (none until the dump tells us the function names)
-- menu selection hooks are registered lazily in the loop (Nav.ensure_hooks),
-- once Tekken's menu widget classes are actually loaded.

-- ---- scheduling --------------------------------------------------------
-- The async callback (NOT the game thread) decides whether any game-thread work
-- is needed this tick. During a match it almost always decides "no" and returns
-- without ever entering ExecuteInGameThread, so the game thread is untouched.
--
--   * In a menu  -> run every tick (responsive reading).
--   * Just left a screen -> stay completely quiet for LOAD_QUIET seconds. This
--     skips the match-load object storm, which is where scanning crashes.
--   * In a match -> probe at a backed-off interval that grows to CLOSED_MAX, so
--     a long match gets only an occasional single lookup -- not per-frame scans.
local busy = false
local hb_div, appear_div = 0, 0
local next_run_at = 0      -- earliest os.clock() at which game-thread work may run
local backoff = 0
local was_open = false
local CLOSED_MIN, CLOSED_MAX, LOAD_QUIET = 1.0, 4.0, 3.0

local function game_tick()
    if Nav.ui_active() then
        was_open = true
        backoff = 0
        next_run_at = os.clock()              -- keep reading every tick in menus
        Nav.poll_active()
        appear_div = appear_div + 1
        if appear_div >= 7 then appear_div = 0; Nav.poll_appear() end
    else
        local now = os.clock()
        if was_open then
            was_open = false
            backoff = LOAD_QUIET              -- screen just vanished: go quiet through load
        else
            Nav.probe_step()                  -- one cheap lookup, then back off further
            backoff = math.min(backoff > 0 and backoff * 1.6 or CLOSED_MIN, CLOSED_MAX)
        end
        next_run_at = now + backoff
    end
    if Subs.enabled then Subs.poll() end
    Dumper.auto_tick()
end

LoopAsync(Config.timing.subtitle_poll_ms, function()
    if busy then return false end

    -- These touch only files/process, never game objects -> safe off-thread.
    launch_speaker_once()
    hb_div = hb_div + 1
    if hb_div >= 13 then
        hb_div = 0
        local f = io.open(HEARTBEAT, "w"); if f then f:write(tostring(os.clock())); f:close() end
    end

    if not master_enabled then return false end
    if os.clock() < next_run_at then return false end   -- nothing due: don't touch game thread

    busy = true
    ExecuteInGameThread(function()
        local ok, err = pcall(game_tick)
        if not ok then print("[A11y] tick error: " .. tostring(err)) end
        busy = false
    end)
    return false
end)

print("[A11y] loaded (no-lag build). Menus need a selection hook (run F11 on a menu). F10 = subtitles.")
SR.speak("Tekken accessibility loaded.", true)
