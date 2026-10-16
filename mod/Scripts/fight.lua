--[[
  fight.lua - opponent beacon and fight announcements.
  About every 40 ms during a fight this reads both fighters' positions and
  the camera's direction and sends them to the helper, which plays the
  Mist World style two-note ping (helper\beacon.c): first note fixed, second
  note higher when the opponent is in the background (up the screen), lower
  in the foreground, panned to their side, faster when closer.

  Fighters are PolarisCharacterActor with PlayerNumber 0 (player 1) and 1.
  The practice dummy has PlayerNumber 2 and is ignored.
]]
local Out = require("out")
local UI  = require("lib/ui")
local D   = require("data")

local Fight = {}
local safe = UI.safe

Fight.me = 0                 -- PlayerNumber of the player's fighter
Fight.beacon = true
local f = { [0] = nil, [1] = nil }
local pc = nil
local active = false
local next_find, next_menu_check, next_hp = 0, 0, 0
local menu_open = false
local hp = { [0] = 100, [1] = 100 }
local match_key = nil

local function find_fighters()
    f[0], f[1] = nil, nil
    local arr = FindAllOf("PolarisCharacterActor")
    if type(arr) ~= "table" then return end
    for _, a in ipairs(arr) do
        local n = safe(function() return a.PlayerNumber end)
        if (n == 0 or n == 1) and safe(function() return a.IsVisibleActor end) then f[n] = a end
    end
end

local function ok_fighters() return UI.valid(f[0]) and UI.valid(f[1]) end

-- character select also has PolarisCharacterActors; a fight has the battle HUD
local HUDS = { "WBP_UI_HUD_S2_C", "WBP_UI_HUD_C" }
local hud = nil
local function hud_up()
    if UI.valid(hud) and UI.shown(hud) then return true end
    hud = nil
    for _, n in ipairs(HUDS) do
        local w = safe(function() return FindFirstOf(n) end)
        if w and UI.shown(w) then hud = w; return true end
    end
    return false
end

-- a pause / practice menu / move list on screen: mute the beacon
local MENUS = { "WBP_UI_PracticeMenu_C", "WBP_UI_CommandList_C", "WBP_UI_Pause_Menu_C", "WBP_UI_Pause_C" }
local function any_menu()
    for _, n in ipairs(MENUS) do
        local w = safe(function() return FindFirstOf(n) end)
        if w and UI.shown(w) then return true end
    end
    return false
end

local function name(n) return D.fighter(safe(function() return f[n].FighterId end)) end

local function start()
    hp[0], hp[1] = nil, nil      -- health reads 0 until the round is set up
    local M = package.loaded["menus"]
    Fight.me = (M and M.side) or 0
    local key = tostring(safe(function() return f[0].FighterId end)) .. ":" .. tostring(safe(function() return f[1].FighterId end))
    if key ~= match_key then
        match_key = key
        local me, op = Fight.me, 1 - Fight.me
        Out.queue(name(me) .. " versus " .. name(op) .. ".")
    end
end

local function health()
    for n = 0, 1 do
        local h = safe(function() return f[n]:GetHPPercentage() end)
        if type(h) == "number" and (hp[n] or h > 0) then
            local mine = n == Fight.me
            local was = hp[n] or h
            if h <= 0 and was > 0 then
                Out.say(mine and "You are down. K.O." or "Opponent K.O.")
            elseif h <= 25 and was > 25 then
                Out.queue(mine and "Your health is low." or "Opponent health low.")
            elseif h <= 50 and was > 50 then
                Out.queue(mine and "You are at half health." or "Opponent at half health.")
            elseif h >= 99 and was < 50 then
                -- new round
            end
            hp[n] = h
        end
    end
end

local function frame()
    local me, op = f[Fight.me], f[1 - Fight.me]
    local a = safe(function() return me:K2_GetActorLocation() end)
    local b = safe(function() return op:K2_GetActorLocation() end)
    if not a or not b then return end
    if not UI.valid(pc) then pc = FindFirstOf("PlayerController") end
    local yaw = safe(function() return pc.PlayerCameraManager:GetCameraRotation().Yaw end) or 0
    local r = math.rad(yaw)
    Out.send(string.format("F\t%.1f\t%.1f\t%.1f\t%.1f\t%.4f\t%.4f", a.X, a.Y, b.X, b.Y, math.cos(r), math.sin(r)))
end

-- game thread
function Fight.tick()
    local t = os.clock()
    if not ok_fighters() then
        if active then active = false; Out.send("F0") end
        if t < next_find then return end
        next_find = t + 1.0
        find_fighters()
        if not ok_fighters() then return end
    end
    if t >= next_menu_check then
        next_menu_check = t + 0.3
        menu_open = any_menu()
        if not hud_up() then
            if active then active = false; Out.send("F0") end
            return
        end
    elseif not active then
        return
    end
    if not active then active = true; start() end
    if t >= next_hp then next_hp = t + 0.2; health() end
    if menu_open or not Fight.beacon then Out.send("F0") return end
    frame()
end

function Fight.active() return active end
function Fight.menu_open() return menu_open end

-- F5: distance and health
function Fight.status()
    if not ok_fighters() then Out.say("Not in a fight.") return end
    local a = safe(function() return f[0]:K2_GetActorLocation() end)
    local b = safe(function() return f[1]:K2_GetActorLocation() end)
    local d = a and b and math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) / 100 or 0
    local me, op = Fight.me, 1 - Fight.me
    Out.say(string.format("%s %d percent, %s %d percent. Distance %.1f meters.",
        name(me), math.floor((hp[me] or 100) + 0.5), name(op), math.floor((hp[op] or 100) + 0.5), d), true)
end

function Fight.toggle_beacon()
    Fight.beacon = not Fight.beacon
    Out.say(Fight.beacon and "Opponent beacon on" or "Opponent beacon off", true)
end

return Fight
