"""From the main menu into a Practice match: side, fighters, stage, waiting for
each screen. python flow.py [right]   (right = play from the right side)"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import t8


def until(s, n=40):
    for _ in range(n):
        if s in t8.visible():
            return True
        time.sleep(1)
    return False


right = len(sys.argv) > 1 and sys.argv[1] == "right"
time.sleep(2)
t8.to_row("Practice")
t8.press("enter", after=1)
print("side", until("SideSelect"))
time.sleep(1.5)
if right:
    t8.press("right", after=0.5)
t8.press("enter", after=1)
print("chars", until("CharSelect"))
time.sleep(2.5)
t8.press("enter", after=2.5)
t8.press("enter", after=1)
print("stage", until("StageSelect"))
time.sleep(3)
t8.press("right", after=0.8)
t8.press("enter", after=1)
print("fight", until("HUD", 60))
time.sleep(7)
