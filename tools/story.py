"""Story helpers. python story.py chapter N   (from a story fight/cutscene or the chapter list)"""
import sys, time, t8, watch
def to_chapter_select():
    if t8.has(t8.state(), "ChapterSelect"): return
    for _ in range(3):
        mark = t8.log_mark(); t8.press("b", after=1.2)
        if t8.says_since(mark): break
    for _ in range(8):
        mark = t8.log_mark(); t8.press("down", after=0.6); s = t8.says_since(mark)
        if s and s[-1].startswith("Chapter Select"): break
    else: raise t8.BotError("no Chapter Select row")
    t8.press("enter", after=1.5)
    for _ in range(4):
        mark = t8.log_mark(); t8.press("up", after=0.6); s = t8.says_since(mark)
        if s and s[-1].startswith("Yes"): break
    t8.press("enter", after=1)
    t8.wait_widget("ChapterSelect", 60); time.sleep(2.5)
def chapter(n):
    to_chapter_select()
    for key in ["right"] * 16 + ["left"] * 16:
        mark = t8.log_mark(); t8.press(key, after=0.7); s = t8.says_since(mark)
        if s and s[-1].startswith(f"Chapter {n},"):
            t8.press("enter", after=1); return
    raise t8.BotError(f"chapter {n} not found")
def skip_movie():
    mark = t8.log_mark(); t8.press("b", after=1.5); s = t8.says_since(mark)
    if s and "Skip" in s[-1]: t8.press("enter", after=0.5); return True
    if s: t8.press("b", after=0.8)      # a fight's pause menu: close it
    return False
if __name__ == "__main__":
    try:
        if sys.argv[1] == "chapter": chapter(int(sys.argv[2]))
        elif sys.argv[1] == "skip": print(skip_movie())
    except t8.BotError as e:
        print("STOPPED", e); sys.exit(2)
