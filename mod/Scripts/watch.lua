--[[
  watch.lua - screens whose cursor moves without a hookable event.
  Runs on the game thread every 40 ms (main.lua), only looks at widgets that
  are on screen, and speaks when a cursor index changes.

  Jukebox (WBP_UI_JukeBox_C): the album carousel is select_jacket_next into
  play_list_infos (JukeBoxPlayList: textId, Selected = now playing,
  Unlocked). Its windows: BgmWin (track list) and StageWin (stage music),
  each ListView_Buttons + selected_index; the series tabs over the track
  list show as its TB_titleName. PresetWin (Preset / Shuffle) is read from its
  Select event (menus.lua hooks Watch.on_preset_select).
]]
local Out = require("out")
local UI  = require("lib/ui")

local Watch = {}
local safe = UI.safe

-- the Jukebox screen widget is handed over by its hooks (menus.lua sets
-- Watch.jb); searching for it costs a whole frame
Watch.jb = nil
local last = {}

local function shown(w) return w and UI.valid(w) and safe(function() return w:IsVisible() end) == true end

local function loc(id) return UI.clean(UI.loc(id or "")) or "" end

-- track list rows: JukeBoxBGM { BgmTextId, Equipped, Playing, Unlocked, Store }
local function bgm_text(info)
    local t = loc(safe(function() return info.BgmTextId:ToString() end))
    if safe(function() return info.Unlocked end) == false then
        t = t .. (safe(function() return info.Store end) and ", in the shop" or ", locked")
    end
    if safe(function() return info.Playing end) then t = t .. ", playing" end
    if safe(function() return info.Equipped end) then t = t .. ", in playlist" end
    return t
end

-- My Playlist rows, one per stage: JukeBoxMyList { SceneTextId, BgmTextId, Climax }
local function stage_text(info)
    local scene = loc(safe(function() return info.SceneTextId:ToString() end))
    local track = loc(safe(function() return info.BgmTextId:ToString() end))
    local t = scene
    if safe(function() return info.Climax end) then t = t .. ", climax" end
    if track ~= "" then t = t .. ": " .. track end
    if safe(function() return info.Unlocked end) == false then t = t .. ", locked" end
    return t
end

local function list_item_text(lv, i, reader)
    local item = safe(function() return lv:GetItemAt(i) end)
    if not UI.valid(item) then return "" end
    local info = safe(function() return item.Info end)
    local t = info and reader and reader(info) or ""
    if t == "" then t = UI.fields_text(item) end
    return t
end

local function jacket_text(i)
    local info = safe(function() return Watch.jb.play_list_infos[i + 1] end)
    if not info then return nil end
    local name = UI.clean(UI.loc(safe(function() return info.textId:ToString() end) or "")) or ("Playlist " .. (i + 1))
    if safe(function() return info.Unlocked end) == false then name = name .. ", locked" end
    if safe(function() return info.Selected end) then name = name .. ", selected" end
    return name
end

-- title_field: a heading over the list (the series name in the track list);
-- said with the row when the list opens or the heading changes (series tab)
local function watch_list(key, win, reader, title_field)
    if not shown(win) then last[key] = nil; last[key .. "_title"] = nil return end
    local title = title_field and UI.clean(UI.text_of(safe(function() return win[title_field] end)) or "") or nil
    local new_title = title and title ~= "" and title ~= last[key .. "_title"]
    local i = safe(function() return win.selected_index end)
    if type(i) ~= "number" or (i == last[key] and not new_title) then return end
    last[key] = i
    local t = list_item_text(safe(function() return win.ListView_Buttons end), i, reader)
    if new_title then
        last[key .. "_title"] = title
        t = title .. ". " .. t
    end
    if t ~= "" then Out.say(t) end
end

