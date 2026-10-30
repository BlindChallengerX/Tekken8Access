"""Drive Tekken 8 for TekkenA11y testing.

Every step checks where the game is (visible widget classes through the dev
console, and what the mod spoke in helper.log) before the next key, and stops
with BotError when the screen is not the one expected, instead of pressing on
blind. Keys go only to the game: the window is looked up by the game's
process each time (it swaps windows while starting) and focus is checked
before every key.

  python t8.py state                   visible widgets + last speech
  python t8.py boot                    after a start: title, news, to the main menu
  python t8.py practice [right]        main menu -> a Practice match (left side default)
  python t8.py pmenu "Throw Escape Training"   Practice pause menu -> that row, Enter
  python t8.py lua "return 1+1"        run Lua in the game (dev console)
  python t8.py luaf file.lua [secs]    run a Lua file
  python t8.py keys down down enter    press keys (wait2 = pause 2 s)
  python t8.py shot out.png            screenshot of the game window
  python t8.py say [n]                 last n SAY lines of the helper log

Needs Mods\\TekkenA11y\\dev.txt at game start (dev console).
"""
import ctypes, ctypes.wintypes as W, os, subprocess, sys, time

TMP = os.path.join(os.environ["TEMP"], "TekkenA11y")
CMD, OUT = os.path.join(TMP, "cmd.lua"), os.path.join(TMP, "out.txt")
HELPER_LOG = os.path.join(TMP, "helper.log")
GAME_EXE = "Polaris-Win64-Shipping.exe"
u32 = ctypes.windll.user32
k32 = ctypes.windll.kernel32


class BotError(RuntimeError):
    pass


