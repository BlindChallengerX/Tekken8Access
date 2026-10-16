/* TekkenA11y helper: speech (Prism) and cue audio for the Tekken 8 UE4SS mod.
 * The Lua mod sends one command per line through \\.\pipe\TekkenA11y. */
#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

extern wchar_t g_mod_dir[MAX_PATH];     /* folder of the exe, ends with a backslash */
void log_line(const char *fmt, ...);
char *to_utf8(const wchar_t *w);
wchar_t *from_utf8(const char *s);

/* speech.c */
void speech_init(void);
void speak(const wchar_t *text, int interrupt);
void speak_utf8(const char *text, int interrupt);
void speech_stop(void);

/* audio.c */
enum { W_SINE, W_SQUARE, W_TRI, W_SAW, W_NOISE, W_WIND, W_REED, W_SOFT };
void audio_init(void);
void tone(float f0, float f1, float seconds, float gain, float pan, int wave);
void tone_at(float delay, float f0, float f1, float seconds, float gain, float pan, int wave);
void hum_set(int slot, float freq, float gain, float pan, int wave);
void hum_all_off(void);
extern volatile float g_master;

/* beacon.c */
void beacon_frame(const float *v, int n);
void beacon_off(void);
void beacon_tick(void);
void beacon_config(const char *key, float value);
