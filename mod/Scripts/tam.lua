--[[
  tam.lua - Arcade Quest (the game calls it TAM, True Arcade Mode).

  You walk an avatar around an arcade. The mod keeps a list of the people
  and machines there (BP_TAM_NPC_Base_C: ghosts, Max, the ghost battle
  machine), and the fight beacon's two-note ping (helper\beacon.c) points
  at the one you picked: panned to its side of the screen, second note
  higher when it is ahead (up the screen), lower when behind, faster when
  closer. F1 / Shift+F1 pick the next / previous one (nearest first), F5
  says the objective and where the pick is.

  When the avatar is close enough to use someone, the player's
  collision_npc is that NPC: the mod says the name and the game's prompt
  (the HeadGuide over their head: "Numpad 4 key, Talk" / "J key, Battle"),
  or "in reach" when the NPC is out of the camera's view (no prompt then).

  Talk: WBP_TAM_Npc_Talk_C (player.ui_talk) keeps the whole current line in
  showingMessage while the window types it out, TB_Name the speaker. Story
  and battle talk: WBP_UI_TAM_Talk_C (player.ui_battle_talk), LastShowMessage
  / TB_RT_message. Objective: WBP_UI_TAM_ObjectiveList_C.TB_task.

  Detection: a hook on BP_TAM_Player_C:ReceiveTick hands over the player
  every frame (no searches). The NPC list is searched when Arcade Quest
  starts, then every 30 s and when F1 asks for a fresh order.
]]
local Out = require("out")
local UI  = require("lib/ui")

local TAM = {}
local safe = UI.safe or function(fn) local ok, v = pcall(fn); if ok then return v end end

local player, seen_t = nil, -10
local pc, objective = nil, nil
local targets, sel = {}, 0
local next_scan, scan_t = 0, -100
local last_coll, coll_t = nil, 0
local last_talk, last_btalk = nil, nil
local last_obj, next_obj = nil, 0
local beacon_sent = false
local started = false

TAM.FAR, TAM.NEAR = 1500, 120     -- cm: slowest / fastest ping

function TAM.on_player_tick(ctx)
    local p = safe(function() return ctx:get() end)
    if p then player = p; seen_t = os.clock() end
end

function TAM.active()
    return os.clock() - seen_t < 0.5 and UI.valid(player)
end

-- UE4SS hands out a new Lua object for the same actor: compare by name
local function key(a) return a and safe(function() return a:GetFullName() end) or nil end

local function loc(a)
    return safe(function() return a:K2_GetActorLocation() end)
end

local function str(v)
    if v == nil then return "" end
    local s = safe(function() return v:ToString() end)
    if type(s) ~= "string" or s == "NULL" then return "" end
    return s
end

-- head widgets: name -> icon texture name (09 = treasure chest, 03 = none)
local function head_icons()
    local m = {}
    for _, h in ipairs(FindAllOf("WBP_UI_Lobby_AvatarHead_C") or {}) do
        local nm = UI.valid(h) and safe(function() return h.TB_name2:GetText():ToString() end)
        if nm and nm ~= "" then
            local icon = h.Rep_T_UI_LOBBY_ICON
            local shown = safe(function() return icon:GetVisibility() end)
            local tex = safe(function() return icon.Brush.ResourceObject:GetFName():ToString() end)
            if shown ~= 1 and shown ~= 2 and tex then m[nm] = tex end
        end
    end
    return m
end

local function npc_name(a)
    local cls = UI.name(safe(function() return a:GetClass() end))
    local n = str(safe(function() return a.GhostName end))
    if n == "" then n = str(safe(function() return a.AvatarHeadName end)) end
    if n == "" and cls:find("GhostMenu") then n = "Ghost battle machine" end
    if n == "" then n = str(safe(function() return a.NpcName end)) end
    return n, cls
end

