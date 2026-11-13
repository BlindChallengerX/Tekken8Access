--[[
  news.lua - the Information screen (News and Log tabs) and notice pop-ups
  (mapped 2026-11-12, NOTES.md "News").

  The game opens Information by itself after the title when there is unread
  news, and from the main menu's shortcut bar (Esc, News).

  WBP_UI_News_C: TB_num ("1 / 8"), tabs WBP_UI_News_Tab_Item_C (tb_title,
  SetAnim_Select = tab cursor). News tab: a column of WBP_UI_News_Banner_C
  (TBR_category = the headline, WBP_UI_Icon_NewBadge = the unread "!",
  SetAnim_Select = cursor). Enter opens WBP_UI_News_Content_C
  (Open_WBP_UI_News_Content; tb_title, TB_text body, then TB_icon_N / TB_text_N
  button guides such as Store and Close). Log tab: WBP_UI_News_Log_C, rows
  WBP_UI_News_Log_List_C (tb_title, TB_text), CanvasNon = "Nothing to show here.".
  Notices (friend online, unlocks): WBP_UI_Notice_C:FrameIn (TB_Message,
  TB_SubMessage).
]]
local Out = require("out")
local UI  = require("lib/ui")

local News = {}
local safe = UI.safe
local Menus                      -- set by News.init

local function self_of(ctx) return safe(function() return ctx:get() end) end
local function arg(p) return safe(function() return p:get() end) end
local function text(w) return UI.clean(UI.text_of(w) or "") or "" end
local function shown(w) return UI.valid(w) and safe(function() return w:IsVisible() end) == true end

-- the Information screen a widget belongs to (banner -> WidgetTree -> News)
local function screen_of(w)
    local o = w
    for _ = 1, 4 do
        o = safe(function() return o:GetOuter() end)
        if not UI.valid(o) then return nil end
        if (safe(function() return o:GetClass():GetFName():ToString() end) or "") == "WBP_UI_News_C" then return o end
    end
    return nil
end

local open_t = -10               -- when the screen opened: its title goes first

local function on_open(ctx)
    open_t = os.clock()
    Menus.touch()
    Out.say("Information. News.", true)
end

local function on_banner(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.touch()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local t = text(safe(function() return w.TBR_category end))
        if t == "" then return end
        if shown(safe(function() return w.WBP_UI_Icon_NewBadge end)) then t = t .. ", new" end
        local s = screen_of(w)
        local num = s and text(safe(function() return s.TB_num end)) or ""
        local a, b = num:match("(%d+)%s*/%s*(%d+)")
        if a then t = t .. ", " .. a .. " of " .. b end
        if os.clock() - open_t < 1.5 then Out.queue(t) else Out.say(t) end
    end, 0.03)
end

local function on_tab(ctx)
    local w = self_of(ctx)
    if not w then return end
    if os.clock() - open_t < 1.5 then return end      -- the open line says the tab
    Menus.touch()
    local t = text(safe(function() return w.tb_title end))
    if t == "" then return end
    Out.say(t)
    -- an empty log shows a single line instead of rows
    local s = screen_of(w)
    Menus.defer(function()
        -- the Log page stays "visible" behind the News tab: go by the tab index
        if not (s and UI.valid(s)) or safe(function() return s.TabIndex end) ~= 1 then return end
        local lg = safe(function() return s.WBP_UI_News_Log end)
        local none = lg and UI.valid(lg) and safe(function() return lg.CanvasNon end)
        if shown(none) then
            local msg = UI.read(none)
            if msg ~= "" then Out.queue(msg) end
        end
    end, 0.4)
end

-- the opened article: headline, whole body, then its buttons ("Y button:
-- Store"). Title and body are read by name: the Store button inside the
-- article has its own TB_text, so the tree walk only collects the guides.
local function read_content(w)
    local title = text(safe(function() return w.tb_title end))
    -- lines of the body become sentences ("Scheduled Early Access" then the date)
    local lines = {}
    local raw = (UI.text_of(safe(function() return w.TB_text end)) or ""):gsub("\r", "")
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local c = UI.clean(line)
        if c then lines[#lines + 1] = c:find("[%.!?:;,]$") and c or (c .. ".") end
    end
    local body = table.concat(lines, " ")
    local parts, icon = {}, nil
    for _, e in ipairs(UI.collect(w)) do
        local c = UI.clean(e.text) or ""
        if e.name:find("^TB_icon_%d") then icon = c
        elseif e.name:find("^TB_text_%d") and c ~= "" then
            parts[#parts + 1] = (icon and icon ~= "" and (icon .. ": ") or "") .. c
            icon = nil
        end
    end
    local t = title
    if body ~= "" then t = t .. (t:find("[%.!?]$") and " " or ". ") .. body end
    if #parts > 0 then t = t .. (t:find("[%.!?]$") and " " or ". ") .. table.concat(parts, ", ") .. "." end
    return t
end

local function on_content(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.touch()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local t = read_content(w)
        if t ~= "" then Out.say(t, true) end
    end, 0.1)
end

-- Log rows (not seen with entries yet: the test account's log was empty)
local function on_log_row(ctx, selected)
    local w = self_of(ctx)
    if not w or arg(selected) == false then return end
    Menus.touch()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local t = UI.read(w)
        if t ~= "" then Out.say(t) end
    end, 0.03)
end

local notice_last, notice_t = "", -10
local function on_notice(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local parts = {}
        for _, n in ipairs({ "TB_Message", "TB_SubMessage", "TB_ID" }) do
            local f = safe(function() return w[n] end)
            if shown(f) then
                local t = text(f)
                if t ~= "" then parts[#parts + 1] = t end
            end
        end
        local msg = table.concat(parts, ". ")
        if msg == "" or (msg == notice_last and os.clock() - notice_t < 3) then return end
        notice_last, notice_t = msg, os.clock()
        Out.queue(msg)
    end, 0.05)
end

local N = "/Game/UI/Widget/News/"
News.HOOKS = {
    { N .. "WBP_UI_News.WBP_UI_News_C:OnInitialized", on_open },
    { N .. "WBP_UI_News_Banner.WBP_UI_News_Banner_C:SetAnim_Select", on_banner },
    { N .. "WBP_UI_News_Tab_Item.WBP_UI_News_Tab_Item_C:SetAnim_Select", on_tab },
    { N .. "WBP_UI_News_Content.WBP_UI_News_Content_C:Open_WBP_UI_News_Content", on_content },
    { N .. "WBP_UI_News_Log_List.WBP_UI_News_Log_List_C:BP_OnItemSelectionChanged", on_log_row },
    { "/Game/UI/Widget/Notice/WBP_UI_Notice.WBP_UI_Notice_C:FrameIn", on_notice },
}
-- loaded at the first maintenance pass (the title screen): the game shows
-- Information before the main menu, where the other screens are preloaded
News.PRELOAD = {
    N .. "WBP_UI_News", N .. "WBP_UI_News_Banner", N .. "WBP_UI_News_Tab_Item",
    N .. "WBP_UI_News_Content", N .. "WBP_UI_News_Log_List", "/Game/UI/Widget/Notice/WBP_UI_Notice",
}
News.OWN_CLASSES = { WBP_UI_News_C = true, WBP_UI_News_Banner_C = true, WBP_UI_News_Tab_Item_C = true,
                     WBP_UI_News_Tab_C = true, WBP_UI_News_Content_C = true, WBP_UI_News_ContentButton_C = true,
                     WBP_UI_News_Log_C = true, WBP_UI_News_Log_List_C = true, WBP_UI_Notice_C = true }

function News.init(menus) Menus = menus end

return News
