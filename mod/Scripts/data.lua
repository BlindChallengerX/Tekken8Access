--[[
  data.lua - names the game only shows as pictures.
  Fighter ids are what WBP_UI_CharSelect_C:OnSetCurrentName passes (and
  PolarisCharacterActor.FighterId); stage ids are what
  WBP_UI_StageSelect_C:_SetSelectedStageID passes. Read off the select
  screens on 2026-10-16 (game ver. 3.02.02).
]]
local D = {}

D.fighters = {
    [0] = "Paul", [1] = "Law", [2] = "King", [3] = "Yoshimitsu", [4] = "Hwoarang", [5] = "Xiaoyu",
    [6] = "Jin", [7] = "Bryan", [8] = "Kazuya", [9] = "Steve", [10] = "Jack-8", [11] = "Asuka",
    [12] = "Devil Jin", [13] = "Feng", [14] = "Lili", [15] = "Dragunov", [16] = "Leo", [17] = "Lars",
    [18] = "Alisa", [19] = "Claudio", [20] = "Shaheen", [21] = "Nina", [22] = "Lee", [23] = "Kuma",
    [24] = "Panda", [25] = "Zafina", [26] = "Leroy", [27] = "Jun", [28] = "Reina", [29] = "Azucena",
    [30] = "Victor", [31] = "Raven", [33] = "Eddy", [34] = "Lidia", [35] = "Heihachi", [36] = "Clive",
    [37] = "Anna", [38] = "Fahkumram", [39] = "Armor King", [40] = "Miary Zo", [41] = "Kunimitsu",
    [42] = "Bob",
}

D.stages = {
    [0] = "Arena", [1] = "Arena, Underground", [4] = "Urban Square, Evening", [7] = "Yakushima",
    [9] = "Coliseum of Fate", [11] = "Rebel Hangar", [13] = "Fallen Destiny",
    [21] = "Descent into Subconscious", [23] = "Sanctum", [25] = "Into the Stratosphere",
    [27] = "Ortiz Farm", [28] = "Celebration on the Seine", [29] = "Secluded Training Ground",
    [30] = "Elegant Palace", [31] = "Midnight Siege", [33] = "Seaside Resort", [34] = "Genmaji Temple",
    [45] = "Phoenix Gate", [46] = "Pac-Pixels", [47] = "Baobab Horizon",
}

-- Ranks by the number ghost rows carry (WBP_UI_Ghost_*list_C.rank); checked
-- against the rank pictures on 2026-11-13: 0 = T_UI_CMN_RNK_S_nyumonsei,
-- 23 = kijin, 24 = bushin. The pictures are named in Japanese (garyu, fujin,
-- tekkenou ...); past God of Destruction they carry a number (hakaishin01-08).
D.ranks = {
    [0] = "Beginner", "1st Dan", "2nd Dan", "Fighter", "Strategist", "Combatant", "Brawler", "Ranger",
    "Cavalry", "Warrior", "Assailant", "Dominator", "Vanquisher", "Destroyer", "Eliminator", "Garyu",
    "Shinryu", "Tenryu", "Mighty Ruler", "Flame Ruler", "Battle Ruler", "Fujin", "Raijin", "Kishin",
    "Bushin", "Tekken King", "Tekken Emperor", "Tekken God", "Tekken God Supreme", "God of Destruction",
}
function D.rank(n, texture)
    local tier = texture and texture:match("hakaishin0*(%d+)$")
    if tier then return "God of Destruction " .. tier end
    return D.ranks[n] or (n and ("rank " .. tostring(n))) or nil
end

function D.fighter(id) return D.fighters[id] or ("fighter " .. tostring(id)) end
function D.stage(id) return D.stages[id] or ("stage " .. tostring(id)) end

return D
