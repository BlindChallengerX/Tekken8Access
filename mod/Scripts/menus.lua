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
local Prof = require("lib/prof")

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
Menus.touch = touched

-- ---------------------------------------------------------------- menus open in a fight
-- The fight module mutes the beacon while these show; it gets the widgets
-- from here (searching for them costs a whole frame).
local function saw_menu(kind, w)
    local F = package.loaded["fight"]
    if F and F.saw_menu then F.saw_menu(kind, w) end
end

-- the pause menu button lives inside WBP_UI_Pause_C: walk up its outers
-- (button -> widget tree -> owning widget ...) once to find it
local pause_found = nil
local function pause_seen(ctx)
    if UI.valid(pause_found) then return end
    local o = self_of(ctx)
    for _ = 1, 8 do
        o = o and safe(function() return o:GetOuter() end)
        if not o or not UI.valid(o) then return end
        local n = safe(function() return o:GetClass():GetFName():ToString() end) or ""
        if n == "WBP_UI_Pause_C" then pause_found = o; saw_menu("pause", o); return end
    end
end

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
    local m = Menus.practice_menu        -- handed over by its cursor hooks (no search)
    if not UI.shown(m) then return end
    if Menus.subscreen_open and Menus.subscreen_open() then return end
    if any_active(safe(function() return m.ListView_2 end)) then return end
    local col = any_active(safe(function() return m.ListView_1 end)) and 2 or 1
    local i = Menus.pm_last[col]
    if i then read_practice_row(m, col, i) end
end

-- The information bar at the bottom explains the highlighted item.
local function info_bar(w)
    Menus.last_menu_t = os.clock()
    local t = UI.read_cached(w)
    if t ~= "" then Out.help(t) end
    Menus.defer(practice_fallback, 0.12)   -- the highlight flag updates a little later
end

function Menus.on_info_bar(ctx) local w = self_of(ctx); if w then info_bar(w) end end

-- ---------------------------------------------------------------- generic
local generic_last, generic_t = nil, -1
local function generic_hover(ctx)
    local w = self_of(ctx)
    if not w then return end
    -- a Practice sub-screen (Throw Escape / Punishment Training) is open over
    -- the pause menu: its row replays its hover when the sub-screen changes
    -- columns; not a move of the user's
    if Menus.subscreen_open and Menus.subscreen_open()
        and UI.name(safe(function() return w:GetClass() end)):find("PracticeMenu_Button") then return end
    if Menus.subscreen_closed then Menus.subscreen_closed() end   -- back on a menu: next open says its title
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
        saw_menu("practice", m)
        Menus.practice_menu = m
        -- the Practice HUD (its tips panel tells throw escapes, fight.lua):
        -- looked up here, in a menu, not in the fight loop
        if not UI.valid(Menus.practice_hud) then
            for _, w in ipairs(FindAllOf("WBP_UI_Practice_S2_C") or {}) do
                if UI.shown(w) then Menus.practice_hud = w; break end
            end
        end
        -- Throw Escape / Punishment Training open over it: the menu refreshes
        -- its rows when that screen changes columns; stay quiet
        if Menus.subscreen_open and Menus.subscreen_open() then return end
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
    saw_menu("commandlist", m)
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

