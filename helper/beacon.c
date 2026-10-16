/*
 * Opponent beacon, after Mist World's (as in Soulcalibur Access):
 * every ping is two soft beeps. The first is always 520 Hz; the second is the
 * same note when the opponent is square-on, a fourth / an octave UP when they
 * have moved into the background (up the screen), DOWN when into the
 * foreground. Panned to their side of the screen. Pings come faster as they
 * get closer. Steps change only once the angle is clearly past a threshold,
 * so idle sway does not wobble the note.
 *
 * The mod sends "F mx my ox oy cx cy" about every 30 ms during a fight:
 * my and the opponent's ground positions (UE units, cm) and the camera's
 * forward direction on the ground.
 */
#include "access.h"
#include <math.h>
#include <string.h>

static CRITICAL_SECTION s_lock;
static int s_init;
static DWORD s_last_frame, s_ping_next;
static int s_level;            /* -2..2: foreground .. background */
static float s_pan, s_dist = 300;
static int s_have;

/* settings (C commands) */
static int s_on = 1;
static float s_vol = 1.0f;
static float s_near = 80, s_far = 700;    /* cm: fastest / slowest ping */

static void init(void) { if (!s_init) { InitializeCriticalSection(&s_lock); s_init = 1; } }

void beacon_config(const char *key, float v) {
    init();
    EnterCriticalSection(&s_lock);
    if (!strcmp(key, "beacon")) s_on = v != 0;
    else if (!strcmp(key, "beacon_vol")) s_vol = v;
    else if (!strcmp(key, "master")) g_master = v;
    LeaveCriticalSection(&s_lock);
}

void beacon_frame(const float *v, int n) {
    if (n < 6) return;
    init();
    float dx = v[2] - v[0], dy = v[3] - v[1];
    float cx = v[4], cy = v[5];
    float cl = sqrtf(cx * cx + cy * cy);
    if (!(cl > 1e-3f)) return;
    cx /= cl; cy /= cl;
    float len = sqrtf(dx * dx + dy * dy);
    /* UE: X forward, Y right (left-handed), so screen right = (-cy, cx) */
    float screen = dx * -cy + dy * cx, depth = dx * cx + dy * cy;
    EnterCriticalSection(&s_lock);
    s_last_frame = GetTickCount();
    s_dist = len;
    if (len > 20) {
        float dep = depth / len, a = fabsf(dep);
        int m = s_level < 0 ? -s_level : s_level;
        if (m == 0) { if (a > 0.27f) m = a > 0.55f ? 2 : 1; }
        else if (m == 1) { if (a > 0.55f) m = 2; else if (a < 0.17f) m = 0; }
        else if (a < 0.45f) m = a < 0.17f ? 0 : 1;
        int lv = dep < 0 ? -m : m;
        if (lv != s_level) log_line("beacon level %d (depth %.2f, dist %.0f)", lv, dep, len);
        s_level = lv;
        s_pan = 0.85f * screen / len;
    }
    s_have = 1;
    LeaveCriticalSection(&s_lock);
}

void beacon_off(void) {
    init();
    EnterCriticalSection(&s_lock);
    s_have = 0; s_level = 0;
    LeaveCriticalSection(&s_lock);
}

void beacon_tick(void) {
    init();
    DWORD now = GetTickCount();
    EnterCriticalSection(&s_lock);
    int live = s_have && s_on && now - s_last_frame < 300;
    float dist = s_dist, pan = s_pan, vol = s_vol; int level = s_level;
    LeaveCriticalSection(&s_lock);
    if (!live || now < s_ping_next) return;
    float k = (s_far - dist) / (s_far - s_near);
    if (k < 0) k = 0; if (k > 1) k = 1;
    static const int semis_for[5] = { -12, -5, 0, 5, 12 };
    float g = (0.12f + 0.06f * k) * vol;
    float f2 = 520 * powf(2, semis_for[level + 2] / 12.0f);
    tone_at(0, 520, 520, 0.08f, g, pan, W_SOFT);
    tone_at(0.11f, f2, f2, 0.08f, g, pan, W_SOFT);
    s_ping_next = now + (DWORD)(250 + 750 * (1 - k));
}
