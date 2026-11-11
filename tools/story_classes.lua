-- Dev console (tools\t8.py luaf): load the story-only widget classes and list
-- their functions and member names (names only, no values are read).
local W = "/Game/UI/Widget/"
local C = {
    W .. "Story_STE/WBP_UI_Story_STE", W .. "Story_STE/WBP_UI_Story_STE_Menu",
    W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices", W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices_ProfList",
    W .. "Story_TwoChoices/WBP_UI_Story_TwoChoices_SelectItem",
    W .. "Story_IW/WBP_UI_Story_IW_HUD", W .. "Story_IW/WBP_UI_Story_IW_HUD_MessageWin",
    W .. "Story_IW/WBP_UI_Story_IW_HUD_NoticeWin", W .. "Story_IW/WBP_UI_Story_IW_HUD_Gauge_Power",
    W .. "Story_Tournament/WBP_UI_Story_Tournament", W .. "Story_Tournament/WBP_UI_Story_Tournament_Panel",
    W .. "Story/WBP_UI_Story_Difficulty", W .. "Story/WBP_UI_Story_Difficulty_Button",
    W .. "Dialog/WBP_UI_Story_Difficulty", W .. "Dialog/WBP_UI_Story_Difficulty_Button",
    W .. "HUD/WBP_UI_HUD_ControlGuide", W .. "HUD/WBP_UI_HUD_ControlGuide_Line",
    W .. "Story_DLC/WBP_UI_Story_DLC", W .. "Story_DLC/WBP_UI_Story_DLC_HUD_MessageWin",
    W .. "Story_DLC/WBP_UI_Story_DLC_Window",
}
for _, base in ipairs(C) do
    local short = base:match("([^/]+)$") .. "_C"
    local path = base .. "." .. short
    pcall(LoadAsset, path)
    local c = StaticFindObject(path)
    if c and c:IsValid() then
        local fs, ps = {}, {}
        pcall(function() c:ForEachFunction(function(f) fs[#fs + 1] = f:GetFName():ToString() end) end)
        pcall(function() c:ForEachProperty(function(pr) ps[#ps + 1] = pr:GetFName():ToString() end) end)
        local sup = ""
        pcall(function() sup = c:GetSuperStruct():GetFName():ToString() end)
        p("== " .. path .. " : " .. sup)
        p("  F: " .. table.concat(fs, " "))
        p("  P: " .. table.concat(ps, " "))
    else
        p("-- missing " .. path)
    end
end
