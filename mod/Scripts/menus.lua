--[[
  menus.lua - menu reading from Blueprint events (no polling).
  Each entry hooks the Blueprint function the game itself calls when the
  cursor lands on something, and speaks that item at once. Hooks are
  registered as their widget classes load (Menus.register_pending runs from
  an async loop); a class that is not loaded yet just fails and is retried.

  Only Blueprint (script) functions are hooked. Hooking native /Script/
  functions with a Lua callback froze UE4SS's Lua thread on this build.

  Besides the named screens, any widget class that has a typical hover
  function (play_hover, PlayAnimHover, ...) gets a generic reader, so most
  other menus speak their highlighted row too (Menus.scan_classes).
]]
local Out = require("out")
local UI  = require("lib/ui")
local D   = require("data")

local Menus = {}
local safe = UI.safe

local function self_of(ctx) return safe(function() return ctx:get() end) end
local function arg(p) return safe(function() return p:get() end) end

Menus.last_menu_t = -10          -- last time a menu event fired (fight module mutes the beacon)

-- Work to do on the next game-thread tick (main.lua frame(), every ~35 ms).
-- Calling ExecuteInGameThread from inside a hook callback hung the Lua side.
local deferred = {}
function Menus.defer(fn, delay) deferred[#deferred + 1] = { fn = fn, at = os.clock() + (delay or 0) } end
function Menus.run_deferred()
    if #deferred == 0 then return end
    local list, now = deferred, os.clock()
    deferred = {}
    for _, d in ipairs(list) do
        if now >= d.at then
            local ok, err = pcall(d.fn)
            if not ok then Out.log("deferred: " .. tostring(err)) end
        else
            deferred[#deferred + 1] = d
        end
    end
end
local function touched() Menus.last_menu_t = os.clock() end

-- ---------------------------------------------------------------- help text
Menus.row_t = -10                -- last time a practice-menu row was spoken

-- Practice menu: Enter and Esc between columns do not always move a cursor,
-- so when the help line changes and no row was spoken, work out the focused
-- column and read its row. A row's is_active flag marks the parent of the
-- open column: an active row in column 2 means the value list has focus (its
-- own cursor event reads it), one in column 1 means column 2 has focus,
-- none means column 1. The cursor index is the last one the game sent for
-- that column (Menus.pm_last; it also sends column 2's as a preview).
Menus.pm_last = {}
local function any_active(lv)
    local n = safe(function() return lv:GetNumItems() end) or 0
    for i = 0, n - 1 do
        local w = safe(function() return lv:GetItemAt(i).Widget end)
        if UI.valid(w) and safe(function() return w.is_active end) then return true end
    end
    return false
end

local read_practice_row     -- defined with the cursor handlers below

local function practice_fallback()
    if os.clock() - Menus.row_t < 0.4 then return end
    local m = safe(function() return FindFirstOf("WBP_UI_PracticeMenu_C") end)
    if not UI.shown(m) then return end
    if any_active(safe(function() return m.ListView_2 end)) then return end
    local col = any_active(safe(function() return m.ListView_1 end)) and 2 or 1
    local i = Menus.pm_last[col]
    if i then read_practice_row(m, col, i) end
end

-- The information bar at the bottom explains the highlighted item.
local function info_bar(w)
    local t = UI.read(w)
    if t ~= "" then Out.help(t) end
    Menus.defer(practice_fallback, 0.12)   -- the highlight flag updates a little later
end

-- ---------------------------------------------------------------- generic
local generic_last, generic_t = nil, -1
local function generic_hover(ctx)
    local w = self_of(ctx)
    if not w then return end
    local t = UI.read(w)
    if t == "" or (t == generic_last and os.clock() - Menus.last_menu_t < 0.15) then return end
    generic_last, generic_t = t, os.clock()
    touched()
    Out.say(t)
end

-- ---------------------------------------------------------------- char select
local cs = { name = nil, side = nil, info = nil, sel_t = 0, name_t = 0 }
local function fighter_info(p)
    local s = arg(p)
    if not s then return nil end
    local f = {}
    for _, k in ipairs({ "style", "Origin", "Height", "Weight" }) do
        local v = safe(function() return s[k]:ToString() end)
        if v and v:find("^TEXT_") then v = UI.clean(UI.loc(v)) end
        if v and v ~= "" and v ~= "Unknown" and v ~= "99" then f[#f + 1] = v end
    end
    if #f == 0 then return nil end
    return table.concat(f, ", ")
end

local function on_name(ctx, left, id)
    local i = arg(id)
    if type(i) ~= "number" then return end
    local t = os.clock()
    -- right after a pick the game re-sends both sides' names
    if cs.decided_t and t - cs.decided_t < 0.4 then return end
    touched()
    local nm = D.fighter(i)
    cs.name_t = t
    cs.name = nm
    -- the cursor on the other side (practice/versus opponent) is marked
    local is_left = arg(left)
    local mine_left = Menus.side ~= 1
    if is_left ~= nil and is_left ~= mine_left then Out.say("Opponent: " .. nm) else Out.say(nm) end
end

local function on_info(ctx, left, info)
    -- only right after a cursor move (it is re-sent after a pick)
    if os.clock() - (cs.name_t or 0) > 0.3 then return end
    local t = fighter_info(info)
    if t then Out.help(t) end
end

local function on_decided(ctx)
    touched()
    if cs.name then
        Out.say(cs.name .. " selected")
        cs.decided, cs.decided_t = cs.name, os.clock()
    end
end

-- ---------------------------------------------------------------- stage select
-- fires every frame, and on Random it cycles through preview ids: speak
-- only when the spoken name changes
local stage_last = nil
local function on_stage(ctx, id)
    local i = arg(id)
    if type(i) ~= "number" then return end
    local w = self_of(ctx)
    local rnd = w and safe(function() return w.WBP_UI_StageSelect_RandomBG:IsVisible() end)
    local name = rnd and "Random" or D.stage(i)
    if name == stage_last then return end
    stage_last = name
    touched()
    Out.say(name)
end

-- ---------------------------------------------------------------- practice / pause menu
-- practice menu list items (BP_PracticeMenu_Button_*_item_C) keep their row
-- widget in .Widget
local function list_row(lv, index)
    local item = safe(function() return lv:GetItemAt(index) end)
    if not UI.valid(item) then return nil end
    local e = safe(function() return item.Widget end)
    if not UI.valid(e) then return nil end
    return e
end

local function skip_practice(n, t)
    return n:find("TB_Rate") or n:find("TB_Button") or n:find("_OFF")
end

-- the item's own text ids, for rows whose widget is not built yet (first
-- row right after a menu opens)
local function item_text(lv, index)
    local item = safe(function() return lv:GetItemAt(index) end)
    if not UI.valid(item) then return "" end
    local parts = {}
    for _, k in ipairs({ "Text", "text2" }) do
        local id = safe(function() return item[k]:ToString() end)
        local s = id and id ~= "" and (id:find("^TEXT_") and UI.clean(UI.loc(id)) or UI.clean(id))
        if s and s ~= "" then parts[#parts + 1] = s end
    end
    return table.concat(parts, ", ")
end

-- get_lv(menu) returns the list view the cursor function belongs to. The
-- read waits for the next tick: when a submenu opens, its cursor is set
-- before its list is filled.
-- The game re-sends every column's cursor on each move (and the next
-- column's cursor as a preview), and the menu's own layer fields never
-- change. So all cursor calls of one tick are collected and only the column
-- whose index actually changed is spoken; the first column wins, and on
-- opening the menu the first column is read.
local PM_LISTS = {
    function(m) return m.ListView_1 end,
    function(m) return m.ListView_2 end,
    function(m) return m.WBP_UI_PracticeMenu_Menu_3.ListView_3 end,
    function(m) return m.ListView_4 end,
}
local pm_last = Menus.pm_last
local pm_batch, pm_menu, pm_t = nil, nil, -10

read_practice_row = function(m, col, i)
    local lv = safe(function() return PM_LISTS[col](m) end)
    local row = list_row(lv, i)
    local t = row and UI.read(row, skip_practice) or ""
    if t == "" then t = item_text(lv, i) end
    if t ~= "" then touched(); Menus.row_t = os.clock(); Out.say(t) end
end

local function practice_flush()
    local b, m = pm_batch, pm_menu
    pm_batch = nil
    if not b or not UI.valid(m) then return end
    local opened = os.clock() - pm_t > 2
    pm_t = os.clock()
    local pick
    if b[1] and (opened or b[1] ~= pm_last[1]) then pick = 1
    else
        for _, l in ipairs({ 3, 4, 2 }) do
            if b[l] and b[l] ~= pm_last[l] then pick = l; break end
        end
    end
    for l, i in pairs(b) do pm_last[l] = i end
    if not pick then return end           -- only a refresh; the help-line fallback may read
    read_practice_row(m, pick, b[pick])
end

local function practice_cursor(layer)
    return function(ctx, index)
        local m = self_of(ctx)
        local i = arg(index)
        if not m or type(i) ~= "number" then return end
        if not pm_batch then pm_batch = {}; Menus.defer(practice_flush) end
        pm_batch[layer], pm_menu = i, m
    end
end


-- ---------------------------------------------------------------- move list
local ml = { count = -1 }
local function movelist_item(m, i)
    local lv = safe(function() return m.WBP_UI_CommandList_Win.ListView_1 end)
    if not lv then return nil, 0 end
    return safe(function() return lv:GetItemAt(i) end), safe(function() return lv:GetNumItems() end) or 0
end

function Menus.move_text(it)
    local function f(field) return safe(function() return it[field]:ToString() end) or "" end
    local name = safe(function() return it.isRawNameText end) and f("nameText") or UI.loc(f("nameText"))
    local cmd = UI.clean(UI.loc(f("commandText"))) or ""
    local note = UI.clean(UI.loc(f("noteText"))) or ""
    local dmg = f("damageText")
    if dmg ~= "" then dmg = UI.clean(UI.loc(dmg)) or dmg end
    return UI.clean(name) or "", cmd, note, dmg or ""
end

local function movelist_tab(m)
    for k = 1, 3 do
        local tab = safe(function() return m.WBP_UI_CommandList_Win["WBP_UI_CommandList_Tab_" .. k] end)
        if tab then
            local on = safe(function() return tab.is_select or tab.IsSelect end)
            local t = UI.read(tab)
            if on and t ~= "" then return t end
        end
    end
    return nil
end

local function on_movelist_cursor(ctx, index)
    local m = self_of(ctx)
    local i = arg(index)
    if not m or type(i) ~= "number" then return end
    local it, count = movelist_item(m, i)
    if not it then return end
    touched()
    local name, cmd, note, dmg = Menus.move_text(it)
    local heading = safe(function() return it.isHeading end)
    local no = safe(function() return it.no end)
    local text
    if heading then
        text = name .. ", heading"
    else
        local numbered = name:match("^%d+%.")
        text = (no and no > 0 and not numbered and (no .. ". ") or "") .. name
        if cmd ~= "" then text = text .. ". " .. cmd end
    end
    if count ~= ml.count then
        if ml.count >= 0 then text = count .. " moves. " .. text end
        ml.count = count
    end
    Out.say(text)
    local extra = {}
    if note ~= "" then extra[#extra + 1] = note end
    if dmg ~= "" then extra[#extra + 1] = dmg end
    if #extra > 0 then Out.help(table.concat(extra, ". ")) end
    Menus.current_move = { name = name, cmd = cmd, note = note, dmg = dmg }
end

-- ---------------------------------------------------------------- dialogs
-- a dialog is drawn by two widgets (frame + menu); the second repeats the
-- question, so skip text already inside the line just spoken. Some dialogs
-- (controller assignment) replay their open animation every second: while
-- the same text keeps firing, it is not repeated.
local dialog_last, dialog_t = "", -1
local function on_dialog(ctx)
    local w = self_of(ctx)
    if not w then return end
    local t = UI.read(w)
    if t == "" then return end
    if os.clock() - dialog_t < 1.5 and dialog_last:find(t, 1, true) then dialog_t = os.clock() return end
    dialog_last, dialog_t = t, os.clock()
    touched()
    -- the default button is selected just before the dialog animates in:
    -- read the question first, then that button again
    local btn = os.clock() - generic_t < 0.8 and generic_last or nil
    Out.say(t, true)
    if btn and btn ~= t then Out.queue(btn) end
end

-- ---------------------------------------------------------------- text events
-- Functions that receive the text to show (Arcade Quest talk and
-- tutorial captions, Tekken Ball info): speak their text arguments. The
-- arguments are also logged, to finish mapping screens not tested yet.
Menus.subtitles = true           -- read by watch.lua (F3)
local args_last, args_t = "", -1
local function speak_args(label, interrupt)
    return function(ctx, ...)
        local parts, raw = {}, {}
        for _, p in ipairs({ ... }) do
            local t = UI.arg_text(p)
            if t then parts[#parts + 1] = t end
            raw[#raw + 1] = tostring(safe(function() local v = p:get(); return type(v) == "userdata" and (safe(function() return v:ToString() end) or "obj") or v end))
        end
        Out.log(label .. "(" .. table.concat(raw, ", ") .. ")")
        if #parts == 0 then return end
        local t = table.concat(parts, ". ")
        if t == args_last and os.clock() - args_t < 1 then return end
        args_last, args_t = t, os.clock()
        touched()
        if interrupt then Out.say(t, true) else Out.queue(t) end
    end
end

function Menus.toggle_subtitles()
    Menus.subtitles = not Menus.subtitles
    Out.say(Menus.subtitles and "Subtitles on" or "Subtitles off", true)
end

-- ---------------------------------------------------------------- Tekken Ball select
-- Ball select: WBP_UI_TB_BallSlot_C:OnCursorMoveUMG(count, index, ...); the
-- names are on WBP_UI_TB_BallSlot_Panel_C (SlotNum, side, IsLocked,
-- TB_name_1P / _2P). The description comes in OnSetInfoUMG(text).
local function ball_slot_cursor(ctx, count, index)
    local w = self_of(ctx)
    local i = arg(index)
    if not w or type(i) ~= "number" then return end
    local side = safe(function() return w.side end) or 0
    touched()
    Menus.defer(function()
        for _, p in ipairs(FindAllOf("WBP_UI_TB_BallSlot_Panel_C") or {}) do
            if UI.valid(p) and safe(function() return p.SlotNum == i and p.side == side and p:IsVisible() end) then
                local nm = UI.clean(UI.text_of(safe(function() return p["TB_name_" .. (side + 1) .. "P"] end)) or "")
                if nm and not nm:find("^Preset") then
                    if safe(function() return p.IsLocked end) then nm = nm .. ", locked" end
                    Out.say(nm)
                    if Menus.ball_info then Out.help(Menus.ball_info) end
                    return
                end
            end
        end
    end)
end

-- arrives in the same frame as the cursor event, before the name is read:
-- kept and given to the help line after the name
local function ball_slot_info(ctx, text)
    Menus.ball_info = UI.arg_text(text)
end

-- Ball damage: WBP_UI_TB_DamageSet_C:OnCursorMoveUMG(level, ...); the value is
-- shown in WBP_UI_TB_DamageSet_Window_C (side, TB_num)
local damage_first = true
local function damage_cursor(ctx)
    touched()
    Menus.defer(function()
        local side = Menus.side or 0
        for _, win in ipairs(FindAllOf("WBP_UI_TB_DamageSet_Window_C") or {}) do
            if UI.valid(win) and safe(function() return win.side == side and win:IsVisible() end) then
                local n = UI.text_of(safe(function() return win.TB_num end))
                if n then
                    Out.say((damage_first and "Ball damage, " or "") .. n .. " percent")
                    damage_first = false
                end
                return
            end
        end
    end)
end

-- ---------------------------------------------------------------- story chapters
-- WBP_UI_Story_ChapterSelect_C:SetChapterTitleText fills TB_ChapterName_Main
-- ("Chapter 1") and TB_ChapterName_Sub (its name); read them a tick later
local chapter_last = ""
local function on_chapter(ctx)
    local w = self_of(ctx)
    touched()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local main = UI.clean(UI.text_of(safe(function() return w.TB_ChapterName_Main end)) or "") or ""
        local sub = UI.clean(UI.text_of(safe(function() return w.TB_ChapterName_Sub end)) or "") or ""
        local t = main .. (sub ~= "" and (", " .. sub) or "")
        if t ~= "" and t ~= chapter_last then chapter_last = t; Out.say(t) end
    end)
end

-- ---------------------------------------------------------------- hook table
local CS = "/Game/UI/Widget/CharSelect/WBP_UI_CharSelect.WBP_UI_CharSelect_C:"
local SS = "/Game/UI/Widget/StageSelect/WBP_UI_StageSelect.WBP_UI_StageSelect_C:"
local SD = "/Game/UI/Widget/SideSelect/WBP_UI_SideSelect.WBP_UI_SideSelect_C:"
local MM = "/Game/UI/Widget/MainMenu/"

local SPECS = {
    { CS .. "OnSetCurrentName", on_name },
    { CS .. "OnSetCurrentFighterInfo", on_info },
    { CS .. "OnDecided1P", on_decided },
    { CS .. "OnDecided2P", on_decided },
    { SS .. "_SetSelectedStageID", on_stage },
    -- the side chosen here decides which fighter the beacon treats as "me"
    { SD .. "OnSelectLeftSide", function() touched(); Menus.side = 0; Out.say("Left side") end },
    { SD .. "OnSelectRightSide", function() touched(); Menus.side = 1; Out.say("Right side") end },
    { MM .. "WBP_UI_MainMenu_Menu_List.WBP_UI_MainMenu_Menu_List_C:play_hover", function(ctx) Menus.side = nil; generic_hover(ctx) end },
    -- in-match pause menu (arcade, versus, story...)
    { "/Game/UI/Widget/Pause/WBP_UI_Pause_MenuButton.WBP_UI_Pause_MenuButton_C:Select", generic_hover },
    -- Jukebox preset window (Preset / Shuffle); the other Jukebox lists are watched (watch.lua)
    { "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox_PresetWin.WBP_UI_JukeBox_PresetWin_C:Select", function(ctx, i) touched(); require("watch").on_preset_select(ctx, i) end },
    -- Tekken Ball: ball and damage select, CPU difficulty
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot.WBP_UI_TB_BallSlot_C:OnCursorMoveUMG", ball_slot_cursor },
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot.WBP_UI_TB_BallSlot_C:OnSetInfoUMG", ball_slot_info },
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_DamageSet.WBP_UI_TB_DamageSet_C:OnCursorMoveUMG", damage_cursor },
    { "/Game/UI/Widget/Dialog/WBP_UI_DifficultySelect_MenuButton.WBP_UI_DifficultySelect_MenuButton_C:Select", generic_hover },
    -- story chapter select
    { "/Game/UI/Widget/Story_ChapterSelect/WBP_UI_Story_ChapterSelect.WBP_UI_Story_ChapterSelect_C:SetChapterTitleText", on_chapter },
    -- story subtitles are read by watch.lua: a hook on CreateFrontSubtitle
    -- fired during a loading screen (another thread) and froze the Lua side
    -- dialogs: read the whole dialog when it opens
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog.WBP_UI_Dialog_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_Menu.WBP_UI_Dialog_Menu_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR.WBP_UI_Dialog_LR_C:OpenDialog", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR_Menu.WBP_UI_Dialog_LR_Menu_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    -- dialog buttons (Yes / No / OK); the LR variant inherits Select
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_TextButton.WBP_UI_Dialog_TextButton_C:Select", generic_hover },
    { "/Game/UI/Widget/Elements/WBP_UI_InformationBar.WBP_UI_InformationBar_C:OnSetMessage", function(ctx) local w = self_of(ctx); if w then info_bar(w) end end },
}
-- classes found at runtime (practice menu, move list) are added by path later
local DYN = {
    WBP_UI_PracticeMenu_C = { { "SetCursorButton1", practice_cursor(1) },
                              { "SetCursorButton2", practice_cursor(2) },
                              { "SetCursorButton3", practice_cursor(3) },
                              { "SetCursorButton4", practice_cursor(4) } },
    WBP_UI_CommandList_C  = { { "SetCursorIndex", on_movelist_cursor } },}
-- function names that mean "this row is now highlighted"
local HOVER_FUNCS = { play_hover = true, PlayAnimHover = true, PlayHover = true, OnHover = true,
                      PlayAnimSelect = true, PlayAnimFocus = true, play_focus = true }
local DIALOG_FUNCS = { PlayAnimIn = true, OpenDialog = true, Open = true }
-- functions handed the text they display (Arcade Quest talk, tutorial
-- captions, Tekken Ball select info): speak the arguments
local TEXT_FUNCS = { OnSetTextId = true, OnSetTelopTextId = true, OnSetTitleTextId = true,
                     OnSetInfoUMG = true }   -- Tekken Ball ball slot has its own handler
-- cursor events with number arguments: logged for now, to map them
local LOG_FUNCS = { OnCursorMoveUMG = true, CallSelectSlotCallback = true }

local registered = {}     -- path -> true once hooked
local pending = {}        -- path -> fn

for _, s in ipairs(SPECS) do pending[s[1]] = s[2] end

local function try_register(path, fn)
    if registered[path] then return true end
    local ok = pcall(RegisterHook, path, function(ctx, ...)
        local ok2, err = pcall(fn, ctx, ...)
        if not ok2 then Out.log("hook error " .. path .. ": " .. tostring(err)) end
    end)
    if ok then registered[path] = true; Out.log("hooked " .. path) end
    return ok
end

function Menus.add_pending(path, fn)
    if not registered[path] then pending[path] = fn end
end

-- game thread (frame, once a second): is any pending hook's class loaded?
-- main.lua's registration job only runs when this says so.
Menus.pending_ready = false
function Menus.check_pending()
    local have = false
    for path in pairs(pending) do
        local cls = path:match("^(.-):")
        local o = cls and StaticFindObject(cls)
        if o and UI.valid(o) then have = true break end
    end
    Menus.pending_ready = have
end

-- game thread (main.lua frame()): register whatever has loaded since last time
function Menus.register_pending()
    for path, fn in pairs(pending) do
        if try_register(path, fn) then pending[path] = nil end
    end
end

-- game thread: look at live widget classes and queue hooks for new ones
local seen_class = {}
function Menus.scan_classes()
    local arr = FindAllOf("UserWidget")
    if type(arr) ~= "table" then return end
    for _, w in ipairs(arr) do
        local c = safe(function() return w:GetClass() end)
        while c and UI.valid(c) do
            local full = safe(function() return c:GetFullName() end) or ""
            if not full:find("^WidgetBlueprintGeneratedClass") or seen_class[full] then break end
            seen_class[full] = true
            local path = full:match("%s(.+)$")
            local short = path and path:match("%.([^.]+)$")
            if path and short then
                local dyn = DYN[short]
                if dyn then
                    for _, d in ipairs(dyn) do pending[path .. ":" .. d[1]] = d[2] end
                end
                local is_dialog = short:find("Dialog") ~= nil and not short:find("Button")
                -- banners animate on every cursor move without being the cursor
                -- (so do whole menu tables: their select animation reads every row)
                if short:find("BlackPen") or short:find("Banner") or short:find("Menu_Table") then dyn = {} end
                safe(function()
                    c:ForEachFunction(function(f)
                        local fn = f:GetFName():ToString()
                        local p = path .. ":" .. fn
                        if not dyn and not registered[p] and not pending[p] then
                            if (HOVER_FUNCS[fn] or (fn == "Select" and short:find("Button"))) and not (short == "WBP_UI_MainMenu_Menu_List_C") then pending[p] = generic_hover
                            elseif is_dialog and DIALOG_FUNCS[fn] then pending[p] = on_dialog
                            elseif TEXT_FUNCS[fn] then pending[p] = speak_args(short .. ":" .. fn, true)
                            elseif LOG_FUNCS[fn] then pending[p] = speak_args(short .. ":" .. fn, false) end
                        end
                    end)
                end)
            end
            c = safe(function() return c:GetSuperStruct() end)
        end
    end
end

-- Load the classes of screens whose first cursor event would otherwise come
-- before the hook exists (game thread, once, from the main menu).
local PRELOAD = {
    "/Game/UI/Widget/CharSelect/WBP_UI_CharSelect",
    "/Game/UI/Widget/StageSelect/WBP_UI_StageSelect",
    "/Game/UI/Widget/SideSelect/WBP_UI_SideSelect",
    "/Game/UI/Widget/Practice/WBP_UI_PracticeMenu",
    "/Game/UI/Widget/Practice/WBP_UI_CommandList",
    "/Game/UI/Widget/Pause/WBP_UI_Pause_MenuButton",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_TextButton",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog",
    "/Game/UI/Widget/Story_ChapterSelect/WBP_UI_Story_ChapterSelect",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_Menu",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR_Menu",
    "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot",
    "/Game/UI/Widget/TekkenBall/WBP_UI_TB_DamageSet",
    "/Game/UI/Widget/Dialog/WBP_UI_DifficultySelect_MenuButton",
    "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox_PresetWin",
}
local preloaded = false
function Menus.preload()
    if preloaded then return end
    preloaded = true
    for _, p in ipairs(PRELOAD) do
        -- LoadAsset wants the class object path: /Game/.../WBP_X.WBP_X_C
        local short = p:match("([^/]+)$") .. "_C"
        local path = p .. "." .. short
        local ok = pcall(LoadAsset, path)
        local dyn = DYN[short]
        if dyn then for _, d in ipairs(dyn) do pending[path .. ":" .. d[1]] = d[2] end end
        Out.log("preload " .. p .. " " .. tostring(ok))
    end
end

-- F7: the whole current move again with its notes
function Menus.repeat_move()
    local m = Menus.current_move
    if not m then Out.say("No move selected.") return end
    local t = m.name .. ". " .. m.cmd
    if m.note ~= "" then t = t .. ". " .. m.note end
    if m.dmg ~= "" then t = t .. ". " .. m.dmg end
    Out.say(t, true)
end

return Menus
