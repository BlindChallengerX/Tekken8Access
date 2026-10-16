-- Hook EVERY Blueprint function of live widget classes whose name contains
-- DISC_FILTER (set it in a command first), logging calls into `ev`.
ev = ev or {}
disc = disc or {}
local filter = DISC_FILTER or "JukeBox"
local SKIP = { tick = true }
local classes, seenc = {}, {}
for _, w in ipairs(FindAllOf("UserWidget") or {}) do
  local c = w:IsValid() and w:GetClass()
  while c and c:IsValid() do
    local fn = c:GetFullName()
    if not fn:find("^WidgetBlueprintGeneratedClass") then break end
    if not seenc[fn] and fn:find(filter) then seenc[fn] = true; classes[#classes + 1] = c end
    c = c:GetSuperStruct()
  end
end
local added = 0
for _, c in ipairs(classes) do
  local cname = c:GetFullName():match("%s(.+)$") or ""
  c:ForEachFunction(function(f)
    local fname = f:GetFName():ToString()
    local l = fname:lower()
    if SKIP[l] or l:find("ubergraph") or l:find("delegatesignature") then return end
    -- hooking functions that return a value (HasFinished..., Get..., Is...) broke the
    -- Jukebox: its input stayed disabled. Leave them alone.
    if fname:find("^Has") or fname:find("^Get") or fname:find("^Is") or fname:find("^Can") then return end
    local path = cname .. ":" .. fname
    if disc[path] then return end
    disc[path] = true
    local short = (cname:match("%.([^.]+)$") or cname) .. ":" .. fname
    if pcall(RegisterHook, path, function(ctx, ...)
      if #ev < 4000 then
        local a, args = {}, { ... }
        for i = 1, math.min(#args, 4) do
          local p = args[i]
          local ok, v = pcall(function() return p:get() end)
          if ok and type(v) ~= "userdata" then a[#a + 1] = tostring(v) end
        end
        ev[#ev + 1] = string.format("%.3f %s(%s)", os.clock(), short, table.concat(a, ","))
      end
    end) then added = added + 1 end
  end)
end
return #classes .. " classes, hooked " .. added
