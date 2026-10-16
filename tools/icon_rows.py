"""Move the move-list cursor to given item rows and save a screenshot of each."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import t8

out = sys.argv[1]
targets = [int(x) for x in sys.argv[2:]]
Q = "return FindFirstOf('WBP_UI_CommandList_C').cursor_index"
for tgt in targets:
    for _ in range(300):
        cur = int(t8.lua(Q).replace("=> ", "").strip())
        if cur == tgt:
            break
        t8.press("down" if cur < tgt else "up", hold=0.05, after=0.12)
    time.sleep(0.4)
    t8.shot(os.path.join(out, f"row{tgt}.png"))
    print(tgt, cur, flush=True)