local function scan()
    scan_t = os.clock()
    next_scan = scan_t + 30
    local old = targets[sel] and targets[sel].key
    local icons = head_icons()
    local list = {}
    for _, a in ipairs(FindAllOf("BP_TAM_NPC_Base_C") or {}) do
        if UI.valid(a) and not safe(function() return a.bHidden end) then
            local l = loc(a)
            local name, cls = npc_name(a)
            -- the battle-machine base sits at (0, 0, 2000), out of the room
            if l and name ~= "" and l.Z < 1900 then
                local t = { actor = a, name = name, key = key(a) }
                local tex = icons[name]
                if tex == "T_UI_LB_Icon_09" then t.note = "treasure"
                elseif tex and tex ~= "T_UI_LB_Icon_03" then t.note = "marked"; Out.log("TAM icon " .. name .. " " .. tex) end
                list[#list + 1] = t
            end
        end
    end
    targets = list
    sel = 0
    for i, t in ipairs(targets) do if t.key == old then sel = i end end
end

local function cam()
    if not UI.valid(pc) then pc = FindFirstOf("PlayerController") end
    local yaw = safe(function() return pc.PlayerCameraManager:GetCameraRotation().Yaw end) or 0
    local r = math.rad(yaw)
    return math.cos(r), math.sin(r)
end

-- "3 meters ahead, a little left"
local function where(t)
    local a, b = loc(player), loc(t.actor)
    if not a or not b then return "" end
    local c, s = cam()
    local dx, dy = b.X - a.X, b.Y - a.Y
    local d = math.sqrt(dx * dx + dy * dy)
    local fwd, right = dx * c + dy * s, dx * -s + dy * c
    local ang = math.deg(math.atan(right, fwd))       -- 0 ahead, 90 right
    local dir
    local aa = math.abs(ang)
    if aa < 20 then dir = "ahead"
    elseif aa < 70 then dir = (fwd > 0 and "ahead " or "") .. (ang > 0 and "right" or "left")
    elseif aa < 110 then dir = ang > 0 and "right" or "left"
    elseif aa < 160 then dir = "behind " .. (ang > 0 and "right" or "left")
    else dir = "behind" end
    local m = math.floor(d / 100 + 0.5)
    return (m < 1 and "close" or (m .. (m == 1 and " meter " or " meters ") .. dir))
end

local function describe(t)
    local s = t.name
    if t.note then s = s .. ", " .. t.note end
    return s
end

function TAM.next(step)
    if not TAM.active() then return false end
    if os.clock() - scan_t > 3 or #targets == 0 then
        local cur = targets[sel] and targets[sel].key
        scan()
        -- fresh list: nearest first
        local a = loc(player)
        if a then
            for _, t in ipairs(targets) do
                local b = loc(t.actor)
                t.d = b and ((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2) or math.huge
            end
            table.sort(targets, function(x, y) return x.d < y.d end)
            sel = 0
            for i, t in ipairs(targets) do if t.key == cur then sel = i end end
        end
    end
    if #targets == 0 then Out.say("Nobody here.", true) return true end
    sel = sel + step
    if sel > #targets then sel = 1 elseif sel < 1 then sel = #targets end
    local t = targets[sel]
    Out.say(describe(t) .. ", " .. where(t), true)
    return true
end

local function objective_text()
    if not UI.valid(objective) then
        -- the first one found is the class's template: take the visible one
        objective = nil
        for _, w in ipairs(FindAllOf("WBP_UI_TAM_ObjectiveList_C") or {}) do
            if UI.valid(w) and safe(function() return w:IsVisible() end) then objective = w break end
        end
        if not objective then return nil end
    end
    if not safe(function() return objective:IsVisible() end) then return nil end
    return UI.clean(UI.text_of(safe(function() return objective.TB_task end)) or "")
end

function TAM.status()
    if not TAM.active() then return false end
    local parts = {}
    local o = objective_text()
    if o then parts[#parts + 1] = "Objective: " .. o:gsub("[.!?]$", "") end
    local t = targets[sel]
    if t and UI.valid(t.actor) then parts[#parts + 1] = describe(t) .. ", " .. where(t)
    else parts[#parts + 1] = "Nobody picked. F1 picks the nearest." end
    Out.say(table.concat(parts, ". "), true)
    return true
end

-- the prompt over the NPC the avatar can use ("J key, Talk")
local function prompt()
    for _, g in ipairs(FindAllOf("WBP_UI_Lobby_HeadGuide_C") or {}) do
        -- a guide not in the name layer (no parent) is not on screen
        local v = UI.valid(g) and safe(function() return g:GetVisibility() end)
        local pv = safe(function() return g:GetParent():GetVisibility() end)
        if (v == 0 or v == 3 or v == 4) and (pv == 0 or pv == 3 or pv == 4) then
            local t = UI.read(g)
            if t ~= "" then return t end
        end
    end
end

local function proximity()
    local c = safe(function() return player.collision_npc end)
    if not UI.valid(c) then c = nil end
    local k = key(c)
    if k ~= last_coll then
        last_coll = k
        coll_t = os.clock()
        if c then
            local n = npc_name(c)
            TAM.pending_prompt = n ~= "" and n or "Someone"
            Out.tone("open")
        end
    end
    -- the prompt widget fills in a frame or two after the collision
    if TAM.pending_prompt and os.clock() - coll_t > 0.1 then
        local p = prompt()
        if p or os.clock() - coll_t > 0.6 then
            -- the game draws its prompt only while the NPC is in view
            Out.say(TAM.pending_prompt .. ", " .. (p or "in reach"))
            TAM.pending_prompt = nil
        end
    end
end

-- WBP_TAM_Npc_Talk_C "Event Show" / "Event Show Next Text" (hooks below)
-- mark a new line; the text is read on the next tick. The window can stay
-- "visible" after it closes, so visibility alone does not mean a new line.
local talk_pending = false
function TAM.on_talk_show() talk_pending = true end

local function talk()
    local w = safe(function() return player.ui_talk end)
    if UI.valid(w) then
        local msg = safe(function() return w.showingMessage:ToString() end) or ""
        local vis = safe(function() return w:IsVisible() end) == true
        if last_talk == nil then last_talk = msg end
        if msg ~= "" and vis and (talk_pending or msg ~= last_talk) then
            local who = UI.clean(UI.text_of(safe(function() return w.TB_Name end)) or "")
            Out.say((who and who ~= "" and (who .. ": ") or "") .. (UI.clean(msg) or msg), true)
        end
        last_talk = msg
    end
    talk_pending = false
    -- story / battle talk window
    local b = safe(function() return player.ui_battle_talk end)
    if UI.valid(b) then
        local msg = str(safe(function() return b.LastShowMessage end))
        if msg == "" and safe(function() return b.m_is_message_finished end) then
            msg = UI.text_of(safe(function() return b.TB_RT_message end)) or ""
        end
        local vis = safe(function() return b:IsVisible() end) == true
        if last_btalk == nil then last_btalk = msg end
        if msg ~= "" and vis and msg ~= last_btalk then
            local who = UI.clean(UI.text_of(safe(function() return b.TB_Name end)) or "")
            Out.say((who and who ~= "" and (who .. ": ") or "") .. (UI.clean(msg) or msg), true)
        end
        last_btalk = msg
    end
end

local function watch_objective()
    if os.clock() < next_obj then return end
    next_obj = os.clock() + 0.5
    local o = objective_text()
    if o and o ~= last_obj then
        Out.queue("Objective: " .. o)
        last_obj = o
    end
end

-- the avatar cannot walk: talk, Max's menu, the arcade map, pause, events
local map_w = nil
local function shown(w) return UI.valid(w) and safe(function() return w:IsVisible() end) == true end
local function busy()
    if shown(map_w) then return true end
    if safe(function() return player.IsTalkTurn or player.IsEventFlag or player.IsPauseMenu end) then return true end
    return shown(safe(function() return player.ui_talk end)) or shown(safe(function() return player.ui_menu_2d end))
        or shown(safe(function() return player.ui_battle_talk end))
end

local function beacon()
    local t = targets[sel]
    local a = loc(player)
    local b = t and UI.valid(t.actor) and loc(t.actor)
    local Fight = package.loaded["fight"]
    local on = not Fight or Fight.beacon
    if not (a and b and on) or (last_coll and t and last_coll == t.key) or busy() then
        if beacon_sent then Out.send("F0"); beacon_sent = false end
        return
    end
    local c, s = cam()
    Out.send(string.format("F\t%.1f\t%.1f\t%.1f\t%.1f\t%.4f\t%.4f\t%d\t%d", a.X, a.Y, b.X, b.Y, c, s, TAM.FAR, TAM.NEAR))
    beacon_sent = true
end

local function stop()
    map_w = nil
    if beacon_sent then Out.send("F0"); beacon_sent = false end
    started = false
    targets, sel = {}, 0
    last_coll, last_talk, last_btalk, last_obj = nil, nil, nil, nil
    objective, pc = nil, nil
end

-- game thread, from main.lua frame() (not during fights)
function TAM.tick()
    if not TAM.active() then
        if started then stop() end
        return
    end
    if not started then
        started = true
        next_scan = os.clock() + 1.5      -- let the room finish loading
        Out.queue("Arcade Quest. F1 picks a person or machine to walk to.")
    end
    if os.clock() >= next_scan then scan() end
    proximity()
    talk()
    watch_objective()
    beacon()
end

-- Max's menu (WBP_UI_TAM_BuddyMenu_C, player.ui_menu_2d) and its submenu:
-- the row buttons are made at run time; OnButtonSelect hands over the row
-- (TB_text_ON). TB_Msg is Max's line for that row ("Wanna head off to
-- another Arcade?"), set in the same frame: read after a rest, as help.
local function on_row_select(ctx)
    local w = safe(function() return ctx:get() end)
    local t = UI.valid(w) and UI.clean(UI.text_of(safe(function() return w.TB_text_ON end)) or "")
    if not t or t == "" then return end
    Out.say(t)
    local M = package.loaded["menus"]
    if M then M.defer(function()
        local m = UI.valid(player) and safe(function() return player.ui_menu_2d end)
        local msg = UI.valid(m) and UI.clean(UI.text_of(safe(function() return m.TB_Msg end)) or "")
        if msg and msg ~= "" then Out.help(msg) end
    end) end
end

-- arcade map (Max: Head Out): WBP_UI_TAM_RPG_Icon_C:PlayAnim_Hover on the
-- spot under the cursor; UI.read gives its name, IsUnlock false = locked
local function on_map_icon(ctx)
    local w = safe(function() return ctx:get() end)
    if not UI.valid(w) then return end
    local t = UI.read(w)
    if t == "" then return end
    if safe(function() return w.IsUnlock end) == false then t = t .. ", locked" end
    Out.say(t)
end
local function on_map(ctx) map_w = safe(function() return ctx:get() end) end

local NPC_TALK = "/Game/TrueArcadeMode/UI/WBP_TAM_Npc_Talk.WBP_TAM_Npc_Talk_C:"
TAM.HOOKS = {
    { "/Game/TrueArcadeMode/BluePrints/Player/BP_TAM_Player.BP_TAM_Player_C:ReceiveTick", TAM.on_player_tick },
    { NPC_TALK .. "Event Show", TAM.on_talk_show },
    { NPC_TALK .. "Event Show Next Text", TAM.on_talk_show },
    { "/Game/UI/Widget/TAM/WBP_UI_TAM_RPG_Icon.WBP_UI_TAM_RPG_Icon_C:PlayAnim_Hover", on_map_icon },
    { "/Game/UI/Widget/TAM/WBP_UI_TAM_RPG_Map.WBP_UI_TAM_RPG_Map_C:Event_Start", on_map },
    { "/Game/UI/Widget/TAM/WBP_UI_TAM_BuddyMenuList.WBP_UI_TAM_BuddyMenuList_C:OnButtonSelect", on_row_select },
    { "/Game/UI/Widget/TAM/WBP_UI_TAM_BuddyMenu_SubList.WBP_UI_TAM_BuddyMenu_SubList_C:OnButtonSelect", on_row_select },
}

return TAM
