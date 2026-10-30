/*
 * TekkenA11y helper. Started by the Lua mod when the game starts; exits when
 * the game exits. Reads commands from \\.\pipe\TekkenA11y, one per line:
 *
 *   S1<tab>text     speak, interrupting       S0<tab>text  speak after current
 *   X               stop speech
 *   F<tab>numbers   fight frame for the beacon (see beacon.c)
 *   F0              fight over: beacon silent
 *   BL<tab>numbers  Tekken Ball: screen depth height dist (beacon.c)   BL0 stop
 *   T<tab>name      UI sound (edge, ...), throw break cue (throw1, throw2, throw12),
 *                   combo challenge (stepN, drop, clear)
 *   C<tab>key<tab>v config value
 *   L<tab>text      write text to the log
 *
 * Log: %TEMP%\TekkenA11y\helper.log (SAY lines carry millisecond times, to
 * measure key-to-speech delay).
 */
#include "access.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <tlhelp32.h>

wchar_t g_mod_dir[MAX_PATH];
static FILE *g_log;
static CRITICAL_SECTION g_loglock;

void log_line(const char *fmt, ...) {
    if (!g_log) return;
    SYSTEMTIME st; GetLocalTime(&st);
    EnterCriticalSection(&g_loglock);
    fprintf(g_log, "%02d:%02d:%02d.%03d ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fputc('\n', g_log); fflush(g_log);
    LeaveCriticalSection(&g_loglock);
}

char *to_utf8(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = malloc(n > 0 ? n : 1);
    if (!s) return NULL;
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL); else s[0] = 0;
    return s;
}

wchar_t *from_utf8(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    wchar_t *w = malloc(sizeof(wchar_t) * (n > 0 ? n : 1));
    if (!w) return NULL;
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n); else w[0] = 0;
    return w;
}

/* UI sounds: short, quiet, out of the way of speech */
static void ui_sound(const char *name) {
    if (!strcmp(name, "edge")) tone(220, 200, 0.06f, 0.10f, 0, W_SOFT);
    else if (!strcmp(name, "open")) { tone(440, 440, 0.05f, 0.07f, 0, W_SOFT); tone_at(0.06f, 660, 660, 0.06f, 0.07f, 0, W_SOFT); }
    else if (!strcmp(name, "round")) { tone(330, 330, 0.08f, 0.10f, 0, W_SOFT); tone_at(0.09f, 495, 495, 0.12f, 0.10f, 0, W_SOFT); }
    /* combo challenge: a step landed (rising with the step number), the combo
       dropped, the challenge cleared */
    else if (!strncmp(name, "step", 4)) {
        int k = atoi(name + 4); if (k < 1) k = 1; if (k > 12) k = 12;
        float f = 440 * powf(2, (k - 1) * 2 / 12.0f);
        tone(f, f, 0.05f, 0.12f, 0, W_TRI);
    }
    else if (!strcmp(name, "drop")) tone(260, 180, 0.15f, 0.10f, 0, W_SOFT);
    else if (!strcmp(name, "clear")) {
        tone(523, 523, 0.10f, 0.14f, 0, W_SOFT); tone_at(0.10f, 659, 659, 0.10f, 0.14f, 0, W_SOFT);
        tone_at(0.20f, 784, 784, 0.10f, 0.14f, 0, W_SOFT); tone_at(0.30f, 1047, 1047, 0.25f, 0.14f, 0, W_SOFT);
    }
    /* opponent's throw is starting: which button breaks it. Reed, louder than
       the soft beacon ping. 1 (also the cue for plain throws, which 1 or 2
       break) = one low note; 2 = two quick high notes; 1+2 = a fast high
       trill of four, so it is not taken for the low note */
    else if (!strcmp(name, "throw1")) tone(392, 392, 0.14f, 0.20f, 0, W_REED);
    else if (!strcmp(name, "throw2")) { tone(784, 784, 0.06f, 0.18f, 0, W_REED); tone_at(0.09f, 784, 784, 0.06f, 0.18f, 0, W_REED); }
    else if (!strcmp(name, "throw12"))
        for (int i = 0; i < 4; i++) tone_at(i * 0.055f, 1047, 1047, 0.035f, 0.17f, 0, W_REED);
}

