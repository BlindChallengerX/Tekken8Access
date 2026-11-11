"""Mash attacks while watching for SPY lines / speech. python fightwatch.py secs [shotdir] [stopword]
Stops mashing for 6 s when a STE (button prompt) line shows, and takes screenshots."""
import sys, time, random, t8, watch
secs = float(sys.argv[1]); shotdir = sys.argv[2] if len(sys.argv) > 2 else None
stopword = sys.argv[3] if len(sys.argv) > 3 else None
mark = t8.log_mark(); end = time.time() + secs; last = None; n = 0; quiet_until = 0; tcheck = 0
while time.time() < end:
    ls, mark = watch.new_lines(mark)
    for l in ls: print(l, flush=True)
    if any("Story_STE" in l for l in ls) and time.time() > quiet_until:
        quiet_until = time.time() + 6
        if shotdir:
            for i in range(3):
                n += 1; t8.shot(f"{shotdir}/ste{n}.png"); print("shot", n, flush=True); time.sleep(0.3)
    if stopword and any(stopword in l for l in ls): break
    if time.time() - tcheck > 3:
        tcheck = time.time()
        st = t8.state(); key = " ".join(sorted(st)) if st is not None else "(no console)"
        if key != last: last = key; print(time.strftime("%H:%M:%S"), "SCREEN", key, flush=True)
    if time.time() < quiet_until: time.sleep(0.1); continue
    r = random.random()
    if r < 0.25: t8.chord(["d", random.choice("uijk")], hold=0.06, after=0.08)
    elif r < 0.35: t8.press("d", hold=0.25, after=0.02)
    else: t8.press(random.choice("uijk"), hold=0.05, after=0.08)
