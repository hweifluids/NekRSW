# NekRS Windows Build

This Windows variant targets a native MSVC + Intel oneAPI ifx + MS-MPI build.
CPU/SERIAL OCCA and CUDA OCCA are supported. HIP/DPCPP/OpenCL, ADIOS, CVODE,
and HYPRE GPU are disabled.

## Prerequisites

- Visual Studio 2022 C++ tools
- Intel oneAPI Fortran (`ifx`)
- Microsoft MPI runtime and SDK
- CMake and Ninja in `PATH`
- NVIDIA CUDA Toolkit for CUDA builds

The scripts auto-detect the standard install locations. Override with:

```powershell
$env:NEKRS_VSDEVCMD = 'C:\path\to\VsDevCmd.bat'
$env:NEKRS_ONEAPI_SETVARS = 'C:\path\to\setvars.bat'
```

## Build

```powershell
cd C:\1_Development\nekRSW
powershell -ExecutionPolicy Bypass -File .\windows\build-msmpi.ps1 -Clean
```

The Windows build script uses the Windows-adapted Nek5000 tree at
`C:\1_Development\Nek5000W` by default. Override it with `-Nek5000SourceDir`
if you need to test another Nek5000 source tree.

CUDA build, installed separately so the CPU build remains available:

```powershell
cd C:\1_Development\nekRSW
powershell -ExecutionPolicy Bypass -File .\windows\build-msmpi.ps1 -Cuda -Clean
```

Useful configuration variables:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\build-msmpi.ps1 `
  -CCompiler cl `
  -CXXCompiler cl `
  -FortranCompiler ifx `
  -MpiIncludeDir 'C:\Program Files (x86)\Microsoft SDKs\MPI\Include' `
  -MpiFortranIncludeDir 'C:\Program Files (x86)\Microsoft SDKs\MPI\Include\x64' `
  -MpiLibraryDir 'C:\Program Files (x86)\Microsoft SDKs\MPI\Lib\x64' `
  -MpiExec 'C:\Program Files\Microsoft MPI\Bin\mpiexec.exe' `
  -Nek5000SourceDir 'C:\1_Development\Nek5000W'
```

CUDA-specific variables:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\build-msmpi.ps1 `
  -Cuda `
  -CudaToolkitRoot 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2' `
  -CudaArch 75
```

## Environment

```cmd
call C:\1_Development\nekRSW\windows\nekrs-env.cmd
```

After install:

```cmd
call C:\1_Development\nekRSW\install_win\bin\nekrs-env.cmd
```

For CUDA:

```cmd
call C:\1_Development\nekRSW\install_win_cuda\bin\nekrs-env.cmd
```

The installer adds `C:\1_Development\nekRSW\install_win\bin` to the user
`PATH`. For the CUDA install, add `C:\1_Development\nekRSW\install_win_cuda\bin`
before the CPU install in `PATH` if you want bare `nrsmpi` to use the CUDA-capable
installation. Open a new terminal after changing `PATH`.

## Run

The Windows wrappers keep the Linux-style command shape:

```powershell
cd C:\1_Development\nekRSW\examples\channel
nrsmpi channel.par 2 --backend CPU --build-only 2
nrsmpi channel.par 2 --backend CPU
```

CUDA run:

```powershell
cd C:\1_Development\nekRSW\examples\channel
nrsmpi channel.par 1 --backend CUDA --build-only 1
nrsmpi channel.par 1 --backend CUDA
```

Two ranks on two local GPUs:

```powershell
nrsmpi channel.par 2 --backend CUDA --device-id LOCAL-RANK --build-only 2
nrsmpi channel.par 2 --backend CUDA --device-id LOCAL-RANK
```

Background run:

```powershell
nrsbmpi channel.par 2 --backend CPU
Get-Content .\logfile
Get-Content (Get-Content .\logfile) -Wait
```

Direct command equivalent:

```powershell
mpiexec -n 2 C:\1_Development\nekRSW\install_win\bin\nekrs.exe --setup channel.par --backend CPU
```

## Current Windows MPI Mode

The Windows Nek5000 interface currently uses a contiguous element-to-rank
partition for the MS-MPI path. parRSB is still built and used for connectivity,
but online repartitioning is bypassed to avoid Windows/MS-MPI redistribution
instability observed during smoke testing.
