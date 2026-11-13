/*
 * Wall cues. The stage walls are PolarisStageWallActor boxes (a 100 cm cube
 * mesh scaled and turned: 32 m long, 6 m thick ...). The mod sends the boxes
 * of the floor the player stands on ("W n  cx cy hx hy cos sin kind ..."),
 * and the helper casts rays from the fighters every frame (positions come
 * with the beacon's "F" line):
 *
 *   behind you        (away from the opponent) low soft hum on your side of
 *                     the screen, 110-150 Hz, from 2.5 m of space left
 *   behind opponent   the same hum a fifth up, quieter, on their side, from 2 m
 *   sidestep up       (into the background) pulsing hum 294 Hz, centre
 *   sidestep down     (toward the camera) pulsing hum 196 Hz, centre
 *                     both from 1.5 m; the pulse turns fast once a sidestep
 *                     that way is blocked (under 60 cm left)
 *
 * Space = distance to the wall face minus the body: in Rebel Hangar the
 * fighters stopped 32-70 cm short of the face (2026-11-12). The low wall hum
 * is SC2 Access's (the user's choice there, 2026-10-14).
 */
#include "access.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

#define MAXW 64
#define BODY 40.0f

typedef struct { float cx, cy, hx, hy, c, s; int kind; } Box;

static CRITICAL_SECTION s_lock;
static int s_init;
static Box s_box[MAXW];
static int s_n;
static int s_on = 1;
static float s_vol = 1.0f;
/* this frame */
static float s_back = 1e9f, s_opp = 1e9f, s_up = 1e9f, s_down = 1e9f;
static int s_kback, s_kopp, s_kup, s_kdown;
static float s_pan_back;
static DWORD s_frame_t;
static int s_have;

static void init(void) { if (!s_init) { InitializeCriticalSection(&s_lock); s_init = 1; } }

/* "W n cx cy hx hy c s kind ..." (n = 0 clears) */
void walls_set(const float *v, int k) {
    init();
    EnterCriticalSection(&s_lock);
    int n = k > 0 ? (int)v[0] : 0;
    if (n > MAXW) n = MAXW;
    if (1 + n * 7 > k) n = (k - 1) / 7;
    for (int i = 0; i < n; i++) {
        const float *b = v + 1 + i * 7;
        s_box[i] = (Box){ b[0], b[1], b[2], b[3], b[4], b[5], (int)b[6] };
    }
    s_n = n;
    LeaveCriticalSection(&s_lock);
    log_line("walls: %d boxes", n);
}

/* distance along unit d from p to the nearest box (0 inside one); kind out */
static float ray(float px, float py, float dx, float dy, int *kind) {
    float best = 1e9f; int bk = 0;
    for (int i = 0; i < s_n; i++) {
        const Box *b = &s_box[i];
        /* into the box's frame */
        float rx = px - b->cx, ry = py - b->cy;
        float lx = rx * b->c + ry * b->s, ly = -rx * b->s + ry * b->c;
        float ex = dx * b->c + dy * b->s, ey = -dx * b->s + dy * b->c;
        float t0 = 0, t1 = 1e9f;
        float o[2] = { lx, ly }, e[2] = { ex, ey }, h[2] = { b->hx, b->hy };
        int miss = 0;
        for (int a = 0; a < 2 && !miss; a++) {
            if (fabsf(e[a]) < 1e-6f) { if (o[a] < -h[a] || o[a] > h[a]) miss = 1; continue; }
            float ta = (-h[a] - o[a]) / e[a], tb = (h[a] - o[a]) / e[a];
            if (ta > tb) { float t = ta; ta = tb; tb = t; }
            if (ta > t0) t0 = ta;
            if (tb < t1) t1 = tb;
            if (t0 > t1) miss = 1;
        }
        if (!miss && t0 < best) { best = t0; bk = b->kind; }
    }
    if (kind) *kind = bk;
    return best;
}

/* called with every beacon frame: me, opponent, camera forward (normalised) */
void walls_frame(float mx, float my, float ox, float oy, float cx, float cy) {
    init();
    float ux = ox - mx, uy = oy - my, len = sqrtf(ux * ux + uy * uy);
    EnterCriticalSection(&s_lock);
    s_frame_t = GetTickCount();
    if (s_n == 0 || len < 1) { s_have = s_n > 0 && s_have; LeaveCriticalSection(&s_lock); return; }
    ux /= len; uy /= len;
    /* sidestep axis: across the fight line, "up" = the side away from the camera */
    float nx = -uy, ny = ux;
    if (nx * cx + ny * cy < 0) { nx = -nx; ny = -ny; }
    s_back = ray(mx, my, -ux, -uy, &s_kback) - BODY;
    s_opp  = ray(ox, oy, ux, uy, &s_kopp) - BODY;
    s_up   = ray(mx, my, nx, ny, &s_kup) - BODY;
    s_down = ray(mx, my, -nx, -ny, &s_kdown) - BODY;
    /* screen right = (-cy, cx): the back wall's side of the screen */
    s_pan_back = 0.8f * (-ux * -cy + -uy * cx);
    s_have = 1;
    LeaveCriticalSection(&s_lock);
}

