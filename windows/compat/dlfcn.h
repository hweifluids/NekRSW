#pragma once

#ifdef _WIN32

#include <windows.h>
#include <stdio.h>

#define RTLD_NOW 0
#define RTLD_GLOBAL 0
#define RTLD_LOCAL 0

static char nekrs_dlerror_buffer[512];

static inline const char *nekrs_format_win32_error(DWORD code)
{
  FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                 NULL,
                 code,
                 MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                 nekrs_dlerror_buffer,
                 sizeof(nekrs_dlerror_buffer),
                 NULL);
  return nekrs_dlerror_buffer;
}

static inline void *dlopen(const char *filename, int flags)
{
  (void)flags;
  HMODULE handle = LoadLibraryA(filename);
  if (!handle) {
    nekrs_format_win32_error(GetLastError());
  } else {
    nekrs_dlerror_buffer[0] = '\0';
  }
  return (void *)handle;
}

static inline void *dlsym(void *handle, const char *symbol)
{
  FARPROC proc = GetProcAddress((HMODULE)handle, symbol);
  if (!proc) {
    nekrs_format_win32_error(GetLastError());
  } else {
    nekrs_dlerror_buffer[0] = '\0';
  }
  return (void *)proc;
}

static inline int dlclose(void *handle)
{
  if (!handle) {
    return 0;
  }
  if (!FreeLibrary((HMODULE)handle)) {
    nekrs_format_win32_error(GetLastError());
    return 1;
  }
  nekrs_dlerror_buffer[0] = '\0';
  return 0;
}

static inline char *dlerror(void)
{
  return nekrs_dlerror_buffer[0] ? nekrs_dlerror_buffer : NULL;
}

#else
#include_next <dlfcn.h>
#endif