local function jukebox(t)
    local jb = Watch.jb
    if not (jb and UI.valid(jb) and UI.shown(jb)) then
        if next(last) then last = {} end
        return
    end
    -- the carousel only counts while no window is open over it
    local win_open = shown(safe(function() return jb.WBP_UI_JukeBox_BgmWin end))
        or shown(safe(function() return jb.WBP_UI_JukeBox_StageWin end))
        or shown(safe(function() return jb.WBP_UI_JukeBox_PresetWin end))
    local sel = safe(function() return jb.select_jacket_next end)
    if not win_open and type(sel) == "number" and sel ~= last.jacket then
        last.jacket = sel
        local name = jacket_text(sel)
        if name then Out.say(name) end
    end
    -- the track list opens over the stage list: only the top one is read
    local bgm = safe(function() return jb.WBP_UI_JukeBox_BgmWin end)
    watch_list("bgm", bgm, bgm_text, "TB_titleName")
    if shown(bgm) then last.stage = nil
    else watch_list("stage", safe(function() return jb.WBP_UI_JukeBox_StageWin end), stage_text) end
end

-- preset window (Preset / Shuffle): WBP_UI_JukeBox_PresetWin_C:Select(index, ...)
function Watch.on_preset_select(ctx, index)
    local pw = safe(function() return ctx:get() end)
    local i = safe(function() return index:get() end)
    if not pw or type(i) ~= "number" then return end
    local opt = safe(function() return pw[i == 0 and "WBP_UI_JukeBox_PresetWin_List" or ("WBP_UI_JukeBox_PresetWin_List_" .. i)] end)
    local t = opt and UI.read(opt) or ""
    if t ~= "" then Out.say(t) end
end

function Watch.tick()
    local t = os.clock()
    jukebox(t)
end

-- Story / cutscene subtitles: WBP_UI_Subtitle_C shows its lines as child
-- widgets of CanvasPanel_31. Hooking CreateFrontSubtitle froze Lua during a
-- loading screen, so this polls, cheaply: the widget is found once (main.lua
-- maintenance), its line widgets and their text blocks are collected only
-- when the number of lines changes, and each tick just reads those texts.
-- Each new line is spoken, interrupting the last (a sighted player only sees
-- the newest).
local sub, sub_n, sub_texts, sub_last = nil, -1, {}, ""
function Watch.has_subtitle_widget() return sub ~= nil and UI.valid(sub) end
function Watch.find_subtitle_widget()
    local w = safe(function() return FindFirstOf("WBP_UI_Subtitle_C") end)
    if w and UI.valid(w) then sub, sub_n = w, -1 end
end

local function text_blocks(w, out, depth)
    depth = depth or 0
    if depth > 12 or not UI.valid(w) then return out end
    if safe(function() return w:GetText() end) ~= nil then out[#out + 1] = w end
    local wt = safe(function() return w.WidgetTree end)
    if wt and UI.valid(wt) then local r = safe(function() return wt.RootWidget end); if r then text_blocks(r, out, depth + 1) end end
    local n = safe(function() return w:GetChildrenCount() end) or 0
    for i = 0, n - 1 do local ch = safe(function() return w:GetChildAt(i) end); if ch then text_blocks(ch, out, depth + 1) end end
    return out
end

function Watch.subtitles()
    local M = package.loaded["menus"]
    if M and M.subtitles == false then return end
    if not (sub and UI.valid(sub)) then sub = nil return end
    local cv = safe(function() return sub.CanvasPanel_31 end)
    local n = cv and safe(function() return cv:GetChildrenCount() end) or 0
    if n ~= sub_n then
        sub_n, sub_texts = n, {}
        for i = 0, n - 1 do
            local line = safe(function() return cv:GetChildAt(i) end)
            if line then sub_texts[#sub_texts + 1] = { line = line, blocks = text_blocks(line, {}) } end
        end
    end
    if n == 0 or not safe(function() return sub:IsVisible() end) then sub_last = "" return end
    local parts = {}
    for _, e in ipairs(sub_texts) do
        if safe(function() return e.line:IsVisible() end) then
            for _, b in ipairs(e.blocks) do
                local s = UI.clean(UI.text_of(b))
                if s and s ~= "" then parts[#parts + 1] = s end
            end
        end
    end
    local line = table.concat(parts, " ")
    if line == "" then sub_last = "" return end
    if line ~= sub_last then
        sub_last = line
        Out.say(line, true)
    end
end

return Watch
