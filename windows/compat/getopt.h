#pragma once

#ifdef _WIN32

#include <string.h>

#define no_argument 0
#define required_argument 1
#define optional_argument 2

struct option {
  const char *name;
  int has_arg;
  int *flag;
  int val;
};

static char *optarg = 0;
static int optind = 1;
static int opterr = 1;
static int optopt = 0;

static inline int getopt_long(int argc,
                              char *const argv[],
                              const char *shortopts,
                              const struct option *longopts,
                              int *longindex)
{
  (void)shortopts;
  optarg = 0;

  if (optind >= argc) {
    return -1;
  }

  const char *arg = argv[optind];
  if (!arg || strncmp(arg, "--", 2) != 0) {
    return -1;
  }

  if (strcmp(arg, "--") == 0) {
    ++optind;
    return -1;
  }

  const char *name = arg + 2;
  const char *value = strchr(name, '=');
  size_t name_len = value ? (size_t)(value - name) : strlen(name);

  for (int i = 0; longopts && longopts[i].name; ++i) {
    if (strlen(longopts[i].name) == name_len && strncmp(name, longopts[i].name, name_len) == 0) {
      if (longindex) {
        *longindex = i;
      }
      if (longopts[i].has_arg == required_argument) {
        if (value) {
          optarg = (char *)(value + 1);
        } else if (optind + 1 < argc) {
          optarg = argv[++optind];
        } else {
          ++optind;
          optopt = longopts[i].val;
          return '?';
        }
      } else if (longopts[i].has_arg == optional_argument) {
        if (value) {
          optarg = (char *)(value + 1);
        } else if (optind + 1 < argc && argv[optind + 1][0] != '-') {
          optarg = argv[++optind];
        }
      }

      ++optind;
      if (longopts[i].flag) {
        *longopts[i].flag = longopts[i].val;
        return 0;
      }
      return longopts[i].val;
    }
  }

  ++optind;
  return '?';
}

#else
#include_next <getopt.h>
#endif