void walls_off(void) {
    init();
    EnterCriticalSection(&s_lock);
    s_have = 0;
    LeaveCriticalSection(&s_lock);
}

void walls_config(const char *key, float v) {
    init();
    EnterCriticalSection(&s_lock);
    if (!strcmp(key, "walls")) s_on = v != 0;
    else if (!strcmp(key, "walls_vol")) s_vol = v;
    LeaveCriticalSection(&s_lock);
}

static float closeness(float space, float range) {
    if (space < 0) space = 0;
    float k = (range - space) / range;
    return k < 0 ? 0 : k > 1 ? 1 : k;
}

/* hums 0-3; from the helper's main loop every ~20 ms */
void walls_tick(void) {
    init();
    EnterCriticalSection(&s_lock);
    int live = s_have && s_on && s_n > 0 && GetTickCount() - s_frame_t < 300;
    float back = s_back, opp = s_opp, up = s_up, down = s_down, pan = s_pan_back, vol = s_vol;
    LeaveCriticalSection(&s_lock);
    static int was_live = 1;
    if (!live) {
        if (was_live) { for (int i = 0; i < 4; i++) hum_set(i, 0, 0, 0, W_SOFT); hum_trem(2, 0); hum_trem(3, 0); }
        was_live = 0;
        return;
    }
    was_live = 1;
    /* log each cue starting, stopping or turning blocked (testing without ears) */
    static int last_state = -1;
    int st = (back < 250) | (opp < 200) << 1 | (up < 150) << 2 | (down < 150) << 3 | (up < 60) << 4 | (down < 60) << 5;
    if (st != last_state) {
        log_line("walls: back %.0f opp %.0f up %.0f down %.0f cm%s%s%s%s%s%s", back, opp, up, down,
                 st & 1 ? " [back]" : "", st & 2 ? " [opp]" : "", st & 4 ? " [up]" : "", st & 8 ? " [down]" : "",
                 st & 16 ? " [up blocked]" : "", st & 32 ? " [down blocked]" : "");
        last_state = st;
    }
    float k = closeness(back, 250);
    hum_set(0, 110 + 40 * k, k > 0 ? (0.05f + 0.30f * k * k) * vol : 0, pan, W_SOFT);
    k = closeness(opp, 200);
    hum_set(1, 165 + 55 * k, k > 0 ? (0.03f + 0.17f * k * k) * vol : 0, -pan, W_SOFT);
    k = closeness(up, 150);
    hum_set(2, 294, k > 0 ? (0.04f + 0.18f * k * k) * vol : 0, 0, W_SOFT);
    hum_trem(2, up < 60 ? 9.0f : 3.0f);
    k = closeness(down, 150);
    hum_set(3, 196, k > 0 ? (0.05f + 0.20f * k * k) * vol : 0, 0, W_SOFT);
    hum_trem(3, down < 60 ? 9.0f : 3.0f);
}

static const char *kind_name(int k) { return k == 2 ? "Balcony" : k == 1 ? "Breakable wall" : "Wall"; }

static int part(char *buf, int n, int size, float dist, int kind, const char *where) {
    if (dist > 5000 || n >= size) return n;      /* no wall that way (or very far) */
    return n + snprintf(buf + n, size - n, "%s %s %.1f meters. ", kind_name(kind), where, (dist < 0 ? 0 : dist) / 100);
}

/* F5: the walls around you, in words (queued after the mod's status line) */
void walls_say(void) {
    init();
    EnterCriticalSection(&s_lock);
    int ok = s_have && s_n > 0 && GetTickCount() - s_frame_t < 1000;
    float back = s_back, opp = s_opp, up = s_up, down = s_down;
    int kb = s_kback, ko = s_kopp, ku = s_kup, kd = s_kdown;
    LeaveCriticalSection(&s_lock);
    if (!ok) { speak(L"No walls on this stage.", 0); return; }
    char buf[400]; int n = 0;
    n = part(buf, n, sizeof buf, back, kb, "behind you");
    n = part(buf, n, sizeof buf, opp, ko, "behind opponent");
    if (up < 60) n += snprintf(buf + n, sizeof buf - n, "Sidestep up blocked. ");
    else n = part(buf, n, sizeof buf, up, ku, "up");
    if (down < 60 && n < (int)sizeof buf) n += snprintf(buf + n, sizeof buf - n, "Sidestep down blocked. ");
    else n = part(buf, n, sizeof buf, down, kd, "down");
    if (!n) snprintf(buf, sizeof buf, "No walls near.");
    speak_utf8(buf, 0);
}
