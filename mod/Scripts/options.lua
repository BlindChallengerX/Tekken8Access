--[[
  options.lua - Options and its sub-screens (mapped 2026-11-11, NOTES.md
  "Options").

  Options list:       WBP_UI_OP_List_Button_C:OnSelect          row name
  Setting screens:    WBP_UI_OP_Setting_Button_C:OnSelect        "name, value"
  (Game Option, Sound, Camera, Screen, Graphics, Player Settings)
                      :SetValueText / :UpdateVolume              new value (only for the
                                                                 highlighted row: the screen
                                                                 sets every row when it opens)
                      volume rows: VolumeValue 0..10, no value text
  Button Mapping:     WBP_UI_OP_ButtonMapping_Menu_Button_C:PlaySelect  device
  Keyboard Settings:  WBP_UI_OP_ButtonMapping_Button_C:PlayAnimSelect   pad button (TB_Button)
                      and the key (TB_Rich_OFF, said as the key, not turned into a pad name);
                      :SetKeyText = a new key; Button2 rows = Check / Restore / Confirm and Exit
  Controller Setup:   WBP_UI_OP_CS_Menu_Btn_*_C:Select           row (+ assigned button);
                      Editable:SetValue = new button. Here EVERY pad button press assigns that
                      button to the highlighted row (J/K/B... on the keyboard too), so the
                      screen says so when it opens.
  Legal pages:        WBP_UI_StartUp_Agreement_C:OnPlayAnimIn    first paragraph; F9 reads all
]]
local Out = require("out")
local UI  = require("lib/ui")
local N   = require("lib/notation")
local Pad = require("lib/pad")

local Options = {}
local safe = UI.safe
local Menus

local function self_of(ctx) return safe(function() return ctx:get() end) end
local function text(w) return UI.clean(UI.text_of(w) or "") or "" end
local function hovering(w) return safe(function() return w:IsAnimationPlaying(w.Anim_Hover) end) == true end

-- ---------------------------------------------------------------- lists
local last = { t = "", at = -10 }
local function say_row(t)
    if t == "" then return end
    if t == last.t and os.clock() - last.at < 0.15 then return end   -- the same event twice
    last.t, last.at = t, os.clock()
    Menus.touch()
    Out.say(t)
end

local function plain_row(ctx)
    local w = self_of(ctx)
    if w then say_row(UI.read(w)) end
end

-- ---------------------------------------------------------------- setting rows
local function setting_value(w)
    -- volume rows show a bar (VolumeValue 0..10); their hidden value text says "VALUE"
    local box = safe(function() return w.HorizontalBox_Volume end)
    if UI.valid(box) and safe(function() return box:IsVisible() end) then
        local n = safe(function() return w.VolumeValue end)
        if type(n) == "number" then return tostring(math.floor(n + 0.5)) .. " of 10" end
    end
    local tb = safe(function() return w.TB_value_ON end)
    if not (UI.valid(tb) and safe(function() return tb:IsVisible() end)) then return "" end
    local v = text(tb)
    return v ~= "VALUE" and v or ""
end

local function setting_row(ctx)
    local w = self_of(ctx)
    if not w then return end
    local name = text(safe(function() return w.TB_Menu_ON end))
    local v = setting_value(w)
    say_row(v ~= "" and (name .. ", " .. v) or name)
end

local val = { t = "", at = -10 }
local function setting_changed(ctx)
    local w = self_of(ctx)
    -- the screen fills every row when it opens: only the highlighted row's change is the player's
    if not w or safe(function() return w.Selected end) ~= true then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local v = setting_value(w)
        if v == "" or (v == val.t and os.clock() - val.at < 0.1) then return end
        val.t, val.at = v, os.clock()
        Menus.touch()
        Out.say(v, true)
    end, 0)
end

