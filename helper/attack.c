/*
 * Attack height sounds: the opponent's move is read from the game's fight
 * data (outside the game, ReadProcessMemory on this helper's own thread, so
 * the game does no extra work) and a short sound plays as each attack starts:
 * high / mid / low / special mid / unblockable. Found 2026-11-11 (NOTES.md
 * "Attack height"):
 *
 *   [exe + root] -> battle object; +0x30 / +0x38 = player 0 / player 1 block
 *   block + 0x511  attack type (dword; low byte 1 low, 2 mid, 4 special mid,
 *                  5 high, 7 unblockable, 0x0a throw; 0xc00000 = recovering)
 *   block + 0x550  move id (changes with every move, so jab, jab plays twice)
 *   block + 0x3540, + 0x35c0  pointers back to the block (used to recognise it)
 *
 * root changes with every game patch, so it is found by scanning the exe's
 * writable data for a pointer whose +0x30 and +0x38 are two such blocks, and
 * kept in attack_root.txt with the exe's build stamp. The type moves before
 * the hit: about 0.2 s ahead of the active frames for a 13-frame mid.
 *
 * The mod sends "A<tab>me<tab>mode" while a fight is on screen and no menu is
 * open (me = the player's PlayerNumber; mode 1 = opponent's attacks, 2 = your
 * own, 3 = both), "A0" otherwise. Your own attacks play on your side of the
 * screen and quieter, so the opponent's stand out when both are on. "T atk_demo" plays each sound
 * with its name.
 */
#include "access.h"
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>
#include <mmsystem.h>

#define OFF_TYPE   0x511
#define OFF_MOVE   0x550
#define OFF_SELF1  0x3540
#define OFF_SELF2  0x35c0
#define OFF_P0     0x30

static volatile LONG s_cfg = -1;        /* me * 4 + mode (1 opponent, 2 self, 3 both); -1 = off */
static HANDLE s_proc;
static uintptr_t s_exe, s_exe_size, s_root;
static DWORD s_stamp;
static DWORD s_next_scan;               /* the object only exists once a fight has loaded: retry */

static int rd(uintptr_t a, void *out, size_t n) {
    SIZE_T got = 0;
    return s_proc && ReadProcessMemory(s_proc, (LPCVOID)a, out, n, &got) && got == n;
}
static uintptr_t rq(uintptr_t a) { uintptr_t v = 0; return rd(a, &v, 8) ? v : 0; }
static int heap_ptr(uintptr_t v) { return v >= 0x10000000000ull && v < 0x7ff000000000ull && !(v & 7); }

static int valid_block(uintptr_t b) {
    return heap_ptr(b) && rq(b + OFF_SELF1) == b && rq(b + OFF_SELF2) == b;
}

static int open_game(void) {
    if (s_proc) {
        DWORD code = 0;
        if (GetExitCodeProcess(s_proc, &code) && code == STILL_ACTIVE) return 1;
        CloseHandle(s_proc); s_proc = NULL; s_exe = 0; s_root = 0;
    }
    DWORD pid = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32W pe; pe.dwSize = sizeof pe;
    if (Process32FirstW(snap, &pe)) do {
        if (!_wcsicmp(pe.szExeFile, L"Polaris-Win64-Shipping.exe")) { pid = pe.th32ProcessID; break; }
    } while (Process32NextW(snap, &pe));
    CloseHandle(snap);
    if (!pid) return 0;
    s_proc = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!s_proc) { log_line("attack: OpenProcess failed %lu", GetLastError()); return 0; }
    snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    MODULEENTRY32W me; me.dwSize = sizeof me;
    if (Module32FirstW(snap, &me)) do {
        if (!_wcsicmp(me.szModule, L"Polaris-Win64-Shipping.exe")) {
            s_exe = (uintptr_t)me.modBaseAddr; s_exe_size = me.modBaseSize; break;
        }
    } while (Module32NextW(snap, &me));
    CloseHandle(snap);
    if (!s_exe) { log_line("attack: exe module not found"); return 0; }
    DWORD lfanew = 0;
    rd(s_exe + 0x3c, &lfanew, 4);
    rd(s_exe + lfanew + 8, &s_stamp, 4);           /* PE TimeDateStamp: changes with every build */
    log_line("attack: exe at %llx size %llx stamp %08lx", (unsigned long long)s_exe, (unsigned long long)s_exe_size, s_stamp);
    return 1;
}

