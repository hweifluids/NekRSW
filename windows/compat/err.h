#pragma once

#ifdef _WIN32

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static inline void warn(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  if (errno) {
    fprintf(stderr, ": %s", strerror(errno));
  }
  fprintf(stderr, "\n");
}

static inline void warnx(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fprintf(stderr, "\n");
}

static inline void vwarnx(const char *fmt, va_list ap)
{
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
}

static inline void err(int eval, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  if (errno) {
    fprintf(stderr, ": %s", strerror(errno));
  }
  fprintf(stderr, "\n");
  exit(eval);
}

static inline void errx(int eval, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fprintf(stderr, "\n");
  exit(eval);
}

#else
#include_next <err.h>
#endif
