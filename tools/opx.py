import t8, time, sys
HOV = '''local UI = require("lib/ui") local out = {}
for _, c in ipairs({%s}) do for _, w in ipairs(FindAllOf(c) or {}) do
  if w:IsValid() then local ok, pl = pcall(function() return w:IsAnimationPlaying(w.Anim_Hover) end)
  if ok and pl then out[#out+1] = UI.read(w) end end end end return table.concat(out, " | ")'''
def hovered(classes):
    return t8.lua(HOV % ",".join('"%s"' % c for c in classes)).replace("=> ", "").strip()
def goto_option(name):
    for _ in range(16):
        if hovered(["WBP_UI_OP_List_Button_C"]) == name: return True
        t8.press("down", after=0.35)
    return False
def events():
    r = t8.lua('local s = {} local seen = {} for _, e in ipairs(ev) do local k = e:match("^%S+ (%S+)") if k and not seen[k] then seen[k] = true s[#s+1] = k end end ev = {} return table.concat(s, " ")')
    return [e for e in r.replace("=> ", "").split() if "Guide" not in e and "InformationBar" not in e]
def explore(name, keys):
    if not goto_option(name): print("no row", name); return
    t8.press("enter", after=2.0)
    st = sorted(t8.state() or [])
    print("=" * 60); print(name, "| screen:", " ".join(st))
    print("  discover:", t8.lua(open("discover.lua").read(), 30))
    t8.lua("ev = {} return 1")
    for k in keys:
        m = t8.log_mark(); t8.press(k, after=0.9)
        said = " | ".join(x.split("SAY")[-1].strip() for x in t8.says_since(m))
        print("  ", k, "SAID:", said[:160]); print("      ev:", " ".join(events())[:400])
    t8.press("esc", after=1.5)
    print("  back:", " ".join(sorted(t8.state() or [])))
which = sys.argv[1:]
for nm in which:
    vals = nm in ("Game Option Settings", "Sound Settings")
    explore(nm, ["down", "down", "right", "left", "up", "up"] if vals else ["down", "down", "up", "up"])
