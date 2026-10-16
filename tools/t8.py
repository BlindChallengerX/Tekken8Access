"""Drive Tekken 8 for TekkenA11y testing.

  python t8.py lua "return 1+1"        run Lua in the game (dev console)
  python t8.py luaf file.lua           run a Lua file
  python t8.py keys down down enter    press keys (game window must exist)
  python t8.py shot out.png            screenshot of the game window
  python t8.py say [n]                 last n SAY lines of the helper log
"""
import ctypes, ctypes.wintypes as W, os, subprocess, sys, time

TMP = os.path.join(os.environ["TEMP"], "TekkenA11y")
CMD, OUT = os.path.join(TMP, "cmd.lua"), os.path.join(TMP, "out.txt")
HELPER_LOG = os.path.join(TMP, "helper.log")
u32 = ctypes.windll.user32


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
            with open(OUT, encoding="utf-8", errors="replace") as f:
                return f.read()
        time.sleep(0.03)
    return "(timeout)"


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
KEYS.update({"numminus": (0x6D, 0x4A, 0), "num9": (0x69, 0x49, 0), "num7": (0x67, 0x47, 0), "num1": (0x61, 0x4F, 0), "num3": (0x63, 0x51, 0), "pgup": (0x21, 0x49, 1), "pgdn": (0x22, 0x51, 1)})


def window():
    found = []
    @ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    def cb(hwnd, _):
        cls = ctypes.create_unicode_buffer(64); u32.GetClassNameW(hwnd, cls, 64)
        if cls.value == "UnrealWindow" and u32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True
    u32.EnumWindows(cb, 0)
    return found[0] if found else None


def focus():
    w = window()
    if not w:
        raise RuntimeError("no game window")
    for _ in range(5):
        if u32.GetForegroundWindow() == w:
            return w
        u32.keybd_event(0x12, 0, 0, 0); u32.keybd_event(0x12, 0, 2, 0)
        u32.ShowWindow(w, 9); u32.BringWindowToTop(w); u32.SetForegroundWindow(w)
        time.sleep(0.3)
    raise RuntimeError("could not focus the game window; not sending keys")


def _send(name, up):
    vk, sc, ext = KEYS[name]
    i = INPUT(type=1)
    i.ki = KI(vk, sc, 0x0008 | (0x0001 if ext else 0) | (0x0002 if up else 0), 0, 0)
    u32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))


def press(name, hold=0.07, after=0.3):
    focus()
    _send(name, False); time.sleep(hold); _send(name, True); time.sleep(after)


def keys(names, after=0.3):
    for n in names:
        if n.startswith("wait"):
            time.sleep(float(n[4:] or 1)); continue
        press(n, after=after)


def shot(path):
    w = window()
    r = W.RECT(); u32.GetClientRect(w, ctypes.byref(r))
    pt = W.POINT(0, 0); u32.ClientToScreen(w, ctypes.byref(pt))
    ps = (f"Add-Type -AssemblyName System.Drawing;"
          f"Add-Type -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool SetProcessDPIAware();' -Name D -Namespace N;"
          f"[N.D]::SetProcessDPIAware()|Out-Null;"
          f"$b=New-Object System.Drawing.Bitmap {r.right},{r.bottom};$g=[System.Drawing.Graphics]::FromImage($b);"
          f"$g.CopyFromScreen({pt.x},{pt.y},0,0,$b.Size);$b.Save('{path}')")
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=True)


VIS = """local r = {}
for _, w in ipairs(FindAllOf("UserWidget") or {}) do
  if w:IsValid() and w:IsInViewport() and w:IsVisible() then r[#r+1] = w:GetClass():GetFName():ToString() end
end
return table.concat(r, " ")"""


def visible():
    return lua(VIS)


def to_main(limit=40):
    """Press Enter through movies/title, then wait for the main menu (news closes with Esc)."""
    for _ in range(limit):
        v = visible()
        if "WBP_UI_News_C" in v:
            press("esc", after=1.0); continue
        if "WBP_UI_MainMenu_C" in v and "Dialog" not in v:
            return True
        if "Dialog" in v and "MainMenu" not in v:
            time.sleep(1.5); continue
        press("enter", after=1.5)
    return False


def say(n=20):
    if not os.path.exists(HELPER_LOG):
        return ""
    with open(HELPER_LOG, encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip() for l in f if " SAY" in l]
    return "\n".join(lines[-n:])


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "lua": print(lua(" ".join(sys.argv[2:])))
    elif c == "luaf": print(lua(open(sys.argv[2], encoding="utf-8").read(), float(sys.argv[3]) if len(sys.argv) > 3 else 20))
    elif c == "keys": keys(sys.argv[2:])
    elif c == "shot": shot(sys.argv[2])
    elif c == "vis": print(visible())
    elif c == "main": print(to_main())
    elif c == "say": print(say(int(sys.argv[2]) if len(sys.argv) > 2 else 20))


def disc():
    return lua(open(os.path.join(os.path.dirname(__file__), "discover.lua"), encoding="utf-8").read(), 60)


def evdump():
    return lua("local t = {} for _, l in ipairs(ev) do if not (l:find('UpdateScroll') or l:find('UpdateBalloon') or l:find('UpdateText')) then t[#t+1] = l end end ev = {}; return table.concat(t, '\\n')")


if __name__ == "__main__" and sys.argv[1] == "disc": print(disc()); lua("ev = {}")
if __name__ == "__main__" and sys.argv[1] == "ev": print(evdump())


CUR_ROW = """for _, w in ipairs(FindAllOf('WBP_UI_MainMenu_Menu_List_C') or {}) do
  if w.State == 1 and w:IsVisible() then return w.TB_title_ON:GetText():ToString() end end return ''"""


def to_row(name, limit=20):
    """Main menu: press down until the highlighted row is `name`."""
    for _ in range(limit):
        cur = lua(CUR_ROW).replace("=> ", "").strip()
        if cur == name:
            return True
        press("down", after=0.35)
    return False


def to_practice():
    to_main()
    time.sleep(1)
    to_row("Practice")
    press("enter", after=3)


if __name__ == "__main__" and sys.argv[1] == "practice": to_practice(); print(visible())


def boot(limit=150):
    """After a (re)start: Enter through title, Esc through news, until the main menu."""
    for i in range(limit):
        v = visible()
        if "MainMenu" in v and "Dialog" not in v:
            return True
        if "News" in v:
            press("esc", after=1); continue
        if "Title" in v or v.strip() in ("=>", "=> ", "(timeout)"):
            press("enter", after=1.2)
        else:
            time.sleep(1)
    return False


if __name__ == "__main__" and sys.argv[1] == "boot": print(boot())