def log(msg):
    print(f"[bot {time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------- dev console

def lua(code, timeout=10):
    os.makedirs(TMP, exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    with open(CMD + ".tmp", "w", encoding="utf-8") as f:
        f.write(code)
    os.replace(CMD + ".tmp", CMD)
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(OUT):
            time.sleep(0.02)
            try:
                with open(OUT, encoding="utf-8", errors="replace") as f:
                    return f.read()
            except FileNotFoundError:   # replaced while we looked
                continue
        time.sleep(0.03)
    return "(timeout)"


VIS = """local r = {}
for _, w in ipairs(FindAllOf("UserWidget") or {}) do
  if w:IsValid() and w:IsInViewport() and w:IsVisible() then r[#r+1] = w:GetClass():GetFName():ToString() end
end
return table.concat(r, " ")"""


def visible():
    return lua(VIS)


def state():
    """Set of in-viewport widget class names; None when the console does not answer."""
    v = visible()
    if v == "(timeout)":
        return None
    return set(v.replace("=>", " ").split())


def has(st, *names):
    return st is not None and any(any(n in c for c in st) for n in names)


# ---------------------------------------------------------------- helper log (speech)

def log_mark():
    try:
        return os.path.getsize(HELPER_LOG)
    except OSError:
        return 0


def says_since(mark):
    """SAY lines (text only) written after log_mark() returned `mark`."""
    try:
        with open(HELPER_LOG, "rb") as f:
            f.seek(mark)
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return []
    out = []
    for l in data.splitlines():
        i = l.find(" SAY")
        if i >= 0:
            out.append(l[i:].split(": ", 1)[-1].strip())
    return out


def say(n=20):
    if not os.path.exists(HELPER_LOG):
        return ""
    with open(HELPER_LOG, encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip() for l in f if " SAY" in l]
    return "\n".join(lines[-n:])


def wait_until(pred, timeout, what, poll=0.5):
    end = time.time() + timeout
    while time.time() < end:
        r = pred()
        if r:
            return r
        time.sleep(poll)
    raise BotError(f"timed out after {timeout:.0f} s waiting for {what}")


def wait_widget(names, timeout=30):
    names = (names,) if isinstance(names, str) else names
    return wait_until(lambda: has(state(), *names), timeout, " / ".join(names))


# ---------------------------------------------------------------- window and keys

class PE(ctypes.Structure):
    _fields_ = [("dwSize", W.DWORD), ("cntUsage", W.DWORD), ("th32ProcessID", W.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t), ("th32ModuleID", W.DWORD), ("cntThreads", W.DWORD),
                ("th32ParentProcessID", W.DWORD), ("pcPriClassBase", W.LONG), ("dwFlags", W.DWORD),
                ("szExeFile", ctypes.c_wchar * 260)]


def game_pid():
    snap = k32.CreateToolhelp32Snapshot(2, 0)
    pe = PE(); pe.dwSize = ctypes.sizeof(PE)
    pid = None
    ok = k32.Process32FirstW(snap, ctypes.byref(pe))
    while ok:
        if pe.szExeFile.lower() == GAME_EXE.lower():
            pid = pe.th32ProcessID
            break
        ok = k32.Process32NextW(snap, ctypes.byref(pe))
    k32.CloseHandle(snap)
    return pid


def window():
    """The game's largest visible top-level window (the splash and the real
    window are different windows while it starts)."""
    pid = game_pid()
    if not pid:
        return None
    best = [None, 0]

    @ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    def cb(hwnd, _):
        p = W.DWORD()
        u32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and u32.IsWindowVisible(hwnd):
            r = W.RECT(); u32.GetWindowRect(hwnd, ctypes.byref(r))
            area = (r.right - r.left) * (r.bottom - r.top)
            if area > best[1]:
                best[0], best[1] = hwnd, area
        return True
    u32.EnumWindows(cb, 0)
    return best[0]


def focus():
    for _ in range(8):
        w = window()
        if not w:
            if not game_pid():
                raise BotError("the game is not running")
            time.sleep(0.5); continue
        if u32.GetForegroundWindow() == w:
            return w
        # let SetForegroundWindow work from a background process: tap Alt,
        # and attach to the foreground thread's input for the call
        fg = u32.GetForegroundWindow()
        t_fg = u32.GetWindowThreadProcessId(fg, None)
        t_me = k32.GetCurrentThreadId()
        u32.keybd_event(0x12, 0, 0, 0); u32.keybd_event(0x12, 0, 2, 0)
        u32.AttachThreadInput(t_me, t_fg, True)
        if u32.IsIconic(w):
            u32.ShowWindow(w, 9)
        u32.BringWindowToTop(w); u32.SetForegroundWindow(w)
        u32.AttachThreadInput(t_me, t_fg, False)
        time.sleep(0.3)
    raise BotError("could not bring the game window to the front; no keys sent")


class KI(ctypes.Structure):
    _fields_ = [("wVk", W.WORD), ("wScan", W.WORD), ("dwFlags", W.DWORD), ("time", W.DWORD), ("dwExtraInfo", ctypes.c_size_t)]
class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", KI), ("pad", ctypes.c_byte * 32)]
    _anonymous_ = ("u",)
    _fields_ = [("type", W.DWORD), ("u", _U)]

# name: (vk, scan, extended)
KEYS = {"up": (0x26, 0x48, 1), "down": (0x28, 0x50, 1), "left": (0x25, 0x4B, 1), "right": (0x27, 0x4D, 1),
        "enter": (0x0D, 0x1C, 0), "esc": (0x1B, 0x01, 0), "space": (0x20, 0x39, 0), "back": (0x08, 0x0E, 0),
        "tab": (0x09, 0x0F, 0), "f1": (0x70, 0x3B, 0), "f2": (0x71, 0x3C, 0), "f3": (0x72, 0x3D, 0), "f4": (0x73, 0x3E, 0),
        "f5": (0x74, 0x3F, 0), "f6": (0x75, 0x40, 0), "f7": (0x76, 0x41, 0), "f8": (0x77, 0x42, 0), "f9": (0x78, 0x43, 0),
        "f10": (0x79, 0x44, 0), "f11": (0x7A, 0x57, 0), "f12": (0x7B, 0x58, 0)}
for ch, sc in zip("qwertyuiop", range(0x10, 0x1A)): KEYS[ch] = (ord(ch.upper()), sc, 0)
for ch, sc in zip("asdfghjkl", range(0x1E, 0x27)): KEYS[ch] = (ord(ch.upper()), sc, 0)
for ch, sc in zip("zxcvbnm", range(0x2C, 0x33)): KEYS[ch] = (ord(ch.upper()), sc, 0)
for i, ch in enumerate("1234567890"): KEYS[ch] = (ord(ch), 0x02 + i, 0)
KEYS.update({"numminus": (0x6D, 0x4A, 0), "num9": (0x69, 0x49, 0), "num7": (0x67, 0x47, 0), "num1": (0x61, 0x4F, 0), "num3": (0x63, 0x51, 0), "num4": (0x64, 0x4B, 0), "num5": (0x65, 0x4C, 0), "num6": (0x66, 0x4D, 0), "num8": (0x68, 0x48, 0), "num2": (0x62, 0x50, 0), "pgup": (0x21, 0x49, 1), "pgdn": (0x22, 0x51, 1)})


def _send(name, up):
    vk, sc, ext = KEYS[name]
    i = INPUT(type=1)
    i.ki = KI(vk, sc, 0x0008 | (0x0001 if ext else 0) | (0x0002 if up else 0), 0, 0)
    u32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))


