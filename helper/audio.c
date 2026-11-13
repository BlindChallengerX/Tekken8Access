/*
 * Audio for TekkenA11y: a small synth on its own waveOut stream (44.1 kHz
 * stereo, 4 buffers of 15 ms, so cues lag the game by under 60 ms).
 *
 * Two kinds of sound:
 *   tones  one-shots that glide from f0 to f1 with a short attack and decay
 *   hums   continuous voices (slot 0..7) whose pitch, loudness and pan
 *          follow targets smoothly, for things that are always there.
 *          W_WIND is noise through a band-pass at the hum's pitch with a
 *          slow gusting swell (the ring-edge drop-off).
 */
#include "access.h"
#include <math.h>
#include <mmsystem.h>
#include <string.h>

#define RATE 44100
#define BUF_FRAMES 662
#define NBUF 4
#define NTONES 48
#define NHUMS 8
#define PI2 6.28318530718f

typedef struct {
    int on; float delay; float t, len, f0, f1, gain, pan, phase; int wave;
    float lp, bp;                     /* W_SWISH band-pass state */
} Tone;
typedef struct {
    float freq, gain, pan;            /* targets */
    float cf, cg, cp, phase;          /* current */
    int wave;
    float lp, bp, gust;               /* W_WIND filter state, gust phase */
    float trem, tph;                  /* pulse rate (Hz, 0 = steady) and phase */
} Hum;

static CRITICAL_SECTION s_lock;
static Tone s_tones[NTONES];
static Hum s_hums[NHUMS];
static uint32_t s_noise = 22222;
volatile float g_master = 1.2f;
static volatile LONG s_bufs_done, s_open_ok;
static volatile float s_peak;
static volatile int s_active_tones;

static float osc(int wave, float ph) {
    switch (wave) {
    case W_SQUARE: return ph < 0.5f ? 0.6f : -0.6f;
    case W_TRI:    return ph < 0.5f ? 4 * ph - 1 : 3 - 4 * ph;
    case W_SAW:    return (2 * ph - 1) * 0.7f;
    case W_NOISE:  s_noise = s_noise * 1664525u + 1013904223u; return ((s_noise >> 9) / 4194304.0f - 1.0f) * 0.7f;
    case W_SOFT:   /* muffled beep: a sine with a little second harmonic */
        return (sinf(PI2 * ph) + 0.12f * sinf(2 * PI2 * ph)) * 0.85f;
    case W_REED: {
        /* Mist World's beacon tone: harmonics 1-11, strong odd, weak even */
        static const float amp[11] = { 1.0f, 0.125f, 0.5f, 0.0625f, 0.25f, 0.0234f, 0.0938f, 0.0078f, 0.0313f, 0.0039f, 0.0078f };
        float v = 0;
        for (int k = 0; k < 11; k++) v += amp[k] * sinf(PI2 * ph * (k + 1));
        return v * 0.45f;
    }
    default:       return sinf(PI2 * ph);
    }
}

/* A NaN anywhere would silence the whole mix for good: refuse bad values. */
static int bad(float v) { return !isfinite(v); }

void tone_at(float delay, float f0, float f1, float seconds, float gain, float pan, int wave) {
    if (bad(delay) || bad(f0) || bad(f1) || bad(seconds) || bad(gain) || bad(pan) || f0 <= 0 || f1 <= 0 || seconds <= 0) {
        log_line("audio: bad tone %g %g %g %g %g %g", delay, f0, f1, seconds, gain, pan);
        return;
    }
    EnterCriticalSection(&s_lock);
    int pick = 0; float best = -1;
    for (int i = 0; i < NTONES; i++) {
        if (!s_tones[i].on) { pick = i; best = 1e9f; break; }
        float left = s_tones[i].len - s_tones[i].t;
        if (best < 0 || left < best) { best = left; pick = i; }
    }
    Tone *t = &s_tones[pick];
    t->on = 1; t->delay = delay; t->t = 0; t->len = seconds; t->f0 = f0; t->f1 = f1;
    t->gain = gain; t->pan = pan < -1 ? -1 : pan > 1 ? 1 : pan; t->phase = 0; t->wave = wave; t->lp = t->bp = 0;
    LeaveCriticalSection(&s_lock);
}

void tone(float f0, float f1, float seconds, float gain, float pan, int wave) {
    tone_at(0, f0, f1, seconds, gain, pan, wave);
}

