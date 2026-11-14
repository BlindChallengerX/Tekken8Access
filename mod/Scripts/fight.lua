--[[
  fight.lua - opponent beacon and fight announcements.
  About every 40 ms during a fight this reads both fighters' positions and
  the camera's direction and sends them to the helper, which plays the
  Mist World style two-note ping (helper\beacon.c): first note fixed, second
  note higher when the opponent is in the background (up the screen), lower
  in the foreground, panned to their side, faster when closer.

  Fighters are PolarisCharacterActor with PlayerNumber 0 (player 1) and 1.
  The practice dummy has PlayerNumber 2 and is ignored.

  Which fighter is "me": the side picked on side select; online (no side
  select) the side whose online ID on the fight HUD is the player's own. The
  mod learns that name in offline fights, where the side is known, and keeps
  it in own_name.txt.

  Throw break cue: when the opponent starts a throw, PolarisBlueprintLibrary
  says it is attacking with damage value 16384 (bit 0x4000). Nothing it
  exposes tells which break the throw needs: the attacking bone is the
  grabbing hand (13 left, 9 right), and 1+2 command throws grab with the left
  hand like 1+3 throws. Tested in Throw Escape Training: a plain 1+3 or 2+4
  throw breaks with 1 or 2 (the game shows "1 or 2"); 1+2 does not break it,
  nor does rolling 1 into 1+2 break a 1+2 throw. So in matches every throw
  plays the "press 1" cue. In Practice the tips panel
  (WBP_UI_Practice_S2_C.WBP_UI_Practice_TIPS.TB_Command) shows the escape
  ("Throw escape 1 or 2" / "1+2") the moment the grab connects, ~0.2 s after
  the start: there the cue waits for it and plays the exact one.
]]
local Out = require("out")
local UI  = require("lib/ui")
local D   = require("data")
local Prof = require("lib/prof")

local Fight = {}
local safe = UI.safe

Fight.me = 0                 -- PlayerNumber of the player's fighter
Fight.beacon = true
local f = { [0] = nil, [1] = nil }
local pc = nil
local active = false
local next_find, next_menu_check, next_hp, next_pc = 0, 0, 0, 0
local menu_open = false
local hp = { [0] = 100, [1] = 100 }
local match_key = nil

-- In Combo Challenges the dummy is PlayerNumber 2 and player 2's fighter is
-- hidden: then the dummy stands in for player 2.
local function find_fighters()
    f[0], f[1] = nil, nil
    local arr = FindAllOf("PolarisCharacterActor")
    if type(arr) ~= "table" then return end
    local dummy = nil
    for _, a in ipairs(arr) do
        local n = UI.valid(a) and safe(function() return a.PlayerNumber end)
        if n and safe(function() return a.IsVisibleActor end) then
            if n == 0 or n == 1 then f[n] = a elseif n == 2 then dummy = a end
        end
    end
    if not f[1] then f[1] = dummy end
end

local function ok_fighters() return UI.valid(f[0]) and UI.valid(f[1]) end
-- a combo challenge started or ended (menus.lua): the fighters swap, so
-- look again. Not on every visibility change: fighters hide and reappear
-- while a fight loads, and searching then (actors being built or torn
-- down) is what took the game down on 2026-10-29.
local refind = false
function Fight.refind() refind = true end

-- FindFirstOf / FindAllOf cost 10-26 ms each here (a whole frame), so the
-- fight loop never searches: the battle HUD's Blueprint Tick (hooked in
-- menus.lua) says a fight is on screen, and menus hand over the widgets they
-- see in their hooks. Fighters and the ball are searched once per fight.
local hud_t = -10
local hud_w = nil
function Fight.on_hud_tick(ctx)
    Prof.frame_gap()
    hud_t = os.clock()
    if ctx and not hud_w then hud_w = safe(function() return ctx:get() end) end
end
local function hud_up() return os.clock() - hud_t < 0.5 end

