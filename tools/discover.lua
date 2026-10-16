-- Hook every loaded widget-blueprint function whose name looks like a
-- cursor/selection event; calls are logged into `ev` (read with evdump.lua).
ev = ev or {}
disc = disc or {}
local PAT = { "hover", "select", "focus", "active", "cursor", "highlight", "change", "index", "decide", "setstate", "^on", "update", "set", "open", "in$", "page", "tab" }
local SKIP = { tick = true, updateballoontime = true, updatescroll = true, updatetext = true }
local function want(n)
  local l = n:lower()
  if n:find("^Has") or n:find("^Get") or n:find("^Is") or n:find("^Can") then return false end  -- return values: hooking broke input
  if SKIP[l] or l:find("ubergraph") or l:find("delegatesignature") or l:find("bndevt") or l:find("k2node") then return false end
  for _, p in ipairs(PAT) do if l:find(p) then return true end end
  return false
end
local classes, seenc = {}, {}
for _, w in ipairs(FindAllOf("UserWidget") or {}) do
  local c = w:IsValid() and w:GetClass()
  while c and c:IsValid() do
    local fn = c:GetFullName()
    if not fn:find("^WidgetBlueprintGeneratedClass") then break end
    if not seenc[fn] then seenc[fn] = true; classes[#classes + 1] = c end
    c = c:GetSuperStruct()
  end
end
local added, total = 0, 0
for _, c in ipairs(classes) do
  local cname = c:GetFullName():match("%s(.+)$") or ""
  c:ForEachFunction(function(f)
    local fname = f:GetFName():ToString()
    total = total + 1
    if want(fname) then
      local path = cname .. ":" .. fname
      if not disc[path] then
        disc[path] = true
        local short = (cname:match("%.([^.]+)$") or cname) .. ":" .. fname
        local ok = pcall(RegisterHook, path, function(ctx)
          if #ev < 4000 then
            local n = "?"; pcall(function() n = ctx:get():GetFName():ToString():match("_(%d+)$") or "" end)
            ev[#ev + 1] = string.format("%.3f %s #%s", os.clock(), short, n)
          end
        end)
        if ok then added = added + 1 end
      end
    end
  end)
end
return #classes .. " classes, " .. total .. " functions, hooked " .. added
