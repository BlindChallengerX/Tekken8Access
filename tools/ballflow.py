"""Main menu -> Tekken Ball, Player vs CPU, through side, fighters, difficulty,
ball and damage select into the match, with the keys the select screens need."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import t8


def until(s, n=40):
    for _ in range(n):
        if s in t8.visible():
            return True
        time.sleep(1)
    return False


time.sleep(2)
t8.to_row("Tekken Ball")
t8.press("enter", after=1.5)
t8.press("down", after=0.5)          # Player vs CPU
t8.press("enter", after=1)
print("side", until("SideSelect"))
time.sleep(1.5); t8.press("enter", after=1)
print("chars", until("CharSelect"))
time.sleep(2.5); t8.press("enter", after=2.5)      # my fighter
t8.press("enter", after=1)                          # CPU fighter
print("difficulty", until("DifficultySelect"))
time.sleep(1); t8.press("up", after=0.6); t8.press("down", after=0.6); t8.press("enter", after=1.5)
print("ball", until("TB_BallSlot"))
time.sleep(1); t8.press("right", after=0.8); t8.press("left", after=0.8); t8.press("enter", after=1.5)
print("damage", until("TB_DamageSet"))
time.sleep(1); t8.press("right", after=0.8); t8.press("left", after=0.8); t8.press("enter", after=1.5)
print("fight", until("HUD", 90))
time.sleep(6)
