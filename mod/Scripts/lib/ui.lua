--[[
  lib/ui.lua - reading text out of UMG widgets.
  Tekken rows usually carry the same label twice (TB_xxx_ON for the highlighted
  look, TB_xxx_OFF for the normal look) and sometimes hidden placeholder
  fields. read() keeps visible texts, prefers ON over OFF and drops repeats.
]]
local N = require("lib/notation")
local UI = {}

local function safe(fn) local ok, v = pcall(fn); if ok then return v end end
UI.safe = safe

function UI.valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end

-- visible here means the widget and its parents are not collapsed/hidden
local function vis(w)
    local v = safe(function() return w:GetVisibility() end)
    return v == nil or v == 0 or v == 3 or v == 4
end

function UI.name(o) return safe(function() return o:GetFName():ToString() end) or "" end

function UI.text_of(w)
    local s = safe(function() return w:GetText():ToString() end)
    if type(s) ~= "string" or s == "" then return nil end
    return s
end

-- speakable form of a raw text: command icons to notation, markup dropped
function UI.clean(s)
    if not s then return nil end
    if s:find("<img") then s = N.convert(s) end
    s = s:gsub("<[^>]*>", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%( ", "("):gsub(" %)", ")"):gsub("\226\128\139", "")   -- stray zero-width space in some names
    if s == "" or s:find("^err%(") then return nil end
    return s
end

local function children(w)
    local kids = {}
    local wt = safe(function() return w.WidgetTree end)
    if wt and UI.valid(wt) then
        local r = safe(function() return wt.RootWidget end)
        if r then kids[#kids + 1] = r end
    end
    local n = safe(function() return w:GetChildrenCount() end)
    if type(n) == "number" and n > 0 then
        for i = 0, n - 1 do
            local c = safe(function() return w:GetChildAt(i) end)
            if c then kids[#kids + 1] = c end
        end
    else
        local c = safe(function() return w:GetContent() end)
        if c then kids[#kids + 1] = c end
    end
    return kids
end

-- all visible texts under w as { {name=, text=} } in tree order
function UI.collect(w, out, depth)
    out = out or {}
    depth = depth or 0
    if depth > 16 or #out > 60 or not UI.valid(w) or not vis(w) then return out end
    local t = UI.text_of(w)
    if t then out[#out + 1] = { name = UI.name(w), text = t } end
    for _, c in ipairs(children(w)) do UI.collect(c, out, depth + 1) end
    return out
end

-- label of a row: ON texts if there are any, else everything; no repeats
function UI.read(w, skip)
    local all = UI.collect(w)
    local has_on = false
    for _, e in ipairs(all) do if e.name:find("_ON") or e.name:find("_On$") then has_on = true break end end
    local parts, seen = {}, {}
    for _, e in ipairs(all) do
        local n = e.name
        local drop = (has_on and (n:find("_OFF") or n:find("_Off$"))) or (skip and skip(n, e.text))
        if not drop then
            local c = UI.clean(e.text)
            if c and not seen[c] then seen[c] = true; parts[#parts + 1] = c end
        end
    end
    return table.concat(parts, ", ")
end

-- localised string for a text id (move list data, etc.)
local lib
function UI.loc(id)
    if not id or id == "" then return "" end
    if not UI.valid(lib) then lib = StaticFindObject("/Script/Polaris.Default__PolarisUMGFunctionLibrary") end
    return safe(function() return lib:GetLocalizeText(id):ToString() end) or ""
end

-- text of a hook argument (FText, FString, text id); nil for anything else
function UI.arg_text(p)
    local v = safe(function() return p:get() end)
    if type(v) == "string" then
    elseif type(v) == "userdata" then v = safe(function() return v:ToString() end)
    else return nil end
    if type(v) ~= "string" or v == "" then return nil end
    if v:find("^TEXT_") then v = UI.loc(v) end
    return UI.clean(v)
end

-- all string/text fields of a data object or struct (text ids localised),
-- for list items and infos that keep their label as data
function UI.fields_text(obj, cls)
    local parts, seen = {}, {}
    cls = cls or safe(function() return obj:GetClass() end)
    if not cls then return "" end
    safe(function()
        cls:ForEachProperty(function(p)
            local kind = p:GetClass():GetFName():ToString()
            if kind == "StrProperty" or kind == "TextProperty" or kind == "NameProperty" then
                local n = p:GetFName():ToString()
                local s = safe(function() return obj[n]:ToString() end)
                if s and s ~= "" then
                    if s:find("^TEXT_") then s = UI.loc(s) end
                    s = UI.clean(s)
                    if s and not seen[s] then seen[s] = true; parts[#parts + 1] = s end
                end
            end
        end)
    end)
    return table.concat(parts, ", ")
end

-- a user widget is on screen
function UI.shown(w)
    return UI.valid(w) and safe(function() return w:IsInViewport() and w:IsVisible() end) == true
end

return UI
