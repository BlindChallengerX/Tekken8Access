"""Search Tekken 8's memory for 32-bit values (read only, from outside the game).

  python memscan.py find 0x00800002 [out.txt]     all private writable addresses holding the value
  python memscan.py keep in.txt 0x00200001 [out.txt]   keep the addresses that now hold another value
  python memscan.py read addr [count]             dump count dwords from addr
"""
import ctypes, ctypes.wintypes as W, struct, sys, subprocess

k32 = ctypes.windll.kernel32
PROCESS_VM_READ, PROCESS_QUERY_INFORMATION = 0x10, 0x400


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_void_p), ("AllocationBase", ctypes.c_void_p), ("AllocationProtect", W.DWORD),
                ("PartitionId", W.WORD), ("RegionSize", ctypes.c_size_t), ("State", W.DWORD), ("Protect", W.DWORD), ("Type", W.DWORD)]


def pid():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Polaris-Win64-Shipping.exe", "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
    return int(out.split(",")[1].strip('"'))


def open_game():
    h = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, pid())
    if not h:
        raise SystemExit("cannot open the game process")
    return h


def read(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t()
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got)):
        return None
    return buf.raw[:got.value]


def regions(h):
    a, mbi = 0, MBI()
    while k32.VirtualQueryEx(h, ctypes.c_void_p(a), ctypes.byref(mbi), ctypes.sizeof(mbi)):
        base, size = mbi.BaseAddress or 0, mbi.RegionSize
        # committed, private, read-write
        if mbi.State == 0x1000 and mbi.Type == 0x20000 and mbi.Protect in (0x04, 0x40):
            yield base, size
        a = base + size
        if a >= 0x7FFFFFFFFFFF:
            break


def find(value):
    h = open_game()
    pat = struct.pack("<I", value)
    hits = []
    for base, size in regions(h):
        for off in range(0, size, 1 << 24):
            data = read(h, base + off, min(1 << 24, size - off))
            if not data:
                continue
            i = data.find(pat)
            while i != -1:
                hits.append(base + off + i)
                i = data.find(pat, i + 1)
    return hits


def keep(addrs, value):
    h = open_game()
    out = []
    for a in addrs:
        d = read(h, a, 4)
        if d and struct.unpack("<I", d)[0] == value:
            out.append(a)
    return out


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "find":
        hits = find(int(sys.argv[2], 0))
        print(len(hits), "hits")
        if len(sys.argv) > 3:
            open(sys.argv[3], "w").write("\n".join(hex(a) for a in hits))
        for a in hits[:20]: print(hex(a))
    elif c == "keep":
        addrs = [int(l, 16) for l in open(sys.argv[2]) if l.strip()]
        hits = keep(addrs, int(sys.argv[3], 0))
        print(len(hits), "kept")
        if len(sys.argv) > 4:
            open(sys.argv[4], "w").write("\n".join(hex(a) for a in hits))
        for a in hits[:40]: print(hex(a))
    elif c == "read":
        h = open_game()
        a, n = int(sys.argv[2], 0), int(sys.argv[3]) if len(sys.argv) > 3 else 16
        d = read(h, a, n * 4)
        for i in range(0, len(d or b""), 4):
            print(hex(a + i), hex(struct.unpack("<I", d[i:i + 4])[0]))
