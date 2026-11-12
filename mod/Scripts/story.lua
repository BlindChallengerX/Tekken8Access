--[[
  story.lua - the main story's special screens (mapped 2026-11-11, NOTES.md
  "Story mode").

  Button prompts ("STE"): WBP_UI_Story_STE_Menu_C owns Button_01..08
  (WBP_UI_Story_STE_C). For each button of a prompt the game calls
  SetupButton(index, type, textId, texture, "{gui_use}") and then AnimIn once.
  The button's TB_Btn then holds the key picture for the device in use
  (<img id="kbd_022_en_US"/>), TB_GuideText the action ("Punish", "Dodge",
  "[Hold] Get up"). The gauge runs about 5 s; AnimSuccess / AnimMiss end it.

  Fighter choice (Chapter 5 tournament): WBP_UI_Story_TwoChoices_C with
  SelectItem_L / _R (TB_CharaName) and four ProfList rows (TB_Prof_Title,
  TB_Prof_L, TB_Prof_R). The item's PlayAnimHover is the cursor.

  Chapter 10 battlefield: WBP_UI_Story_IW_HUD_MessageWin_C (radio lines,
  TB_Name_Character + TB_Message, FrameIn) and _NoticeWin_C (TB_Message_Center,
  FrameIn). Tutorial pop-ups: WBP_UI_HelpDialog_C (tb_title, TB_text per page,
  UpdateCursor(page)).

  In-fight control list: WBP_UI_HUD_ControlGuide_C:SetButtonData(side, row,
  buttons, textId, kind) fills the list shown at the bottom of the screen in
  story fights; kept here and read on request (Shift+F5).
]]
local Out = require("out")
local UI  = require("lib/ui")
local Pad = require("lib/pad")

