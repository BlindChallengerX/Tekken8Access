"""Find static pointer chains to a Tekken 8 address (read only, from outside the game).

  python ptrchain.py <target> [depth] [max_offset]

Backward search: level 1 = every place holding a pointer to target - k
(0 <= k < max_offset), level 2 = places pointing at those, ... until a place
inside the game exe's writable data is reached. Prints chains as
  exe+0xOFFSET, o1, o2, ... (dereference after adding each offset; the last
  value is the target minus its own offset).
The whole memory is read once and kept in RAM (numpy), so every level is a
vectorised search.
"""
import ctypes, ctypes.wintypes as W, sys, time
import numpy as np
import memscan

h = memscan.open_game()
psapi = ctypes.windll.psapi
mods = (ctypes.c_void_p * 1024)(); need = W.DWORD()
psapi.EnumProcessModulesEx(h, mods, ctypes.sizeof(mods), ctypes.byref(need), 3)
EXE = mods[0]


class MI(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p), ("SizeOfImage", W.DWORD), ("EntryPoint", ctypes.c_void_p)]


mi = MI(); psapi.GetModuleInformation(h, ctypes.c_void_p(EXE), ctypes.byref(mi), ctypes.sizeof(mi))
EXE_END = EXE + mi.SizeOfImage


def all_regions():
    a, mbi = 0, memscan.MBI()
    while memscan.k32.VirtualQueryEx(h, ctypes.c_void_p(a), ctypes.byref(mbi), ctypes.sizeof(mbi)):
        base, size = mbi.BaseAddress or 0, mbi.RegionSize
        if mbi.State == 0x1000 and mbi.Protect in (0x04, 0x08, 0x40) and (mbi.Type == 0x20000 or EXE <= base < EXE_END):
            yield base, size
        a = base + size
        if a >= 0x7FFFFFFFFFFF:
            break


def load():
    """generator: (address, uint64 array) chunks of all heap + exe data, read fresh each pass"""
    for base, size in all_regions():
        if base < 0x10000000000 and not (EXE <= base < EXE_END):
            continue                     # thread stacks: not stable roots
        for off in range(0, size, 1 << 24):
            n = min(1 << 24, size - off)
            d = memscan.read(h, base + off, n)
            if d and len(d) >= 8:
                yield base + off, np.frombuffer(d[:len(d) // 8 * 8], dtype=np.uint64)


def sources(chunks, targets, max_off):
    """chunks: iterable. places whose value v satisfies t - max_off < v <= t for some target t: {place: (t, t - v)}"""
    ts = np.array(sorted(targets), dtype=np.uint64)
    out = {}
    for base, arr in chunks:
        # v in (t - max_off, t]: find the first t >= v, check t - v < max_off
        idx = np.searchsorted(ts, arr, side="left")
        ok = idx < len(ts)
        idx2 = np.where(ok, idx, 0)
        diff = ts[idx2] - arr
        hit = ok & (diff < max_off) & (arr > 0x10000)
        for i in np.nonzero(hit)[0]:
            out[base + int(i) * 8] = (int(ts[idx2[i]]), int(diff[i]))
    return out


def main():
    target = int(sys.argv[1], 0)
    depth = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    max_off = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x400
    level = {target: []}           # address -> offsets after it
    for d in range(depth):
        t0 = time.time()
        src = sources(load(), level.keys(), max_off if d else 1)
        print("pass %d took %.0f s" % (d + 1, time.time() - t0), flush=True)
        nxt = {}
        for place, (t, off) in src.items():
            nxt[place] = [off] + level[t]
        statics = {p: o for p, o in nxt.items() if EXE <= p < EXE_END}
        print("level %d: %d places, %d in the exe" % (d + 1, len(nxt), len(statics)), flush=True)
        for p, o in sorted(statics.items())[:30]:
            print("  exe+%s, %s" % (hex(p - EXE), ", ".join(hex(x) for x in o)), flush=True)
        if statics and d >= 1:
            break
        if len(nxt) > 200000:
            print("too many places, stopping"); break
        level = nxt


if __name__ == "__main__":
    main()
