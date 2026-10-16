--[[
  out.lua - everything the player hears goes through the helper process
  (speaker\TekkenA11yHelper.exe) over the named pipe \\.\pipe\TekkenA11y.
  A pipe write takes microseconds, so speech starts as soon as a hook fires.

  Out.say(text)        speak now, interrupting (cursor moves)
  Out.queue(text)      speak after whatever is speaking
  Out.help(text)       speak after the cursor rests ~350 ms (descriptions)
  Out.send(line)       raw command (beacon frames, tones, config)
]]
local Out = {}

local PIPE = "\\\\.\\pipe\\TekkenA11y"
local pipe, next_try = nil, 0

local function now() return os.clock() end

function Out.send(line)
    if not pipe then
        if now() < next_try then return false end
        next_try = now() + 0.5
        pipe = io.open(PIPE, "w")
        if not pipe then return false end
        pipe:setvbuf("no")
    end
    local ok = pcall(function()
        local r, e = pipe:write(line, "\n")
        if not r then error(e) end
    end)
    if not ok then
        pcall(function() pipe:close() end)
        pipe = nil
        return false
    end
    return true
end

local function clean(t)
    if type(t) ~= "string" then return nil end
    t = t:gsub("[\t\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then return nil end
    return t
end

local last_text, last_t = nil, -1
local help_text, help_at = nil, 0
Out.enabled = true
Out.last = ""

function Out.say(text, force)
    text = clean(text)
    if not text or not Out.enabled then return end
    local t = now()
    if not force and text == last_text and t - last_t < 0.25 then return end
    help_text = nil
    -- a second line from the same key press (tab name, then its first row)
    -- follows the first instead of cutting it off
    if not force and t - last_t < 0.12 then
        last_text, last_t = text, t
        Out.last = Out.last .. ". " .. text
        Out.send("S0\t" .. text)
        return
    end
    last_text, last_t = text, t
    Out.last = text
    Out.send("S1\t" .. text)
end

function Out.queue(text)
    text = clean(text)
    if not text or not Out.enabled then return end
    Out.last = Out.last .. " " .. text
    Out.send("S0\t" .. text)
end

function Out.help(text, delay)
    text = clean(text)
    if not text then help_text = nil return end
    help_text, help_at = text, now() + (delay or 0.35)
end

function Out.stop() help_text = nil; Out.send("X") end
function Out.log(text) Out.send("L\t" .. tostring(text):gsub("[\r\n\t]", " ")) end
function Out.tone(name) Out.send("T\t" .. name) end
function Out.config(key, value) Out.send("C\t" .. key .. "\t" .. tostring(value)) end

-- called from a 50 ms async loop
function Out.tick()
    if help_text and now() >= help_at then
        local t = help_text
        help_text = nil
        if Out.enabled and t ~= last_text then
            Out.last = Out.last .. " " .. t
            Out.send("S0\t" .. t)
        end
    end
end

return Out