static void handle(char *line) {
    size_t n = strlen(line);
    while (n && (line[n - 1] == '\r' || line[n - 1] == '\n')) line[--n] = 0;
    if (!n) return;
    char *arg = strchr(line, '\t');
    if (arg) *arg++ = 0; else arg = line + n;
    if (!strcmp(line, "S1") || !strcmp(line, "S0")) {
        /* the mod sends \n inside text as the two characters \ n */
        for (char *p = arg; *p; p++) if (p[0] == '\\' && p[1] == 'n') { p[0] = ' '; p[1] = ' '; }
        speak_utf8(arg, line[1] == '1');
    } else if (!strcmp(line, "X")) speech_stop();
    else if (!strcmp(line, "F")) {
        float v[16]; int k = 0;
        char *p = arg;
        while (*p && k < 16) { char *e; v[k] = strtof(p, &e); if (e == p) break; k++; p = e; while (*p == '\t' || *p == ' ') p++; }
        beacon_frame(v, k);
    } else if (!strcmp(line, "F0")) beacon_off();
    else if (!strcmp(line, "BL")) {
        float v[8]; int k = 0;
        char *p = arg;
        while (*p && k < 8) { char *e; v[k] = strtof(p, &e); if (e == p) break; k++; p = e; while (*p == '\t' || *p == ' ') p++; }
        ball_frame(v, k);
    } else if (!strcmp(line, "BL0")) ball_off();
    else if (!strcmp(line, "T")) ui_sound(arg);
    else if (!strcmp(line, "C")) {
        char *v = strchr(arg, '\t');
        if (v) { *v++ = 0; beacon_config(arg, strtof(v, NULL)); }
    } else if (!strcmp(line, "L")) log_line("mod: %s", arg);
    else log_line("unknown command %s", line);
}

static DWORD WINAPI pipe_thread(LPVOID unused) {
    (void)unused;
    static char buf[65536];
    for (;;) {
        HANDLE h = CreateNamedPipeW(L"\\\\.\\pipe\\TekkenA11y", PIPE_ACCESS_INBOUND,
                                    PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 0, 65536, 0, NULL);
        if (h == INVALID_HANDLE_VALUE) { log_line("CreateNamedPipe failed %lu", GetLastError()); Sleep(1000); continue; }
        if (!ConnectNamedPipe(h, NULL) && GetLastError() != ERROR_PIPE_CONNECTED) { CloseHandle(h); Sleep(200); continue; }
        log_line("mod connected");
        size_t have = 0;
        for (;;) {
            DWORD got = 0;
            if (!ReadFile(h, buf + have, (DWORD)(sizeof buf - 1 - have), &got, NULL) || !got) break;
            have += got; buf[have] = 0;
            char *start = buf, *nl;
            while ((nl = memchr(start, '\n', have - (start - buf)))) { *nl = 0; handle(start); start = nl + 1; }
            have -= start - buf;
            memmove(buf, start, have);
            if (have >= sizeof buf - 1) have = 0;     /* runaway line: drop it */
        }
        log_line("mod disconnected");
        DisconnectNamedPipe(h); CloseHandle(h);
    }
    return 0;
}

static DWORD find_game(void) {
    DWORD pid = 0;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    PROCESSENTRY32W pe; pe.dwSize = sizeof pe;
    if (Process32FirstW(snap, &pe)) do {
        if (!_wcsicmp(pe.szExeFile, L"Polaris-Win64-Shipping.exe")) { pid = pe.th32ProcessID; break; }
    } while (Process32NextW(snap, &pe));
    CloseHandle(snap);
    return pid;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmd, int show) {
    (void)inst; (void)prev; (void)cmd; (void)show;
    CreateMutexW(NULL, TRUE, L"TekkenA11yHelper");
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;

    GetModuleFileNameW(NULL, g_mod_dir, MAX_PATH);
    wchar_t *slash = wcsrchr(g_mod_dir, L'\\'); if (slash) slash[1] = 0;

    wchar_t logp[MAX_PATH];
    DWORD tn = GetEnvironmentVariableW(L"TEMP", logp, MAX_PATH);
    if (!tn || tn > MAX_PATH - 40) wcscpy(logp, L"C:\\Temp");
    wcscat(logp, L"\\TekkenA11y"); CreateDirectoryW(logp, NULL);
    wcscat(logp, L"\\helper.log");
    InitializeCriticalSection(&g_loglock);
    g_log = _wfopen(logp, L"w");
    log_line("TekkenA11y helper 0.7.1 started");

    speech_init();
    audio_init();
    CloseHandle(CreateThread(NULL, 0, pipe_thread, NULL, 0, NULL));

    /* live as long as the game; give it 60 s to appear */
    HANDLE game = NULL;
    for (int i = 0; i < 120 && !game; i++) {
        DWORD pid = find_game();
        if (pid) game = OpenProcess(SYNCHRONIZE, FALSE, pid);
        if (!game) Sleep(500);
    }
    if (!game) { log_line("game not found, exiting"); return 0; }
    for (;;) {
        if (WaitForSingleObject(game, 20) == WAIT_OBJECT_0) break;
        beacon_tick();
    }
    log_line("game exited");
    return 0;
}
