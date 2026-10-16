--[[
  lib/notation.lua  -- Tekken analog of SF6Access InputNameResolver
  ----------------------------------------------------------------------------
  Tekken movelists, command lists, and combo trials render moves as direction
  ARROWS + colored BUTTON squares with no text equivalent -- exactly the
  problem SF6's InputNameResolver solves for key-config glyphs. This turns
  Tekken notation tokens into spoken English.

  Two layers:
    1. TOKEN -> SPEECH dictionary (known, provided here).
    2. extracting the token sequence for a given move from the on-screen
       widget -- that mapping (icon/enum -> token) is per-game DISCOVERY; the
       dumper exposes the raw move command so we can fill resolve_glyph().
]]

local N = {}

-- Directions (Tekken uses arrows; lowercase = tap, UPPERCASE = hold) ---------
local DIRECTIONS = {
    ["u"]  = "up",            ["U"]  = "hold up",
    ["d"]  = "down",          ["D"]  = "hold down",
    ["f"]  = "forward",       ["F"]  = "hold forward",
    ["b"]  = "back",          ["B"]  = "hold back",
    ["df"] = "down-forward",  ["DF"] = "hold down-forward",
    ["db"] = "down-back",     ["DB"] = "hold down-back",
    ["uf"] = "up-forward",    ["UF"] = "hold up-forward",
    ["ub"] = "up-back",       ["UB"] = "hold up-back",
    ["n"]  = "neutral",
    ["qcf"] = "quarter circle forward",
    ["qcb"] = "quarter circle back",
    ["hcf"] = "half circle forward",
    ["hcb"] = "half circle back",
}

-- Buttons (Tekken standard four-button layout) ------------------------------
local BUTTONS = {
    ["1"] = "Left Punch",
    ["2"] = "Right Punch",
    ["3"] = "Left Kick",
    ["4"] = "Right Kick",
    ["1+2"] = "both punches",
    ["3+4"] = "both kicks",
    ["1+3"] = "Left Punch plus Left Kick",
    ["2+4"] = "Right Punch plus Right Kick",
    ["1+4"] = "Left Punch plus Right Kick",
    ["2+3"] = "Heat",                 -- default Heat engager input in Tekken 8
    ["1+2+3+4"] = "all four buttons",
}

-- States / stances / conditions ---------------------------------------------
local STATES = {
    ["WS"] = "while standing",
    ["FC"] = "full crouch",
    ["SS"] = "sidestep",
    ["SSL"] = "sidestep left",
    ["SSR"] = "sidestep right",
    ["WR"] = "while running",
    ["BT"] = "back turned",
    ["CH"] = "counter hit",
    ["iWS"] = "instant while standing",
    ["H."] = "heat",
}

-- Resolve a single token to speech (tries states, then buttons, then dirs).
function N.token(tok)
    if tok == nil or tok == "" then return nil end
    return STATES[tok] or BUTTONS[tok] or DIRECTIONS[tok] or DIRECTIONS[tok:lower()] or tok
end

-- Parse a Tekken-notation command string into spoken English.
-- Accepts forms like: "f,n,d,df+2"  /  "WS 4,4"  /  "qcf+2"  /  "b+1+2"
-- Separators: comma = then, space = then, '+' = simultaneous.
function N.speak_command(cmd)
    if type(cmd) ~= "string" or cmd == "" then return nil end
    local out = {}
    -- split into sequential steps on commas and spaces
    for step in cmd:gmatch("[^,%s]+") do
        -- a step may be "df+2" or "1+2": split the simultaneous parts on '+'
        -- but '+' inside a known button combo (1+2) should stay grouped.
        if BUTTONS[step] then
            out[#out + 1] = BUTTONS[step]
        elseif step:find("+", 1, true) then
            local parts = {}
            for p in step:gmatch("[^+]+") do parts[#parts + 1] = N.token(p) or p end
            out[#out + 1] = table.concat(parts, " plus ")
        else
            out[#out + 1] = N.token(step) or step
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, ", then ")
end

-- Placeholder for the discovery half: map a raw on-screen glyph/enum value
-- (as revealed by the dumper for a move command) to a notation token.
-- Fill GLYPHS once the dumper shows how Tekken encodes movelist inputs.
local GLYPHS = {
    -- [<raw enum/id from dump>] = "df",
    -- [<raw enum/id from dump>] = "2",
}
function N.resolve_glyph(raw)
    return GLYPHS[raw]
end

N.DIRECTIONS = DIRECTIONS
N.BUTTONS = BUTTONS
N.STATES = STATES
return N