void hum_set(int slot, float freq, float gain, float pan, int wave) {
    if (slot < 0 || slot >= NHUMS) return;
    if (bad(freq) || bad(gain) || bad(pan)) {
        static DWORD last;
        if (GetTickCount() - last > 2000) { last = GetTickCount(); log_line("audio: bad hum %d %g %g %g", slot, freq, gain, pan); }
        freq = 200; gain = 0; pan = 0;
    }
    EnterCriticalSection(&s_lock);
    Hum *h = &s_hums[slot];
    if (h->cg < 0.001f) { h->cf = freq; h->cp = pan; }   /* starting from silence: jump to the pitch */
    h->freq = freq; h->gain = gain; h->pan = pan < -1 ? -1 : pan > 1 ? 1 : pan; h->wave = wave;
    LeaveCriticalSection(&s_lock);
}

/* pulse a hum: its level swells and dips `rate` times a second (0 = steady) */
void hum_trem(int slot, float rate) {
    if (slot < 0 || slot >= NHUMS || bad(rate)) return;
    EnterCriticalSection(&s_lock);
    s_hums[slot].trem = rate;
    LeaveCriticalSection(&s_lock);
}

void hum_all_off(void) {
    EnterCriticalSection(&s_lock);
    for (int i = 0; i < NHUMS; i++) s_hums[i].gain = 0;
    LeaveCriticalSection(&s_lock);
}

static void mix(short *out, int frames) {
    static float buf[BUF_FRAMES * 2];
    memset(buf, 0, sizeof buf);
    const float dt = 1.0f / RATE;
    EnterCriticalSection(&s_lock);
    for (int i = 0; i < NTONES; i++) {
        Tone *t = &s_tones[i];
        if (!t->on) continue;
        float lg = sqrtf(0.5f * (1 - t->pan)), rg = sqrtf(0.5f * (1 + t->pan));
        for (int n = 0; n < frames; n++) {
            if (t->delay > 0) { t->delay -= dt; continue; }
            if (t->t >= t->len) { t->on = 0; break; }
            float k = t->t / t->len;
            float f = t->f0 * powf(t->f1 / t->f0, k);
            /* short notes get a short release; W_SOFT fades in and out gently */
            float att = t->wave == W_SOFT ? 0.015f : t->wave == W_SWISH ? t->len * 0.35f : 0.004f;
            float rel = t->wave == W_SOFT || t->wave == W_SWISH ? t->len * 0.5f : fminf(0.03f, t->len * 0.25f);
            float env = fminf(1.0f, t->t / att) * fminf(1.0f, (t->len - t->t) / rel);
            float s;
            if (t->wave == W_SWISH) {
                /* swing whoosh: noise through a band-pass that follows the glide */
                float c = 2 * sinf(3.14159265f * fminf(f, 8000.0f) / RATE);
                float x = osc(W_NOISE, 0);
                t->lp += c * t->bp;
                t->bp += c * (x - t->lp - 0.5f * t->bp);
                if (!isfinite(t->bp) || !isfinite(t->lp)) t->lp = t->bp = 0;
                s = t->bp * 1.6f * env * t->gain;
            } else s = osc(t->wave, t->phase) * env * t->gain;
            t->phase += f * dt; t->phase -= floorf(t->phase);
            buf[2 * n] += s * lg; buf[2 * n + 1] += s * rg;
            t->t += dt;
        }
    }
    for (int i = 0; i < NHUMS; i++) {
        Hum *h = &s_hums[i];
        if (h->gain < 0.001f && h->cg < 0.0005f) { h->cg = 0; continue; }
        for (int n = 0; n < frames; n++) {
            h->cg += (h->gain - h->cg) * 0.0015f;
            h->cf += (h->freq - h->cf) * 0.002f;
            h->cp += (h->pan - h->cp) * 0.002f;
            float s;
            if (h->wave == W_WIND) {
                /* two slow LFOs make uneven gusts; they swell the level and
                 * sweep the filter so it whooshes rather than hisses */
                h->gust += dt * 0.21f; if (h->gust >= 100) h->gust -= 100;
                float g = 0.5f + 0.5f * sinf(PI2 * h->gust) * (0.6f + 0.4f * sinf(PI2 * h->gust * 2.7f));
                float fc = h->cf * (0.7f + 0.6f * g);
                float c = 2 * sinf(3.14159265f * fminf(fc, 6000.0f) / RATE);
                float x = osc(W_NOISE, 0);
                h->lp += c * h->bp;
                h->bp += c * (x - h->lp - 0.9f * h->bp);
                s = h->bp * 2.2f * (0.55f + 0.45f * g) * h->cg;
            } else {
                s = osc(h->wave, h->phase) * h->cg;
                h->phase += h->cf * dt; h->phase -= floorf(h->phase);
                if (h->trem > 0) {
                    h->tph += h->trem * dt; h->tph -= floorf(h->tph);
                    float w = 0.5f + 0.5f * sinf(PI2 * h->tph);
                    s *= 0.12f + 0.88f * w * w;
                }
            }
            buf[2 * n] += s * sqrtf(0.5f * (1 - h->cp)); buf[2 * n + 1] += s * sqrtf(0.5f * (1 + h->cp));
        }
    }
    LeaveCriticalSection(&s_lock);
    float m = g_master, pk = 0;
    for (int n = 0; n < frames * 2; n++) {
        if (!isfinite(buf[n])) {
            buf[n] = 0;
            EnterCriticalSection(&s_lock);
            for (int i = 0; i < NHUMS; i++) if (!isfinite(s_hums[i].cg) || !isfinite(s_hums[i].cf) || !isfinite(s_hums[i].cp) || !isfinite(s_hums[i].phase) || !isfinite(s_hums[i].bp) || !isfinite(s_hums[i].lp)) memset(&s_hums[i], 0, sizeof s_hums[i]);
            for (int i = 0; i < NTONES; i++) if (!isfinite(s_tones[i].phase)) s_tones[i].on = 0;
            LeaveCriticalSection(&s_lock);
        }
        float v = tanhf(buf[n] * m) * 30000.0f;
        out[n] = (short)v;
        if (fabsf(v) > pk) pk = fabsf(v);
    }
    if (pk > s_peak) s_peak = pk;
}

