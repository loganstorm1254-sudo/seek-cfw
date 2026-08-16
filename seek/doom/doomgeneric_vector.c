// doomgeneric_vector.c — SeekOS / Anki Vector face port
//
// Renders Doom to 184x96 RGB565 and sends frames to wired over a Unix
// socket. Reads key events from /run/seek-doom/keys (dashboard + API).

#include "doomkeys.h"
#include "doomgeneric.h"
#include "m_argv.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef DOOMGENERIC_RESX
#define DOOMGENERIC_RESX 320
#endif
#ifndef DOOMGENERIC_RESY
#define DOOMGENERIC_RESY 200
#endif

#define FACE_W 184
#define FACE_H 96
#define FACE_BYTES (FACE_W * FACE_H * 2)

#define KEYQUEUE_SIZE 64
#define FRAME_SOCK_PATH "/run/seek-doom/frames.sock"
#define KEYS_PATH "/run/seek-doom/keys"

static struct timeval startTime;
static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int s_KeyQueueWriteIndex;
static unsigned int s_KeyQueueReadIndex;
static int s_keysFd = -1;
static int s_frameFd = -1;
static uint16_t s_face[FACE_W * FACE_H];

static void addKeyToQueue(int pressed, unsigned char key)
{
	unsigned short keyData = (unsigned short)((pressed << 8) | key);
	s_KeyQueue[s_KeyQueueWriteIndex] = keyData;
	s_KeyQueueWriteIndex = (s_KeyQueueWriteIndex + 1) % KEYQUEUE_SIZE;
}

static void drainKeysFile(void)
{
	if (s_keysFd < 0) {
		s_keysFd = open(KEYS_PATH, O_RDONLY | O_NONBLOCK);
		if (s_keysFd < 0) {
			return;
		}
	}
	for (;;) {
		unsigned char pair[2];
		ssize_t n = read(s_keysFd, pair, 2);
		if (n == 2) {
			addKeyToQueue(pair[0] ? 1 : 0, pair[1]);
			continue;
		}
		if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			break;
		}
		if (n == 0) {
			// Writers closed — reopen next tick.
			close(s_keysFd);
			s_keysFd = -1;
			break;
		}
		if (n == 1) {
			// Partial — push back not supported; drop.
			break;
		}
		break;
	}
}

static int connectFrameSocket(void)
{
	if (s_frameFd >= 0) {
		return 0;
	}
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0) {
		return -1;
	}
	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, FRAME_SOCK_PATH, sizeof(addr.sun_path) - 1);
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}
	s_frameFd = fd;
	return 0;
}

static void scaleToFace(void)
{
	// Nearest-neighbor scale DOOMGENERIC_RES → 184x96, RGB888 → RGB565 BE
	// (Vector face expects high-byte-first RGB565, same as Seek Media).
	const pixel_t *src = DG_ScreenBuffer;
	for (int y = 0; y < FACE_H; y++) {
		int sy = (y * DOOMGENERIC_RESY) / FACE_H;
		for (int x = 0; x < FACE_W; x++) {
			int sx = (x * DOOMGENERIC_RESX) / FACE_W;
			pixel_t p = src[sy * DOOMGENERIC_RESX + sx];
			unsigned r = (p >> 16) & 0xff;
			unsigned g = (p >> 8) & 0xff;
			unsigned b = p & 0xff;
			uint16_t rgb565 = (uint16_t)(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
			// big-endian store for Vector LCD path via DisplayFaceImageRGB
			s_face[y * FACE_W + x] = (uint16_t)((rgb565 << 8) | (rgb565 >> 8));
		}
	}
}

void DG_Init(void)
{
	gettimeofday(&startTime, NULL);
	s_KeyQueueWriteIndex = 0;
	s_KeyQueueReadIndex = 0;
	memset(s_KeyQueue, 0, sizeof(s_KeyQueue));
	// Best-effort connect; wired may come up a moment later.
	(void)connectFrameSocket();
	s_keysFd = open(KEYS_PATH, O_RDONLY | O_NONBLOCK);
}

void DG_DrawFrame(void)
{
	drainKeysFile();
	scaleToFace();
	if (connectFrameSocket() != 0) {
		return;
	}
	// Packet: "FRAM" + RGB565 face
	unsigned char pkt[4 + FACE_BYTES];
	pkt[0] = 'F';
	pkt[1] = 'R';
	pkt[2] = 'A';
	pkt[3] = 'M';
	memcpy(pkt + 4, s_face, FACE_BYTES);
	size_t off = 0;
	while (off < sizeof(pkt)) {
		ssize_t n = send(s_frameFd, pkt + off, sizeof(pkt) - off, MSG_NOSIGNAL);
		if (n <= 0) {
			close(s_frameFd);
			s_frameFd = -1;
			return;
		}
		off += (size_t)n;
	}
}

void DG_SleepMs(uint32_t ms)
{
	usleep(ms * 1000);
}

uint32_t DG_GetTicksMs(void)
{
	struct timeval now;
	gettimeofday(&now, NULL);
	uint32_t ticks = (now.tv_sec - startTime.tv_sec) * 1000;
	ticks += (now.tv_usec - startTime.tv_usec) / 1000;
	return ticks;
}

int DG_GetKey(int *pressed, unsigned char *doomKey)
{
	drainKeysFile();
	if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex) {
		return 0;
	}
	unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];
	s_KeyQueueReadIndex = (s_KeyQueueReadIndex + 1) % KEYQUEUE_SIZE;
	*pressed = keyData >> 8;
	*doomKey = keyData & 0xff;
	return 1;
}

void DG_SetWindowTitle(const char *title)
{
	(void)title;
}

int main(int argc, char **argv)
{
	doomgeneric_Create(argc, argv);
	for (;;) {
		doomgeneric_Tick();
	}
	return 0;
}
