#ifndef ANDROID_STUB_LOG_H
#define ANDROID_STUB_LOG_H
#include <stdio.h>
#define ANDROID_LOG_ERROR 6
#define ANDROID_LOG_INFO 4
#define ALOGE(...) fprintf(stderr, __VA_ARGS__)
#define ALOGI(...) fprintf(stderr, __VA_ARGS__)
#endif
