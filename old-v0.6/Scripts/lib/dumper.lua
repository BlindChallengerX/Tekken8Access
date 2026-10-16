--[[
  lib/dumper.lua  (v0.5)
  ----------------------------------------------------------------------------
  F11 : dump the CURRENT screen, including a SELECTION PROBE for every menu
        widget -- its text plus the values of properties most likely to mark
        "this is the highlighted item" (bSelected, Index, opacity, etc.). The
        selected item will show a value different from its siblings, which is
        exactly what we need to wire menu reading correctly.
  F7  : toggle auto-dump (records each newly-seen widget class). Off by default.
  Output: %TEMP%\TekkenA11y\dump.txt
]]

local GTR = require("lib/gui_text_reader")
local SR  = require("lib/screen_reader")

local D = {}

-- Put the dump somewhere easy to find: the mod's own folder
--   ...\Win64\Mods\TekkenA11y\dump.txt   (right next to Scripts and speaker)
-- Fall back to %TEMP% only if that folder is read-only (some Program Files
-- installs are). We probe writability once and remember the result.
local function mod_dir()
    for entry in package.path:gmatch("[^;]+") do
        local d = entry:match("(.-[\\/]Mods[\\/]TekkenA11y)[\\/]Scripts")
        if d then return d end
    end
    return nil
end

