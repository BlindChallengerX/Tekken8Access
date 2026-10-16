--[[
  hooks/subtitles.lua
  ----------------------------------------------------------------------------
  Auto-reads story / cutscene subtitles. Mirrors SF6Access PollComicSubtitles:
  poll the configured subtitle widget(s), speak when the line changes. Toggle
  with F10. SF6 reads subtitles raw and converts inline icons -- we keep the
  hook for notation here for cinematic input prompts if Tekken uses them.
]]

local Config   = require("config")
local SR       = require("lib/screen_reader")
local GTR      = require("lib/gui_text_reader")
local Notation = require("lib/notation")

local Subs = {}
Subs.enabled = false
local last_line = nil

function Subs.toggle()
    Subs.enabled = not Subs.enabled
    SR.speak(Subs.enabled and "Subtitle reading on" or "Subtitle reading off", true)
end

local function safe(fn, ...) local ok, a = pcall(fn, ...); if ok then return a end end

function Subs.poll()
    if not Subs.enabled then return end
    local classes = Config.tekken.subtitle_widget_classes or {}
    if #classes == 0 then return end

    for _, short in ipairs(classes) do
        local arr = safe(function() return FindAllOf(short) end)
        if type(arr) == "table" then
            for _, w in ipairs(arr) do
                if GTR.is_valid(w) and GTR.is_visible(w) then
                    local line = GTR.read_joined(w, " ")
                    if line and line ~= "" and line ~= last_line then
                        last_line = line
                        -- subtitles interrupt the previous line (latest wins),
                        -- matching how a sighted player only sees the newest
                        SR.speak(line, true)
                        return
                    end
                end
            end
        end
    end
end

return Subs
