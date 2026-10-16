--[[
  dev.lua - developer console, only loaded when Mods\TekkenA11y\dev.txt exists.
  tools\t8.py writes Lua to %TEMP%\TekkenA11y\cmd.lua; it runs on the game
  thread and its output (p(...) calls and the return value) lands in out.txt.
  Globals set by commands persist in Dev.env between calls.
]]
local Dev = {}
local base = (os.getenv("TEMP") or "C:\\Temp") .. "\\TekkenA11y"
local CMD, OUT = base .. "\\cmd.lua", base .. "\\out.txt"
os.execute('if not exist "' .. base .. '" mkdir "' .. base .. '" >NUL 2>&1')

Dev.env = setmetatable({}, { __index = _G })

local function write_out(text)
    local o = io.open(OUT .. ".tmp", "w")
    if not o then return end
    o:write(text); o:close()
    os.remove(OUT); os.rename(OUT .. ".tmp", OUT)
end

local function run(code)
    local buf = {}
    Dev.env.p = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        buf[#buf + 1] = table.concat(t, "\t")
    end
    local fn, err = load(code, "cmd", "t", Dev.env)
    local ok, res
    if fn then ok, res = pcall(fn) else ok, res = false, err end
    if not ok then buf[#buf + 1] = "ERROR: " .. tostring(res)
    elseif res ~= nil then buf[#buf + 1] = "=> " .. tostring(res) end
    write_out(table.concat(buf, "\n"))
end

LoopAsync(50, function()
    local f = io.open(CMD, "r")
    if not f then return false end
    local code = f:read("a"); f:close(); os.remove(CMD)
    if code:sub(1, 6) == "--async" then run(code)        -- off the game thread
    else ExecuteInGameThread(function() run(code) end) end
    return false
end)

print("[A11y] dev console on")
return Dev
