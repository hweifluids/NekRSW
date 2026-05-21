#include <iostream>

#include <occa/defines.hpp>
#include <occa/internal/io/cache.hpp>
#include <occa/internal/io/utils.hpp>
#include <occa/utils/hash.hpp>
#include <occa/internal/utils/env.hpp>
#include <occa/internal/utils/lex.hpp>
#include <occa/types/json.hpp>
#include <occa/internal/utils/sys.hpp>

namespace occa {
  namespace io {
    namespace {
      void winTrace(const std::string &message) {
#if (OCCA_OS == OCCA_WINDOWS_OS)
        if (getenv("OCCA_WIN_TRACE")) {
          std::cerr << "[occa-win] " << message << std::endl;
        }
#else
        (void)message;
#endif
      }
    }

    bool isCached(const std::string &filename) {
      // Directory, not file
      if (filename.size() == 0) {
        return false;
      }

      std::string expFilename = io::expandFilename(filename);

      // File is already cached
      const std::string &cPath = cachePath();
      return startsWith(expFilename, cPath);
    }

    std::string hashDir(const hash_t &hash) {
      return hashDir("", hash);
    }

    std::string hashDir(const std::string &filename,
                        const hash_t &hash) {
      bool fileIsCached = isCached(filename);

      const std::string &cPath = cachePath();
      std::string cacheDir = cPath;

      const bool useHash = !filename.size() || !fileIsCached;

      // Regular file, use hash
      if (useHash) {
        if (hash.initialized) {
          return (cacheDir + hash.getString() + "/");
        }
        return cacheDir;
      }

      // Extract hash out of filename
      const char *c = filename.c_str() + cacheDir.size();
      lex::skipTo(c, '/');
      if (!c) {
        return filename;
      }
      return filename.substr(0, c - filename.c_str() + 1);
    }

    std::string cacheFile(const std::string &filename,
                          const std::string &cachedName,
                          const std::string &header) {
      return cacheFile(filename,
                       cachedName,
                       occa::hashFile(filename),
                       header);
    }

    std::string cacheFile(const std::string &filename,
                          const std::string &cachedName,
                          const hash_t &hash,
                          const std::string &header) {
      winTrace("io::cacheFile: enter filename=" + filename);
      const std::string expFilename = io::expandFilename(filename);
      winTrace("io::cacheFile: expFilename=" + expFilename);
      const std::string hashDir     = io::hashDir(expFilename, hash);
      winTrace("io::cacheFile: hashDir=" + hashDir);
      const std::string buildFile   = hashDir + kc::buildFile;
      const std::string sourceFile  = hashDir + cachedName;

      // File is already cached
      if (filename == sourceFile) {
        return filename;
      }

      if (!io::isFile(sourceFile)) {
        winTrace("io::cacheFile: before read");
        std::stringstream ss;
        ss << header << '\n'
           << io::read(expFilename);
        winTrace("io::cacheFile: after read");
        winTrace("io::cacheFile: before stageFile");
        io::stageFile(
          sourceFile,
          true,
          [&](const std::string &tempFilename) -> bool {
            winTrace("io::cacheFile: before write temp=" + tempFilename);
            io::write(tempFilename, ss.str());
            winTrace("io::cacheFile: after write");
            return true;
          }
        );
        winTrace("io::cacheFile: after stageFile");
      }
      winTrace("io::cacheFile: leave sourceFile=" + sourceFile);
      return sourceFile;
    }

    bool cachedFileIsComplete(const std::string &hashDir,
                              const std::string &filename) {
      std::string successFile = hashDir;
      successFile += filename;

      return io::exists(successFile);
    }

    void setBuildProps(occa::json &props) {
      props["date"]       = sys::date();
      props["human_date"] = sys::humanDate();
      props["version/occa"] = OCCA_VERSION_STR;
      props["version/okl"]  = OKL_VERSION_STR;
    }

    void writeBuildFile(const std::string &filename,
                        const occa::json &props) {
      io::stageFile(
        filename,
        true,
        [&](const std::string &tempFilename) -> bool {
          occa::json info = props;
          setBuildProps(info["build"]);
          info.write(tempFilename);

          return true;
        }
      );
    }
  }
}
