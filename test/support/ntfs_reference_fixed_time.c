/* Original fixed wall clock for external fixture tools. SPDX-License-Identifier: MIT. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/time.h>
#include <time.h>

time_t time(time_t *result) {
  const time_t fixed = 946684800;
  if (result) *result = fixed;
  return fixed;
}

int gettimeofday(struct timeval *tv, void *tz) {
  (void)tz;
  tv->tv_sec = 946684800; tv->tv_usec = 0;
  return 0;
}

int clock_gettime(clockid_t id, struct timespec *value) {
  if (id == CLOCK_REALTIME || id == CLOCK_REALTIME_COARSE) {
    value->tv_sec = 946684800; value->tv_nsec = 0;
    return 0;
  }
  static int (*original)(clockid_t, struct timespec *);
  if (!original) original = dlsym(RTLD_NEXT, "clock_gettime");
  return original(id, value);
}
