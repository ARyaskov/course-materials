#define _POSIX_C_SOURCE 200809L
#include "util/clock.h"

#include <stdio.h>
#include <time.h>

uint64_t nst_now_mono_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

uint64_t nst_now_wall_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

void nst_format_time_ms(uint64_t ms, char buf[static 32]) {
    time_t secs = (time_t)(ms / 1000u);
    unsigned frac = (unsigned)(ms % 1000u);
    struct tm tm_buf;
    gmtime_r(&secs, &tm_buf);
    char base[24];
    strftime(base, sizeof base, "%Y-%m-%dT%H:%M:%S", &tm_buf);
    snprintf(buf, 32, "%s.%03uZ", base, frac);
}
