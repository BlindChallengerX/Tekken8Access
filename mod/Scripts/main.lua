--[[
  TekkenA11y 1.0 - screen reader and audio cues for Tekken 8 (UE4SS Lua mod)

  Speech and sounds come from speaker\TekkenA11yHelper.exe (Prism + a small
  synth), fed through a named pipe, so there is no file polling between a
  key press and speech. Menus are read from the game's own Blueprint events
  (menus.lua); the fight beacon reads fighter positions (fight.lua).

  Keys: F1 / Shift+F1 Arcade Quest: next / previous person or machine,
        F3 subtitles on/off, F4 Tekken Ball sound on/off, F5 fight status (Arcade Quest: objective and pick),
        Shift+F5 story fight control list,
        F6 beacon on/off, F7 repeat move with notes, F8 repeat last speech,
        F2 throw break sounds on/off, F9 read screen, F11 speech on/off.

  Threads: everything that touches the game runs on the game thread, inside
  the game's own per-frame Blueprint ticks (frame() below). UE4SS 3.0.1 hung
  the game (game thread waiting for the Lua lock while UE4SS's async thread,
  holding it, waited on the game-thread queue) when work was sent there with
  LoopAsync + ExecuteInGameThread, so neither is used for regular work. The
  one async loop only registers the frame hooks at startup and then stops.
]]
local MOD_DIR = (package.path or ""):match("([^;]*[\\/]Mods[\\/]TekkenA11y)[\\/]Scripts")

local Out   = require("out")
local UI    = require("lib/ui")
local Menus = require("menus")
local Fight = require("fight")
Fight.dir = MOD_DIR
local Watch = require("watch")
local TAM   = require("tam")
local Prof  = require("lib/prof")

print("[A11y] TekkenA11y 1.0 loading\n")

-- helper process: one instance, exits with the game
if MOD_DIR then
    os.execute('start "" "' .. MOD_DIR .. '\\speaker\\TekkenA11yHelper.exe"')
end

local Dev = nil
do
    local f = MOD_DIR and io.open(MOD_DIR .. "\\dev.txt", "r")
    if f then
        f:close()
        local ok, e = pcall(require, "dev")
        if ok then Dev = e else print("[A11y] dev: " .. tostring(e) .. "\n") end
    end
end