-- ---------------------------------------------------------------- keyboard settings
-- TB_Button: the pad button (btn_X_xsx) or a stick direction (btn_LS_xsx + cmd_04/06/07/09)
local STICK = { ["04"] = "down", ["06"] = "left", ["07"] = "right", ["09"] = "up" }
local function pad_part(rich)
    if not rich then return "" end
    local pic, dir = rich:match('btn_([%w_]+)_%a+%d?"/><img id="cmd_(%d+)"')
    if pic then
        local stick = Pad.picture("XSX_" .. pic:upper()) or pic
        return stick .. " " .. (STICK[dir] or "")
    end
    pic = rich:match('btn_([%w_]+)_%a+%d?"')
    return pic and (Pad.picture("XSX_" .. pic:upper()) or pic:gsub("_", " ")) or (UI.clean(rich) or "")
end

local function key_part(w)
    local raw = UI.text_of(safe(function() return w.TB_Rich_ON end)) or UI.text_of(safe(function() return w.TB_Rich_OFF end))
    if not raw or raw == "" or raw == "--" then return "no key" end
    return N.key_name(raw) or UI.clean(raw) or "no key"
end

local function keymap_row(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if UI.valid(w) then say_row(pad_part(UI.text_of(safe(function() return w.TB_Button end))) .. ": " .. key_part(w)) end
    end, 0)
end

local key_edit_t = -10
local function keymap_decide() key_edit_t = os.clock() end
local function keymap_newkey(ctx)
    local w = self_of(ctx)
    if not w or os.clock() - key_edit_t > 30 then return end    -- not while the screen fills its rows
    Menus.defer(function()
        if UI.valid(w) then Menus.touch(); Out.say(key_part(w), true) end
    end, 0.05)
end

-- ---------------------------------------------------------------- controller setup
local function cs_button(w)
    local raw = UI.text_of(safe(function() return w.TB_Btn end))
    return raw and pad_part(raw) or ""
end

local function cs_editable(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local name = text(safe(function() return w.TB_title_commnd_ON end))
        if name == "" or name:find("^err%(") then return end
        say_row(name .. ": " .. cs_button(w))
    end, 0)
end

local function cs_assigned(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        -- SetValue runs for every row when the screen opens; speak only the highlighted one
        if UI.valid(w) and hovering(w) then
            Menus.touch()
            Out.say(cs_button(w), true)
        end
    end, 0.05)
end

local function cs_value_row(ctx)       -- layout type ("Custom") and Character Movements
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local t = UI.read(w)
        local mv = text(safe(function() return w.TB_title_ON end))
        if mv ~= "" then
            local a = UI.text_of(safe(function() return w.TB_Btn_1peace_1 end))
            local b = UI.text_of(safe(function() return w.TB_Btn_1peace_2 end))
            t = mv .. ": " .. table.concat({ pad_part(a), pad_part(b) }, " and ")
        else
            local v = text(safe(function() return w.TB_value_ON end))
            if v ~= "" then t = "Button layout: " .. v end
        end
        say_row(t)
    end, 0)
end

local function cs_value_change(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local v = text(safe(function() return w.TB_value_ON end))
        if v ~= "" then Menus.touch(); Out.say(v, true) end
    end, 0.05)
end

local cs_open_t = -10
local function cs_open()
    if os.clock() - cs_open_t < 2 then return end
    cs_open_t = os.clock()
    Menus.touch()
    -- after the first row, which is spoken as the screen opens and would cut this off
    Menus.defer(function()
        Out.queue("Careful: any button you press here is set for the highlighted row. Up and down move. "
            .. "Leave with Confirm and Exit at the bottom, or Restore Previous Settings first to undo.")
    end, 0.4)
end

