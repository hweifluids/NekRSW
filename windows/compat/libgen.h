#pragma once

#ifdef _WIN32

#include <string.h>

static inline char *basename(char *path)
{
  if (!path) {
    return path;
  }
  char *slash = strrchr(path, '\\');
  char *fslash = strrchr(path, '/');
  if (fslash && (!slash || fslash > slash)) {
    slash = fslash;
  }
  return slash ? slash + 1 : path;
}

static inline char *dirname(char *path)
{
  if (!path) {
    return path;
  }
  char *slash = strrchr(path, '\\');
  char *fslash = strrchr(path, '/');
  if (fslash && (!slash || fslash > slash)) {
    slash = fslash;
  }
  if (slash) {
    *slash = '\0';
  }
  return path;
}

#else
#include_next <libgen.h>
#endif