def press(name, hold=0.07, after=0.3):
    focus()
    _send(name, False); time.sleep(hold); _send(name, True); time.sleep(after)


def chord(names, hold=0.08, after=0.3):
    """Several keys down together (throws, directions + buttons)."""
    focus()
    for n in names: _send(n, False)
    time.sleep(hold)
    for n in reversed(names): _send(n, True)
    time.sleep(after)


def keys(names, after=0.3):
    for n in names:
        if n.startswith("wait"):
            time.sleep(float(n[4:] or 1)); continue
        press(n, after=after)


def press_expect(key, pred, what, timeout=3.0, after=0.0):
    """Press a key, then wait for pred(new_speech_lines) to be true."""
    mark = log_mark()
    press(key, after=after)
    return wait_until(lambda: pred(says_since(mark)), timeout, f"{what} after {key}", poll=0.1)


def shot(path):
    w = window()
    if not w:
        raise BotError("no game window")
    r = W.RECT(); u32.GetClientRect(w, ctypes.byref(r))
    pt = W.POINT(0, 0); u32.ClientToScreen(w, ctypes.byref(pt))
    ps = (f"Add-Type -AssemblyName System.Drawing;"
          f"Add-Type -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool SetProcessDPIAware();' -Name D -Namespace N;"
          f"[N.D]::SetProcessDPIAware()|Out-Null;"
          f"$b=New-Object System.Drawing.Bitmap {r.right},{r.bottom};$g=[System.Drawing.Graphics]::FromImage($b);"
          f"$g.CopyFromScreen({pt.x},{pt.y},0,0,$b.Size);$b.Save('{path}')")
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=True)


# ---------------------------------------------------------------- screens

def at_main(st):
    return has(st, "WBP_UI_MainMenu_C") and not has(st, "Dialog")


MOVIE = """for _, w in ipairs(FindAllOf("WBP_UI_StoryMoviePlayer_C") or {}) do
  if w:IsValid() and w:IsVisible() then return "StoryMoviePlayer" end end return """""


def boot(timeout=240):
    """After a (re)start: press through movies and the title, close news and
    notices, until the main menu. Raises BotError if it does not get there."""
    log("waiting for the dev console")
    wait_until(lambda: lua("return 1", 3).startswith("=> 1"), 120, "the mod's dev console (is dev.txt there?)")
    end = time.time() + timeout
    last, same_since = None, time.time()
    while time.time() < end:
        st = state()
        if st is None:
            time.sleep(1); continue
        if at_main(st):
            log("main menu")
            return True
        key = frozenset(st)
        if key != last:
            last, same_since = key, time.time()
            log("screen: " + (" ".join(sorted(st)) or "(no widgets: movie/title)"))
        elif time.time() - same_since > 90:
            raise BotError("stuck on the same screen for 90 s; the title may be ignoring the "
                           "keyboard (press a controller button there once)")
        if has(st, "News"):
            press("esc", after=1.0)
        elif not st and "StoryMoviePlayer" in lua(MOVIE):
            press("esc", after=1.5)         # the attract movie ignores Enter
        else:
            press("enter", after=1.5)       # movies, title, notices
    raise BotError("did not reach the main menu")


CUR_ROW = """for _, w in ipairs(FindAllOf('WBP_UI_MainMenu_Menu_List_C') or {}) do
  if w.State == 1 and w:IsVisible() then return w.TB_title_ON:GetText():ToString() end end return ''"""
HAS_ROW = """local n = %s for _, w in ipairs(FindAllOf("WBP_UI_MainMenu_Menu_List_C") or {}) do
  if w.State ~= 0 and w:IsVisible() and w.TB_title_ON:GetText():ToString() == n then return "yes" end end return "no\""""


def to_main(limit=10):
    """From any menu screen back to the main menu with Esc."""
    for _ in range(limit):
        st = state()
        if at_main(st):
            return True
        if has(st, "HUD"):
            raise BotError("in a match: leave it from the pause menu first")
        if has(st, "Dialog"):
            # "Return to Side Selection?" and the like: answer Yes
            for key in ("up", "left"):
                try:
                    menu_row("Yes", key=key, limit=2)
                    break
                except BotError:
                    pass
            press("enter", after=1.5)
            continue
        press("esc", after=1.2)
    raise BotError("Esc did not get back to the main menu")


