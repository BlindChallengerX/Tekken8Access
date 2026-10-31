--[[
  lib/prof.lua - cost of the mod's game-thread work, to find what slows fights.
  Every hook callback and every frame() step is timed; during a fight a
  summary goes to the helper log every 5 s:
    prof gaps: frame gaps (battle HUD ticks) avg / max / count over 25 ms
    prof busy: the costliest names, total ms in the window / calls / worst ms
  os.clock() is wall time with ~1 ms steps here, so totals over many calls
  are what count, not single small readings.
]]
local Prof = {}
local stats = {}
local win_t = os.clock()
local gap_last, gap_n, gap_sum, gap_max, gap_slow = nil, 0, 0, 0, 0

function Prof.add(name, dt)
    local s = stats[name]
    if not s then s = { 0, 0, 0 }; stats[name] = s end
    s[1], s[2] = s[1] + dt, s[2] + 1
    if dt > s[3] then s[3] = dt end
end

-- once per game frame (the battle HUD's Tick)
function Prof.frame_gap()
    local t = os.clock()
    if gap_last then
        local g = t - gap_last
        gap_n, gap_sum = gap_n + 1, gap_sum + g
        if g > gap_max then gap_max = g end
        if g > 0.025 then gap_slow = gap_slow + 1 end
    end
    gap_last = t
end

function Prof.flush(log, fighting)
    local t = os.clock()
    if t - win_t < 5 then return end
    if fighting and gap_n > 0 then
        log(string.format("prof gaps: %d frames avg %.1f ms max %.0f ms, %d over 25 ms",
            gap_n, gap_sum / gap_n * 1000, gap_max * 1000, gap_slow))
        local list = {}
        for k, s in pairs(stats) do list[#list + 1] = { k, s } end
        table.sort(list, function(a, b) return a[2][1] > b[2][1] end)
        local parts = {}
        for i = 1, math.min(8, #list) do
            local k, s = list[i][1], list[i][2]
            parts[#parts + 1] = string.format("%s %.0f/%d/%.0f", k:match("[^.:/]+:[^:]+$") or k, s[1] * 1000, s[2], s[3] * 1000)
        end
        log("prof busy (ms total/calls/worst ms): " .. table.concat(parts, ", "))
    end
    stats, win_t = {}, t
    gap_last, gap_n, gap_sum, gap_max, gap_slow = nil, 0, 0, 0, 0
end

return Prof
