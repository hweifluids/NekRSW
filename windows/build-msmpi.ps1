param(
    [string]$SourceDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$BuildDir,
    [string]$InstallDir,
    [string]$CCompiler = 'cl',
    [string]$CXXCompiler = 'cl',
    [string]$FortranCompiler = 'ifx',
    [string]$Generator = 'Ninja',
    [string]$MpiIncludeDir,
    [string]$MpiFortranIncludeDir,
    [string]$MpiLibraryDir,
    [string]$MpiExec,
    [switch]$Cuda,
    [string]$CudaToolkitRoot = $env:CUDA_PATH,
    [string]$CudaArch,
    [switch]$Clean,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'

if (-not $BuildDir) {
    $BuildDir = Join-Path $SourceDir ($(if ($Cuda) { 'build_win_cuda_msmpi' } else { 'build_win_msmpi' }))
}
if (-not $InstallDir) {
    $InstallDir = Join-Path $SourceDir ($(if ($Cuda) { 'install_win_cuda' } else { 'install_win' }))
}
if (-not $MpiIncludeDir) {
    $MpiIncludeDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\MPI\Include'
}
if (-not $MpiFortranIncludeDir) {
    $MpiFortranIncludeDir = (Join-Path $MpiIncludeDir 'x64')
}
if (-not $MpiLibraryDir) {
    $MpiLibraryDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\MPI\Lib\x64'
}
if (-not $MpiExec) {
    $MpiExec = Join-Path $env:ProgramFiles 'Microsoft MPI\Bin\mpiexec.exe'
}
if ($Cuda -and -not $CudaToolkitRoot) {
    throw 'CUDA requested, but CUDA_PATH is not set. Pass -CudaToolkitRoot or install NVIDIA CUDA Toolkit.'
}

foreach ($path in @($SourceDir, $MpiIncludeDir, $MpiFortranIncludeDir, $MpiLibraryDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path was not found: $path"
    }
}
if ($Cuda) {
    $nvcc = Join-Path $CudaToolkitRoot 'bin\nvcc.exe'
    if (-not (Test-Path -LiteralPath $nvcc)) {
        throw "CUDA requested, but nvcc was not found: $nvcc"
    }
    $env:CUDA_PATH = $CudaToolkitRoot
    $env:CUDAToolkit_ROOT = $CudaToolkitRoot
    $env:PATH = (Join-Path $CudaToolkitRoot 'bin') + ';' + $env:PATH
}

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}

$envCmd = Join-Path $SourceDir 'windows\nekrs-env.cmd'
if (-not (Test-Path -LiteralPath $envCmd)) {
    throw "NekRS environment script was not found: $envCmd"
}

$mpiC = (Join-Path $MpiLibraryDir 'msmpi.lib') -replace '\\', '/'
$mpiF = @(
    (Join-Path $MpiLibraryDir 'msmpi.lib'),
    (Join-Path $MpiLibraryDir 'msmpifec.lib')
) -join ';'
$mpiF = $mpiF -replace '\\', '/'
$mpiInc = $MpiIncludeDir -replace '\\', '/'
$mpiFInc = (($MpiIncludeDir -replace '\\', '/'), ($MpiFortranIncludeDir -replace '\\', '/')) -join ';'
$source = $SourceDir -replace '\\', '/'
$build = $BuildDir -replace '\\', '/'
$install = $InstallDir -replace '\\', '/'
$cudaRoot = if ($Cuda) { $CudaToolkitRoot -replace '\\', '/' } else { '' }
$occaCuda = if ($Cuda) { 'ON' } else { 'OFF' }
$cudaCompilerFlags = '-w -O3 -lineinfo --use_fast_math'
if ($CudaArch) {
    $cudaCompilerFlags += " -arch=sm_$CudaArch"
}

$cmakeArgs = @(
    '-S', "`"$source`"",
    '-B', "`"$build`"",
    '-G', "`"$Generator`"",
    "-DCMAKE_C_COMPILER=$CCompiler",
    "-DCMAKE_CXX_COMPILER=$CXXCompiler",
    "-DCMAKE_Fortran_COMPILER=$FortranCompiler",
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo',
    "-DCMAKE_INSTALL_PREFIX=`"$install`"",
    "-DOCCA_ENABLE_CUDA=$occaCuda",
    '-DOCCA_ENABLE_HIP=OFF',
    '-DOCCA_ENABLE_DPCPP=OFF',
    '-DOCCA_ENABLE_OPENCL=OFF',
    '-DENABLE_ADIOS=OFF',
    '-DENABLE_CVODE=OFF',
    '-DENABLE_AMGX=OFF',
    '-DENABLE_HYPRE_GPU=OFF',
    '-DNEKRS_BUILD_FLOAT=OFF',
    '-DMAX_NUM_KERNEL_ARGS=120',
    "-DMPI_C_INCLUDE_DIRS=`"$mpiInc`"",
    "-DMPI_CXX_INCLUDE_DIRS=`"$mpiInc`"",
    "-DMPI_Fortran_INCLUDE_DIRS=`"$mpiFInc`"",
    "-DMPI_C_LIBRARIES=`"$mpiC`"",
    "-DMPI_CXX_LIBRARIES=`"$mpiC`"",
    "-DMPI_Fortran_LIBRARIES=`"$mpiF`"",
    "-DNEKRS_MS_MPI_INCLUDE_DIR=`"$mpiInc`"",
    "-DMPIEXEC_EXECUTABLE=`"$($MpiExec -replace '\\', '/')`""
) -join ' '
if ($Cuda) {
    $cmakeArgs += " -DCUDAToolkit_ROOT=`"$cudaRoot`" -DOCCA_CUDA_COMPILER_FLAGS=`"$cudaCompilerFlags`""
}

$buildArgs = "--build `"$build`" --config RelWithDebInfo --target install"
$cmd = ''
if ($Cuda) {
    $cmd += "set `"CUDA_PATH=$CudaToolkitRoot`" && set `"CUDAToolkit_ROOT=$CudaToolkitRoot`" && "
}
$cmd += "call `"$envCmd`" && set `"NEKRS_MPIEXEC=$MpiExec`""
$cmd += " && cmake $cmakeArgs"
if (-not $ConfigureOnly) {
    $cmd += " && cmake $buildArgs"
}

& $env:ComSpec /v:on /c $cmd
if ($LASTEXITCODE -ne 0) {
    throw "NekRS Windows build failed with exit code $LASTEXITCODE"
}

Write-Host "NekRS install: $InstallDir"
Write-Host "Use: call `"$InstallDir\bin\nekrs-env.cmd`""
