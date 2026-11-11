-- Dev console: log every call (with arguments) of the story prompt screens.
-- Lines go to helper.log as "SPY ...". Run once per game start.
local Out = require("out")
local W = "/Game/UI/Widget/"
local T = {
    [W .. "Story_STE/WBP_UI_Story_STE.WBP_UI_Story_STE_C"] =
        { "Init", "SetButtonText", "PlayAnimHold", "SetAnimGauge", "SetPause", "SetButton", "SetText", "SetType",
          "PlayAnimGaugeReset", "PlayAnimGaugeMiss", "PlayAnimGaugeSuccess", "PlayAnimGauge", "PlayAnimIn" },
    [W .. "Story_STE/WBP_UI_Story_STE_Menu.WBP_UI_Story_STE_Menu_C"] =
        { "AnimHold", "SetAnimGaugeTime", "PauseButton", "ResetAllButton", "InitializeButtons", "GaugeReset", "AnimMiss",
          "AnimSuccess", "AnimGauge", "AnimIn", "SetButton", "SetupButton", "ResetButtons" },
    [W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices.WBP_UI_Story_TwoChoices_C"] =
        { "SetChooseText", "onUnselect", "OnSelect", "OnDecide", "InitializeButton", "SetCharacterInfo", "SetProfileList",
          "OnSetup", "SetProfile", "SetCharacter", "SetChoosePlayerText", "PlayAnimIn", "PlayAnimOut" },
    [W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices_SelectItem.WBP_UI_Story_TwoChoices_SelectItem_C"] =
        { "SetCharaNameText", "Select", "Unselect", "Decide" },
    [W .. "Story_IW/WBP_UI_Story_IW_HUD_MessageWin.WBP_UI_Story_IW_HUD_MessageWin_C"] =
        { "SetText", "SetFighterInfos", "SetFighterInfo", "FrameIn", "FrameOut", "SetFighterInfoById",
          "SetFighterInfoByString", "SetTextById", "SetTextByString" },
    [W .. "Story_IW/WBP_UI_Story_IW_HUD_NoticeWin.WBP_UI_Story_IW_HUD_NoticeWin_C"] =
        { "SetText", "SetType", "SetTextById", "SetTextByString", "FrameIn", "FrameOut" },
    [W .. "Story_Tournament/WBP_UI_Story_Tournament.WBP_UI_Story_Tournament_C"] =
        { "SetAreaTexts", "PlayVSEnd", "PlayVSStart", "SetupPanels", "PlayPanelResult", "OnPreBattleStart",
          "OnPreBattleEnd", "OnPostBattleStart", "OnPostBattleEnd", "OnSetup" },
    [W .. "Story/WBP_UI_Story_Difficulty.WBP_UI_Story_Difficulty_C"] =
        { "InitializeStoryModeDifficulty", "OnSelectMenu", "OnDecideMenu", "SelectMenu", "PlayAnimIn", "InitializeMenu", "SetSide" },
    [W .. "Story_DLC/WBP_UI_Story_DLC_HUD_MessageWin.WBP_UI_Story_DLC_HUD_MessageWin_C"] =
        { "SetText", "SetFighterInfos", "SetFighterInfo", "FrameIn", "FrameOut" },
}
local n = 0
for cls, fns in pairs(T) do
    pcall(LoadAsset, cls)
    local short = cls:match("%.([^.]+)$")
    for _, fn in ipairs(fns) do
        local ok = pcall(RegisterHook, cls .. ":" .. fn, function(ctx, ...)
            local raw = {}
            for _, a in ipairs({ ... }) do
                local v
                pcall(function() v = a:get() end)
                if type(v) == "userdata" then
                    local s
                    pcall(function() s = v:ToString() end)
                    if not s then pcall(function() s = "obj:" .. v:GetFullName() end) end
                    v = s or "userdata"
                end
                raw[#raw + 1] = tostring(v)
            end
            local name = ""
            pcall(function() name = ctx:get():GetFName():ToString() end)
            Out.log("SPY " .. short .. "[" .. name .. "]:" .. fn .. "(" .. table.concat(raw, " | ") .. ")")
        end)
        if ok then n = n + 1 else p("failed " .. short .. ":" .. fn) end
    end
end
return n .. " spy hooks"
