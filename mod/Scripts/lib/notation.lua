--[[
  lib/notation.lua - Tekken 8 command icons to standard notation text.
  The game writes moves as rich text: <img id="cmd_07"/><img id="cmd_22"/>.
  Icon ids (worked out from Yoshimitsu's list against the screen, NOTES.md):
    01 / 02   bracket pair drawn around some inputs
    03-10     tap  db d df b f ub u uf
    11-18     hold DB D DF B F UB U UF
    19        neutral (assumed: the slot before the buttons)
    20-34     buttons, 19 + bitmask (1=1, 2=2, 3=4, 4=8): 20 = 1, 22 = 1+2, 27 = 4, 31 = 3+4
    35        star
    38        next part of a sequence (green triangle)
  Output reads like written notation: "f+1+2", "b+2, 2", "d+1, then 3".
]]
local N = {}

local DIRS = { [3] = "d/b", [4] = "d", [5] = "d/f", [6] = "b", [7] = "f", [8] = "u/b", [9] = "u", [10] = "u/f",
               [11] = "hold d/b", [12] = "hold d", [13] = "hold d/f", [14] = "hold b", [15] = "hold f",
               [16] = "hold u/b", [17] = "hold u", [18] = "hold u/f", [19] = "n" }

local function buttons(mask)
    local t = {}
    for b = 1, 4 do if mask & (1 << (b - 1)) ~= 0 then t[#t + 1] = tostring(b) end end
    return table.concat(t, "+")
end

-- one icon -> { kind = "dir"/"btn"/"word", text = ... }
local function icon(id)
    local n = tonumber(id:match("^cmd_(%d+)$"))
    if n then
        if DIRS[n] then return { kind = "dir", text = DIRS[n] } end
        if n >= 20 and n <= 34 then return { kind = "btn", text = buttons(n - 19) } end
        if n == 1 then return { kind = "word", text = "bracket" } end
        if n == 2 then return { kind = "word", text = "end bracket" } end
        if n == 35 then return { kind = "word", text = "star" } end
        if n == 38 then return { kind = "word", text = "then" } end
        return { kind = "word", text = "icon " .. n }
    end
    -- keyboard key pictures (shortcut keys, Special Style); which key is not known yet
    if id:find("^kbd_") then return { kind = "word", text = "keyboard key" } end
    return { kind = "word", text = (id:gsub("_", " ")) }
end

-- Turn a rich text string into speakable notation.
function N.convert(s)
    if not s or s == "" then return s end
    local out, prev = {}, nil
    local pos = 1
    local function emit_text(t)
        t = t:gsub("<[^>]*>", "")        -- other markup (style tags)
        if t:match("%S") then
            out[#out + 1] = t
            prev = "text"
        elseif t ~= "" and (prev == "dir" or prev == "btn") then
            prev = "space"                -- a gap between icon groups
        end
    end
    while true do
        local a, b, id = s:find('<img id="([^"]+)"%s*/>', pos)
        if not a then emit_text(s:sub(pos)); break end
        emit_text(s:sub(pos, a - 1))
        local ic = icon(id)
        if ic.kind == "btn" and prev == "dir" then
            out[#out] = out[#out] .. "+" .. ic.text
        elseif ic.kind == "dir" or ic.kind == "btn" then
            if prev == "dir" or prev == "btn" or prev == "space" then out[#out] = out[#out] .. "," end
            out[#out + 1] = ic.text
        else
            if (prev == "dir" or prev == "btn" or prev == "space") and ic.text == "then" then out[#out] = out[#out] .. "," end
            out[#out + 1] = ic.text
        end
        prev = ic.kind
        pos = b + 1
    end
    local r = table.concat(out, " ")
    r = r:gsub("%s+", " "):gsub(" ,", ","):gsub("%s+$", ""):gsub("^%s+", "")
    return r
end

return N