-- ---------------------------------------------------------------- keys
-- Key callbacks run on UE4SS's own thread: they only queue the action, the
-- next frame on the game thread performs it.
local key_queue = {}
local function bind(key, fn, mod)
    if not Key[key] then return end
    if mod then
        RegisterKeyBind(Key[key], { ModifierKey[mod] }, function() key_queue[#key_queue + 1] = { key, fn } end)
    else
        RegisterKeyBind(Key[key], function() key_queue[#key_queue + 1] = { key, fn } end)
    end
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

bind("F3", Menus.toggle_subtitles)
bind("F4", Fight.toggle_ball)
bind("F5", function() if not TAM.status() then Fight.status() end end)
bind("F5", function() if not require("story").controls() then Out.say("No control list here.", true) end end, "SHIFT")
bind("F1", function() TAM.next(1) end)
bind("F1", function() TAM.next(-1) end, "SHIFT")
bind("F6", Fight.toggle_beacon)
bind("F7", Menus.repeat_move)
bind("F8", function() Out.send("S1\t" .. (Out.last ~= "" and Out.last or "Nothing yet.")) end)
bind("F9", read_screen)
bind("F2", Fight.toggle_throws)
bind("F11", function()
    Out.enabled = not Out.enabled
    Out.send("S1\t" .. (Out.enabled and "Speech on" or "Speech off"))
end)

-- ---------------------------------------------------------------- frame
-- Runs at most every 35 ms on the game thread: keys, the delayed help line,
-- deferred menu reads, screen watchers, subtitles, the fight beacon.
local last_run, n = -1, 0
local function step(name, fn)
    local t0 = os.clock()
    local ok, err = pcall(fn)
    Prof.add(name, os.clock() - t0)
    if not ok then Out.log(name .. ": " .. tostring(err)) end
end

local function frame()
    local t = os.clock()
    if t - last_run < 0.035 then return end
    last_run = t
    n = n + 1
    while #key_queue > 0 do
        local k = table.remove(key_queue, 1)
        step("key " .. k[1], k[2])
    end
    step("out", Out.tick)
    step("deferred", Menus.run_deferred)
    if not Fight.active() then step("watch", Watch.tick); step("tam", TAM.tick) end
    step("subtitles", Watch.subtitles)
    step("fight", Fight.tick)
    step("challenge", Menus.challenge_tick)
    if Dev then step("dev", Dev.poll) end
    if A11Y_MAINT then A11Y_MAINT() end
    Prof.flush(Out.log, Fight.active())
end

-- Per-frame Blueprint events: the effect managers tick in menus and battles,
-- the information bar wherever it shows. Several are hooked; frame() runs
-- once per 35 ms whichever arrives first.
local FRAME_HOOKS = {
    "/Game/Blueprints/BP_PolarisEffectManager.BP_PolarisEffectManager_C:ReceiveTick",
    "/Game/Stage/Common/Blueprints/BP_PolarisStageEffectManager.BP_PolarisStageEffectManager_C:ReceiveTick",
    "/Game/Blueprints/BP_PolarisItemEffectManager.BP_PolarisItemEffectManager_C:ReceiveTick",
    "/Game/UI/Widget/Elements/WBP_UI_InformationBar.WBP_UI_InformationBar_C:Tick",
}
for _, p in ipairs(FRAME_HOOKS) do Menus.add_pending(p, frame) end
-- Arcade Quest: the avatar's tick hands tam.lua the player (no searches)
for _, h in ipairs(TAM.HOOKS) do Menus.add_pending(h[1], h[2]) end

-- Maintenance: register hooks for classes that have loaded, load the screens
-- we hook, look for new widget classes and the subtitle widget. Runs on the
-- game thread from inside the mod's hooks (frame() and the bootstrap hook),
-- at most once a second. Never on UE4SS's async thread:
--   * RegisterHook from the async thread, on a function the game thread was
--     running, crashed UE4SS (access violation in hook dispatch);
--   * ExecuteInGameThread from the async thread waits for a lock the game
--     thread holds while it runs a Lua hook, and that hook waits for the Lua
--     lock the async thread holds: the game hung (user saw "fatal error").
-- Searches cost a frame or more (FindFirstOf 10-25 ms, a class scan ~36 ms,
-- a StaticFindObject miss ~13 ms),
-- so none happen in a fight, and scans only right after menu activity.
local last_maint, preload_done, last_scan, last_sub_find = -10, false, -10, -10
local function maint()
    local t = os.clock()
    if t - last_maint < 1.0 then return end
    last_maint = t
    -- hooks: lookups that find nothing cost ~13 ms, so check_pending keeps
    -- them to one a pass and none in a fight (menus.lua)
    Menus.check_pending(Fight.active())
    if Menus.pending_ready then Menus.register_pending() end
    if Fight.active() then return end
    if not preload_done and t - Menus.last_menu_t < 3 then
        local mm = FindFirstOf("WBP_UI_MainMenu_C")
        if UI.shown(mm) then Menus.preload(); preload_done = true end
    end
    if t - Menus.last_menu_t < 3 and t - last_scan > 5 then last_scan = t; Menus.scan_classes() end
    if not Watch.has_subtitle_widget() and t - last_sub_find > 10 and t - Menus.last_menu_t < 3 then
        last_sub_find = t
        Watch.find_subtitle_widget()
    end
end
A11Y_MAINT = function() step("maint", maint) end

-- Bootstrap: one hook on the information bar's message (it fires when a
-- screen or help line changes, not every frame), registered from the async
-- thread before any of the mod's hooks exist; the loop then stops for good.
-- Its callback runs maintenance, which hooks the per-frame ticks.
local BOOT = "/Game/UI/Widget/Elements/WBP_UI_InformationBar.WBP_UI_InformationBar_C:OnSetMessage"
LoopAsync(500, function()
    if pcall(RegisterHook, BOOT, function(ctx)
        step("info bar", function() Menus.on_info_bar(ctx) end)
        step("maint", maint)
    end) then
        print("[A11y] boot hook on\n")
        return true
    end
    return false
end)

Out.say("Tekken accessibility loaded.")
print("[A11y] loaded\n")
