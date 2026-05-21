@echo off
rem Initializes the Windows-native NekRS compiler/runtime environment.
rem Override discovery with NEKRS_SOURCE_ROOT, NEKRS_HOME, NEKRS_VSDEVCMD, or NEKRS_ONEAPI_SETVARS.

set "NEKRS_ENV_SCRIPT_DIR=%~dp0"
for %%I in ("%NEKRS_ENV_SCRIPT_DIR%..") do set "NEKRS_ENV_PARENT=%%~fI"

if not defined NEKRS_SOURCE_ROOT (
  if exist "%NEKRS_ENV_PARENT%\CMakeLists.txt" (
    set "NEKRS_SOURCE_ROOT=%NEKRS_ENV_PARENT%"
  ) else (
    set "NEKRS_SOURCE_ROOT=%NEKRS_ENV_PARENT%"
  )
)

if not defined NEKRS_HOME (
  if exist "%NEKRS_ENV_PARENT%\nekrs.conf" (
    set "NEKRS_HOME=%NEKRS_ENV_PARENT%"
  ) else (
    set "NEKRS_HOME=%NEKRS_SOURCE_ROOT%\install_win"
  )
)

if exist "%NEKRS_SOURCE_ROOT%\bin" set "PATH=%NEKRS_SOURCE_ROOT%\bin;%PATH%"
if exist "%NEKRS_HOME%\bin" set "PATH=%NEKRS_HOME%\bin;%PATH%"

if not defined MSMPI_BIN if exist "%ProgramFiles%\Microsoft MPI\Bin\mpiexec.exe" set "MSMPI_BIN=%ProgramFiles%\Microsoft MPI\Bin"
if not defined MSMPI_INC if exist "%ProgramFiles(x86)%\Microsoft SDKs\MPI\Include\mpi.h" set "MSMPI_INC=%ProgramFiles(x86)%\Microsoft SDKs\MPI\Include"
if not defined MSMPI_INC64 if exist "%ProgramFiles(x86)%\Microsoft SDKs\MPI\Include\x64\mpifptr.h" set "MSMPI_INC64=%ProgramFiles(x86)%\Microsoft SDKs\MPI\Include\x64"
if not defined MSMPI_LIB64 if exist "%ProgramFiles(x86)%\Microsoft SDKs\MPI\Lib\x64\msmpi.lib" set "MSMPI_LIB64=%ProgramFiles(x86)%\Microsoft SDKs\MPI\Lib\x64"
if not defined NEKRS_MPIEXEC if defined MSMPI_BIN set "NEKRS_MPIEXEC=%MSMPI_BIN%\mpiexec.exe"
if defined MSMPI_BIN set "PATH=%MSMPI_BIN%;%PATH%"

if not defined CUDA_PATH (
  for /d %%I in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v*") do set "CUDA_PATH=%%~fI"
)
if defined CUDA_PATH (
  if exist "%CUDA_PATH%\bin\nvcc.exe" set "PATH=%CUDA_PATH%\bin;%PATH%"
  if not defined CUDAToolkit_ROOT set "CUDAToolkit_ROOT=%CUDA_PATH%"
)

where cl >nul 2>nul
if errorlevel 1 (
  if defined NEKRS_VSDEVCMD (
    call "%NEKRS_VSDEVCMD%" -arch=x64 -no_logo >nul
  ) else if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" (
    call "%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -no_logo >nul
  ) else if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat" (
    call "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat" -arch=x64 -no_logo >nul
  ) else if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" (
    call "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" -arch=x64 -no_logo >nul
  ) else if exist "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
    call "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
  ) else (
    echo Visual Studio 2022 DevCmd was not found. Set NEKRS_VSDEVCMD.
    exit /b 1
  )
  if errorlevel 1 exit /b %ERRORLEVEL%
)

where ifx >nul 2>nul
if errorlevel 1 (
  if defined NEKRS_ONEAPI_SETVARS (
    if not exist "%NEKRS_ONEAPI_SETVARS%" (
      echo Intel oneAPI setvars.bat was not found: "%NEKRS_ONEAPI_SETVARS%"
      exit /b 1
    )
    call "%NEKRS_ONEAPI_SETVARS%" intel64 >nul
  ) else (
    if not exist "%ProgramFiles(x86)%\Intel\oneAPI\setvars.bat" (
      echo Intel oneAPI setvars.bat was not found: "%ProgramFiles(x86)%\Intel\oneAPI\setvars.bat"
      exit /b 1
    )
    call "%ProgramFiles(x86)%\Intel\oneAPI\setvars.bat" intel64 >nul
  )
  if errorlevel 1 exit /b %ERRORLEVEL%
)

where cl >nul 2>nul || (echo Required command cl was not found after Visual Studio initialization.& exit /b 1)
where ifx >nul 2>nul || (echo Required command ifx was not found after oneAPI initialization.& exit /b 1)
where cmake >nul 2>nul || (echo Required command cmake was not found in PATH.& exit /b 1)
if not defined NEKRS_MPIEXEC set "NEKRS_MPIEXEC=mpiexec"

set "NEKRS_WIN_ENV_READY=1"
exit /b 0
