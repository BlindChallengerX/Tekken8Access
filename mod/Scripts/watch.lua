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

local jb, next_find = nil, 0
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
    local info = safe(function() return jb.play_list_infos[i + 1] end)
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
    if not shown(jb) then
        if t < next_find then return end
        next_find = t + 1.0
        jb = safe(function() return FindFirstOf("WBP_UI_JukeBox_C") end)
        if not (jb and UI.shown(jb)) then jb = nil; last = {} return end
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

-- Story / cutscene subtitles: WBP_UI_Subtitle_C creates its lines as child
-- widgets. Read what it shows and speak each new line (interrupting the last,
-- as a sighted player only sees the newest). Hooking CreateFrontSubtitle froze
-- Lua when it fired during a loading screen, so this polls one cached widget.
local sub, sub_next, sub_last = nil, 0, ""
function Watch.subtitles()
    local M = package.loaded["menus"]
    if M and M.subtitles == false then return end
    local t = os.clock()
    if not (sub and UI.valid(sub)) then
        if t < sub_next then return end
        sub_next = t + 1.0
        sub = safe(function() return FindFirstOf("WBP_UI_Subtitle_C") end)
        if not (sub and UI.valid(sub)) then sub = nil return end
    end
    if not shown(sub) then sub_last = "" return end
    local line = UI.read(sub)
    if line == "" then sub_last = "" return end
    if line ~= sub_last then
        sub_last = line
        Out.say(line, true)
    end
end

return Watch
