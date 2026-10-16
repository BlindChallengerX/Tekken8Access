"""Stability run: for N seconds press fight keys and the mod's keys, and check the
dev console answers and the game window responds. python soak.py [seconds]"""
import ctypes, os, random, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import t8

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 180
end = time.time() + secs
keys = ["up", "down", "f5", "left", "right", "u", "i", "j", "k", "b"]
fails = 0
i = 0
while time.time() < end:
    k = random.choice(keys)
    try:
        t8.press(k, hold=0.05, after=0.4)
        if k == "b":                      # close the practice menu again
            t8.press("b", hold=0.05, after=0.6)
    except RuntimeError as e:
        print("press failed", e); break
    i += 1
    if i % 5 == 0:
        r = t8.lua("return 'alive'", timeout=5)
        hung = subprocess.run(["powershell", "-NoProfile", "-Command",
                               "(Get-Process Polaris-Win64-Shipping).Responding"], capture_output=True, text=True).stdout.strip()
        print(f"{int(end - time.time()):4d}s left: lua={r.strip()} responding={hung}", flush=True)
        if "alive" not in r:
            fails += 1
            if fails >= 3:
                print("Lua stopped answering"); break
        else:
            fails = 0
print("done", i, "presses")
