--[[
  lib/pad.lua - button names for prompts.
  The game draws a keyboard key picture (kbd_NNN, NNN = scan code) when the
  keyboard was used last and a pad picture otherwise. Prompts are spoken with
  controller names either way: a keyboard key is turned back into the pad
  button it stands for under the default keyboard layout (KEY_TO_BTN, checked
  in game on the main menu guide bar), then named for the chosen pad style.
  Styles: "xbox" (default), "playstation", "keyboard" (the keys themselves).
  Shift+F11 cycles them; the choice is kept in Mods\TekkenA11y\pad.txt. The
  game's pad pictures are not used to guess the style: hidden widgets keep a
  PS5 default picture even with an Xbox pad.
  Pad pictures: rich text <img id="btn_LB_xsx"/> (Xbox letters + family) and
  story prompt textures T_UI_STE_BTN_PS5_SQUARE / _XSX_X.
]]
local Pad = {}
Pad.style = "xbox"
local file = nil

-- logical buttons -> names per style. Face buttons by position.
local NAMES = {
    xbox = { west = "X button", north = "Y button", south = "A button", east = "B button",
             l1 = "LB", r1 = "RB", l2 = "LT", r2 = "RT", l3 = "Left stick click", r3 = "Right stick click",
             start = "Menu button", select = "View button",
             up = "Up", down = "Down", left = "Left", right = "Right", ls = "Left stick", rs = "Right stick" },
    playstation = { west = "Square", north = "Triangle", south = "Cross", east = "Circle",
             l1 = "L1", r1 = "R1", l2 = "L2", r2 = "R2", l3 = "L3", r3 = "R3",
             start = "Options button", select = "Create button",
             up = "Up", down = "Down", left = "Left", right = "Right", ls = "Left stick", rs = "Right stick" },
}
-- Tekken buttons on a pad (default layout): 1 = west, 2 = north, 3 = south, 4 = east
local TEKKEN = { "west", "north", "south", "east" }

-- keyboard scan code (+128 for extended keys) -> logical button. Read off the
-- main menu guide bar with the keyboard and then the pad in use (2026-11-11).
local KEY_TO_BTN = {
    [17] = "up", [30] = "left", [31] = "down", [32] = "right",          -- W A S D
    [200] = "up", [208] = "down", [203] = "left", [205] = "right",      -- arrow keys
    [22] = "west", [23] = "north", [36] = "south", [37] = "east",       -- U I J K = 1 2 3 4 (X Y A B)
    [75] = "south",                                                     -- Numpad 4: use, like J
    [24] = "l1", [25] = "r1",                                           -- O P: tabs, pages
    [38] = "l2", [39] = "r2",                                           -- L ;: banner
    [46] = "l3", [49] = "r3",                                           -- C: Tekken Shop, N: hide UI / name tags
    [48] = "start",                                                     -- B: pause / Arcade Quest menu
}

-- pad picture names (T_UI_STE_BTN_PS5_SQUARE, _XSX_X ...) -> logical button
local PIC = {
    SQUARE = "west", TRIANGLE = "north", CROSS = "south", CIRCLE = "east",
    X = "west", Y = "north", A = "south", B = "east",
    L1 = "l1", R1 = "r1", L2 = "l2", R2 = "r2", L3 = "l3", R3 = "r3",
    LB = "l1", RB = "r1", LT = "l2", RT = "r2", LS = "ls", RS = "rs", L = "ls", R = "rs",
    LSB = "l3", RSB = "r3",
    UP = "up", DOWN = "down", LEFT = "left", RIGHT = "right",
    OPTIONS = "start", MENU = "start", START = "start", VIEW = "select", SHARE = "select", CREATE = "select",
}

local function names() return NAMES[Pad.style] or NAMES.xbox end

-- name of a logical button in the current pad style (keyboard style: xbox names)
function Pad.name(logical) return names()[logical] end

-- Tekken button 1-4
function Pad.tekken(n) return names()[TEKKEN[n]] or tostring(n) end

-- spoken name for a keyboard key picture, or nil to say the key itself
function Pad.key(scancode)
    if Pad.style == "keyboard" then return nil end
    local l = KEY_TO_BTN[scancode]
    return l and names()[l]
end

-- spoken name for a pad picture suffix ("PS5_SQUARE", "XSX_RB", "SQUARE")
function Pad.picture(suffix)
    if not suffix then return nil end
    local function known(k) return PIC[k] or PIC[(k:gsub("^RS_", ""))] end
    local family, key = suffix:match("^(%u+%d?)_(.+)$")
    if not family or not known(key) then family, key = nil, suffix end
    local l = known(key)
    if not l then return nil end
    local nm = (Pad.style == "keyboard" and (family and family:find("^PS") and NAMES.playstation or NAMES.xbox) or names())[l]
    local dir = key:match("^RS_(%u+)$")
    if dir then nm = "Right stick " .. dir:lower() end
    return nm
end

function Pad.load(dir)
    file = dir and (dir .. "\\pad.txt")
    local f = file and io.open(file, "r")
    if not f then return end
    local s = (f:read("l") or ""):match("^%s*(%a+)")
    f:close()
    if s and (NAMES[s] or s == "keyboard") then Pad.style = s end
end

local ORDER = { "xbox", "playstation", "keyboard" }
local SAY = { xbox = "Xbox button names", playstation = "PlayStation button names", keyboard = "Keyboard key names" }
function Pad.cycle()
    local i = 1
    for k, v in ipairs(ORDER) do if v == Pad.style then i = k end end
    Pad.style = ORDER[i % #ORDER + 1]
    local f = file and io.open(file, "w")
    if f then f:write(Pad.style, "\n"); f:close() end
    return SAY[Pad.style]
end

return Pad
