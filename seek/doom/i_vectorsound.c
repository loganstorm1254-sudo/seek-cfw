// i_vectorsound.c — SeekOS Vector sound backend for doomgeneric
//
// Mixes Doom SFX to mono s16le @ 16 kHz and streams them over a Unix
// socket to wired, which plays via ExternalAudioStreamPlayback (speaker).

#include "config.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "deh_str.h"
#include "doomtype.h"
#include "i_sound.h"
#include "m_misc.h"
#include "w_wad.h"
#include "z_zone.h"

#define NUM_CHANNELS 8
#define OUT_RATE 16000
#define MIX_SLICE 512
#define AUDIO_SOCK_PATH "/run/seek-doom/audio.sock"

// Symbols referenced by i_sound.c when FEATURE_SOUND is set.
int use_libsamplerate = 0;
float libsamplerate_scale = 0.65f;

typedef struct {
	int16_t *data;
	unsigned int len; // samples
} cached_sfx_t;

typedef struct {
	cached_sfx_t *sfx;
	unsigned int pos;
	int vol; // 0-127
	boolean active;
} channel_t;

static boolean sound_initialized = false;
static boolean use_sfx_prefix = true;
static channel_t channels[NUM_CHANNELS];
static int audio_fd = -1;
static int16_t mixbuf[MIX_SLICE];

static snddevice_t sound_devices[] = { SNDDEVICE_SB };

static void close_audio(void)
{
	if (audio_fd >= 0) {
		close(audio_fd);
		audio_fd = -1;
	}
}

static int connect_audio(void)
{
	if (audio_fd >= 0) {
		return 0;
	}
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0) {
		return -1;
	}
	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, AUDIO_SOCK_PATH, sizeof(addr.sun_path) - 1);
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}
	// Non-blocking so a stalled speaker path cannot freeze the game loop.
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags >= 0) {
		fcntl(fd, F_SETFL, flags | O_NONBLOCK);
	}
	audio_fd = fd;
	return 0;
}

static void GetSfxLumpName(sfxinfo_t *sfx, char *buf, size_t buf_len)
{
	if (sfx->link != NULL) {
		sfx = sfx->link;
	}
	if (use_sfx_prefix) {
		M_snprintf(buf, buf_len, "ds%s", DEH_String(sfx->name));
	} else {
		M_snprintf(buf, buf_len, "%s", DEH_String(sfx->name));
	}
}

static boolean CacheSFX(sfxinfo_t *sfxinfo)
{
	int lumpnum = sfxinfo->lumpnum;
	byte *data = W_CacheLumpNum(lumpnum, PU_STATIC);
	unsigned int lumplen = W_LumpLength(lumpnum);

	if (lumplen < 8 || data[0] != 0x03 || data[1] != 0x00) {
		W_ReleaseLumpNum(lumpnum);
		return false;
	}

	int samplerate = (data[3] << 8) | data[2];
	unsigned int length = (data[7] << 24) | (data[6] << 16) | (data[5] << 8) | data[4];
	if (samplerate <= 0 || length > lumplen - 8 || length <= 48) {
		W_ReleaseLumpNum(lumpnum);
		return false;
	}

	// DMX skips first/last 16 bytes of sample data.
	data += 16;
	length -= 32;

	// Resample 8-bit unsigned @ samplerate → s16le @ OUT_RATE
	unsigned int out_len = (unsigned int)((uint64_t)length * OUT_RATE / (unsigned)samplerate);
	if (out_len < 1) {
		out_len = 1;
	}
	int16_t *out = (int16_t *)malloc(out_len * sizeof(int16_t));
	if (out == NULL) {
		W_ReleaseLumpNum(lumpnum);
		return false;
	}

	for (unsigned int i = 0; i < out_len; i++) {
		uint64_t src_pos = (uint64_t)i * (unsigned)samplerate;
		unsigned int idx = (unsigned int)(src_pos / OUT_RATE);
		if (idx >= length) {
			idx = length - 1;
		}
		int sample = (int)data[idx] - 128; // signed 8-bit
		out[i] = (int16_t)(sample << 8);
	}

	cached_sfx_t *cached = (cached_sfx_t *)malloc(sizeof(cached_sfx_t));
	if (cached == NULL) {
		free(out);
		W_ReleaseLumpNum(lumpnum);
		return false;
	}
	cached->data = out;
	cached->len = out_len;
	sfxinfo->driver_data = cached;

	W_ReleaseLumpNum(lumpnum);
	return true;
}

static void free_cached(sfxinfo_t *sfxinfo)
{
	if (sfxinfo->driver_data == NULL) {
		return;
	}
	cached_sfx_t *c = (cached_sfx_t *)sfxinfo->driver_data;
	free(c->data);
	free(c);
	sfxinfo->driver_data = NULL;
}

static void I_Vector_PrecacheSounds(sfxinfo_t *sounds, int num_sounds)
{
	char namebuf[9];
	for (int i = 0; i < num_sounds; i++) {
		GetSfxLumpName(&sounds[i], namebuf, sizeof(namebuf));
		sounds[i].lumpnum = W_CheckNumForName(namebuf);
		if (sounds[i].lumpnum != -1) {
			CacheSFX(&sounds[i]);
		}
	}
}

static int I_Vector_GetSfxLumpNum(sfxinfo_t *sfx)
{
	char namebuf[9];
	GetSfxLumpName(sfx, namebuf, sizeof(namebuf));
	return W_GetNumForName(namebuf);
}

