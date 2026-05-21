#pragma once

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#ifdef UNALIGNED
#undef UNALIGNED
#endif

#include <direct.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <share.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846264338327950288
#endif

#ifndef PATH_MAX
#define PATH_MAX _MAX_PATH
#endif

#ifndef __attribute__
#define __attribute__(x)
#endif

#ifndef ssize_t
typedef intptr_t ssize_t;
#endif

#if defined(_MSC_VER) && !defined(_MODE_T_DEFINED)
typedef int mode_t;
#define _MODE_T_DEFINED
#endif

#ifndef S_IRUSR
#define S_IRUSR _S_IREAD
#endif
#ifndef S_IWUSR
#define S_IWUSR _S_IWRITE
#endif
#ifndef S_IXUSR
#define S_IXUSR 0
#endif
#ifndef S_IRGRP
#define S_IRGRP 0
#endif
#ifndef S_IWGRP
#define S_IWGRP 0
#endif
#ifndef S_IXGRP
#define S_IXGRP 0
#endif
#ifndef S_IROTH
#define S_IROTH 0
#endif
#ifndef S_IWOTH
#define S_IWOTH 0
#endif
#ifndef S_IXOTH
#define S_IXOTH 0
#endif
#ifndef S_IRWXU
#define S_IRWXU (S_IRUSR | S_IWUSR | S_IXUSR)
#endif
#ifndef S_IRWXG
#define S_IRWXG (S_IRGRP | S_IWGRP | S_IXGRP)
#endif
#ifndef S_IRWXO
#define S_IRWXO (S_IROTH | S_IWOTH | S_IXOTH)
#endif

#ifndef F_OK
#define F_OK 0
#endif
#ifndef R_OK
#define R_OK 4
#endif
#ifndef W_OK
#define W_OK 2
#endif
#ifndef X_OK
#define X_OK 0
#endif

#ifdef __cplusplus
static inline int access(const char *path, int mode) { return _access(path, mode); }
static inline int chdir(const char *path) { return _chdir(path); }
static inline int close(int fd) { return _close(fd); }
static inline int dup2(int fd1, int fd2) { return _dup2(fd1, fd2); }
static inline FILE *fdopen(int fd, const char *mode) { return _fdopen(fd, mode); }
static inline int fileno(FILE *stream) { return _fileno(stream); }
static inline int fsync(int fd) { return _commit(fd); }
static inline int getpid(void) { return _getpid(); }
static inline int isatty(int fd) { return _isatty(fd); }
static inline long lseek(int fd, long offset, int origin) { return _lseek(fd, offset, origin); }
static inline int lstat(const char *path, struct _stat64 *buffer) { return _stat64(path, buffer); }
static inline int strcasecmp(const char *a, const char *b) { return _stricmp(a, b); }
static inline char *strdup(const char *s) { return _strdup(s); }
#else
#define access _access
#define chdir _chdir
#define close _close
#define dup2 _dup2
#define fdopen _fdopen
#define fileno _fileno
#define fsync _commit
#define getpid _getpid
#define isatty _isatty
#define lseek _lseek
#define lstat _stat64
#define open _open
#define read _read
#define mkdir(path, mode) _mkdir(path)
#define strcasecmp _stricmp
#define strdup _strdup
#define write _write
#endif

static inline int nekrs_setenv(const char *name, const char *value, int overwrite)
{
  if (!name || !*name || !value) {
    errno = EINVAL;
    return -1;
  }
  if (!overwrite && getenv(name)) {
    return 0;
  }
  return _putenv_s(name, value);
}
#define setenv nekrs_setenv

static inline int nekrs_gethostname(char *name, size_t len)
{
  if (!name || len == 0) {
    errno = EINVAL;
    return -1;
  }
  DWORD size = (DWORD)len;
  if (!GetComputerNameA(name, &size)) {
    errno = EINVAL;
    return -1;
  }
  if (size >= len) {
    errno = ERANGE;
    return -1;
  }
  return 0;
}
#define gethostname nekrs_gethostname

static inline int nekrs_fchmod(int fd, int mode)
{
  (void)fd;
  (void)mode;
  return 0;
}
#define fchmod nekrs_fchmod

static inline int nekrs_mkstemp(char *tpl)
{
  if (!tpl) {
    errno = EINVAL;
    return -1;
  }
  if (_mktemp_s(tpl, strlen(tpl) + 1) != 0) {
    return -1;
  }
  int fd = -1;
  if (_sopen_s(&fd, tpl, _O_CREAT | _O_EXCL | _O_RDWR | _O_BINARY, _SH_DENYNO, _S_IREAD | _S_IWRITE) != 0) {
    return -1;
  }
  return fd;
}
#define mkstemp nekrs_mkstemp

static inline char *nekrs_realpath(const char *path, char *resolved_path)
{
  char tmp[_MAX_PATH];
  char *out = resolved_path ? resolved_path : (char *)malloc(_MAX_PATH);
  if (!out) {
    errno = ENOMEM;
    return NULL;
  }
  if (!_fullpath(tmp, path, _MAX_PATH)) {
    if (!resolved_path) {
      free(out);
    }
    return NULL;
  }
  strcpy_s(out, _MAX_PATH, tmp);
  return out;
}
#define realpath nekrs_realpath

#endif
