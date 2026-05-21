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

start "NekRS %NEKRS_CASE%" /b cmd /c ""%NEKRS_MPIEXEC%" -n %NEKRS_TASKS% "%NEKRS_EXE%" --setup "%NEKRS_CASE%" %NEKRS_ARGS% > "%NEKRS_LOG%" 2>&1"
echo %NEKRS_LOG%> logfile
echo started job in background, redirecting output to .\%NEKRS_LOG% ...
exit /b 0
