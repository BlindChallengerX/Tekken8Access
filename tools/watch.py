"""Watch the game for N seconds: print screen changes, speech and SPY log lines.
   python watch.py secs [key ...]   keys are pressed first"""
import sys, time, t8
def new_lines(mark):
    try:
        with open(t8.HELPER_LOG, "rb") as f:
            f.seek(mark); data = f.read().decode("utf-8", "replace")
    except OSError:
        return [], mark
    return [l for l in data.splitlines() if " SAY" in l or "SPY" in l or "error" in l], mark + len(data.encode("utf-8", "replace"))
def watch(secs, stop=None):
    mark = t8.log_mark(); last = None; end = time.time() + secs
    while time.time() < end:
        st = t8.state()
        key = " ".join(sorted(st)) if st is not None else "(no console)"
        if key != last:
            last = key; print(time.strftime("%H:%M:%S"), "SCREEN", key, flush=True)
        ls, mark = new_lines(mark)
        for l in ls: print(l, flush=True)
        if stop and any(stop in l for l in ls): return True
        time.sleep(0.4)
if __name__ == "__main__":
    t8.keys(sys.argv[2:])
    watch(float(sys.argv[1]))
