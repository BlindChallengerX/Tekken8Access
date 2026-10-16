--[[
  hooks/navigation.lua  (v1.2 - stable spread-probe gate, names, capture)
  ----------------------------------------------------------------------------
  Match safety: the gate validates ONE cached root cheaply each tick; while no
  screen is up it probes ONE widget class per ~300ms, spread out so it never
  stalls the game thread. No NotifyOnNewObject and no holding many widget refs
  across frames -- that combination crashed match loads.

  Menus: transition detection (announce the row that just became selected).
  Char select: read the hovered profile, prefix the fighter's NAME via the
  in-game height+weight (ground truth), and keep logging profiles to fill gaps.
]]

local Config = require("config")
local SR  = require("lib/screen_reader")
local ST  = require("lib/state_tracker")
local GTR = require("lib/gui_text_reader")

local Nav = {}
local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end end
local function now_s() local ok, t = pcall(os.clock); return ok and t or 0 end
local function mod_dir()
    local p = package.path or ""
    local d = p:match("(.-[\\/]Mods[\\/]TekkenA11y)[\\/]")
    if d then return d end
    return (os.getenv("TEMP") or ".") .. "\\TekkenA11y"
end

-- Resolve a WRITABLE path for the capture log, mirroring the dumper: try the
-- mod folder, and if it's read-only (Program Files installs) fall back to
-- %TEMP%\TekkenA11y -- the same folder dump.txt lands in.
local capture_resolved = nil
local function capture_path()
    if capture_resolved then return capture_resolved end
    for entry in (package.path or ""):gmatch("[^;]+") do
        local d = entry:match("(.-[\\/]Mods[\\/]TekkenA11y)[\\/]Scripts")
        if d then
            local p = d .. "\\charselect_profiles.txt"
            local f = io.open(p, "a")           -- probe: writable?
            if f then f:close(); capture_resolved = p; return p end
        end
    end
    local t = (os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp") .. "\\TekkenA11y"
    os.execute('if not exist "' .. t .. '" mkdir "' .. t .. '" >NUL 2>&1')
    capture_resolved = t .. "\\charselect_profiles.txt"
    return capture_resolved
end

-- =====================================================================
-- Sentinels
-- =====================================================================
local SCREEN_SENTINELS = {
    "WBP_UI_CharSelect_C", "WBP_UI_StageSelect_C", "WBP_UI_SideSelect_C",
    "WBP_UI_Pause_Menu_C", "WBP_UI_MainMenu_C",
}
local POPUP_SENTINELS = {
    "WBP_UI_Dialog_C", "WBP_UI_Dialog_LR_C", "WBP_UI_News_Content_C",
    "WBP_UI_Notice_C", "WBP_UI_Title_C", "WBP_UI_StartUp_Licence_C",
}

-- =====================================================================
-- State
-- =====================================================================
local ui_root = nil
Nav.screen = nil
local prev_screen_set = {}    -- last screen-text set (diff)
local prev_state = {}         -- short -> { index -> last State } (numbers only)

local function set_screen(short, w)
    if Nav.screen ~= short then
        Nav.screen = short
        ST.clear()
        prev_state = {}        -- drop stale per-row transition state
        prev_screen_set = {}
    end
    ui_root = w
end

local function find_visible(short)
    local w = safe(function() return FindFirstOf(short) end)
    if w and GTR.is_valid(w) and GTR.is_visible(w) then return w end
    return nil
end

-- =====================================================================
-- Gate: validate the single cached root cheaply; only probe (one class per
-- call, spread out) while no screen is up. We deliberately do NOT use
-- NotifyOnNewObject or hold many widget refs across frames -- that destabilized
-- match loads. This is the spread-probe gate that ran matches cleanly.
-- =====================================================================
function Nav.ui_active()
    if ui_root and GTR.is_valid(ui_root) and GTR.is_visible(ui_root) then return true end
    ui_root = nil; Nav.screen = nil
    return false
end

local PROBE_ROTATION = {
    "WBP_UI_Pause_Menu_C", "WBP_UI_Dialog_C", "WBP_UI_MainMenu_C",
    "WBP_UI_Pause_Menu_C", "WBP_UI_Dialog_C", "WBP_UI_CharSelect_C",
    "WBP_UI_Pause_Menu_C", "WBP_UI_Dialog_C", "WBP_UI_Dialog_LR_C",
    "WBP_UI_Pause_Menu_C", "WBP_UI_Dialog_C", "WBP_UI_StageSelect_C",
    "WBP_UI_Pause_Menu_C", "WBP_UI_Dialog_C", "WBP_UI_SideSelect_C",
    "WBP_UI_News_Content_C", "WBP_UI_Notice_C", "WBP_UI_Title_C",
    "WBP_UI_StartUp_Licence_C",
}
local probe_idx = 0
function Nav.probe_step()
    probe_idx = (probe_idx % #PROBE_ROTATION) + 1
    local short = PROBE_ROTATION[probe_idx]
    local w = find_visible(short)
    if w then set_screen(short, w); return true end
    return false
end

-- =====================================================================
-- Menu reading via transition detection
-- =====================================================================
local MENU_MAX = 220
local function poll_transition(short, selected_values)
    -- fresh lookup every call: we never hold widget references across frames, so
    -- a screen tearing down can't leave us reading freed objects.
    local arr = safe(function() return FindAllOf(short) end)
    if type(arr) ~= "table" then return false end
    local prev = prev_state[short] or {}
    local cur, newly = {}, nil
    local n = math.min(#arr, MENU_MAX)
    for i = 1, n do
        local w = arr[i]
        if w and GTR.is_valid(w) then
            local st = safe(function() return w.State end)
            cur[i] = st
            if not newly then
                for _, sv in ipairs(selected_values) do
                    if st == sv and prev[i] ~= sv then
                        if GTR.is_visible(w) then newly = w end
                        break
                    end
                end
            end
        end
    end
    prev_state[short] = cur
    if newly then
        local txt = GTR.read_first(newly)
        if txt and txt ~= "" then SR.speak(txt, true); return true end
    end
    return false
end

function Nav.poll_menu()
    if poll_transition("WBP_UI_MainMenu_Menu_ListSub_C", { 2, 1 }) then return end
    poll_transition("WBP_UI_MainMenu_Menu_List_C", { 1 })
end

-- =====================================================================
-- Char/stage/side select: profile on change, with names + capture
-- =====================================================================
local SCREEN_IGNORE = {
    ["[ID]"] = true, ["fps"] = true,
    ["Player 1"] = true, ["Player 2"] = true, ["OK"] = true,
    ["Preset 01"] = true, ["Preset 02"] = true, ["Preset 03"] = true, ["DEFAULT PRESET"] = true,
    ["Weight"] = true, ["Height"] = true, ["Nationality"] = true, ["Fighting Style"] = true,
    ["Random Side Selection"] = true, ["Confirm"] = true, ["Back"] = true,
}

local function name_for(text)
    -- key on the in-game height+weight (ground truth from the capture); these
    -- are unique per fighter, so this won't mis-name the way style alone could.
    local cm = text:match("(%d+)%s*cm")
    local kg = text:match("([%d%.]+)%s*kg")
    if cm and kg then
        local nm = (Config.tekken.char_names or {})[cm .. "|" .. kg]
        if nm then return nm end
    end
    return nil
end

-- log unseen profiles so the roster's name table can be filled from ground truth
local captured = {}
local function capture_profile(joined)
    if joined == "" or captured[joined] then return end
    captured[joined] = true
    local f = io.open(capture_path(), "a")
    if f then f:write(joined .. "\r\n"); f:close() end
end

local screen_text_t = 0
function Nav.poll_screen_text()
    local t = now_s()
    if (t - screen_text_t) < 0.4 then return end
    screen_text_t = t

    local blocks = GTR.read_screen({})
    local cur, new_parts = {}, {}
    for _, b in ipairs(blocks) do
        local tx = b.text
        if not SCREEN_IGNORE[tx] and not (#tx <= 3 and tx:match("^%d+$")) then
            cur[tx] = true
            if not prev_screen_set[tx] then new_parts[#new_parts + 1] = tx end
        end
    end
    prev_screen_set = cur
    if #new_parts == 0 then return end

    local joined = table.concat(new_parts, ", ")
    if Nav.screen == "WBP_UI_CharSelect_C" then
        -- full current profile (sorted) for a stable capture line + name lookup
        local full = {}
        for k in pairs(cur) do full[#full + 1] = k end
        table.sort(full)
        local full_joined = table.concat(full, ", ")
        capture_profile(full_joined)

        local nm = name_for(full_joined)
        if nm then joined = nm .. ". " .. joined end
    end
    SR.speak(joined, true)
end

-- =====================================================================
-- Pop-ups
-- =====================================================================
local last_appear = {}
function Nav.poll_appear()
    for _, short in ipairs(POPUP_SENTINELS) do
        local arr = safe(function() return FindAllOf(short) end)
        local found = nil
        if type(arr) == "table" then
            for _, w in ipairs(arr) do
                if GTR.is_valid(w) and GTR.is_visible(w) then
                    local txt = GTR.read_joined(w, ". ")
                    if txt and txt ~= "" then found = txt break end
                end
            end
        end
        if found then
            if last_appear[short] ~= found then last_appear[short] = found; SR.speak(found, false) end
        else
            last_appear[short] = nil
        end
    end
end

-- =====================================================================
-- Router + manual keys
-- =====================================================================
local TEXT_SCREENS = {
    WBP_UI_CharSelect_C = true, WBP_UI_SideSelect_C = true, WBP_UI_StageSelect_C = true,
}
function Nav.poll_active()
    if TEXT_SCREENS[Nav.screen] then
        Nav.poll_screen_text()
    elseif Nav.screen == "WBP_UI_MainMenu_C" or Nav.screen == "WBP_UI_Pause_Menu_C" then
        Nav.poll_menu()
    end
end

function Nav.read_screen()
    local blocks = GTR.read_screen({})
    local parts = {}
    for _, b in ipairs(blocks) do
        local tx = b.text
        if not SCREEN_IGNORE[tx] and not (#tx <= 3 and tx:match("^%d+$")) then parts[#parts + 1] = tx end
    end
    if #parts == 0 then SR.speak("No readable text on screen.", true) return end
    SR.speak(table.concat(parts, ", "), true)
end
function Nav.read_focused() Nav.read_screen() end

return Nav
