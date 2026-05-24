param(
  [string]$ProcessName = 'nekrs',
  [int]$Tasks = 0,
  [string]$CommandLineContains = '',
  [int]$WaitSeconds = 600,
  [int]$Passes = 0,
  [int]$PassDelaySeconds = 15,
  [int]$FastPasses = 20,
  [int]$FastPassDelayMilliseconds = 500,
  [string]$LogPath = '',
  [switch]$IncludeExisting
)

$ErrorActionPreference = 'Stop'
$script:StartedAt = (Get-Date).AddSeconds(-5)
if ($IncludeExisting) {
  $script:StartedAt = [datetime]::MinValue
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
  $LogPath = Join-Path (Get-Location) "$ProcessName.affinity.log"
}

$logDir = Split-Path -Parent $LogPath
if (-not [string]::IsNullOrWhiteSpace($logDir)) {
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

function Write-AffinityLog {
  param([string]$Message)
  $line = '{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message
  Add-Content -LiteralPath $LogPath -Value $line
}

Write-AffinityLog ("launching helper pid={0} process={1} tasks={2} filter=""{3}""" -f `
  $PID, $ProcessName, $Tasks, $CommandLineContains)

function Convert-CimDateTime {
  param($Value)
  if ($Value -is [datetime]) {
    return $Value
  }
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return [datetime]::MinValue
  }
  return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)
}

$source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class NekRsWinAffinity
{
    private const int RelationProcessorCore = 0;
    private const uint THREAD_SET_INFORMATION = 0x0020;

    [StructLayout(LayoutKind.Sequential)]
    public struct GROUP_AFFINITY
    {
        public UIntPtr Mask;
        public ushort Group;
        public ushort Reserved0;
        public ushort Reserved1;
        public ushort Reserved2;
    }

    public struct CpuSlot
    {
        public ushort Group;
        public ulong Mask;
        public int CoreIndex;
        public bool Primary;

        public CpuSlot(ushort group, ulong mask, int coreIndex, bool primary)
        {
            Group = group;
            Mask = mask;
            CoreIndex = coreIndex;
            Primary = primary;
        }

        public override string ToString()
        {
            return String.Format("group={0} mask=0x{1:X} core={2} primary={3}",
                Group, Mask, CoreIndex, Primary);
        }
    }

    [DllImport("kernel32.dll")]
    private static extern ushort GetActiveProcessorGroupCount();

    [DllImport("kernel32.dll")]
    private static extern uint GetActiveProcessorCount(ushort GroupNumber);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetLogicalProcessorInformationEx(
        int RelationshipType,
        IntPtr Buffer,
        ref uint ReturnedLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenThread(
        uint dwDesiredAccess,
        bool bInheritHandle,
        uint dwThreadId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetThreadGroupAffinity(
        IntPtr hThread,
        ref GROUP_AFFINITY GroupAffinity,
        IntPtr PreviousGroupAffinity);

    public static int ActiveGroupCount()
    {
        return GetActiveProcessorGroupCount();
    }

    public static int ActiveProcessorCount(int group)
    {
        return (int)GetActiveProcessorCount((ushort)group);
    }

    public static bool SetThread(int threadId, ushort group, ulong mask, out int error)
    {
        error = 0;
        IntPtr handle = OpenThread(
            THREAD_SET_INFORMATION,
            false,
            (uint)threadId);

        if (handle == IntPtr.Zero)
        {
            error = Marshal.GetLastWin32Error();
            return false;
        }

        try
        {
            GROUP_AFFINITY affinity = new GROUP_AFFINITY();
            affinity.Group = group;
            affinity.Mask = (UIntPtr)mask;

            bool ok = SetThreadGroupAffinity(handle, ref affinity, IntPtr.Zero);
            if (!ok)
            {
                error = Marshal.GetLastWin32Error();
            }
            return ok;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    public static CpuSlot[] GetCpuSlots()
    {
        CpuSlot[] topologySlots = TryGetTopologySlots();
        if (topologySlots.Length > 0)
        {
            return topologySlots;
        }
        return BuildFallbackSlots();
    }

    private static CpuSlot[] TryGetTopologySlots()
    {
        uint length = 0;
        GetLogicalProcessorInformationEx(RelationProcessorCore, IntPtr.Zero, ref length);
        if (length == 0)
        {
            return new CpuSlot[0];
        }

        IntPtr buffer = Marshal.AllocHGlobal((int)length);
        try
        {
            if (!GetLogicalProcessorInformationEx(RelationProcessorCore, buffer, ref length))
            {
                return new CpuSlot[0];
            }

            List<CpuSlot> primary = new List<CpuSlot>();
            List<CpuSlot> secondary = new List<CpuSlot>();
            long current = buffer.ToInt64();
            long end = current + length;
            int coreIndex = 0;

            while (current < end)
            {
                int relationship = Marshal.ReadInt32(new IntPtr(current));
                int size = Marshal.ReadInt32(new IntPtr(current + 4));
                if (size <= 0)
                {
                    break;
                }

                if (relationship == RelationProcessorCore)
                {
                    ushort groupCount = (ushort)Marshal.ReadInt16(new IntPtr(current + 30));
                    long groupMaskPtr = current + 32;

                    for (int groupIndex = 0; groupIndex < groupCount; groupIndex++)
                    {
                        long entry = groupMaskPtr + (groupIndex * 16);
                        ulong mask = (ulong)Marshal.ReadInt64(new IntPtr(entry));
                        ushort group = (ushort)Marshal.ReadInt16(new IntPtr(entry + 8));
                        bool firstThread = true;

                        foreach (int bit in SetBits(mask))
                        {
                            CpuSlot slot = new CpuSlot(group, 1UL << bit, coreIndex, firstThread);
                            if (firstThread)
                            {
                                primary.Add(slot);
                            }
                            else
                            {
                                secondary.Add(slot);
                            }
                            firstThread = false;
                        }
                    }
                    coreIndex++;
                }

                current += size;
            }

            primary.AddRange(secondary);
            return primary.ToArray();
        }
        catch
        {
            return new CpuSlot[0];
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static CpuSlot[] BuildFallbackSlots()
    {
        List<CpuSlot> primary = new List<CpuSlot>();
        List<CpuSlot> secondary = new List<CpuSlot>();
        ushort groups = GetActiveProcessorGroupCount();
        int coreIndex = 0;

        for (ushort group = 0; group < groups; group++)
        {
            int count = (int)GetActiveProcessorCount(group);
            for (int bit = 0; bit < count; bit += 2)
            {
                primary.Add(new CpuSlot(group, 1UL << bit, coreIndex++, true));
            }
        }

        for (ushort group = 0; group < groups; group++)
        {
            int count = (int)GetActiveProcessorCount(group);
            for (int bit = 1; bit < count; bit += 2)
            {
                secondary.Add(new CpuSlot(group, 1UL << bit, coreIndex++, false));
            }
        }

        primary.AddRange(secondary);
        return primary.ToArray();
    }

    private static IEnumerable<int> SetBits(ulong mask)
    {
        for (int bit = 0; bit < 64; bit++)
        {
            if ((mask & (1UL << bit)) != 0)
            {
                yield return bit;
            }
        }
    }
}
'@

if (-not ('NekRsWinAffinity' -as [type])) {
  function Select-ExistingPathList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
      return ''
    }
    $paths = foreach ($entry in ($Value -split ';')) {
      $trimmed = $entry.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
      }
      $expanded = [System.Environment]::ExpandEnvironmentVariables($trimmed)
      try {
        $fullPath = [System.IO.Path]::GetFullPath($expanded)
      } catch {
        continue
      }
      if (Test-Path -LiteralPath $fullPath) {
        $fullPath
      }
    }
    return ($paths -join ';')
  }

  $oldLib = $env:LIB
  $oldLibPath = $env:LIBPATH
  try {
    $env:LIB = Select-ExistingPathList $env:LIB
    $env:LIBPATH = Select-ExistingPathList $env:LIBPATH
    Add-Type -TypeDefinition $source -IgnoreWarnings
  } finally {
    $env:LIB = $oldLib
    $env:LIBPATH = $oldLibPath
  }
}

function Get-TargetProcesses {
  $imageName = $ProcessName
  if (-not $imageName.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    $imageName = "$imageName.exe"
  }

  Get-CimInstance Win32_Process -Filter "Name = '$imageName'" |
    Where-Object {
      $include = $true
      if ([int]$_.ProcessId -eq $PID) {
        $include = $false
      } elseif ($_.CommandLine -like '*set-msmpi-rank-affinity.ps1*') {
        $include = $false
      } else {
        $created = Convert-CimDateTime $_.CreationDate
        if ($created -lt $script:StartedAt) {
          $include = $false
        } elseif (-not [string]::IsNullOrWhiteSpace($CommandLineContains)) {
          $include = ($_.CommandLine -like "*$CommandLineContains*")
        }
      }
      $include
    } |
    Sort-Object ProcessId
}

function Format-GroupCounts {
  param($Assignments)
  $counts = @{}
  foreach ($assignment in $Assignments) {
    $key = [string]$assignment.Group
    if (-not $counts.ContainsKey($key)) {
      $counts[$key] = 0
    }
    $counts[$key]++
  }
  ($counts.GetEnumerator() | Sort-Object {[int]$_.Key} | ForEach-Object {
    'group {0}={1}' -f $_.Key, $_.Value
  }) -join ', '
}

$slots = @([NekRsWinAffinity]::GetCpuSlots())
if ($slots.Count -eq 0) {
  Write-AffinityLog 'no processor slots detected'
  exit 2
}

$groupInfo = for ($group = 0; $group -lt [NekRsWinAffinity]::ActiveGroupCount(); $group++) {
  'group {0}={1}' -f $group, [NekRsWinAffinity]::ActiveProcessorCount($group)
}

Write-AffinityLog ("starting helper process={0} tasks={1} filter=""{2}"" wait={3}s passes={4} slots={5} ({6})" -f `
  $ProcessName, $Tasks, $CommandLineContains, $WaitSeconds, $Passes, $slots.Count, ($groupInfo -join ', '))

if ($Tasks -gt $slots.Count) {
  Write-AffinityLog ("warning: tasks={0} exceeds detected logical processor slots={1}; assignments will wrap" -f $Tasks, $slots.Count)
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$targets = @()
do {
  $targets = @(Get-TargetProcesses)
  if ($targets.Count -gt 0 -and ($Tasks -le 0 -or $targets.Count -ge $Tasks)) {
    break
  }
  Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

if ($targets.Count -eq 0) {
  Write-AffinityLog 'no target processes found before timeout'
  exit 3
}

if ($Tasks -gt 0 -and $targets.Count -lt $Tasks) {
  Write-AffinityLog ("warning: found only {0} target processes for {1} requested tasks before timeout" -f $targets.Count, $Tasks)
}

$observedTargets = $false
$pass = 0

while ($true) {
  $targets = @(Get-TargetProcesses)
  if ($targets.Count -eq 0) {
    if ($observedTargets) {
      Write-AffinityLog 'target processes exited; helper exiting'
      break
    }
    Start-Sleep -Milliseconds 500
    continue
  }

  $observedTargets = $true
  $pass++
  $processIndex = 0
  $threadCount = 0
  $failureCount = 0
  $failureCodes = @{}
  $assignments = @()

  foreach ($target in $targets) {
    $slot = $slots[$processIndex % $slots.Count]
    $assignments += $slot

    try {
      $process = Get-Process -Id $target.ProcessId -ErrorAction Stop
    } catch {
      $processIndex++
      continue
    }

    foreach ($thread in $process.Threads) {
      $errorCode = 0
      $ok = [NekRsWinAffinity]::SetThread([int]$thread.Id, [uint16]$slot.Group, [uint64]$slot.Mask, [ref]$errorCode)
      if ($ok) {
        $threadCount++
      } else {
        $failureCount++
        $key = [string]$errorCode
        if (-not $failureCodes.ContainsKey($key)) {
          $failureCodes[$key] = 0
        }
        $failureCodes[$key]++
      }
    }

    if ($pass -eq 1) {
      Write-AffinityLog ("pid={0} slot={1}" -f $target.ProcessId, $slot.ToString())
    }
    $processIndex++
  }

  if ($pass -eq 1 -or $pass -le $FastPasses -or ($pass % 10) -eq 0 -or $failureCount -gt 0) {
    $failureSummary = ''
    if ($failureCodes.Count -gt 0) {
      $failureSummary = ' failureCodes=' + (($failureCodes.GetEnumerator() | Sort-Object {[int]$_.Key} | ForEach-Object {
        '{0}:{1}' -f $_.Key, $_.Value
      }) -join ',')
    }
    Write-AffinityLog ("pass={0} processes={1} threadsPinned={2} failures={3}{4} {5}" -f `
      $pass, $targets.Count, $threadCount, $failureCount, $failureSummary, (Format-GroupCounts $assignments))
  }

  if ($Passes -gt 0 -and $pass -ge $Passes) {
    Write-AffinityLog ("completed {0} passes; helper exiting" -f $Passes)
    break
  }

  if ($pass -le $FastPasses) {
    Start-Sleep -Milliseconds $FastPassDelayMilliseconds
  } else {
    Start-Sleep -Seconds $PassDelaySeconds
  }
}