static void root_file(wchar_t *p) { wcscpy(p, g_mod_dir); wcscat(p, L"..\\attack_root.txt"); }

static int root_ok(uintptr_t root) {
    uintptr_t obj = rq(s_exe + root);
    return heap_ptr(obj) && valid_block(rq(obj + OFF_P0)) && valid_block(rq(obj + OFF_P0 + 8));
}

/* scan the exe's writable data for the battle object pointer (a few seconds, once per build) */
static uintptr_t scan_root(void) {
    DWORD t0 = GetTickCount();
    MEMORY_BASIC_INFORMATION mbi;
    uintptr_t a = s_exe;
    static uintptr_t buf[0x10000 / 8];
    while (a < s_exe + s_exe_size && VirtualQueryEx(s_proc, (LPCVOID)a, &mbi, sizeof mbi)) {
        uintptr_t base = (uintptr_t)mbi.BaseAddress, end = base + mbi.RegionSize;
        if (mbi.State == MEM_COMMIT && (mbi.Protect == PAGE_READWRITE || mbi.Protect == PAGE_WRITECOPY)) {
            for (uintptr_t p = base; p < end; p += sizeof buf) {
                size_t n = end - p < sizeof buf ? end - p : sizeof buf;
                if (!rd(p, buf, n)) continue;
                for (size_t i = 0; i < n / 8; i++) {
                    uintptr_t v = buf[i];
                    if (!heap_ptr(v)) continue;
                    uintptr_t pair[2];
                    if (!rd(v + OFF_P0, pair, 16) || !heap_ptr(pair[0]) || !heap_ptr(pair[1]) || pair[0] == pair[1]) continue;
                    if (valid_block(pair[0]) && valid_block(pair[1])) {
                        uintptr_t root = p + i * 8 - s_exe;
                        log_line("attack: root exe+%llx found in %lu ms", (unsigned long long)root, GetTickCount() - t0);
                        return root;
                    }
                }
            }
        }
        a = end;
    }
    log_line("attack: no battle object found (%lu ms); game layout changed?", GetTickCount() - t0);
    return 0;
}

static int find_root(void) {
    if (s_root && root_ok(s_root)) return 1;
    wchar_t path[MAX_PATH]; root_file(path);
    FILE *f = _wfopen(path, L"r");
    if (f) {
        unsigned long stamp = 0; unsigned long long off = 0;
        if (fscanf(f, "%lx %llx", &stamp, &off) == 2 && stamp == s_stamp && root_ok((uintptr_t)off)) {
            fclose(f); s_root = (uintptr_t)off; return 1;
        }
        fclose(f);
    }
    if (GetTickCount() < s_next_scan) return 0;
    uintptr_t r = scan_root();
    if (!r) { s_next_scan = GetTickCount() + 3000; return 0; }
    s_root = r;
    f = _wfopen(path, L"w");
    if (f) { fprintf(f, "%08lx %llx\n", s_stamp, (unsigned long long)r); fclose(f); }
    return 1;
}

/* ------------------------------------------------------------------ sounds */
/* height = pitch register, twice over: a short pluck (880 / 440 / 220 Hz)
   and a swing whoosh (band-passed noise, bright and rising for high, falling
   for low). Special mid = mid pluck then low. Unblockable = a low buzz.
   Panned to the opponent's side like the beacon. Throws keep their reed
   notes (ui_sound "throw1"). */
