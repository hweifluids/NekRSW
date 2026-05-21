#pragma once

#ifdef _WIN32

#include <string.h>

#ifndef RUSAGE_SELF
#define RUSAGE_SELF 0
#endif

struct rusage {
  long ru_maxrss;
};

static inline int getrusage(int who, struct rusage *usage)
{
  (void)who;
  if (usage) {
    memset(usage, 0, sizeof(*usage));
  }
  return 0;
}

#endif