static DWORD WINAPI audio_thread(LPVOID unused) {
    (void)unused;
    HANDLE ev = CreateEventW(NULL, FALSE, FALSE, NULL);
    WAVEFORMATEX wf; memset(&wf, 0, sizeof wf);
    wf.wFormatTag = WAVE_FORMAT_PCM; wf.nChannels = 2; wf.nSamplesPerSec = RATE;
    wf.wBitsPerSample = 16; wf.nBlockAlign = 4; wf.nAvgBytesPerSec = RATE * 4;
    HWAVEOUT wo;
    if (waveOutOpen(&wo, WAVE_MAPPER, &wf, (DWORD_PTR)ev, 0, CALLBACK_EVENT) != MMSYSERR_NOERROR) {
        log_line("audio: waveOutOpen failed"); return 0;
    }
    s_open_ok = 1;
    log_line("audio: stream open");
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    static short data[NBUF][BUF_FRAMES * 2];
    WAVEHDR hdr[NBUF];
    for (int i = 0; i < NBUF; i++) {
        memset(&hdr[i], 0, sizeof hdr[i]);
        hdr[i].lpData = (LPSTR)data[i]; hdr[i].dwBufferLength = sizeof data[i];
        mix(data[i], BUF_FRAMES);
        waveOutPrepareHeader(wo, &hdr[i], sizeof hdr[i]);
        waveOutWrite(wo, &hdr[i], sizeof hdr[i]);
    }
    for (;;) {
        WaitForSingleObject(ev, 100);
        for (int i = 0; i < NBUF; i++) {
            if (hdr[i].dwFlags & WHDR_DONE) {
                s_bufs_done++;
                mix(data[i], BUF_FRAMES);
                waveOutWrite(wo, &hdr[i], sizeof hdr[i]);
            }
        }
    }
    return 0;
}

void audio_init(void) {
    InitializeCriticalSection(&s_lock);
    CloseHandle(CreateThread(NULL, 0, audio_thread, NULL, 0, NULL));
}

void audio_stat(void) {
    int tones = 0;
    EnterCriticalSection(&s_lock);
    for (int i = 0; i < NTONES; i++) tones += s_tones[i].on;
    int hums = 0; for (int i = 0; i < NHUMS; i++) hums += s_hums[i].cg > 0.001f;
    LeaveCriticalSection(&s_lock);
    log_line("audio: open %ld, buffers played %ld, tones on %d, hums on %d, peak %.0f, master %.2f", s_open_ok, s_bufs_done, tones, hums, s_peak, g_master);
    s_peak = 0;
}