local function temp_dir()
    return (os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp") .. "\\TekkenA11y"
end

local resolved_path = nil
local function dump_path()
    if resolved_path then return resolved_path end
    local md = mod_dir()
    if md then
        local p = md .. "\\dump.txt"
        local f = io.open(p, "a")          -- probe: can we write here?
        if f then f:close(); resolved_path = p; return p end
    end
    local t = temp_dir()                    -- fallback
    os.execute('if not exist "' .. t .. '" mkdir "' .. t .. '" >NUL 2>&1')
    resolved_path = t .. "\\dump.txt"
    return resolved_path
end

local function append(lines)
    local f = io.open(dump_path(), "a")
    if not f then return end
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end

local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end end

-- property names that commonly mark a selected/highlighted/focused item
local PROBE = {
    "bSelected", "bIsSelected", "IsSelected", "Selected",
    "bFocused", "bIsFocused", "Focused", "bHasFocus",
    "bHighlight", "bHighlighted", "Highlighted",
    "bActive", "bIsActive", "bCurrent", "bCursor", "bOn", "bChecked", "bEnable",
    "Index", "SelectedIndex", "CurrentIndex", "FocusIndex", "CursorIndex",
    "MenuIndex", "ItemIndex", "SlotIndex", "Number", "Value", "State",
}

-- read a probe property; return "name=value" only for booleans/numbers
local function probe_one(w, name)
    local ok, v = pcall(function() return w[name] end)
    if not ok then return nil end
    local t = type(v)
    if t == "boolean" then return name .. "=" .. tostring(v) end
    if t == "number" then return name .. "=" .. tostring(v) end
    return nil
end

local function probe_selection(w)
    local bits = {}
    for _, name in ipairs(PROBE) do
        local s = probe_one(w, name)
        if s then bits[#bits + 1] = s end
    end
    local op = safe(function() return w:GetRenderOpacity() end)
    if type(op) == "number" then bits[#bits + 1] = "opacity=" .. string.format("%.2f", op) end
    return table.concat(bits, " ")
end

local function dump_class_functions(widget, out)
    local cls = safe(function() return widget:GetClass() end)
    if not cls then return end
    out[#out + 1] = "      functions:"
    local listed = false
    pcall(function()
        cls:ForEachFunction(function(fn)
            local fname = safe(function() return fn:GetFName():ToString() end)
            if fname then out[#out + 1] = "         " .. fname; listed = true end
        end)
    end)
    if not listed then out[#out + 1] = "         (function list unavailable in this UE4SS build)" end
end

-- Enumerate EVERY property + its current value (this is how we find a clean
-- "SelectedIndex"-type signal that doesn't suffer the per-tab State problem).
local function dump_all_properties(widget, out)
    local cls = safe(function() return widget:GetClass() end)
    if not cls then return end
    out[#out + 1] = "      properties (name = value):"
    local count, listed = 0, false
    pcall(function()
        cls:ForEachProperty(function(prop)
            if count >= 60 then return end
            local pname = safe(function() return prop:GetFName():ToString() end)
            if not pname then return end
            local ok, v = pcall(function() return widget[pname] end)
            local vs
            if ok then
                local t = type(v)
                if t == "boolean" or t == "number" then vs = tostring(v)
                elseif t == "string" then vs = (#v <= 40 and v or (v:sub(1, 40) .. "...")) end
            end
            if vs ~= nil then
                out[#out + 1] = "         " .. pname .. " = " .. vs
                count = count + 1; listed = true
            end
        end)
    end)
    if not listed then out[#out + 1] = "         (property enumeration unavailable in this UE4SS build)" end
end

function D.dump()
    local lines = { "", "================ TekkenA11y DUMP ================" }

    local widgets = safe(function() return FindAllOf("UserWidget") end) or {}

    -- live classes + counts
    local counts = {}
    for _, w in ipairs(widgets) do
        if GTR.is_valid(w) then
            local c = GTR.class_name(w)
            counts[c] = (counts[c] or 0) + 1
        end
    end
    lines[#lines + 1] = "-- Live UserWidget classes (name x count) --"
    for c, n in pairs(counts) do lines[#lines + 1] = string.format("   %-44s x%d", c, n) end

    -- visible text
    lines[#lines + 1] = "-- Visible text blocks (class :: text) --"
    for _, b in ipairs(GTR.read_screen({})) do
        lines[#lines + 1] = "   " .. b.cls .. " :: " .. b.text
    end

    -- SELECTION PROBE: per menu-widget instance, text + likely "selected" props
    lines[#lines + 1] = "-- SELECTION PROBE (menu widgets: text | probed properties) --"
    local patterns = { "Menu", "List", "Button", "Select", "Tab", "Pause", "Dialog", "Item", "Slot", "CharSelect" }
    local function looks_menu(c)
        for _, p in ipairs(patterns) do if c:find(p, 1, true) then return true end end
        return false
    end
    -- group instances by class
    local by_class = {}
    for _, w in ipairs(widgets) do
        if GTR.is_valid(w) and GTR.is_visible(w) then
            local c = GTR.class_name(w)
            if looks_menu(c) then
                by_class[c] = by_class[c] or {}
                local t = by_class[c]
                if #t < 60 then t[#t + 1] = w end
            end
        end
    end
    local funcs_done = {}
    for c, list in pairs(by_class) do
        lines[#lines + 1] = "  [" .. c .. "]  (" .. #list .. " visible)"
        local fullpath = safe(function() return list[1]:GetClass():GetFullName() end)
        if fullpath then lines[#lines + 1] = "     class: " .. fullpath end
        for _, w in ipairs(list) do
            local txt = GTR.read_first(w) or "(no text)"
            local probe = probe_selection(w)
            lines[#lines + 1] = "     '" .. txt .. "'  ::  " .. (probe ~= "" and probe or "(no probed props)")
        end
        if not funcs_done[c] and list[1] then
            funcs_done[c] = true
            dump_class_functions(list[1], lines)
            -- full property dump for containers / selection trackers, where a
            -- clean SelectedIndex-type field is most likely to live
            if c:find("Menu_C", 1, true) or c:find("Table", 1, true) or c:find("Menu_List", 1, true)
               or c:find("CharSelect", 1, true) or c:find("SideSelect", 1, true)
               or c:find("Pause", 1, true) or c:find("Jukebox", 1, true) then
                dump_all_properties(list[1], lines)
            end
        end
    end

    lines[#lines + 1] = "================================================="
    append(lines)
    local p = dump_path()
    local in_mod = p:find("Mods", 1, true) ~= nil
    SR.speak(in_mod and "Dump saved in the Tekken accessibility mod folder, as dump dot txt."
                     or "Dump saved in the temp folder, as dump dot txt.", true)
    print("[A11y] dump written to: " .. p)
end

-- auto-dump (opt-in, off by default)
D.auto_enabled = false
local seen = {}
function D.toggle_auto()
    D.auto_enabled = not D.auto_enabled
    SR.speak(D.auto_enabled and "Auto dump enabled" or "Auto dump disabled", true)
    if D.auto_enabled then append({ "", "==== AUTO-DUMP SESSION START ====" }) end
end
function D.auto_tick()
    if not D.auto_enabled then return end
    local widgets = safe(function() return FindAllOf("UserWidget") end) or {}
    for _, w in ipairs(widgets) do
        if GTR.is_valid(w) and GTR.is_visible(w) then
            local c = GTR.class_name(w)
            if not seen[c] then
                seen[c] = true
                local lines = { "[new widget] " .. c }
                local txt = GTR.read_joined(w, " | ")
                if txt then lines[#lines + 1] = "   text: " .. txt end
                append(lines)
            end
        end
    end
end

return D
