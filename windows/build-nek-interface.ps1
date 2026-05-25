param(
    [Parameter(Mandatory = $true)][string]$CacheDir,
    [Parameter(Mandatory = $true)][string]$CaseDir,
    [Parameter(Mandatory = $true)][string]$CaseName,
    [string]$InstallDir = $env:NEKRS_HOME,
    [string]$Nek5000Dir,
    [string]$NekInterfaceDir,
    [string]$ParRsbDir,
    [string]$FortranCompiler = 'ifx',
    [string]$CCompiler = 'cl',
    [string]$MpiIncludeDir = $env:MSMPI_INC,
    [string]$MpiFortranIncludeDir = $env:MSMPI_INC64,
    [string]$MpiLibraryDir = $env:MSMPI_LIB64,
    [switch]$VerboseBuild
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingPath([string]$Path, [string]$Name) {
    if (-not $Path) {
        throw "$Name is not set"
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Name was not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    if ($VerboseBuild) {
        Write-Host ($Exe + ' ' + ($Arguments -join ' '))
    }
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe failed with exit code $LASTEXITCODE"
    }
}

function Add-StubIfMissing([System.Text.StringBuilder]$Builder, [string]$SourceText, [string]$Name, [string]$Body) {
    if ($SourceText -notmatch "(?im)^\s*subroutine\s+$([regex]::Escape($Name))(\s|\(|$)") {
        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('c automatically added by NekRS Windows build')
        [void]$Builder.Append($Body.TrimEnd())
        [void]$Builder.AppendLine()
    }
}

if (-not $InstallDir) {
    $InstallDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

$InstallDir = Resolve-ExistingPath $InstallDir 'InstallDir'
$CacheDir = Resolve-ExistingPath $CacheDir 'CacheDir'
$CaseDir = Resolve-ExistingPath $CaseDir 'CaseDir'

if (-not $Nek5000Dir) {
    $Nek5000Dir = Join-Path $InstallDir 'nek5000'
}
if (-not $NekInterfaceDir) {
    $NekInterfaceDir = Join-Path $InstallDir 'nekInterface'
}
if (-not $MpiIncludeDir) {
    $MpiIncludeDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\MPI\Include'
}
if (-not $MpiFortranIncludeDir) {
    $MpiFortranIncludeDir = Join-Path $MpiIncludeDir 'x64'
}
if (-not $MpiLibraryDir) {
    $MpiLibraryDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs\MPI\Lib\x64'
}

$Nek5000Dir = Resolve-ExistingPath $Nek5000Dir 'Nek5000Dir'
$NekInterfaceDir = Resolve-ExistingPath $NekInterfaceDir 'NekInterfaceDir'
$MpiIncludeDir = Resolve-ExistingPath $MpiIncludeDir 'MpiIncludeDir'
$MpiFortranIncludeDir = Resolve-ExistingPath $MpiFortranIncludeDir 'MpiFortranIncludeDir'
$MpiLibraryDir = Resolve-ExistingPath $MpiLibraryDir 'MpiLibraryDir'

$CoreDir = Resolve-ExistingPath (Join-Path $Nek5000Dir 'core') 'Nek5000 core'
$ParRsbCandidates = @()
if ($ParRsbDir) {
    $ParRsbCandidates += $ParRsbDir
}
$ParRsbCandidates += (Join-Path $Nek5000Dir '3rd_party\parRSB')
$ParRsbCandidates += (Join-Path (Split-Path -Parent $InstallDir) '3rd_party\nek5000_parRSB')
$ParRsbSrcDir = $null
foreach ($candidate in $ParRsbCandidates) {
    if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'src\parRSB.h'))) {
        $ParRsbSrcDir = Resolve-ExistingPath (Join-Path $candidate 'src') 'parRSB source'
        break
    }
}
if (-not $ParRsbSrcDir) {
    throw "parRSB source was not found. Checked: $($ParRsbCandidates -join '; ')"
}
$CompatDir = Join-Path $InstallDir 'windows\compat'
if (-not (Test-Path -LiteralPath $CompatDir)) {
    $CompatDir = Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path 'windows\compat'
}
$CompatDir = Resolve-ExistingPath $CompatDir 'Windows compat headers'

