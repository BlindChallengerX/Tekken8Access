"""Press keys and report what the helper spoke after each, with the delay from
key-down to the SAY log line.  python lat.py down down up enter ..."""
import datetime, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import t8

LOG = t8.HELPER_LOG


def log_lines():
    with open(LOG, encoding="utf-8", errors="replace") as f:
        return f.readlines()


def ms(ts):
    h, m, s = ts.split(":")
    return (int(h) * 3600 + int(m) * 60 + float(s)) * 1000


for k in sys.argv[1:]:
    if k.startswith("wait"):
        time.sleep(float(k[4:] or 1)); continue
    n0 = len(log_lines())
    t8.focus()
    now = datetime.datetime.now()
    t_key = (now.hour * 3600 + now.minute * 60 + now.second + now.microsecond / 1e6) * 1000
    t8._send(k, False); time.sleep(0.06); t8._send(k, True)
    time.sleep(0.9)
    new = [l.rstrip() for l in log_lines()[n0:] if " SAY" in l]
    if not new:
        print(f"{k:6} -> (nothing)")
    for l in new:
        ts, rest = l.split(" ", 1)
        print(f"{k:6} +{ms(ts) - t_key:5.0f} ms  {rest}")
