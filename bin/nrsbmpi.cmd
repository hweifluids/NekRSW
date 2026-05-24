@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "NEKRS_WRAPPER_DIR=%~dp0"
for %%I in ("%NEKRS_WRAPPER_DIR%..") do set "NEKRS_SOURCE_ROOT=%%~fI"
if exist "%NEKRS_WRAPPER_DIR%nekrs-env.cmd" (
  call "%NEKRS_WRAPPER_DIR%nekrs-env.cmd" >nul
) else (
  call "%NEKRS_SOURCE_ROOT%\windows\nekrs-env.cmd" >nul
)
if errorlevel 1 exit /b %ERRORLEVEL%

if "%~2"=="" (
  echo usage: nrsbmpi casename #tasks [args]
  exit /b 1
)

set "NEKRS_CASE=%~1"
set "NEKRS_TASKS=%~2"
for %%I in ("%NEKRS_CASE%") do set "NEKRS_CASE_NAME=%%~nI"
set "NEKRS_LOG=%NEKRS_CASE%.log.%NEKRS_TASKS%"
if exist "%NEKRS_LOG%" move /Y "%NEKRS_LOG%" "%NEKRS_CASE%.log1.%NEKRS_TASKS%" >nul

shift /1
shift /1
set "NEKRS_ARGS="
:nekrs_args_loop
if "%~1"=="" goto nekrs_args_done
set NEKRS_ARGS=!NEKRS_ARGS! "%~1"
shift /1
goto nekrs_args_loop
:nekrs_args_done

set "NEKRS_EXE=%NEKRS_HOME%\bin\nekrs.exe"
if "%FP32%"=="1" set "NEKRS_EXE=%NEKRS_HOME%\bin\nekrs-fp32.exe"
if not exist "%NEKRS_EXE%" (
  echo NekRS executable not found: "%NEKRS_EXE%"
  echo Run windows\build-msmpi.ps1 first.
  exit /b 1
)

call :maybe_start_affinity_helper

start "NekRS %NEKRS_CASE%" /b cmd /c ""%NEKRS_MPIEXEC%" -n %NEKRS_TASKS% "%NEKRS_EXE%" --setup "%NEKRS_CASE%" %NEKRS_ARGS% > "%NEKRS_LOG%" 2>&1"
echo %NEKRS_LOG%> logfile
echo started job in background, redirecting output to .\%NEKRS_LOG% ...
exit /b 0

:maybe_start_affinity_helper
set "NEKRS_PIN_GROUPS=%NEKRS_WIN_PIN_GROUPS%"
if not defined NEKRS_PIN_GROUPS (
  set "NEKRS_PIN_GROUPS=0"
  set /a NEKRS_TASKS_NUM=%NEKRS_TASKS% >nul 2>nul
  if !NEKRS_TASKS_NUM! GTR 64 set "NEKRS_PIN_GROUPS=1"
)
if /I not "%NEKRS_PIN_GROUPS%"=="1" exit /b 0

set "NEKRS_AFFINITY_HELPER=%NEKRS_WRAPPER_DIR%set-msmpi-rank-affinity.ps1"
if not exist "%NEKRS_AFFINITY_HELPER%" (
  echo Windows processor-group pinning helper not found: "%NEKRS_AFFINITY_HELPER%"
  exit /b 0
)

if not defined NEKRS_AFFINITY_LOG set "NEKRS_AFFINITY_LOG=%CD%\%NEKRS_CASE_NAME%.affinity.%NEKRS_TASKS%.log"
if not defined NEKRS_WIN_PIN_WAIT_SECONDS set "NEKRS_WIN_PIN_WAIT_SECONDS=600"
if not defined NEKRS_WIN_PIN_PASSES set "NEKRS_WIN_PIN_PASSES=0"
if not defined NEKRS_WIN_PIN_DELAY_SECONDS set "NEKRS_WIN_PIN_DELAY_SECONDS=15"
if not defined NEKRS_WIN_PIN_FAST_PASSES set "NEKRS_WIN_PIN_FAST_PASSES=20"
if not defined NEKRS_POWERSHELL set "NEKRS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%NEKRS_POWERSHELL%" set "NEKRS_POWERSHELL=powershell.exe"

echo Windows processor-group pinning enabled; log: "%NEKRS_AFFINITY_LOG%"
start "NekRS affinity" "%NEKRS_POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%NEKRS_AFFINITY_HELPER%" -ProcessName nekrs -Tasks %NEKRS_TASKS% -CommandLineContains "%NEKRS_CASE%" -WaitSeconds %NEKRS_WIN_PIN_WAIT_SECONDS% -Passes %NEKRS_WIN_PIN_PASSES% -PassDelaySeconds %NEKRS_WIN_PIN_DELAY_SECONDS% -FastPasses %NEKRS_WIN_PIN_FAST_PASSES% -LogPath "%NEKRS_AFFINITY_LOG%"
exit /b 0