$ObjDir = Join-Path $CacheDir 'obj_win'
New-Item -ItemType Directory -Force -Path $ObjDir | Out-Null

$parallelSource = Join-Path $CoreDir 'PARALLEL.dprocmap'
if (-not (Test-Path -LiteralPath $parallelSource)) {
    $parallelSource = Join-Path $CoreDir 'PARALLEL.default'
}
Copy-Item -LiteralPath $parallelSource -Destination (Join-Path $ObjDir 'PARALLEL') -Force

$LocalMpiIncludeDir = Join-Path $ObjDir 'msmpi_include'
$LocalMpiLibraryDir = Join-Path $ObjDir 'msmpi_lib'
New-Item -ItemType Directory -Force -Path $LocalMpiIncludeDir, $LocalMpiLibraryDir | Out-Null
Copy-Item -Path (Join-Path $MpiIncludeDir '*') -Destination $LocalMpiIncludeDir -Recurse -Force
Copy-Item -Path (Join-Path $MpiFortranIncludeDir '*') -Destination $LocalMpiIncludeDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $MpiLibraryDir 'msmpi.lib') -Destination $LocalMpiLibraryDir -Force
Copy-Item -LiteralPath (Join-Path $MpiLibraryDir 'msmpifec.lib') -Destination $LocalMpiLibraryDir -Force

$UsrCache = Join-Path $CacheDir "$CaseName.usr"
if (-not (Test-Path -LiteralPath $UsrCache)) {
    $UsrCache = Join-Path $CaseDir "$CaseName.usr"
}
if (-not (Test-Path -LiteralPath $UsrCache)) {
    $UsrCache = Join-Path $CoreDir 'zero.usr'
}

$UsrGenerated = Join-Path $CacheDir "$CaseName.f"
$usrText = Get-Content -LiteralPath $UsrCache -Raw
$builder = [System.Text.StringBuilder]::new()
[void]$builder.Append($usrText.TrimEnd())

Add-StubIfMissing $builder $usrText 'uservp' @'
      subroutine uservp(ix,iy,iz,eg)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'userf' @'
      subroutine userf(ix,iy,iz,eg)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'userq' @'
      subroutine userq(ix,iy,iz,eg)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'useric' @'
      subroutine useric(ix,iy,iz,eg)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'userbc' @'
      subroutine userbc(ix,iy,iz,iside,eg)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'userchk' @'
      subroutine userchk()
      return
      end
'@
Add-StubIfMissing $builder $usrText 'usrdat0' @'
      subroutine usrdat0()
      return
      end
'@
Add-StubIfMissing $builder $usrText 'usrdat' @'
      subroutine usrdat()
      return
      end
'@
Add-StubIfMissing $builder $usrText 'usrdat2' @'
      subroutine usrdat2()
      return
      end
'@
Add-StubIfMissing $builder $usrText 'usrdat3' @'
      subroutine usrdat3
      return
      end
'@
Add-StubIfMissing $builder $usrText 'usrsetvert' @'
      subroutine usrsetvert(glo_num,nel,nx,ny,nz)
      integer*8 glo_num(1)
      return
      end
'@
Add-StubIfMissing $builder $usrText 'userqtl' @'
      subroutine userqtl
      call userqtl_scig
      return
      end
'@
Set-Content -LiteralPath $UsrGenerated -Value $builder.ToString() -NoNewline -Encoding ASCII

$coreObjects = New-Object System.Collections.Generic.List[string]
$sourceByObject = @{}