void attack_sound(int code, float pan, float vol) {
    const float g = 0.15f * vol, s = 0.12f * vol;
    switch (code) {
    case 5:  /* high */
        tone(1100, 2200, 0.09f, s, pan, W_SWISH);
        tone(880, 920, 0.07f, g, pan, W_TRI);
        break;
    case 2:  /* mid */
        tone(650, 800, 0.09f, s, pan, W_SWISH);
        tone(440, 440, 0.07f, g, pan, W_TRI);
        break;
    case 1:  /* low */
        tone(520, 260, 0.11f, s, pan, W_SWISH);
        tone(220, 205, 0.09f, g * 1.2f, pan, W_TRI);
        break;
    case 4:  /* special mid: blockable crouching too */
        tone(650, 500, 0.12f, s, pan, W_SWISH);
        tone(440, 440, 0.05f, g, pan, W_TRI);
        tone_at(0.06f, 220, 220, 0.06f, g * 1.2f, pan, W_TRI);
        break;
    case 7:  /* unblockable */
        tone(160, 150, 0.22f, g * 0.8f, pan, W_SAW);
        tone(400, 300, 0.2f, s, pan, W_SWISH);
        break;
    }
}

static DWORD WINAPI demo_thread(LPVOID unused) {
    (void)unused;
    static const struct { const wchar_t *name; int code; } d[] = {
        { L"High", 5 }, { L"Mid", 2 }, { L"Low", 1 }, { L"Special mid", 4 }, { L"Unblockable", 7 } };
    for (int i = 0; i < 5; i++) {
        speak(d[i].name, 1);
        Sleep(650);
        attack_sound(d[i].code, 0, 1);
        Sleep(700);
    }
    return 0;
}
void attack_demo(void) { CloseHandle(CreateThread(NULL, 0, demo_thread, NULL, 0, NULL)); }

/* ------------------------------------------------------------------ watcher */
void attack_watch(int me, int mode) { InterlockedExchange(&s_cfg, mode > 0 && me >= 0 ? me * 4 + mode : -1); }

static DWORD WINAPI watch_thread(LPVOID unused) {
    (void)unused;
    timeBeginPeriod(1);
    unsigned last_move[2] = { 0 }, last_type[2] = { 0 };
    DWORD next_check = 0, last_cue[2] = { 0 };
    int was = -1;
    for (;;) {
        int cfg = (int)s_cfg;
        if (cfg < 0) { was = -1; Sleep(20); continue; }
        if (cfg != was) {               /* a fight, side or mode started: (re)find the data */
            if (!open_game() || !find_root()) { Sleep(500); continue; }
            was = cfg; next_check = 0;
            memset(last_move, 0, sizeof last_move); memset(last_type, 0, sizeof last_type);
        }
        int me = cfg / 4 > 1 ? 1 : cfg / 4, mode = cfg & 3;
        /* slot 0 = opponent, slot 1 = you */
        int idx[2] = { 1 - me, me }, want[2] = { mode & 1, mode & 2 };
        DWORD now = GetTickCount();
        uintptr_t obj = rq(s_exe + s_root);
        int broken = 0;
        for (int k = 0; k < 2 && !broken; k++) {
            if (!want[k]) continue;
            uintptr_t blk = rq(obj + OFF_P0 + 8 * idx[k]);
            if (now >= next_check && !valid_block(blk)) { broken = 1; break; }
            unsigned char raw[OFF_MOVE + 4 - OFF_TYPE];
            if (!rd(blk + OFF_TYPE, raw, sizeof raw)) { broken = 1; break; }
            unsigned type, move;
            memcpy(&type, raw, 4); memcpy(&move, raw + (OFF_MOVE - OFF_TYPE), 4);
            int code = type & 0xff;
            int height = (type >> 16) && (code == 1 || code == 2 || code == 4 || code == 5 || code == 7);
            if (height && (move != last_move[k] || type != last_type[k]) && now - last_cue[k] > 60) {
                float pan = beacon_pan();
                attack_sound(code, k ? -pan : pan, k ? 0.6f : 1.0f);
                last_cue[k] = now;
                log_line("attack %s %d (type %08x move %x)", k ? "own" : "opponent", code, type, move);
            }
            last_move[k] = move; last_type[k] = type;
        }
        if (now >= next_check) next_check = now + 500;     /* blocks rechecked twice a second */
        if (broken) { was = -1; s_root = s_root && root_ok(s_root) ? s_root : 0; Sleep(200); continue; }
        Sleep(2);
    }
    return 0;
}

void attack_init(void) { CloseHandle(CreateThread(NULL, 0, watch_thread, NULL, 0, NULL)); }
