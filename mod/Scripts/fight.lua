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
-- (the in-match pause menu, WBP_UI_Pause_C, is nested in another widget: it
-- is never "in viewport", only its visibility changes)
local MENUS = { "WBP_UI_PracticeMenu_C", "WBP_UI_CommandList_C" }
local function any_menu()
    for _, n in ipairs(MENUS) do
        local w = safe(function() return FindFirstOf(n) end)
        if w and UI.shown(w) then return true end
    end
    local p = safe(function() return FindFirstOf("WBP_UI_Pause_C") end)
    return p ~= nil and UI.valid(p) and safe(function() return p:IsVisible() end) == true
end

local function name(n)
    local id = safe(function() return f[n].FighterId end)
    return D.fighters[id] or (n == Fight.me and "You" or "Opponent")
end

local function start()
    hp[0], hp[1] = nil, nil      -- health reads 0 until the round is set up
    local M = package.loaded["menus"]
    Fight.me = (M and M.side) or 0
    local key = tostring(safe(function() return f[0].FighterId end)) .. ":" .. tostring(safe(function() return f[1].FighterId end))
    if key ~= match_key then
        match_key = key
        local me, op = Fight.me, 1 - Fight.me
        -- story mode uses fighter versions with their own ids (not on the
        -- select screen, so not in data.lua): then just say the fight starts
        local a = D.fighters[safe(function() return f[me].FighterId end)]
        local b = D.fighters[safe(function() return f[op].FighterId end)]
        Out.queue(a and b and (a .. " versus " .. b .. ".") or "Fight start.")
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

-- Tekken Ball: the ball in play is a visible PolarisBallActor
local ball, next_ball, ball_sent = nil, 0, false
Fight.ball_cue = true
Fight.ball_info = nil       -- last { d = cm, h = cm, side = "left"/"right" } for F5

local function find_ball()
    ball = nil
    local arr = FindAllOf("PolarisBallActor")
    if type(arr) ~= "table" then return end
    for _, x in ipairs(arr) do
        if UI.valid(x) and safe(function() return x.IsVisibleActor end) then ball = x; return end
    end
end

-- floor height is about 100 cm below a standing fighter's actor origin
local function ball_frame(a, c, s)
    local t = os.clock()
    if t >= next_ball then
        next_ball = t + 1.0
        if not (UI.valid(ball) and safe(function() return ball.IsVisibleActor end)) then find_ball() end
    end
    local l = ball and safe(function() return ball:K2_GetActorLocation() end)
    if not l or not Fight.ball_cue then
        if ball_sent then ball_sent = false; Out.send("BL0") end
        Fight.ball_info = nil
        return
    end
    local dx, dy = l.X - a.X, l.Y - a.Y
    local screen, depth = dx * -s + dy * c, dx * c + dy * s
    local h, d = l.Z - (a.Z - 100), math.sqrt(dx * dx + dy * dy)
    Fight.ball_info = { d = d, h = h, side = screen < 0 and "left" or "right" }
    ball_sent = true
    Out.send(string.format("BL\t%.1f\t%.1f\t%.1f\t%.1f", screen, depth, h, d))
end

local function frame()
    local me, op = f[Fight.me], f[1 - Fight.me]
    local a = safe(function() return me:K2_GetActorLocation() end)
    local b = safe(function() return op:K2_GetActorLocation() end)
    if not a or not b then return end
    if not UI.valid(pc) then pc = FindFirstOf("PlayerController") end
    local yaw = safe(function() return pc.PlayerCameraManager:GetCameraRotation().Yaw end) or 0
    local r = math.rad(yaw)
    local c, s = math.cos(r), math.sin(r)
    if Fight.beacon then
        Out.send(string.format("F\t%.1f\t%.1f\t%.1f\t%.1f\t%.4f\t%.4f", a.X, a.Y, b.X, b.Y, c, s))
    else
        Out.send("F0")
    end
    ball_frame(a, c, s)
end

-- game thread
function Fight.tick()
    local t = os.clock()
    if not ok_fighters() then
        if active then active = false; Out.send("F0"); Out.send("BL0") end
        if t < next_find then return end
        next_find = t + 1.0
        find_fighters()
        if not ok_fighters() then return end
    end
    if t >= next_menu_check then
        next_menu_check = t + 0.3
        menu_open = any_menu()
        if not hud_up() then
            if active then active = false; Out.send("F0"); Out.send("BL0") end
            return
        end
    elseif not active then
        return
    end
    if not active then active = true; start() end
    if t >= next_hp then next_hp = t + 0.2; health() end
    if menu_open then Out.send("F0"); Out.send("BL0"); ball_sent = false return end
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
    local text = string.format("%s %d percent, %s %d percent. Distance %.1f meters.",
        name(me), math.floor((hp[me] or 100) + 0.5), name(op), math.floor((hp[op] or 100) + 0.5), d)
    local bi = Fight.ball_info
    if bi then
        text = text .. string.format(" Ball %.1f meters to your %s, %s.", bi.d / 100, bi.side,
            bi.h < 60 and "low" or bi.h < 180 and "chest high" or "high")
    end
    Out.say(text, true)
end

function Fight.toggle_beacon()
    Fight.beacon = not Fight.beacon
    Out.say(Fight.beacon and "Opponent beacon on" or "Opponent beacon off", true)
end

function Fight.toggle_ball()
    Fight.ball_cue = not Fight.ball_cue
    Out.say(Fight.ball_cue and "Ball sound on" or "Ball sound off", true)
end

return Fight
