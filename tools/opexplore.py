import t8, time, sys, re
def lua(c): return t8.lua(c, 10)
def events():
    r = lua('local s = {} local seen = {} for _, e in ipairs(ev) do local k = e:match("^%S+ (%S+)") if k and not seen[k] then seen[k] = true s[#s+1] = k end end ev = {} return table.concat(s, " ")')
    return r.replace("=> ", "").split()
rows = int(sys.argv[1]); count = int(sys.argv[2])
for i in range(rows, rows + count):
    # go to the top, then down i
    for _ in range(14): t8.press("up", after=0.12)
    for _ in range(i): t8.press("down", after=0.25)
    time.sleep(0.5)
    name = t8.say(1).split("SAY")[-1]
    lua("ev = {} return 1")
    mark = t8.log_mark()
    t8.press("enter", after=2.0)
    st = t8.state()
    open_ev = events()
    seq = []
    for k in ["down", "down", "right", "left"]:
        m = t8.log_mark(); t8.press(k, after=0.9)
        seq.append((k, t8.says_since(m), events()))
    print("=" * 70); print("ROW", i, name.strip(), "| screen:", " ".join(sorted(st or [])))
    print("  open ev:", " ".join(e for e in open_ev if "Guide" not in e and "InformationBar" not in e)[:600])
    for k, s, e in seq:
        print("  ", k, "SAID:", " | ".join(x.split("SAY")[-1].strip() for x in s)[:200])
        print("      ev:", " ".join(x for x in e if "Guide" not in x and "InformationBar" not in x)[:500])
    t8.press("esc", after=1.5)
    if "OP_C" not in " ".join(t8.state() or []): t8.press("esc", after=1.5)