-- a pause / practice menu / move list on screen: mute the beacon. The widgets
-- come from their hooks (Fight.saw_menu). The in-match pause menu,
-- WBP_UI_Pause_C, is nested: it is never "in viewport", only its visibility
-- changes, so for it the visibility is checked.
local menus = {}
function Fight.saw_menu(kind, w) if UI.valid(w) then menus[kind] = w end end
local function any_menu()
    for kind, w in pairs(menus) do
        if not UI.valid(w) then menus[kind] = nil
        elseif kind == "pause" then
            if safe(function() return w:IsVisible() end) then return true end
        elseif UI.shown(w) then return true end
    end
    return false
end

local function name(n)
    local id = safe(function() return f[n].FighterId end)
    return D.fighters[id] or (n == Fight.me and "You" or "Opponent")
end

-- PolarisBlueprintLibrary: sides, attacks (StaticFindObject once, 0.2 ms)
local lib = nil
local function L()
    if not UI.valid(lib) then lib = StaticFindObject("/Script/Polaris.Default__PolarisBlueprintLibrary") end
    return lib
end

-- the player's own online ID, learned offline
local own_name = nil
local function own_file() return Fight.dir and (Fight.dir .. "\\own_name.txt") end
local function load_own()
    local f = own_file() and io.open(own_file(), "r")
    if f then own_name = (f:read("l") or ""):match("^%s*(.-)%s*$"); f:close() end
    if own_name == "" then own_name = nil end
end
local function save_own(n)
    own_name = n
    local f = own_file() and io.open(own_file(), "w")
    if f then f:write(n, "\n"); f:close() end
end
load_own()

local function hud_names()
    local p = safe(function() return hud_w.WBP_UI_HUD_Gauge_S2.WBP_UI_HUD_Player_S2 end)
    if not UI.valid(p) then return nil end
    local function t(n) return UI.clean(UI.text_of(safe(function() return p[n] end)) or "") end
    return t("TB_OnlIneID_L2"), t("TB_OnlIneID_R2")
end

-- PolarisBlueprintLibrary is native and does not check its player id: called
-- while a fight loads, or for player 2 in a combo challenge (where that
-- player is hidden and the dummy is PlayerNumber 2), it took the game down
-- with no crash report (three times on 2026-10-29). So it is only asked
-- once both real fighters are up and the round is set up (health read).
local function lib_safe()
    return hp[0] and hp[1]
        and safe(function() return f[0].PlayerNumber == 0 and f[1].PlayerNumber == 1 end) == true
end

local function pn_for_side(side)
    for n = 0, 1 do
        if safe(function() return L():GetSideByPlayerID(n) end) == side then return n end
    end
    return side
end

-- decide which fighter is me; true once settled. Retried for a few seconds
-- after the fight starts, since the HUD fills in the names during the intro.
local side_known, side_tries, next_side = false, 0, 0
local function resolve_side()
    local M = package.loaded["menus"]
    local picked = M and M.side
    local l, r = hud_names()
    local side
    if picked then
        side = picked
        local mine, other = (side == 0 and l or r), (side == 0 and r or l)
        if mine and mine ~= "" and mine ~= other and mine ~= own_name then
            save_own(mine)
            Out.log("own name learned: " .. mine)
        end
    elseif l and own_name and (l == own_name or r == own_name) and l ~= r then
        side = l == own_name and 0 or 1
        if side == 1 then Out.queue("You are on the right.") end
    elseif l and (l ~= "") ~= (r ~= "") then
        side = l ~= "" and 0 or 1      -- versus the CPU: only the player has a name
    end
    if side then Fight.me = pn_for_side(side) end
    return side ~= nil
end

-- story fighter choice (story.lua): the chosen fighter is me while fights
-- with that fighter follow; the first fight without it ends the choice
local function story_choice()
    local S = package.loaded["story"]
    local want = S and S.chosen
    if not want then return nil end
    want = want:lower()
    for n = 0, 1 do
        local nm = D.fighters[safe(function() return f[n].FighterId end)]
        if nm and nm:lower() == want then return n end
    end
    S.chosen = nil
    return nil
end