-- ---------------------------------------------------------------- combo challenges
-- Practice pause menu > Combo Challenges (WBP_UI_ComboChallenge_C). The list
-- items (BP_ComboChallenge_Button_Item_C) hold a text id and `checked`
-- (cleared). The selected challenge's steps are WBP_UI_ComboChallenge_Command_C
-- rows added to Win.VerticalBox_Command (the five named Command_1..5 are
-- hidden design placeholders), filled after the cursor moves, so they are
-- read a moment later. Difficulty = how many T_UI_PL_Difficulty_N show.
local cc = { count = -1 }
function Menus.combo_challenge_text(m)
    local win = safe(function() return m.WBP_UI_ComboChallenge_Win end)
    if not UI.valid(win) then return nil end
    local steps = {}
    local vb = win.VerticalBox_Command
    local n = safe(function() return vb:GetChildrenCount() end) or 0
    for k = 0, n - 1 do
        local c = safe(function() return vb:GetChildAt(k) end)
        if UI.valid(c) and safe(function() return c:IsVisible() end) then
            local raw = UI.text_of(safe(function() return c.TB_Command end)) or ""
            -- "(or <keyboard key picture>)": the keyboard alternative, not readable
            raw = raw:gsub('%(or%s*<img id="kbd_[^"]*"%s*/>%s*%)', "")
            local t = UI.clean(raw)
            if t then steps[#steps + 1] = t end
        end
    end
    local diff = 0
    for k = 1, 5 do
        if safe(function() return win["T_UI_PL_Difficulty_" .. k]:IsVisible() end) then diff = k end
    end
    local dmg = UI.clean(UI.text_of(safe(function() return win.TB_Damage_2 end)) or "")
    local note = UI.clean(UI.text_of(safe(function() return win.TB_Note end)) or "")
    local parts = {}
    if #steps > 0 then parts[#parts + 1] = table.concat(steps, ", then ") end
    if diff > 0 then parts[#parts + 1] = "Difficulty " .. diff .. " of 5" end
    if dmg then parts[#parts + 1] = dmg .. " damage" end
    if note then parts[#parts + 1] = note end
    return table.concat(parts, ". ")
end

local function on_combo_cursor(ctx, index)
    local m = self_of(ctx)
    local i = arg(index)
    if not m or type(i) ~= "number" then return end
    saw_menu("combochallenge", m)
    if Menus.drop_challenge_panel then Menus.drop_challenge_panel() end
    local lv = safe(function() return m.WBP_UI_ComboChallenge_Win.ListView_Challenge end)
    local it = lv and safe(function() return lv:GetItemAt(i) end)
    if not UI.valid(it) then return end
    touched()
    local name = UI.clean(UI.loc(safe(function() return it.Text:ToString() end) or "")) or ("Challenge " .. (i + 1))
    if safe(function() return it.checked end) then name = name .. ", cleared" end
    local count = safe(function() return lv:GetNumItems() end) or 0
    local addr = safe(function() return m:GetAddress() end)
    if addr ~= cc.w then cc.w, cc.count = addr, -1 end     -- screen (re)opened
    if count ~= cc.count then
        name = "Combo challenges, " .. count .. ". " .. name
        cc.count = count
    end
    Out.say(name)
    cc.i = i
    Menus.defer(function()
        if cc.i ~= i then return end      -- moved on already
        local t = Menus.combo_challenge_text(m)
        if t and t ~= "" then
            Out.queue(t)
            Menus.current_move = { name = name:gsub("^Combo challenges, %d+%. ", ""), cmd = t, note = "", dmg = "" }
        end
    end, 0.1)
end

-- Throw Escape Training and Punishment Training (WBP_UI_CounterPractice_C):
-- left column = difficulty buttons (Win.VerticalBox_DifficultyButton,
-- TB_Menu_ON), moved with SetCurrentTab(i); right column = moves
-- (Win.ScrollBox_Command children, WBP_UI_CounterPractice_Command_C:
-- TB_Number, TB_name, TB_Command, TB_Damage, TB_Message, TB_Note), moved with
-- SetCursorIndex(i); SetActiveLayer(0/1) = which column. In Throw Escape the
-- check mark (T_UI_CheckMark, Hidden = off) says whether the dummy uses that
-- throw; Enter toggles it and sends SetCursorIndex again. TB_Note holds
-- design placeholder text ("1234567890") and Message a "no recommended
-- punishment" line on throws: both skipped.
local cp = { addr = nil, row = {} }
local function cp_text(w, n) return UI.clean(UI.text_of(safe(function() return w[n] end)) or "") end

local function cp_left(m, i)
    local win = safe(function() return m.WBP_UI_CounterPractice_Win end)
    local b = win and safe(function() return win.VerticalBox_DifficultyButton:GetChildAt(i) end)
    return UI.valid(b) and cp_text(b, "TB_Menu_ON") or nil
end

local function cp_right(m, i)
    local win = safe(function() return m.WBP_UI_CounterPractice_Win end)
    local c = win and safe(function() return win.ScrollBox_Command:GetChildAt(i) end)
    if not UI.valid(c) then return nil end
    local head = win and cp_text(win, "TB_Head_List") or ""
    local no, name, cmd = cp_text(c, "TB_Number"), cp_text(c, "TB_name"), cp_text(c, "TB_Command")
    if not name then return cp_text(c, "TB_Heading") or UI.read(c), nil end     -- a heading row
    local t = (no and (no .. ". ") or "") .. name .. (cmd and (". " .. cmd) or "")
    if head == "Throws" then
        local vis = safe(function() return c.T_UI_CheckMark:GetVisibility() end)
        t = t .. ((vis == 1 or vis == 2) and ", off" or ", on")
    end
    local extra = {}
    local dmg = cp_text(c, "TB_Damage")
    if dmg then extra[#extra + 1] = dmg end
    local msg = cp_text(c, "TB_Message")
    if msg and not msg:find("^There are no recommended") then extra[#extra + 1] = msg end
    local note = cp_text(c, "TB_Note")
    if note and not note:find("1234567890") then extra[#extra + 1] = note end
    return t, table.concat(extra, ". ")
end

function Menus.subscreen_open() return cp.m ~= nil and UI.shown(cp.m) end
function Menus.subscreen_closed() cp.addr = nil end

local function cp_first(m)
    local a = safe(function() return m:GetFullName() end)
    if a == cp.addr then return "" end
    cp.addr = a
    local win = safe(function() return m.WBP_UI_CounterPractice_Win end)
    local head = win and cp_text(win, "TB_Head_List")
    return head and (head .. ". ") or ""
end

local function cp_say_left(m, i)
    local t = cp_left(m, i)
    if t then Out.say(cp_first(m) .. "Difficulty " .. t) end
end

local function cp_say_right(m, i)
    local t, extra = cp_right(m, i)
    if t then
        Out.say(cp_first(m) .. t)
        if extra and extra ~= "" then Out.help(extra) end
        Menus.current_move = { name = t, cmd = "", note = extra or "", dmg = "" }
    end
end

-- opening the screen fires all three at once: one reading per tick, by the
-- active column when SetActiveLayer came, else the latest move
local function cp_flush()
    local b = cp.batch
    cp.batch = nil
    local m = b and b.m
    if not UI.valid(m) then return end
    if b.layer ~= nil then
        if b.layer == 0 then cp_say_left(m, safe(function() return m.tab_index end) or 0)
        else cp_say_right(m, safe(function() return m.cursor_index end) or 0) end
    elseif b.last == "left" then cp_say_left(m, b.left)
    else cp_say_right(m, b.right) end
end

local function cp_hook(which)
    return function(ctx, index)
        local m = self_of(ctx)
        local i = arg(index)
        if not m or type(i) ~= "number" then return end
        saw_menu("counterpractice", m)
        cp.m = m
        touched()
        -- the rows are refilled in the same call: read them a tick later
        if not cp.batch then cp.batch = {}; Menus.defer(cp_flush, 0.03) end
        cp.batch.m = m
        cp.batch[which] = i
        if which ~= "layer" then cp.batch.last = which end
    end
end

-- In the challenge itself the steps are WBP_UI_Practice_ComboChallenge_C
-- (TB_Challenge, VerticalBox_Command of _Line_C rows: TB_Command_ON text).
-- The current step loops its Anim_Hover; a step that lands plays
-- Anim_Completed and the hover moves on; a dropped combo puts the hover back
-- on the first row. No Blueprint event fires for any of it, so the rows are
-- polled (every 50 ms, ~20 IsAnimationPlaying calls) while the panel shows.
-- Opening the challenge list (B) from inside a challenge frees widgets a few
-- seconds later: polling rows kept from before crashed the game every time
-- (2026-10-29). So no row is kept between polls, and while any menu is open
-- the panel is dropped too and looked up again (one search) once it closes.
local ch = { panel = nil, step = nil, done = false, steps = nil, next_t = 0, resume = false }

local function challenge_rows(p, with_text)
    local out = {}
    local vb = safe(function() return p.VerticalBox_Command end)
    local n = UI.valid(vb) and safe(function() return vb:GetChildrenCount() end) or 0
    for k = 0, n - 1 do
        local l = safe(function() return vb:GetChildAt(k) end)
        if UI.valid(l) and safe(function() return l:IsVisible() end) then
            local row = { w = l }
            if with_text then
                local raw = UI.text_of(safe(function() return l.TB_Command_ON end)) or ""
                raw = raw:gsub('%(or%s*<img id="kbd_[^"]*"%s*/>%s*%)', "")
                row.text = UI.clean(raw) or ""
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function playing(l, anim)
    return safe(function() return l:IsAnimationPlaying(l[anim]) end) == true
end

local function find_challenge_panel()
    for _, w in ipairs(FindAllOf("WBP_UI_Practice_ComboChallenge_C") or {}) do
        if UI.valid(w) and safe(function() return w:IsVisible() end) then return w end
    end
end

local function drop_panel()
    if ch.panel then ch.panel, ch.resume = nil, true end
end
Menus.drop_challenge_panel = drop_panel

-- the list's PlayAnimDecide (OnDecide never fires): a challenge starts. Find
-- its panel once it is up (one search, outside the fight loop's per-frame work).
local function on_combo_decide()
    touched()
    ch.resume = false
    local tries = 0
    local function look()
        tries = tries + 1
        local p = find_challenge_panel()
        if p then
            ch.panel, ch.step, ch.done = p, nil, false
            local F = package.loaded["fight"]; if F then F.refind() end
            ch.steps = {}
            for k, row in ipairs(challenge_rows(p, true)) do ch.steps[k] = row.text end
            ch.title = UI.clean(UI.text_of(safe(function() return p.TB_Challenge end)) or "") or "Challenge"
            Out.say(ch.title .. ". " .. table.concat(ch.steps, ", then "))
        elseif tries < 6 then
            Menus.defer(look, 0.5)
        end
    end
    Menus.defer(look, 0.5)
end

function Menus.challenge_tick()
    local t = os.clock()
    if t < ch.next_t then return end
    ch.next_t = t + 0.05
    local F = package.loaded["fight"]
    local menu = F and F.menu_open()
    if menu then drop_panel() return end
    if ch.resume then
        -- back from a menu: still in the challenge? (one search)
        ch.resume = false
        ch.next_t = t + 0.5
        ch.panel = find_challenge_panel()
        if not ch.panel then ch.steps = nil; if F then F.refind() end end
        return
    end
    local p = ch.panel
    if not p then return end
    if not UI.valid(p) or not safe(function() return p:IsVisible() end) then
        ch.panel, ch.steps = nil, nil
        if F then F.refind() end
        return
    end
    local rows = challenge_rows(p, false)
    local cur, completed = nil, nil
    for k, row in ipairs(rows) do
        if not cur and playing(row.w, "Anim_Hover") then cur = k end
        if playing(row.w, "Anim_Completed") then completed = k end
    end
    if completed and completed == #rows and not ch.done then
        ch.done = true
        Out.send("T\tclear")
        Out.say("Challenge cleared!")
    elseif cur and cur ~= ch.step then
        if ch.step and cur > ch.step then Out.send("T\tstep" .. (cur - 1))
        elseif ch.step and cur == 1 and ch.step > 1 and not ch.done then Out.send("T\tdrop") end
        if cur == 1 then ch.done = false end
        ch.step = cur
    end
end

function Menus.in_challenge() return ch.steps ~= nil end

-- F7 in a challenge: the steps, with the one to do next marked
function Menus.repeat_challenge()
    local parts = {}
    for k, text in ipairs(ch.steps or {}) do
        parts[k] = (k == ch.step and "Next: " or "") .. text
    end
    Out.say((ch.title or "Challenge") .. ". " .. table.concat(parts, ", then "), true)
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
local ball_panels = nil
local function ball_slot_cursor(ctx, count, index)
    local w = self_of(ctx)
    local i = arg(index)
    if not w or type(i) ~= "number" then return end
    local side = safe(function() return w.side end) or 0
    touched()
    Menus.defer(function()
        -- the panels are searched once per visit (a search costs ~25 ms)
        if not (ball_panels and ball_panels[1] and UI.valid(ball_panels[1])) then
            ball_panels = FindAllOf("WBP_UI_TB_BallSlot_Panel_C") or {}
        end
        for _, p in ipairs(ball_panels) do
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

-- ---------------------------------------------------------------- character episodes
-- WBP_UI_Story_CharaEpisode_C: SetBgInfo(_, name, style, origin, height,
-- weight) (text ids) comes just before SelectEpisode(index). Rows are the
-- ScrollBox_List children: TB_text_ON ("DEVIL JIN"), Locked, img_Clear
-- (visibility 0 = cleared).
local episode_info = nil
local function title_case(s)
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
local function on_episode_info(ctx, _, name, style, origin, height, weight)
    local parts = {}
    for _, p in ipairs({ name, style, origin, height, weight }) do
        local t = UI.arg_text(p)
        if t then parts[#parts + 1] = t end
    end
    episode_info = table.concat(parts, ", ")
end
local function on_episode_select(ctx, index)
    local w = self_of(ctx)
    local i = arg(index)
    if not w or type(i) ~= "number" then return end
    touched()
    local row = safe(function() return w.ScrollBox_List:GetChildAt(i) end)
    local nm = UI.valid(row) and UI.clean(UI.text_of(safe(function() return row.TB_text_ON end)) or "")
    if not nm or nm == "" then return end
    local t = title_case(nm)
    if safe(function() return row.Locked end) then t = t .. ", locked"
    elseif safe(function() return row.img_Clear:GetVisibility() end) == 0 then t = t .. ", cleared" end
    Out.say(t)
    if episode_info and episode_info ~= "" then Out.help(episode_info) end
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
    -- the battle HUD ticks only while a fight is on screen: free fight detection
    { "/Game/UI/Widget/HUD/S2/WBP_UI_HUD_S2.WBP_UI_HUD_S2_C:Tick", function(ctx) local F = package.loaded["fight"]; if F then F.on_hud_tick(ctx) end end },
    -- in-match pause menu (arcade, versus, story...)
    { "/Game/UI/Widget/Pause/WBP_UI_Pause_MenuButton.WBP_UI_Pause_MenuButton_C:Select", function(ctx) pause_seen(ctx); generic_hover(ctx) end },
    -- Jukebox: the screen widget for the watcher (watch.lua), the preset window
    { "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox.WBP_UI_JukeBox_C:SetInputEnable", function(ctx) require("watch").jb = self_of(ctx) end },
    { "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox.WBP_UI_JukeBox_C:RequestAnimIn", function(ctx) require("watch").jb = self_of(ctx) end },
    { "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox_PresetWin.WBP_UI_JukeBox_PresetWin_C:Select", function(ctx, i) touched(); require("watch").on_preset_select(ctx, i) end },
    -- Tekken Ball: ball and damage select, CPU difficulty
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot.WBP_UI_TB_BallSlot_C:OnCursorMoveUMG", ball_slot_cursor },
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot.WBP_UI_TB_BallSlot_C:OnSetInfoUMG", ball_slot_info },
    { "/Game/UI/Widget/TekkenBall/WBP_UI_TB_DamageSet.WBP_UI_TB_DamageSet_C:OnCursorMoveUMG", damage_cursor },
    { "/Game/UI/Widget/Dialog/WBP_UI_DifficultySelect_MenuButton.WBP_UI_DifficultySelect_MenuButton_C:Select", generic_hover },
    -- story chapter select
    { "/Game/UI/Widget/Story_ChapterSelect/WBP_UI_Story_ChapterSelect.WBP_UI_Story_ChapterSelect_C:SetChapterTitleText", on_chapter },
    { "/Game/UI/Widget/Story_CharaEpisode/WBP_UI_Story_CharaEpisode.WBP_UI_Story_CharaEpisode_C:SetBgInfo", on_episode_info },
    { "/Game/UI/Widget/Story_CharaEpisode/WBP_UI_Story_CharaEpisode.WBP_UI_Story_CharaEpisode_C:SelectEpisode", on_episode_select },
    -- story subtitles are read by watch.lua: a hook on CreateFrontSubtitle
    -- fired during a loading screen (another thread) and froze the Lua side
    -- dialogs: read the whole dialog when it opens
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog.WBP_UI_Dialog_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_Menu.WBP_UI_Dialog_Menu_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR.WBP_UI_Dialog_LR_C:OpenDialog", function(ctx) on_dialog(ctx) end },
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR_Menu.WBP_UI_Dialog_LR_Menu_C:PlayAnimIn", function(ctx) on_dialog(ctx) end },
    -- dialog buttons (Yes / No / OK); the LR variant inherits Select
    { "/Game/UI/Widget/Dialog/WBP_UI_Dialog_TextButton.WBP_UI_Dialog_TextButton_C:Select", generic_hover },
    -- (the information bar's OnSetMessage is main.lua's bootstrap hook: it
    -- calls Menus.on_info_bar)
}
-- classes found at runtime (practice menu, move list) are added by path later
local DYN = {
    WBP_UI_PracticeMenu_C = { { "SetCursorButton1", practice_cursor(1) },
                              { "SetCursorButton2", practice_cursor(2) },
                              { "SetCursorButton3", practice_cursor(3) },
                              { "SetCursorButton4", practice_cursor(4) } },
    WBP_UI_CommandList_C  = { { "SetCursorIndex", on_movelist_cursor } },
    WBP_UI_CounterPractice_C = { { "SetCurrentTab", cp_hook("left") },
                                 { "SetCursorIndex", cp_hook("right") },
                                 { "SetActiveLayer", cp_hook("layer") } },
    WBP_UI_ComboChallenge_C = { { "SetCursorIndex", on_combo_cursor },
                                { "PlayAnimDecide", on_combo_decide } },}
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

local important = {}      -- SPECS and add_pending paths (fixed hooks)
for _, s in ipairs(SPECS) do pending[s[1]] = s[2]; important[s[1]] = true end
-- the story's prompt, choice and message screens (story.lua)
local Story = require("story")
Story.init(Menus)
for _, s in ipairs(Story.HOOKS) do pending[s[1]] = s[2]; important[s[1]] = true end

local function try_register(path, fn)
    if registered[path] then return true end
    local ok = pcall(RegisterHook, path, function(ctx, ...)
        local t0 = os.clock()
        local ok2, err = pcall(fn, ctx, ...)
        Prof.add(path, os.clock() - t0)
        if not ok2 then Out.log("hook error " .. path .. ": " .. tostring(err)) end
    end)
    if ok then registered[path] = true; Out.log("hooked " .. path) end
    return ok
end

function Menus.add_pending(path, fn)
    if not registered[path] then pending[path] = fn; important[path] = true end
end

-- game thread (main.lua maint(), once a second): is a pending hook's class
-- loaded? A StaticFindObject that finds nothing costs ~13 ms (measured in a
-- fight, 2026-10-31); one that finds the class is quick. The Arcade Quest
-- hooks stay pending everywhere else: looking for them every second froze
-- the game ~200 ms a second (felt as input lag in fights). Checking only one
-- class a second instead left the pause menu and move list unhooked (the
-- preloaded screens were found too late). So: every class not missed yet is
-- checked each pass (quick while they are found); a miss marks the class,
-- and marked classes are tried again one every 5 s, only outside fights.
-- At most one miss per pass.
local function pending_has(cls)
    for path in pairs(pending) do if path:sub(1, #cls + 1) == cls .. ":" then return true end end
    return false
end

Menus.pending_ready = false
local missed = {}          -- class -> true after a lookup found nothing
local miss_list, miss_pos, last_retry = {}, 0, -10
local ready_cls = {}
function Menus.check_pending(fighting)
    local seen, misses = {}, {}
    local budget = 1
    for path in pairs(pending) do
        local cls = path:match("^(.-):")
        if cls and not seen[cls] then
            seen[cls] = true
            if missed[cls] then misses[#misses + 1] = cls
            elseif budget > 0 then
                local o = StaticFindObject(cls)
                if o and UI.valid(o) then ready_cls[cls] = true; Menus.pending_ready = true
                else missed[cls] = true; budget = 0 end
            end
        end
    end
    if fighting or budget == 0 or #misses == 0 or os.clock() - last_retry < 5 then return end
    last_retry = os.clock()
    if miss_pos >= #miss_list then miss_list, miss_pos = misses, 0 end
    miss_pos = miss_pos + 1
    local cls = miss_list[miss_pos]
    if cls and pending_has(cls) then
        local o = StaticFindObject(cls)
        -- one screen's classes load together (Arcade Quest): look at every
        -- marked class again, they are quick once found
        if o and UI.valid(o) then missed = {}; ready_cls[cls] = true; Menus.pending_ready = true end
    end
end

-- game thread (main.lua maint()): register the hooks whose class has loaded.
-- A hook that still fails on a loaded class (no such function) is dropped
-- after three tries.
local reg_fails = {}
function Menus.register_pending()
    for path, fn in pairs(pending) do
        if ready_cls[path:match("^(.-):") or ""] then
            if try_register(path, fn) then pending[path] = nil
            else
                reg_fails[path] = (reg_fails[path] or 0) + 1
                if reg_fails[path] >= 3 then pending[path] = nil; Out.log("hook dropped " .. path) end
            end
        end
    end
    ready_cls, Menus.pending_ready = {}, false
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
                ready_cls[path], Menus.pending_ready = true, true    -- live, so loaded
                local dyn = DYN[short]
                if dyn then
                    for _, d in ipairs(dyn) do pending[path .. ":" .. d[1]] = d[2] end
                end
                if Story.OWN_CLASSES[short] then dyn = {} end
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
    "/Game/UI/Widget/Practice/WBP_UI_ComboChallenge",
    "/Game/UI/Widget/Practice/WBP_UI_CounterPractice",
    "/Game/UI/Widget/Pause/WBP_UI_Pause_MenuButton",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_TextButton",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog",
    "/Game/UI/Widget/Story_ChapterSelect/WBP_UI_Story_ChapterSelect",
    "/Game/UI/Widget/Story_CharaEpisode/WBP_UI_Story_CharaEpisode",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_Menu",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR",
    "/Game/UI/Widget/Dialog/WBP_UI_Dialog_LR_Menu",
    "/Game/UI/Widget/TekkenBall/WBP_UI_TB_BallSlot",
    "/Game/UI/Widget/TekkenBall/WBP_UI_TB_DamageSet",
    "/Game/UI/Widget/Dialog/WBP_UI_DifficultySelect_MenuButton",
    "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox_PresetWin",
    "/Game/UI/Widget/JukeBox/WBP_UI_JukeBox",
    "/Game/UI/Widget/HUD/S2/WBP_UI_HUD_S2",
}
for _, p in ipairs(Story.PRELOAD) do PRELOAD[#PRELOAD + 1] = p end
local preloaded = false
function Menus.preload()
    if preloaded then return end
    preloaded = true
    for _, p in ipairs(PRELOAD) do
        -- LoadAsset wants the class object path: /Game/.../WBP_X.WBP_X_C
        local short = p:match("([^/]+)$") .. "_C"
        local path = p .. "." .. short
        local ok = pcall(LoadAsset, path)
        -- loaded now: its hooks register on the next maintenance pass, without
        -- waiting for the slow retry of classes looked up before the preload
        -- (maintenance does not run during story movies, so that retry left
        -- the pause menu and the story prompts unhooked for a minute or two)
        if ok then ready_cls[path], missed[path], Menus.pending_ready = true, nil, true end
        local dyn = DYN[short]
        if dyn then for _, d in ipairs(dyn) do pending[path .. ":" .. d[1]] = d[2]; important[path .. ":" .. d[1]] = true end end
        Out.log("preload " .. p .. " " .. tostring(ok))
    end
end

-- F7: the whole current move again with its notes
function Menus.repeat_move()
    if ch.steps then Menus.repeat_challenge() return end
    local m = Menus.current_move
    if not m then Out.say("No move selected.") return end
    local t = m.name .. ". " .. m.cmd
    if m.note ~= "" then t = t .. ". " .. m.note end
    if m.dmg ~= "" then t = t .. ". " .. m.dmg end
    Out.say(t, true)
end

return Menus