-- ---------------------------------------------------------------- legal pages
local function agreement_open(ctx)
    local w = self_of(ctx)
    if not w then return end
    Menus.defer(function()
        if not UI.valid(w) then return end
        local body = UI.text_of(safe(function() return w.tb_title end)) or ""
        -- about the first 600 characters, cut at a line end
        local first = body:sub(1, 600)
        if #body > 600 then first = first:match("^(.*)\n") or first end
        first = UI.clean((first:gsub("\r?\n", " "))) or ""
        Menus.touch()
        Out.say(first .. (#body > #first + 20 and " ... F9 reads the whole text." or ""), true)
    end, 0.2)
end

-- ---------------------------------------------------------------- hooks
local OP = "/Game/UI/Widget/Option/"
local BM = OP .. "ButtonMapping/"
local CS = OP .. "ControllerSetting/"
Options.HOOKS = {
    { OP .. "WBP_UI_OP_List_Button.WBP_UI_OP_List_Button_C:OnSelect", plain_row },
    { OP .. "WBP_UI_OP_Setting_Button.WBP_UI_OP_Setting_Button_C:OnSelect", setting_row },
    { OP .. "WBP_UI_OP_Setting_Button.WBP_UI_OP_Setting_Button_C:SetValueText", setting_changed },
    { OP .. "WBP_UI_OP_Setting_Button.WBP_UI_OP_Setting_Button_C:UpdateVolume", setting_changed },
    { BM .. "WBP_UI_OP_ButtonMapping_Menu_Button.WBP_UI_OP_ButtonMapping_Menu_Button_C:PlaySelect", plain_row },
    { BM .. "WBP_UI_OP_ButtonMapping_Button.WBP_UI_OP_ButtonMapping_Button_C:PlayAnimSelect", keymap_row },
    { BM .. "WBP_UI_OP_ButtonMapping_Button.WBP_UI_OP_ButtonMapping_Button_C:PlayAnimDecide", keymap_decide },
    { BM .. "WBP_UI_OP_ButtonMapping_Button.WBP_UI_OP_ButtonMapping_Button_C:SetKeyText", keymap_newkey },
    { BM .. "WBP_UI_OP_ButtonMapping_Button2.WBP_UI_OP_ButtonMapping_Button2_C:PlayAnimSelect", plain_row },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Editable.WBP_UI_OP_CS_Menu_Btn_Editable_C:Select", cs_editable },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Editable.WBP_UI_OP_CS_Menu_Btn_Editable_C:SetValue", cs_assigned },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Command.WBP_UI_OP_CS_Menu_Btn_Command_C:Select", plain_row },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Move.WBP_UI_OP_CS_Menu_Btn_Move_C:Select", cs_value_row },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Asist.WBP_UI_OP_CS_Menu_Btn_Asist_C:Select", cs_value_row },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Asist.WBP_UI_OP_CS_Menu_Btn_Asist_C:OnArrowLeft", cs_value_change },
    { CS .. "WBP_UI_OP_CS_Menu_Btn_Asist.WBP_UI_OP_CS_Menu_Btn_Asist_C:OnArrowRight", cs_value_change },
    { CS .. "WBP_UI_OP_CS_List.WBP_UI_OP_CS_List_C:OnPlayFrameInAnimation", cs_open },
    { "/Game/UI/Widget/StartUp/WBP_UI_StartUp_Agreement.WBP_UI_StartUp_Agreement_C:OnPlayAnimIn", agreement_open },
}
Options.PRELOAD = {
    OP .. "WBP_UI_OP_List_Button", OP .. "WBP_UI_OP_Setting_Button",
    BM .. "WBP_UI_OP_ButtonMapping_Menu_Button", BM .. "WBP_UI_OP_ButtonMapping_Button", BM .. "WBP_UI_OP_ButtonMapping_Button2",
    CS .. "WBP_UI_OP_CS_Menu_Btn_Editable", CS .. "WBP_UI_OP_CS_Menu_Btn_Command", CS .. "WBP_UI_OP_CS_Menu_Btn_Move",
    CS .. "WBP_UI_OP_CS_Menu_Btn_Asist", CS .. "WBP_UI_OP_CS_List",
    "/Game/UI/Widget/StartUp/WBP_UI_StartUp_Agreement",
}
-- classes the generic reader must leave alone (it would read them a second time)
Options.OWN_CLASSES = {
    WBP_UI_OP_List_Button_C = true, WBP_UI_OP_Setting_Button_C = true, WBP_UI_OP_ButtonMapping_Menu_Button_C = true,
    WBP_UI_OP_ButtonMapping_Button_C = true, WBP_UI_OP_ButtonMapping_Button2_C = true,
    WBP_UI_OP_CS_Menu_Btn_Editable_C = true, WBP_UI_OP_CS_Menu_Btn_Command_C = true,
    WBP_UI_OP_CS_Menu_Btn_Move_C = true, WBP_UI_OP_CS_Menu_Btn_Asist_C = true,
}

function Options.init(menus) Menus = menus end

return Options