local function start()
    hp[0], hp[1] = nil, nil      -- health reads 0 until the round is set up
    tips = nil
    local M = package.loaded["menus"]
    Fight.me = (M and M.side) or 0
    side_known, side_tries, next_side = false, 0, 0
    local chosen = story_choice()
    if chosen then
        Fight.me, side_known = chosen, true
        Out.log("story choice: me = " .. chosen)
    end
    local key = tostring(safe(function() return f[0].FighterId end)) .. ":" .. tostring(safe(function() return f[1].FighterId end))
    local challenge = safe(function() return f[1].PlayerNumber end) == 2
    if key ~= match_key and not challenge then
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
    local now = {}
    for n = 0, 1 do now[n] = safe(function() return f[n]:GetHPPercentage() end) end
    -- both bars dropping to 0 in one read is the fight being torn down (story
    -- fights after the K.O. was already said), not a double K.O.
    -- (<= 0: leaving Practice on 2026-11-12 still said both K.O. lines)
    local teardown = type(now[0]) == "number" and type(now[1]) == "number" and now[0] <= 0 and now[1] <= 0
        and (hp[0] or 0) > 0 and (hp[1] or 0) > 0
    for n = 0, 1 do
        local h = now[n]
        if type(h) == "number" and (hp[n] or h > 0) then
            local mine = n == Fight.me
            local was = hp[n] or h
            if teardown then
                -- silent
            elseif h <= 0 and was > 0 then
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

-- Tekken Ball: the ball in play is a visible PolarisBallActor. Searched a few
-- times after a fight starts (1, 3, 6 s); in a match that has one, again
-- every 3 s while it is missing (between rounds). Other matches stop looking.
local ball, ball_sent, ball_mode, ball_tries, next_ball = nil, false, false, 0, 0
local BALL_TRIES = { 1, 2, 3 }
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
    if t >= next_ball and not (UI.valid(ball) and safe(function() return ball.IsVisibleActor end)) then
        if ball_mode then
            next_ball = t + 3
            find_ball()
        elseif ball_tries < #BALL_TRIES then
            ball_tries = ball_tries + 1
            next_ball = t + BALL_TRIES[ball_tries] + 1
            find_ball()
            if ball then ball_mode = true end
        else
            next_ball = math.huge
        end
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

-- opponent throw start -> "T throw1/throw2/throw12" once per throw
Fight.throws = true
local throw_on = false
local tips = nil           -- Practice tips panel, looked up once per fight
local tip_wait = nil       -- os.clock() deadline while waiting for the tip

-- The panel can stay up between throws with dimmed icons (cmd_20d); the
-- icons light up (cmd_20) when the grab connects: that is the current throw.
local function tip_cue()
    local raw = UI.valid(tips) and safe(function() return tips:IsVisible() end)
        and UI.text_of(safe(function() return tips.TB_Command end))
    if not raw or not raw:find('cmd_%d+"') then return nil end
    local t = UI.clean(raw)
    if not t or not t:find("^Throw escape") then return nil end
    if t:find("1%+2") then return "throw12" end
    if t:find(" or ") or t:find(" 1$") then return "throw1" end
    if t:find(" 2$") then return "throw2" end
    return "throw1"
end

local function throws()
    local op = 1 - Fight.me
    local lb = L()
    local dmg = safe(function() return lb:GetFighterAttackingDamageValue(op) end)
    local is_throw = type(dmg) == "number" and math.floor(dmg / 16384) % 2 == 1
        and safe(function() return lb:IsFighterAttackingMot(op) end) == true
    if is_throw and not throw_on and Fight.throws then
        -- Practice: the tips panel tells the escape (menus.lua finds the
        -- Practice HUD when the pause menu is used)
        if not UI.valid(tips) then
            local M = package.loaded["menus"]
            local ps = M and M.practice_hud
            tips = UI.valid(ps) and safe(function() return ps.WBP_UI_Practice_TIPS end) or nil
        end
        local raw = UI.valid(tips) and safe(function() return tips:IsVisible() end)
            and UI.text_of(safe(function() return tips.TB_Command end))
        if raw and raw:find("^Throw escape") then      -- Throw Escape Training
            tip_wait = os.clock() + 0.45
        else
            Out.send("T\tthrow1")
            Out.log("throw")
        end
    end
    throw_on = is_throw
    if tip_wait then
        local cue = tip_cue()
        if cue or os.clock() > tip_wait then
            tip_wait = nil
            Out.send("T\t" .. (cue or "throw1"))
            Out.log("throw (practice tip) " .. tostring(cue))
        end
    end
