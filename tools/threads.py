"""Where are the game's threads? For each thread: RIP module and the modules of
return-address-looking values on its stack (heuristic). Finds deadlocks.
python threads.py [max_threads]"""
import ctypes, ctypes.wintypes as W, struct, subprocess, sys

k32 = ctypes.windll.kernel32
psapi = ctypes.windll.psapi
pid = int(subprocess.run(["powershell", "-NoProfile", "-Command", "(Get-Process Polaris-Win64-Shipping).Id"],
                         capture_output=True, text=True).stdout.strip())
hp = k32.OpenProcess(0x1F0FFF, False, pid)

# modules
mods = (W.HMODULE * 1024)(); need = W.DWORD()
psapi.EnumProcessModulesEx(hp, mods, ctypes.sizeof(mods), ctypes.byref(need), 3)
class MI(ctypes.Structure): _fields_ = [("base", ctypes.c_void_p), ("size", W.DWORD), ("entry", ctypes.c_void_p)]
ranges = []
for i in range(need.value // ctypes.sizeof(W.HMODULE)):
    m = mods[i]; mi = MI(); name = ctypes.create_unicode_buffer(260)
    psapi.GetModuleInformation(hp, ctypes.c_void_p(m), ctypes.byref(mi), ctypes.sizeof(mi))
    psapi.GetModuleBaseNameW(hp, ctypes.c_void_p(m), name, 260)
    ranges.append((mi.base, mi.base + mi.size, name.value))

def mod_of(a):
    for b, e, n in ranges:
        if b <= a < e:
            return f"{n}+{a - b:x}"
    return None

class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", W.DWORD), ("cntUsage", W.DWORD), ("th32ThreadID", W.DWORD), ("th32OwnerProcessID", W.DWORD),
                ("tpBasePri", W.LONG), ("tpDeltaPri", W.LONG), ("dwFlags", W.DWORD)]
snap = k32.CreateToolhelp32Snapshot(4, 0)
te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
tids = []
if k32.Thread32First(snap, ctypes.byref(te)):
    while True:
        if te.th32OwnerProcessID == pid:
            tids.append(te.th32ThreadID)
        if not k32.Thread32Next(snap, ctypes.byref(te)):
            break

CONTEXT_SIZE = 1232
buf = ctypes.create_string_buffer(CONTEXT_SIZE + 16)
addr = ctypes.addressof(buf); addr = (addr + 15) & ~15
ctx = (ctypes.c_char * CONTEXT_SIZE).from_address(addr)
k32.GetThreadContext.argtypes = [W.HANDLE, ctypes.c_void_p]
k32.ReadProcessMemory.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 400
for tid in tids[:limit]:
    ht = k32.OpenThread(0x001A, False, tid)   # suspend/resume, get context, query
    if not ht:
        continue
    k32.SuspendThread(ht)
    ctypes.memset(addr, 0, CONTEXT_SIZE)
    struct.pack_into("<I", ctx, 0x30, 0x10000B)  # CONTEXT_FULL (AMD64)
    ok = k32.GetThreadContext(ht, addr)
    rip = struct.unpack_from("<Q", ctx, 0xF8)[0]; rsp = struct.unpack_from("<Q", ctx, 0x98)[0]
    # read as much of the stack as is mapped (a read past its end fails whole)
    got = ctypes.c_size_t(0)
    for size in (0x10000, 0x8000, 0x4000, 0x2000, 0x1000):
        stack = ctypes.create_string_buffer(size)
        if k32.ReadProcessMemory(hp, ctypes.c_void_p(rsp), stack, size, ctypes.byref(got)) and got.value:
            break
    k32.ResumeThread(ht); k32.CloseHandle(ht)
    frames = []
    for off in range(0, got.value - 8, 8):
        v = struct.unpack_from("<Q", stack.raw, off)[0]
        m = mod_of(v)
        if m and not m.startswith("ntdll") and (not frames or frames[-1] != m):
            frames.append(m)
        if len(frames) >= 30:
            break
    mods_seen = ",".join(sorted({f.split("+")[0] for f in frames}))
    if "UE4SS" in mods_seen or "lua" in mods_seen.lower() or "--all" in sys.argv:
        print(f"tid {tid} rip {mod_of(rip)}\n   " + " < ".join(frames))