function Add-CoreObjectSource([string]$ObjectName, [string]$SourcePath) {
    if (-not $coreObjects.Contains($ObjectName)) {
        $coreObjects.Add($ObjectName)
    }
    $sourceByObject[$ObjectName] = $SourcePath
}

function Add-DefaultCoreObjectSource([string]$ObjectName, [string]$RelativeSource) {
    if (-not $sourceByObject.ContainsKey($ObjectName)) {
        Add-CoreObjectSource $ObjectName (Join-Path $CoreDir $RelativeSource)
    } elseif (-not $coreObjects.Contains($ObjectName)) {
        $coreObjects.Add($ObjectName)
    }
}

$templatePath = Join-Path $CoreDir 'makefile.template'
if (Test-Path -LiteralPath $templatePath) {
    $template = Get-Content -LiteralPath $templatePath
    $collectCore = $false
    foreach ($line in $template) {
        $work = $line
        if (-not $collectCore -and $work -match '^\s*CORE\s*=') {
            $collectCore = $true
            $work = $work -replace '^\s*CORE\s*=\s*', ''
        } elseif (-not $collectCore) {
            continue
        }

        $continues = $work.TrimEnd().EndsWith('\')
        $work = $work.Replace('\', ' ')
        foreach ($token in ($work -split '\s+')) {
            if ($token -match '\.o$') {
                $coreObjects.Add($token)
            }
        }
        if (-not $continues) {
            break
        }
    }

    foreach ($line in $template) {
        if ($line -match '^\$\(OBJDIR\)/([^\s:]+)\s*:\s*([^;]+);') {
            $obj = $matches[1]
            $dep = ($matches[2].Trim() -split '\s+')[0]
            $dep = $dep.Replace('$S', $Nek5000Dir)
            $sourceByObject[$obj] = $dep
        }
    }
} else {
    Write-Host "Nek5000 core makefile.template not found; using Windows Nek5000 source list."
    $fortranCore = @(
        'drive1.f', 'drive2.f', 'comm_mpi.f', 'plan5.f', 'plan4.f', 'bdry.f', 'coef.f',
        'conduct.f', 'connect1.f', 'connect2.f', 'dssum.f', 'eigsolv.f',
        'gauss.f', 'genxyz.f', 'navier1.f', 'makeq.f', 'navier0.f',
        'navier2.f', 'navier3.f', 'navier4.f', 'prepost.f', 'speclib.f',
        'map2.f', 'mvmesh.f', 'ic.f', 'gfldr.f', 'ssolv.f', 'planx.f',
        'hmholtz.f', 'subs1.f', 'subs2.f', 'gmres.f', 'hsmg.f', 'convect.f',
        'convect2.f', 'induct.f', 'perturb.f', 'navier5.f', 'navier6.f', 'navier7.f',
        'navier8.f', 'fast3d.f', 'fasts.f', 'calcz.f', 'byte_mpi.f',
        'postpro.f', 'interp.f', 'cvode_driver.f', 'multimesh.f', 'vprops.f',
        'makeq_aux.f', 'papi.f', 'hpf.f', 'hrefine.f',
        'reader_rea.f', 'reader_par.f', 'reader_re2.f', 'math.f', 'dprocmap.f',
        'mxm_wrapper.f', 'mxm_std.f', '3rd_party\nek_in_situ.f'
    )
    $cCore = @(
        'byte.c',
        'fcrs.c',
        'crs_xxt.c',
        'crs_amg.c',
        'experimental\fem_amg_preco.c',
        'experimental\crs_hypre.c',
        'partitioner.c',
        'nekio.c',
        '3rd_party\finiparser.c',
        '3rd_party\iniparser.c',
        '3rd_party\dictionary.c'
    )
    foreach ($rel in ($fortranCore + $cCore)) {
        $obj = ([IO.Path]::GetFileNameWithoutExtension($rel) + '.o')
        Add-CoreObjectSource $obj (Join-Path $CoreDir $rel)
    }
}

$winHelpersSource = Join-Path $Nek5000Dir 'windows\chelpers_win.c'
if (Test-Path -LiteralPath $winHelpersSource) {
    Add-CoreObjectSource 'chelpers.o' $winHelpersSource
} else {
    Add-DefaultCoreObjectSource 'chelpers.o' 'chelpers.c'
}
Add-DefaultCoreObjectSource 'dprocmap.o' 'dprocmap.f'
Add-DefaultCoreObjectSource 'mxm_std.o' 'mxm_std.f'
Add-DefaultCoreObjectSource 'comm_mpi.o' 'comm_mpi.f'

$Nek5000WindowsDir = Join-Path $Nek5000Dir 'windows'
$includeDirs = @(
    $CacheDir,
    $ObjDir,
    $CaseDir,
    $CoreDir,
    (Join-Path $CoreDir 'experimental'),
    $Nek5000WindowsDir,
    (Join-Path $InstallDir 'include\core\bdry'),
    (Join-Path $InstallDir 'gslib\include'),
    $ParRsbSrcDir,
    $LocalMpiIncludeDir
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$fortranIncludes = $includeDirs | ForEach-Object { "/I`"$_`"" }
$cIncludes = $includeDirs | ForEach-Object { "/I`"$_`"" }

$fortranBase = @(
    '/nologo',
    '/c',
    '/fpp',
    '/extend-source:132',
    '/real-size:64',
    '/names:lowercase',
    '/assume:underscore',
    '/DMPI',
    '/DTIMER',
    '/DPARRSB',
    '/DDPROCMAP',
    '/DNEKRS_WINDOWS_CONTIGUOUS_MAP'
) + $fortranIncludes

$fortranName = [IO.Path]::GetFileNameWithoutExtension($FortranCompiler)
if ($fortranName -match '^(ifx|ifort)$') {
    $dynamicCommonBlocks = 'vptsol,gmre1,gmre2,gmres,spltprec,gxyz,giso1,giso2,gisod,gmfact,gsurf,gvolm,mass,solnd,bqcb,vptmsk,cbm2,diverg,input5,input6,input8,input9,inputmi,cbout_mask,mghr,chkrms,cbplan_vol_ms,adj_real,chkavg'
    $fortranBase += "/Qdyncom`"$dynamicCommonBlocks`""
    Write-Host "Dynamic COMMON: $dynamicCommonBlocks"
}

$cBase = @(
    '/nologo',
    '/c',
    '/O2',
    '/MT',
    '/std:c11',
    '/D_CRT_SECURE_NO_WARNINGS',
    '/DWIN32',
    '/D_WINDOWS',
    '/DMPI',
    '/DTIMER',
    '/DCOMM_H',
    '/DUNDERSCORE',
    '/DPARRSB',
    '/DPARRSB_MPI',
    '/DPARRSB_UNDERSCORE',
    '/DPARRSB_SYNC_BY_REDUCTION',
    '/DGSLIB_USE_MPI',
    '/DGSLIB_UNDERSCORE',
    '/DGSLIB_PREFIX=gslib_',
    '/DGSLIB_FPREFIX=fgslib_',
    '/DGSLIB_USE_GLOBAL_LONG_LONG',
    '/DGSLIB_USE_NAIVE_BLAS',
    "/I`"$CompatDir`"",
    "/FInekrs_windows_compat.h"
) + $cIncludes

$objects = New-Object System.Collections.Generic.List[string]
foreach ($src in (Get-ChildItem -LiteralPath $ParRsbSrcDir -Filter '*.c' | Sort-Object Name)) {
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($src.Name)).Replace('-', '_')
    $obj = Join-Path $ObjDir "parrsb_$safeName.obj"
    Invoke-Checked $CCompiler ($cBase + @('/O2', "/Fo$obj", $src.FullName))
    $objects.Add($obj)
}

foreach ($objName in $coreObjects) {
    if (-not $sourceByObject.ContainsKey($objName)) {
        throw "No source rule for $objName in Nek5000 makefile.template"
    }
    $src = $sourceByObject[$objName]
    $obj = Join-Path $ObjDir ($objName -replace '\.o$', '.obj')
    $ext = [IO.Path]::GetExtension($src).ToLowerInvariant()
    if ($ext -eq '.c') {
        Invoke-Checked $CCompiler ($cBase + @("/Fo$obj", $src))
    } else {
        $optFlag = if ($objName -eq 'prepost.o' -or $objName -eq 'convect2.o') { '/Od' } elseif ($objName -eq 'math.o') { '/O3' } else { '/O2' }
        Invoke-Checked $FortranCompiler ($fortranBase + @($optFlag, "/object:$obj", $src))
    }
    $objects.Add($obj)
}

$usrObj = Join-Path $ObjDir "$CaseName.obj"
Invoke-Checked $FortranCompiler ($fortranBase + @('/O2', "/object:$usrObj", $UsrGenerated))
$objects.Add($usrObj)

$interfaceObj = Join-Path $ObjDir 'nekInterface.obj'
Invoke-Checked $FortranCompiler ($fortranBase + @('/O2', "/I`"$NekInterfaceDir`"", "/object:$interfaceObj", (Join-Path $NekInterfaceDir 'nekInterface.f')))
$objects.Add($interfaceObj)

$defFile = Join-Path $ObjDir "$CaseName.def"
@(
    "LIBRARY $CaseName",
    'EXPORTS',
    'usrdat_',
    'usrdat2_',
    'usrdat3_',
    'userchk_',
    'uservp_',
    'userf_',
    'userq_',
    'userbc_',
    'useric_',
    'userqtl_',
    'usrsetvert_',
    'nekf_bootstrap_',
    'nekf_setup_',
    'nekf_uic_',
    'nekf_end_',
    'nekf_outfld_',
    'nekf_openfld_',
    'nekf_readfld_',
    'nekf_hrefine_map_elements_',
    'nekf_hrefine_readfld_',
    'nekf_restart_',
    'nekf_lglel_',
    'nekf_ifoutfld_',
    'nekf_setics_',
    'nekf_bcmap_',
    'nekf_gen_bcmap_',
    'map_m_to_n_',
    'nekf_nbid_',
    'nekf_set_vert_',
    'setbd_',
    'setabbd_',
    'nekf_updggeom_',
    'mesh_metrics_',
    'gllnid_',
    'gllel_'
) | Set-Content -LiteralPath $defFile -Encoding ASCII

$libFile = Join-Path $CacheDir "$CaseName.dll"
Remove-Item -LiteralPath $libFile -Force -ErrorAction SilentlyContinue

$linkInputs = @($objects.ToArray())
foreach ($lib in @(
    (Join-Path $InstallDir 'lib\nekrs.lib'),
    (Join-Path $InstallDir 'lib\gs.lib'),
    (Join-Path $InstallDir 'lib\libblas.lib'),
    (Join-Path $InstallDir 'lib\liblapack.lib'),
    (Join-Path $LocalMpiLibraryDir 'msmpi.lib'),
    (Join-Path $LocalMpiLibraryDir 'msmpifec.lib')
)) {
    if (Test-Path -LiteralPath $lib) {
        $linkInputs += $lib
    }
}
$linkInputs += 'Ws2_32.lib'
$linkInputs += 'Psapi.lib'

Invoke-Checked $FortranCompiler (@('/nologo', '/dll', "/Fe:$libFile") + $linkInputs + @('/link', "/DEF:$defFile", '/INCREMENTAL:NO'))

if (-not (Test-Path -LiteralPath $libFile)) {
    throw "NekInterface DLL was not created: $libFile"
}

Write-Host "created $libFile"
