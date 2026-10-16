--[[
  watch.lua - screens whose cursor moves without a hookable event.
  Runs on the game thread every 40 ms (main.lua), only looks at widgets that
  are on screen, and speaks when a cursor index changes.

  Jukebox (WBP_UI_JukeBox_C): the album carousel is select_jacket_next into
  play_list_infos (JukeBoxPlayList: textId, Selected = now playing,
  Unlocked). Its windows: BgmWin (track list) and StageWin (stage music),
  each ListView_Buttons + selected_index; TabMenu (series logos with
  Selected + Info.textId); PresetWin (two options, select_old).
]]
local Out = require("out")
local UI  = require("lib/ui")

local Watch = {}
local safe = UI.safe

local jb, next_find = nil, 0
local last = {}

local function shown(w) return w and UI.valid(w) and safe(function() return w:IsVisible() end) == true end

local function list_item_text(lv, i)
    local item = safe(function() return lv:GetItemAt(i) end)
    if not UI.valid(item) then return "" end
    local w = safe(function() return item.Widget end)
    local t = UI.valid(w) and UI.read(w) or ""
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

local function watch_list(key, win, title_field)
    if not shown(win) then last[key] = nil return end
    local i = safe(function() return win.selected_index end)
    if type(i) ~= "number" or i == last[key] then return end
    local first = last[key] == nil
    last[key] = i
    local t = list_item_text(safe(function() return win.ListView_Buttons end), i)
    if first and title_field then
        local title = UI.clean(UI.text_of(safe(function() return win[title_field] end)) or "")
        if title and title ~= "" then t = title .. ". " .. t end
    end
    if t ~= "" then Out.say(t) end
end

local function watch_tabs(tm)
    if not shown(tm) then last.tab = nil return end
    for k = 0, 7 do
        local logo = safe(function() return tm[k == 0 and "WBP_UI_JukeBox_TabMenu_Logo" or ("WBP_UI_JukeBox_TabMenu_Logo_" .. k)] end)
        if logo and safe(function() return logo.Selected end) then
            local id = safe(function() return logo.Info.textId:ToString() end) or ""
            local name = UI.clean(UI.loc(id)) or ""
            if name ~= "" and name ~= last.tab then last.tab = name; Out.say(name) end
            return
        end
    end
end

local function watch_presets(pw)
    if not shown(pw) then last.preset = nil return end
    local i = safe(function() return pw.select_old end)
    if type(i) ~= "number" or i == last.preset then return end
    last.preset = i
    local opt = safe(function() return pw[i == 0 and "WBP_UI_JukeBox_PresetWin_List" or ("WBP_UI_JukeBox_PresetWin_List_" .. i)] end)
    local t = opt and UI.read(opt) or ""
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
    watch_list("bgm", safe(function() return jb.WBP_UI_JukeBox_BgmWin end), "TB_titleName")
    watch_list("stage", safe(function() return jb.WBP_UI_JukeBox_StageWin end))
    watch_tabs(safe(function() return jb.WBP_UI_JukeBox_TabMenu end))
    watch_presets(safe(function() return jb.WBP_UI_JukeBox_PresetWin end))
end

function Watch.tick()
    local t = os.clock()
    jukebox(t)
end

return Watch