local Story = {}
local safe = UI.safe
local Menus                      -- set by Story.init (menus.lua requires this file's hooks)

local function self_of(ctx) return safe(function() return ctx:get() end) end
local function arg(p) return safe(function() return p:get() end) end
local function text(w) return UI.clean(UI.text_of(w) or "") or "" end
local function title_case(s)
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- ---------------------------------------------------------------- button prompts
-- what the prompt asks for when no picture can be read
local TAG = { gui_use = "the button", gui_left = "left", gui_right = "right", gui_up = "up", gui_down = "down" }

local ste = { tags = {}, said = "", t = -10 }

local function button_name(b, tag)
    -- controller: a button texture (T_UI_STE_BTN_PS5_SQUARE, _XSX_X ...)
    local img = safe(function() return b.Rep_T_UI_STE_BTN end)
    local shown = UI.valid(img) and safe(function() return img:IsVisible() end)
    local tex = shown and safe(function() return img.Brush.ResourceObject:GetFName():ToString() end)
    local nm = Pad.picture(tex and tex:match("^T_UI_STE_BTN_(.+)$"))
    if nm then return nm end
    -- keyboard: the key picture is rich text in TB_Btn; lib/pad names it as the pad button
    local raw = UI.text_of(safe(function() return b.TB_Btn end))
    local s = raw and raw:find("<img") and UI.clean(raw)
    if s and s ~= "" then return s end
    local t = tag and tag:match("{(.-)}") or ""
    return TAG[t] or (t ~= "" and t:gsub("gui_", ""):gsub("_", " ")) or "button"
end

local function ste_setup(ctx, index, kind, text_id, texture, btn)
    local i = arg(index)
    if type(i) ~= "number" then return end
    local tag = arg(btn)
    tag = type(tag) == "userdata" and safe(function() return tag:ToString() end) or tag
    ste.tags[i] = type(tag) == "string" and tag or ""
end

local function ste_in(ctx)
    local menu = self_of(ctx)
    local tags = ste.tags
    ste.tags = {}
    if not menu then return end
    Out.tone("open")
    Menus.defer(function()
        if not UI.valid(menu) then return end
        local parts = {}
        for i = 1, 8 do
            if tags[i] then
                local b = safe(function() return menu["Button_0" .. i] end)
                if UI.valid(b) then
                    local what = text(safe(function() return b.TB_GuideText end))
                    local key = button_name(b, tags[i])
                    local hold = what:find("^%[Hold%]")
                    what = what:gsub("^%[Hold%]%s*", "")
                    parts[#parts + 1] = (hold and "Hold " or "") .. key .. (what ~= "" and (", " .. what) or "")
                end
            end
        end
        if #parts == 0 then return end
        ste.said, ste.t = table.concat(parts, ". Or ") .. ".", os.clock()
        Out.say(ste.said, true)
    end, 0.03)
end

local function ste_result(tone)
    return function()
        if os.clock() - ste.t > 30 then return end      -- the menu resets its buttons at fight start too
        ste.t = -10
        Out.tone(tone)
    end
end

-- ---------------------------------------------------------------- fighter choice
local two = { w = nil, open_t = -10, last = "" }
-- The fighter the cursor was on when the choice screen closed is the one you
-- play: in the Chapter 5 tournament the right-hand pick is PlayerNumber 1
-- (King on the right, 2026-11-11). fight.lua makes that fighter "me" in the
-- fights that follow and drops it once a fight without that fighter starts.
Story.chosen = nil

local function two_side(w, left)
    local it = safe(function() return w[left and "WBP_UI_Story_TwoChoices_SelectItem_L" or "WBP_UI_Story_TwoChoices_SelectItem_R"] end)
    local nm = UI.valid(it) and text(safe(function() return it.TB_CharaName end)) or ""
    local prof = {}
    for _, n in ipairs({ "", "_1", "_2", "_3" }) do
        local l = safe(function() return w["WBP_UI_Story_TwoChoices_ProfList" .. n] end)
        local v = UI.valid(l) and text(safe(function() return l[left and "TB_Prof_L" or "TB_Prof_R"] end)) or ""
        if v ~= "" then prof[#prof + 1] = v end
    end
    return nm ~= "" and title_case(nm) or "", table.concat(prof, ", ")
end

local function two_open(ctx)
    local w = self_of(ctx)
    if not w or os.clock() - two.open_t < 2 then return end
    two.w, two.open_t, two.last = w, os.clock(), ""
    Menus.touch()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local a, b = two_side(w, true), two_side(w, false)
        if a == "" or b == "" then two.open_t = -10 return end      -- names not set yet: the next PlayAnimIn has them
        local ask = text(safe(function() return w.TB_ChooseText_1 end))
        Out.say((ask ~= "" and ask or "Choose your fighter") .. ": " .. a .. " or " .. b .. ". Left and right to choose.", true)
        -- which one the cursor starts on (its hover came before the names were set)
        for _, left in ipairs({ true, false }) do
            local it = safe(function() return w[left and "WBP_UI_Story_TwoChoices_SelectItem_L" or "WBP_UI_Story_TwoChoices_SelectItem_R"] end)
            if UI.valid(it) and safe(function() return it:IsAnimationPlaying(it.Anim_Hover) end) then
                local nm, prof = two_side(w, left)
                two.last = nm
                Story.chosen = nm
                Out.queue("On " .. nm .. ". " .. prof)
            end
        end
    end, 0.1)
end

local function two_hover(ctx)
    local it = self_of(ctx)
    local w = two.w
    if not it or not UI.valid(w) then return end
    local left = UI.name(it):find("_L$") ~= nil
    Menus.touch()
    Menus.defer(function()
        if not UI.valid(w) then return end
        local nm, prof = two_side(w, left)
        if nm == "" or nm == "Text Block" then return end
        Story.chosen = nm
        if nm == two.last and os.clock() - two.open_t < 1 then return end
        two.last = nm
        -- the first hover comes with the screen: it follows the question
        if os.clock() - two.open_t < 1.5 then Out.queue(nm .. ". " .. prof) else Out.say(nm); Out.help(prof) end
    end, 0.12)
end

-- ---------------------------------------------------------------- battlefield (Chapter 10)
local function radio(ctx)
    local w = self_of(ctx)
    if not w or Menus.subtitles == false then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local who = text(safe(function() return w.TB_Name_Character end))
        local msg = text(safe(function() return w.TB_Message end))
        if msg == "" then return end
        Out.say((who ~= "" and (title_case(who) .. ": ") or "") .. msg, true)
    end, 0.05)
end

local notice_last, notice_t = "", -10
local function notice(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local msg = text(safe(function() return w.TB_Message_Center end))
        if msg == "" or (msg == notice_last and os.clock() - notice_t < 3) then return end
        notice_last, notice_t = msg, os.clock()
        Out.queue(msg)
    end, 0.05)
end

-- ---------------------------------------------------------------- tutorial pop-up
local help = { page = -1, t = -10 }
-- Pages is a map UE4SS cannot count; "page button visible" says there is more
-- than one page. TB_icon order: previous page, next page, close.
local function help_read(w, opening, page)
    local title = text(safe(function() return w.tb_title end))
    local body, close, keys = "", "", {}
    for _, e in ipairs(UI.collect(w)) do
        if e.name == "TB_text" then body = UI.clean(e.text) or body end
        if e.name == "TB_Guide" then close = UI.clean(e.text) or close end
        if e.name == "TB_icon" then keys[#keys + 1] = UI.clean(e.text) or "" end
    end
    local t
    if opening then
        t = title .. ". " .. body
        if safe(function() return w["page button visible"] end) and keys[1] and keys[2] and #keys >= 3 then
            t = t .. " More pages: " .. keys[1] .. " and " .. keys[2] .. " turn pages."
        end
        if close ~= "" and keys[#keys] then t = t .. " " .. keys[#keys] .. ": " .. close .. "." end
    else
        t = "Page " .. (page + 1) .. ". " .. body
    end
    Out.say(t, true)
end

local function help_open(ctx)
    local w = self_of(ctx)
    if not w then return end
    help.page, help.t = 0, os.clock()
    Menus.touch()
    Menus.defer(function() if UI.valid(w) then help_read(w, true) end end, 0.15)
end

local function help_page(ctx, page)
    local w = self_of(ctx)
    local i = arg(page)
    if not w or type(i) ~= "number" then return end
    if os.clock() - help.t < 0.3 or i == help.page then help.page = i return end      -- the open event reads page 1
    help.page = i
    local asked = os.clock()
    Menus.touch()
    Menus.defer(function()
        -- the game sets the cursor just before PlayAnimIn: the open read covers it
        if help.t >= asked then return end
        if UI.valid(w) then help_read(w, false, i) end
    end, 0.15)
end

-- ---------------------------------------------------------------- control list
local guide = {}          -- row -> { buttons =, text = } for side 0
local function guide_data(ctx, side, row, buttons, text_id)
    local s, r = arg(side), arg(row)
    if s ~= 0 or type(r) ~= "number" then return end
    if r == 0 then guide = {} end
    local b = arg(buttons)
    b = type(b) == "userdata" and safe(function() return b:ToString() end) or b
    guide[r + 1] = { tag = type(b) == "string" and b or "", text = UI.arg_text(text_id) or "" }
end

local GUIDE_BTN = { gui_bank0_LP = 1, gui_bank0_RP = 2, gui_bank0_LK = 3, gui_bank0_RK = 4,
                    gui_bank0_heat = "Heat button", gui_bank0_rage = "Rage button" }
local function guide_button(tag)
    local b = GUIDE_BTN[tag]
    if type(b) == "number" then return Pad.style == "keyboard" and (("UIJK"):sub(b, b) .. " key") or Pad.tekken(b) end
    return b or tag:gsub("gui_bank0_", ""):gsub("_", " ")
end
function Story.controls()
    local parts = {}
    for _, g in ipairs(guide) do
        local keys = {}
        for tag in g.tag:gmatch("{(.-)}") do keys[#keys + 1] = (guide_button(tag)) end
        if g.text ~= "" then parts[#parts + 1] = table.concat(keys, " and ") .. ": " .. g.text end
    end
    if #parts == 0 then return false end
    Out.say("Controls. " .. table.concat(parts, ". ") .. ".", true)
    return true
end

-- ---------------------------------------------------------------- hooks
local W = "/Game/UI/Widget/"
local STE = W .. "Story_STE/WBP_UI_Story_STE_Menu.WBP_UI_Story_STE_Menu_C:"
local TWO = W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices"
local IW  = W .. "Story_IW/WBP_UI_Story_IW_HUD_"
local HELP = W .. "HelpDialog/WBP_UI_HelpDialog.WBP_UI_HelpDialog_C:"

Story.HOOKS = {
    { STE .. "SetupButton", ste_setup },
    { STE .. "AnimIn", ste_in },
    { STE .. "AnimSuccess", ste_result("round") },
    { STE .. "AnimMiss", ste_result("drop") },
    { TWO .. ".WBP_UI_Story_TwoChoices_C:PlayAnimIn", two_open },
    { TWO .. "_SelectItem.WBP_UI_Story_TwoChoices_SelectItem_C:PlayAnimHover", two_hover },
    { IW .. "MessageWin.WBP_UI_Story_IW_HUD_MessageWin_C:FrameIn", radio },
    { IW .. "NoticeWin.WBP_UI_Story_IW_HUD_NoticeWin_C:FrameIn", notice },
    { W .. "Story_DLC/WBP_UI_Story_DLC_HUD_MessageWin.WBP_UI_Story_DLC_HUD_MessageWin_C:FrameIn", radio },
    { HELP .. "PlayAnimIn", help_open },
    { HELP .. "UpdateCursor", help_page },
    { W .. "ControlGuide/WBP_UI_HUD_ControlGuide.WBP_UI_HUD_ControlGuide_C:SetButtonData", guide_data },
}
-- loaded from the main menu so the first prompt of a chapter is already hooked
Story.PRELOAD = {
    W .. "Story_STE/WBP_UI_Story_STE_Menu", TWO, TWO .. "_SelectItem",
    IW .. "MessageWin", IW .. "NoticeWin", W .. "HelpDialog/WBP_UI_HelpDialog",
    W .. "ControlGuide/WBP_UI_HUD_ControlGuide", W .. "Story_DLC/WBP_UI_Story_DLC_HUD_MessageWin",
}
-- widget classes the generic menu reader must leave alone (it read the whole
-- choice screen on every cursor move)
Story.OWN_CLASSES = { WBP_UI_Story_TwoChoices_C = true, WBP_UI_Story_TwoChoices_SelectItem_C = true,
                      WBP_UI_HelpDialog_C = true, WBP_UI_Story_STE_C = true, WBP_UI_Story_STE_Menu_C = true }

function Story.init(menus) Menus = menus end
-- the fight HUD came or went (fight.lua via Menus.forget_widgets): drop kept widgets
function Story.forget() two.w = nil end

return Story
