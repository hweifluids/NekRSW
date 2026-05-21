set(GS_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/3rd_party/gslib/)
set(GS_LIB 3rd_party/gslib/libgs.a)

# Copy source into CMake build dir.  We do this since gslib is built in-source,
# and we want to keep source tree clean.
FetchContent_Declare(
    gs_content
    URL ${GS_SOURCE_DIR} 
)
FetchContent_GetProperties(gs_content)
if (NOT gs_content_POPULATED)
    FetchContent_MakeAvailable(gs_content)
endif()
set(GS_SOURCE_DIR ${gs_content_SOURCE_DIR})

if(WIN32)
  set(GS_WIN_INCLUDE_DIR ${CMAKE_CURRENT_BINARY_DIR}/gslib_win/include)
  file(MAKE_DIRECTORY ${GS_WIN_INCLUDE_DIR}/gslib)
  file(WRITE ${GS_WIN_INCLUDE_DIR}/gslib/config.h
"#ifndef GSLIB_USE_MPI
#define GSLIB_USE_MPI
#endif
#ifndef GSLIB_UNDERSCORE
#define GSLIB_UNDERSCORE
#endif
#ifndef GSLIB_PREFIX
#define GSLIB_PREFIX gslib_
#endif
#ifndef GSLIB_FPREFIX
#define GSLIB_FPREFIX fgslib_
#endif
#ifndef GSLIB_USE_GLOBAL_LONG_LONG
#define GSLIB_USE_GLOBAL_LONG_LONG
#endif
#ifndef GSLIB_USE_NAIVE_BLAS
#define GSLIB_USE_NAIVE_BLAS
#endif
")
  file(WRITE ${GS_WIN_INCLUDE_DIR}/gslib.h
"// Automatically generated file
#include \"gslib/gslib.h\"
")
  file(COPY ${GS_SOURCE_DIR}/src/ DESTINATION ${GS_WIN_INCLUDE_DIR}/gslib FILES_MATCHING REGEX "\\.h$")

  set(GS_WIN_SOURCES
    ${GS_SOURCE_DIR}/src/gs.c
    ${GS_SOURCE_DIR}/src/sort.c
    ${GS_SOURCE_DIR}/src/sarray_transfer.c
    ${GS_SOURCE_DIR}/src/sarray_sort.c
    ${GS_SOURCE_DIR}/src/gs_local.c
    ${GS_SOURCE_DIR}/src/fail.c
    ${GS_SOURCE_DIR}/src/crystal.c
    ${GS_SOURCE_DIR}/src/comm.c
    ${GS_SOURCE_DIR}/src/tensor.c
    ${GS_SOURCE_DIR}/src/fcrystal.c
    ${GS_SOURCE_DIR}/src/findpts.c
    ${GS_SOURCE_DIR}/src/findpts_local.c
    ${GS_SOURCE_DIR}/src/obbox.c
    ${GS_SOURCE_DIR}/src/poly.c
    ${GS_SOURCE_DIR}/src/lob_bnd.c
    ${GS_SOURCE_DIR}/src/findpts_el_3.c
    ${GS_SOURCE_DIR}/src/findpts_el_2.c
  )

  add_library(gs STATIC ${GS_WIN_SOURCES})
  target_include_directories(gs PUBLIC ${GS_WIN_INCLUDE_DIR} ${GS_SOURCE_DIR}/src)
  target_link_libraries(gs PUBLIC MPI::MPI_C)
  target_compile_definitions(gs PUBLIC
    GSLIB_USE_MPI
    GSLIB_UNDERSCORE
    GSLIB_PREFIX=gslib_
    GSLIB_FPREFIX=fgslib_
    GSLIB_USE_GLOBAL_LONG_LONG
    GSLIB_USE_NAIVE_BLAS)

  install(DIRECTORY ${GS_SOURCE_DIR}/src/ DESTINATION gslib/include/gslib FILES_MATCHING REGEX "\.h$")
  install(FILES ${GS_WIN_INCLUDE_DIR}/gslib/config.h DESTINATION gslib/include/gslib)
  install(FILES ${GS_WIN_INCLUDE_DIR}/gslib.h DESTINATION gslib/include)
  install(TARGETS gs ARCHIVE DESTINATION lib)
  return()
endif()

# Build gslib
ExternalProject_Add(
        gs_build
        SOURCE_DIR ${GS_SOURCE_DIR}
        BUILD_IN_SOURCE on
        CONFIGURE_COMMAND ""
        BUILD_COMMAND "" 
        INSTALL_COMMAND cd ${GS_SOURCE_DIR} && $(MAKE) CC=${CMAKE_C_COMPILER} "CFLAGS=-fPIC ${EXTERNAL_C_FLAGS}" install
        USES_TERMINAL_BUILD on
)

# Target for libraries
add_library(gs STATIC IMPORTED)
add_dependencies(gs gs_build)
set_target_properties(gs PROPERTIES IMPORTED_LOCATION ${GS_SOURCE_DIR}/build/lib/libgs.a)
file(MAKE_DIRECTORY ${GS_SOURCE_DIR}/build/include)
target_include_directories(gs INTERFACE ${GS_SOURCE_DIR}/build/include)

set(file_pattern "\.cu$|\.hip$|\.okl$|\.c$|\.hpp$|\.tpp$|\.h$$")

install(DIRECTORY
        ${GS_SOURCE_DIR}/build/include 
        DESTINATION gslib
        FILES_MATCHING REGEX "\.h$")
