--[[
  TekkenA11y 0.7.0 - screen reader and audio cues for Tekken 8 (UE4SS Lua mod)

  Speech and sounds come from speaker\TekkenA11yHelper.exe (Prism + a small
  synth), fed through a named pipe, so there is no file polling between a
  key press and speech. Menus are read from the game's own Blueprint events
  (menus.lua); the fight beacon reads fighter positions (fight.lua).

  Keys: F5 fight status, F6 beacon on/off, F7 repeat move with notes,
        F8 repeat last speech, F9 read screen, F11 speech on/off.
]]
local MOD_DIR = (package.path or ""):match("([^;]*[\\/]Mods[\\/]TekkenA11y)[\\/]Scripts")

local Out   = require("out")
local UI    = require("lib/ui")
local Menus = require("menus")
local Fight = require("fight")

print("[A11y] TekkenA11y 0.7.0 loading\n")

-- helper process: one instance, exits with the game
if MOD_DIR then
    os.execute('start "" "' .. MOD_DIR .. '\\speaker\\TekkenA11yHelper.exe"')
end

do
    local f = MOD_DIR and io.open(MOD_DIR .. "\\dev.txt", "r")
    if f then f:close(); local ok, e = pcall(require, "dev"); if not ok then print("[A11y] dev: " .. tostring(e) .. "\n") end end
end

-- ---------------------------------------------------------------- keys
local function bind(key, fn)
    if not Key[key] then return end
    RegisterKeyBind(Key[key], function()
        local ok, err = pcall(fn)
        if not ok then Out.log("key " .. key .. ": " .. tostring(err)) end
    end)
end

local function read_screen()
    local parts, seen = {}, {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if UI.shown(w) then
            local t = UI.read(w)
            if t ~= "" and not seen[t] then seen[t] = true; parts[#parts + 1] = t end
        end
    end
    Out.say(#parts > 0 and table.concat(parts, ". ") or "No text on screen.", true)
end

bind("F5", Fight.status)
bind("F6", Fight.toggle_beacon)
bind("F7", Menus.repeat_move)
bind("F8", function() Out.send("S1\t" .. (Out.last ~= "" and Out.last or "Nothing yet.")) end)
bind("F9", read_screen)
bind("F11", function()
    Out.enabled = not Out.enabled
    Out.send("S1\t" .. (Out.enabled and "Speech on" or "Speech off"))
end)

-- ---------------------------------------------------------------- loops
-- 50 ms: delayed help text; once a second, hook classes that have loaded.
-- RegisterHook runs on the game thread only: called from this async thread
-- while a hooked function fired on the game thread, it deadlocked UE4SS.
local n50 = 0
local scan_busy = false
LoopAsync(50, function()
    Out.tick()
    n50 = n50 + 1
    if n50 % 20 == 0 and not scan_busy then
        scan_busy = true
        -- in a fight, scan only while a pause/practice menu is open
        local scan = n50 % 40 == 0 and (not Fight.active() or Fight.menu_open())
        ExecuteInGameThread(function()
            local ok, err = pcall(function()
                if scan then Menus.scan_classes() end
                if not Fight.active() and UI.shown(FindFirstOf("WBP_UI_MainMenu_C")) then Menus.preload() end
                Menus.register_pending()
            end)
            if not ok then Out.log("scan: " .. tostring(err)) end
            scan_busy = false
        end)
    end
    return false
end)

-- 40 ms: deferred menu reads, fight beacon
local fight_busy = false
LoopAsync(40, function()
    if fight_busy then return false end
    fight_busy = true
    ExecuteInGameThread(function()
        Menus.run_deferred()
        local ok, err = pcall(Fight.tick)
        if not ok then Out.log("fight: " .. tostring(err)) end
        fight_busy = false
    end)
    return false
end)

Out.say("Tekken accessibility loaded.")
print("[A11y] loaded\n")