end

-- Walls: PolarisStageWallActor boxes (a 100 cm cube mesh, scaled and
-- turned). Live walls have State 1 (unused placeholders sit at the origin
-- with State 0). Stages with floor or balcony breaks keep one set per floor
-- (FloorNo; Rebel Hangar: the upper floor's walls are FloorNo 0 from 6 m up,
-- the ground floor's FloorNo 1). Searched once per fight; the floor under the
-- player and the walls' State are checked twice a second, and the helper gets
-- the boxes only when the set changes. It casts the rays itself
-- (helper/walls.c), so a fight frame costs nothing extra here.
Fight.walls_on = true
local walls = nil          -- { {a=actor, cx, cy, hx, hy, c, s, zmin, zmax, floor, kind} }
local walls_key, next_walls, my_z = nil, 0, nil

local function find_walls()
    walls = {}
    for _, a in ipairs(FindAllOf("PolarisStageWallActor") or {}) do
        local w = UI.valid(a) and safe(function()
            local m = a.StaticMeshComponent
            local mn, mx = {}, {}
            m:GetLocalBounds(mn, mx)
            local l, r, sc = m:K2_GetComponentLocation(), m:K2_GetComponentRotation(), m:K2_GetComponentScale()
            local yaw = math.rad(r.Yaw)
            local c, s = math.cos(yaw), math.sin(yaw)
            local ox, oy = (mn.X + mx.X) / 2 * sc.X, (mn.Y + mx.Y) / 2 * sc.Y
            local name = a:GetFName():ToString()
            return { a = a, cx = l.X + ox * c - oy * s, cy = l.Y + ox * s + oy * c,
                     hx = math.abs((mx.X - mn.X) / 2 * sc.X), hy = math.abs((mx.Y - mn.Y) / 2 * sc.Y),
                     c = c, s = s, zmin = l.Z + mn.Z * sc.Z, zmax = l.Z + mx.Z * sc.Z,
                     floor = a.FloorNo, kind = name:find("Balcony") and 2 or name:find("Break") and 1 or 0 }
        end)
        if w and w.hx > 1 and w.hy > 1 then walls[#walls + 1] = w end
    end
    Out.log("walls: " .. #walls .. " wall actors")
end

local function send_walls(t)
    -- fighters stand at the origin for the first moments of a load
    if t < next_walls or not my_z then return end
    next_walls = t + 0.5
    if not walls then find_walls() end
    local live = {}
    for _, w in ipairs(walls) do
        if UI.valid(w.a) and safe(function() return w.a.State end) == 1 then live[#live + 1] = w end
    end
    -- the floor under the player: the set whose walls start highest but not
    -- above the feet (a standing fighter's origin is ~1 m up)
    local feet = (my_z or 0) - 100
    local floor, top = nil, -1e9
    for _, w in ipairs(live) do
        if w.zmin <= feet + 80 and w.zmin > top then top, floor = w.zmin, w.floor end
    end
    local parts, n = {}, 0
    if Fight.walls_on then
        for _, w in ipairs(live) do
            if w.floor == floor then
                n = n + 1
                parts[#parts + 1] = string.format("%.0f\t%.0f\t%.0f\t%.0f\t%.4f\t%.4f\t%d", w.cx, w.cy, w.hx, w.hy, w.c, w.s, w.kind)
            end
        end
    end
    local key = n .. ":" .. table.concat(parts, "|")
    if key == walls_key then return end
    walls_key = key
    Out.send(n > 0 and ("W\t" .. n .. "\t" .. table.concat(parts, "\t")) or "W0")
    Out.log("walls sent: " .. n .. " (floor " .. tostring(floor) .. ", feet " .. string.format("%.0f", feet) .. ")")
end

local function frame()
    local me, op = f[Fight.me], f[1 - Fight.me]
    local a = safe(function() return me:K2_GetActorLocation() end)
    local b = safe(function() return op:K2_GetActorLocation() end)
    if not a or not b then return end
    if a.X ~= 0 or a.Y ~= 0 then my_z = a.Z end
    if not UI.valid(pc) then
        if os.clock() < next_pc then return end
        next_pc = os.clock() + 2
        pc = FindFirstOf("PlayerController")
    end
    local yaw = safe(function() return pc.PlayerCameraManager:GetCameraRotation().Yaw end) or 0
    local r = math.rad(yaw)
    local c, s = math.cos(r), math.sin(r)
    -- positions go every frame (walls need them too); the beacon's on/off is
    -- a helper setting (F6)
    Out.send(string.format("F\t%.1f\t%.1f\t%.1f\t%.1f\t%.4f\t%.4f", a.X, a.Y, b.X, b.Y, c, s))
    send_walls(os.clock())
    ball_frame(a, c, s)
end

-- game thread. Nothing here searches every tick: the HUD tick says a fight
-- is on, fighters are looked up when it starts (and at most every 2 s while
-- they are missing).
-- Attack height sounds: the helper reads the fighters' moves from the game's
-- fight data itself (helper/attack.c); the mod only says whom to watch, and
-- stops it outside fights and while a menu is open.
-- Shift+F2 cycles whose attacks are heard; kept in attack_mode.txt.
local ATTACK_MODES = { "opponent", "own", "both", "off" }
local ATTACK_BITS = { opponent = 1, own = 2, both = 3, off = 0 }
local ATTACK_SAY = { opponent = "Attack sounds: opponent's attacks", own = "Attack sounds: your attacks",
                     both = "Attack sounds: both fighters", off = "Attack sounds off" }
Fight.attack_mode = "opponent"
local function attack_file() return Fight.dir and (Fight.dir .. "\\attack_mode.txt") end
local atk_sent = nil
local function attack_set(cmd)
    if cmd ~= atk_sent then atk_sent = cmd; Out.send(cmd) end
end

-- Actors die with their level. UI.valid on a freed actor is not safe: UE4SS
-- reads the object's own memory, and once the game has released it that is
-- an access violation. Two crashes on 2026-11-13 (both while Ranked standby
-- practice loaded a new stage after the previous fight's HUD went down)
-- were the old fighters / PlayerController being checked. So every actor
-- kept for a fight is dropped the moment that fight's HUD goes, and looked up
-- again for the next one.
local function drop_actors()
    f[0], f[1], pc, ball = nil, nil, nil, nil
    next_find, next_pc = 0, 0
end

local function stop()
    attack_set("A0")
    if active then
        active = false
        -- drop the Practice HUD too: a later match must not use a widget
        -- from a screen that is gone
        tips, tip_wait = nil, nil
        local M = package.loaded["menus"]; if M then M.practice_hud = nil end
        Out.send("F0"); Out.send("BL0")
        walls, walls_key, next_walls, my_z = nil, nil, 0, nil
        Out.send("W0")
    end
end

-- Widgets kept from a screen that is torn down must never be touched again:
-- a pause menu opened during a story movie, then polled by any_menu() after
-- Skip Movie loaded the fight, closed the game silently (2026-11-11, same as
-- the challenge rows on 2026-10-29). So everything kept is dropped whenever
-- the fight HUD comes or goes; the hooks hand the widgets over again.
-- Story fights put the fight HUD up during the intro scenes, seconds before
-- the round (Chapter 5: HUD at 23:51:20, IsBattleMain at 23:51:22.8 with the
-- first real attack). In story mode the beacon, attack and throw cues wait
-- for IsBattleMain (no player id, so safe while a fight loads; the library
-- is only reached once both fighters exist). Other modes start with the HUD.
local in_round, next_round_check, story_mode = false, 0, nil
local function round_on(t)
    if t < next_round_check then return in_round end
    next_round_check = t + 0.1
    if story_mode == nil then story_mode = safe(function() return L():IsStoryMode() end) == true end
    in_round = not story_mode or safe(function() return L():IsBattleMain() end) == true
    return in_round
end

local hud_was_up = false
local function forget_widgets()
    menus, hud_w = {}, nil
    local M = package.loaded["menus"]
    if M and M.forget_widgets then M.forget_widgets() end
end

function Fight.tick()
    local t = os.clock()
    local up = hud_up()
    if up ~= hud_was_up then hud_was_up = up; forget_widgets(); drop_actors(); story_mode, next_round_check = nil, 0 end
    if not up then stop() return end
    if refind then refind = false; f[0], f[1], next_find = nil, nil, 0 end
    if not ok_fighters() then
        stop()
        if t < next_find then return end
        next_find = t + 2.0
        find_fighters()
        if not ok_fighters() then return end
    end
    if t >= next_menu_check then
        next_menu_check = t + 0.3
        menu_open = any_menu()
    end
    if not active then
        active = true
        ball, ball_mode, ball_tries, next_ball = nil, false, 0, t + 1
        start()
    end
    if not side_known and side_tries < 20 and t >= next_side and lib_safe() then
        side_tries, next_side = side_tries + 1, t + 0.5
        side_known = resolve_side()
    end
    if t >= next_hp then next_hp = t + 0.2; health() end
    local quiet = menu_open or not round_on(t)
    if not quiet and lib_safe() then throws() end
    local bits = ATTACK_BITS[Fight.attack_mode] or 0
    attack_set((bits > 0 and not quiet) and ("A\t" .. Fight.me .. "\t" .. bits) or "A0")
    if quiet then Out.send("F0"); Out.send("BL0"); ball_sent = false return end
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
    if Fight.walls_on then Out.send("WS") end    -- the helper adds the walls
end

function Fight.toggle_beacon()
    Fight.beacon = not Fight.beacon
    Out.send("C\tbeacon\t" .. (Fight.beacon and 1 or 0))
    Out.say(Fight.beacon and "Opponent beacon on" or "Opponent beacon off", true)
end

-- Ctrl+F6: wall sounds
function Fight.toggle_walls()
    Fight.walls_on = not Fight.walls_on
    walls_key, next_walls = nil, 0
    Out.send("C\twalls\t" .. (Fight.walls_on and 1 or 0))
    Out.say(Fight.walls_on and "Wall sounds on" or "Wall sounds off", true)
end

function Fight.toggle_throws()
    Fight.throws = not Fight.throws
    Out.say(Fight.throws and "Throw break sounds on" or "Throw break sounds off", true)
end

function Fight.load_attack_mode()
    local f = attack_file() and io.open(attack_file(), "r")
    if not f then return end
    local m = (f:read("l") or ""):match("^%s*(%a+)")
    f:close()
    if m and ATTACK_BITS[m] then Fight.attack_mode = m end
end

function Fight.toggle_attacks()
    local i = 1
    for k, v in ipairs(ATTACK_MODES) do if v == Fight.attack_mode then i = k end end
    Fight.attack_mode = ATTACK_MODES[i % #ATTACK_MODES + 1]
    if Fight.attack_mode == "off" then attack_set("A0") end
    local f = attack_file() and io.open(attack_file(), "w")
    if f then f:write(Fight.attack_mode, "\n"); f:close() end
    Out.say(ATTACK_SAY[Fight.attack_mode], true)
end

-- Ctrl+F2: hear each attack sound with its name
function Fight.attack_demo() Out.send("T\tatk_demo") end

function Fight.toggle_ball()
    Fight.ball_cue = not Fight.ball_cue
    Out.say(Fight.ball_cue and "Ball sound on" or "Ball sound off", true)
end

return Fight