static void I_Vector_UpdateSoundParams(int handle, int vol, int sep)
{
	(void)sep;
	if (!sound_initialized || handle < 0 || handle >= NUM_CHANNELS) {
		return;
	}
	if (vol < 0) {
		vol = 0;
	}
	if (vol > 127) {
		vol = 127;
	}
	channels[handle].vol = vol;
}

static int I_Vector_StartSound(sfxinfo_t *sfxinfo, int channel, int vol, int sep)
{
	(void)sep;
	if (!sound_initialized || channel < 0 || channel >= NUM_CHANNELS) {
		return -1;
	}
	if (sfxinfo->driver_data == NULL) {
		if (sfxinfo->lumpnum < 0) {
			char namebuf[9];
			GetSfxLumpName(sfxinfo, namebuf, sizeof(namebuf));
			sfxinfo->lumpnum = W_CheckNumForName(namebuf);
		}
		if (sfxinfo->lumpnum < 0 || !CacheSFX(sfxinfo)) {
			return -1;
		}
	}
	if (vol < 0) {
		vol = 0;
	}
	if (vol > 127) {
		vol = 127;
	}
	channels[channel].sfx = (cached_sfx_t *)sfxinfo->driver_data;
	channels[channel].pos = 0;
	channels[channel].vol = vol;
	channels[channel].active = true;
	return channel;
}

static void I_Vector_StopSound(int handle)
{
	if (handle < 0 || handle >= NUM_CHANNELS) {
		return;
	}
	channels[handle].active = false;
	channels[handle].sfx = NULL;
}

static boolean I_Vector_SoundIsPlaying(int handle)
{
	if (handle < 0 || handle >= NUM_CHANNELS) {
		return false;
	}
	return channels[handle].active;
}

static void mix_and_send(void)
{
	memset(mixbuf, 0, sizeof(mixbuf));

	for (int c = 0; c < NUM_CHANNELS; c++) {
		channel_t *ch = &channels[c];
		if (!ch->active || ch->sfx == NULL || ch->sfx->data == NULL) {
			continue;
		}
		for (unsigned int i = 0; i < MIX_SLICE; i++) {
			if (ch->pos >= ch->sfx->len) {
				ch->active = false;
				ch->sfx = NULL;
				break;
			}
			int s = (int)ch->sfx->data[ch->pos++];
			s = (s * ch->vol) / 127;
			int mixed = (int)mixbuf[i] + s;
			if (mixed > 32767) {
				mixed = 32767;
			}
			if (mixed < -32768) {
				mixed = -32768;
			}
			mixbuf[i] = (int16_t)mixed;
		}
	}

	if (connect_audio() != 0) {
		return;
	}

	const unsigned char *p = (const unsigned char *)mixbuf;
	size_t left = sizeof(mixbuf);
	while (left > 0) {
		ssize_t n = send(audio_fd, p, left, MSG_NOSIGNAL);
		if (n > 0) {
			p += (size_t)n;
			left -= (size_t)n;
			continue;
		}
		if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			// Drop remainder this slice rather than stall the game.
			break;
		}
		close_audio();
		break;
	}
}

static void I_Vector_UpdateSound(void)
{
	if (!sound_initialized) {
		return;
	}
	mix_and_send();
}

static boolean I_Vector_InitSound(boolean _use_sfx_prefix)
{
	use_sfx_prefix = _use_sfx_prefix;
	memset(channels, 0, sizeof(channels));
	sound_initialized = true;
	(void)connect_audio(); // best-effort; wired may come up a moment later
	return true;
}

static void I_Vector_ShutdownSound(void)
{
	for (int i = 0; i < NUM_CHANNELS; i++) {
		channels[i].active = false;
		channels[i].sfx = NULL;
	}
	close_audio();
	sound_initialized = false;
}

sound_module_t DG_sound_module = {
	sound_devices,
	arrlen(sound_devices),
	I_Vector_InitSound,
	I_Vector_ShutdownSound,
	I_Vector_GetSfxLumpNum,
	I_Vector_UpdateSound,
	I_Vector_UpdateSoundParams,
	I_Vector_StartSound,
	I_Vector_StopSound,
	I_Vector_SoundIsPlaying,
	I_Vector_PrecacheSounds,
};

// --- Stub music (keep -nomusic; module must exist for FEATURE_SOUND link) ---

static snddevice_t music_devices[] = { SNDDEVICE_GENMIDI };

static boolean I_Vector_InitMusic(void) { return true; }
static void I_Vector_ShutdownMusic(void) {}
static void I_Vector_SetMusicVolume(int volume) { (void)volume; }
static void I_Vector_PauseSong(void) {}
static void I_Vector_ResumeSong(void) {}
static void *I_Vector_RegisterSong(void *data, int len)
{
	(void)data;
	(void)len;
	return NULL;
}
static void I_Vector_UnRegisterSong(void *handle) { (void)handle; }
static void I_Vector_PlaySong(void *handle, boolean looping)
{
	(void)handle;
	(void)looping;
}
static void I_Vector_StopSong(void) {}
static boolean I_Vector_MusicIsPlaying(void) { return false; }
static void I_Vector_PollMusic(void) {}

music_module_t DG_music_module = {
	music_devices,
	arrlen(music_devices),
	I_Vector_InitMusic,
	I_Vector_ShutdownMusic,
	I_Vector_SetMusicVolume,
	I_Vector_PauseSong,
	I_Vector_ResumeSong,
	I_Vector_RegisterSong,
	I_Vector_UnRegisterSong,
	I_Vector_PlaySong,
	I_Vector_StopSong,
	I_Vector_MusicIsPlaying,
	I_Vector_PollMusic,
};

void I_InitTimidityConfig(void) {}
