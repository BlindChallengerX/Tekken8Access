"""press keys, report what was said and key-to-speech delay. python lat2.py key key ..."""
import t8, time, sys, datetime
def sayings_after(t0, wait=1.0):
    time.sleep(wait)
    out = []
    for l in open(t8.HELPER_LOG, encoding="utf-8", errors="replace").read().splitlines()[-40:]:
        if " SAY" not in l: continue
        hh, mm, rest = l[:12].split(":"); ss = float(rest)
        d = datetime.datetime.now().replace(hour=int(hh), minute=int(mm), second=int(ss), microsecond=int((ss % 1) * 1e6))
        ts = d.timestamp()
        if ts >= t0 - 0.01: out.append((int((ts - t0) * 1000), l[13:]))
    return out
for k in sys.argv[1:]:
    t8.focus()
    t0 = time.time()
    t8._send(k, False); time.sleep(0.05); t8._send(k, True)
    s = sayings_after(t0)
    print(k.ljust(6), " | ".join("%d ms %s" % x for x in s)[:220] or "(nothing)")
