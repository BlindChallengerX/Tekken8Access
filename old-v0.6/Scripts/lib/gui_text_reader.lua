--[[
  lib/gui_text_reader.lua  -- port of SF6Access GuiTextReader to UE5 UMG
  ----------------------------------------------------------------------------
  SF6 walks via.gui.Control trees with getChildren and reads via.gui.Text.
  The UMG equivalent: walk a UWidget tree via GetChildrenCount/GetChildAt and
  read UTextBlock / URichTextBlock. Used by:
    * read_focused  (read the text inside the highlighted item subtree)
    * read_screen   (read every visible text block on screen)
    * the dumper    (label every text block with its owning class)

  Everything is pcall-guarded because UMG calls throw on the wrong widget type.
]]

local GTR = {}

local MAX_DEPTH = 12
local MAX_TEXTS = 300

local function safe(fn, ...)
    local ok, a = pcall(fn, ...)
    if ok then return a end
    return nil
end

local function is_valid(o)
    return o ~= nil and safe(function() return o:IsValid() end) == true
end

local function class_name(o)
    return safe(function() return o:GetClass():GetFName():ToString() end) or "?"
end

-- strip UMG rich-text markup: <img id="x"/>, <Style>..</>, etc. Keep inner text.
local function strip_tags(s)
    if not s then return s end
    s = s:gsub("<[^>]*>", " ")
    s = s:gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function widget_text(w)
    local ft = safe(function() return w:GetText() end)
    if ft == nil then return nil end
    local s = safe(function() return ft:ToString() end)
    if type(s) ~= "string" then
        if type(ft) == "string" then s = ft else return nil end
    end
    s = strip_tags(s)
    if s == "" then return nil end
    return s
end

local function raw_text(w) -- unstripped, reveals inline icon tags for the dumper
    local ft = safe(function() return w:GetText() end)
    if ft == nil then return nil end
    local s = safe(function() return ft:ToString() end)
    if type(s) ~= "string" then return nil end
    return s
end

local function is_visible(w)
    local v = safe(function() return w:IsVisible() end)
    if v ~= nil then return v == true end
    return true -- unknown -> assume visible rather than stay silent
end

-- Try every way a UMG widget exposes children, INCLUDING a UserWidget's
-- internal WidgetTree (Tekken's menu rows are UserWidgets whose label lives
-- inside their WidgetTree, not as a direct panel child -- without this they
-- read as "(no text)").
local function get_children(w)
    local kids = {}
    -- UserWidget -> descend into its WidgetTree root
    local wt = safe(function() return w.WidgetTree end)
    if wt then
        local root = safe(function() return wt.RootWidget end)
        if not root then root = safe(function() return wt:GetRootWidget() end) end
        if root then kids[#kids + 1] = root end
    end
    local n = safe(function() return w:GetChildrenCount() end)        -- UPanelWidget
    if type(n) == "number" and n > 0 then
        for i = 0, n - 1 do
            local c = safe(function() return w:GetChildAt(i) end)
            if c then kids[#kids + 1] = c end
        end
        return kids
    end
    local content = safe(function() return w:GetContent() end)        -- UContentWidget
    if content then kids[#kids + 1] = content end
    return kids
end

-- Recursively collect text under `w`. results = array of {text, raw, cls}.
local function walk(w, depth, results, visible_only, stop_at_first)
    if not is_valid(w) or depth > MAX_DEPTH or #results >= MAX_TEXTS then return end
    if visible_only and not is_visible(w) then return end

    local t = widget_text(w)
    if t then
        results[#results + 1] = { text = t, raw = raw_text(w), cls = class_name(w) }
        if stop_at_first then return end
    end
    for _, c in ipairs(get_children(w)) do
        walk(c, depth + 1, results, visible_only, stop_at_first)
        if stop_at_first and #results > 0 then return end
        if #results >= MAX_TEXTS then return end
    end
end

-- Public: all visible texts under a single widget subtree (a focused item).
function GTR.read_subtree(widget, visible_only)
    local results = {}
    if visible_only == nil then visible_only = true end
    pcall(function() walk(widget, 0, results, visible_only, false) end)
    return results
end

-- Public: first non-empty text under a widget (cheap probe).
function GTR.read_first(widget)
    local results = {}
    pcall(function() walk(widget, 0, results, true, true) end)
    return results[1] and results[1].text or nil
end

-- Public: join a subtree's texts into one announcement string.
function GTR.read_joined(widget, sep)
    sep = sep or ", "
    local parts = {}
    for _, r in ipairs(GTR.read_subtree(widget, true)) do parts[#parts + 1] = r.text end
    if #parts == 0 then return nil end
    return table.concat(parts, sep)
end

-- Public: every visible text block on screen, via FindAllOf (no focus needed).
-- ignore = array of class names to skip.
function GTR.read_screen(ignore)
    local out, seen = {}, {}
    local ignoreset = {}
    for _, c in ipairs(ignore or {}) do ignoreset[c] = true end
    local function scan(short)
        local arr = safe(function() return FindAllOf(short) end)
        if type(arr) ~= "table" then return end
        for _, w in ipairs(arr) do
            if is_valid(w) and is_visible(w) then
                local cls = class_name(w)
                if not ignoreset[cls] then
                    local t = widget_text(w)
                    if t and not seen[t] then
                        seen[t] = true
                        out[#out + 1] = { text = t, cls = cls }
                    end
                end
            end
        end
    end
    scan("TextBlock"); scan("RichTextBlock")
    return out
end

GTR.class_name = class_name
GTR.is_valid = is_valid
GTR.is_visible = is_visible
GTR.widget_text = widget_text
GTR.raw_text = raw_text

return GTR