def to_row(name, limit=20):
    """Main menu: switch tabs until a row `name` is listed, then move to it."""
    if not at_main(state()):
        raise BotError("not on the main menu")
    for _ in range(7):
        if "yes" in lua(HAS_ROW % ('"' + name + '"')):
            break
        press("numminus", after=0.6)
    else:
        raise BotError(f"no main menu tab has a row {name!r}")
    for _ in range(limit):
        if lua(CUR_ROW).replace("=> ", "").strip() == name:
            return True
        press("down", after=0.35)
    raise BotError(f"could not highlight {name!r}")


def enter_until(widget, tries=3, wait=7):
    """Enter, and again if the screen did not change (menus ignore keys while
    they animate in)."""
    for _ in range(tries):
        press("enter", after=0.3)
        try:
            return wait_widget(widget, wait)
        except BotError:
            log(f"Enter did not open {widget}, again")
    raise BotError(f"{widget} did not open")


def practice(side="left"):
    """Main menu -> Practice -> side -> the default fighters -> a stage -> in the match."""
    to_row("Practice")
    enter_until("SideSelect")
    log("side select")
    time.sleep(1.0)                     # the screen takes input a moment after it shows
    if side == "right":
        press_expect("right", lambda s: any("Right side" in l for l in s), "Right side")
    mark = log_mark()
    press("enter", after=0.5)
    wait_widget("CharSelect", 20)
    log("character select")
    # the cursor is live once the mod has spoken the first fighter's name
    wait_until(lambda: says_since(mark)[1:], 15, "the first fighter name")
    time.sleep(0.8)
    if has(state(), "Dialog"):
        raise BotError("character select shows a dialog (controller assignment?)")
    for who in ("player", "dummy"):
        for attempt in range(3):
            try:
                press_expect("enter", lambda s: any("selected" in l for l in s), f"{who} selected", timeout=3, after=0.3)
                break
            except BotError:
                if attempt == 2 or has(state(), "StageSelect"):
                    break
                log(f"{who}: Enter not taken, again")
        time.sleep(1.0)
        if has(state(), "StageSelect"):
            break
    wait_widget("StageSelect", 20)
    log("stage select")
    time.sleep(2.0)
    press("enter", after=0.5)
    wait_widget("HUD_S2", 90)
    wait_widget("Practice_S2", 30)
    log("in the Practice match")
    time.sleep(3)
    return True


def pause_menu():
    """Practice: open the pause menu (B) unless it is open."""
    for _ in range(3):
        if has(state(), "PracticeMenu"):
            time.sleep(0.5)
            return True
        press("b", after=0.3)
        try:
            wait_widget("PracticeMenu", 3)
        except BotError:
            log("B did not open the pause menu, again")
    raise BotError("the Practice pause menu did not open")


def menu_row(name, key="down", limit=20):
    """Move the cursor until the mod speaks `name` (rows are spoken as they get the cursor)."""
    for _ in range(limit):
        mark = log_mark()
        press(key, after=0.5)
        heard = says_since(mark)
        if heard and heard[0].startswith(name):
            return True
    raise BotError(f"menu row {name!r} not reached")


def pmenu(name):
    """Practice pause menu -> row `name` -> Enter."""
    pause_menu()
    menu_row(name)
    press("enter", after=1.0)
    return True


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "state"
    try:
        if c == "lua": print(lua(" ".join(sys.argv[2:])))
        elif c == "luaf": print(lua(open(sys.argv[2], encoding="utf-8").read(), float(sys.argv[3]) if len(sys.argv) > 3 else 20))
        elif c == "keys": keys(sys.argv[2:])
        elif c == "shot": shot(sys.argv[2])
        elif c == "vis": print(visible())
        elif c == "say": print(say(int(sys.argv[2]) if len(sys.argv) > 2 else 20))
        elif c == "state": print(" ".join(sorted(state() or ["(console not answering)"]))); print(say(3))
        elif c == "boot": boot()
        elif c == "main": to_main()
        elif c == "practice": practice("right" if len(sys.argv) > 2 and sys.argv[2] == "right" else "left")
        elif c == "pmenu": pmenu(sys.argv[2])
        else: print(__doc__)
    except BotError as e:
        log("STOPPED: " + str(e))
        try:
            log("screen: " + " ".join(sorted(state() or [])))
        except Exception:
            pass
        sys.exit(2)
