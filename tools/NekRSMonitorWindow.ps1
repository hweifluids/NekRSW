param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [int]$Columns = 200,
  [int]$Lines = 60,
  [int]$TimeoutMs = 8000
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class NekRSMonitorWindowNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowTextLength(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int cmd);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, UInt32 flags);
}
'@

function Get-TaggedMonitorWindow {
  param([string]$WindowTag)
  $script:matchedWindows = @()
  $script:windowTag = $WindowTag
  $callback = [NekRSMonitorWindowNative+EnumWindowsProc]{
    param([IntPtr]$handle, [IntPtr]$lParam)
    if (-not [NekRSMonitorWindowNative]::IsWindowVisible($handle)) { return $true }
    $length = [NekRSMonitorWindowNative]::GetWindowTextLength($handle)
    if ($length -le 0) { return $true }
    $builder = New-Object System.Text.StringBuilder ($length + 1)
    [void][NekRSMonitorWindowNative]::GetWindowText($handle, $builder, $builder.Capacity)
    $title = $builder.ToString()
    if ($title -like '*NekRS visual background*' -and $title.Contains($script:windowTag)) {
      $rect = New-Object NekRSMonitorWindowNative+RECT
      [void][NekRSMonitorWindowNative]::GetWindowRect($handle, [ref]$rect)
      $width = $rect.Right - $rect.Left
      $height = $rect.Bottom - $rect.Top
      $script:matchedWindows += [pscustomobject]@{
        Handle = $handle
        Width = $width
        Height = $height
        Area = $width * $height
      }
    }
    return $true
  }
  [void][NekRSMonitorWindowNative]::EnumWindows($callback, [IntPtr]::Zero)
  return @($script:matchedWindows | Sort-Object Area -Descending)
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$desiredWidth = [Math]::Min(1850, [Math]::Max(900, $screen.Width - 16))
$desiredHeight = [Math]::Min(1000, [Math]::Max(700, $screen.Height - 16))
$left = [Math]::Max(0, $screen.Left + [int](($screen.Width - $desiredWidth) / 2))
$top = [Math]::Max(0, $screen.Top + [int](($screen.Height - $desiredHeight) / 2))

$deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
do {
  $window = @(Get-TaggedMonitorWindow $Tag | Select-Object -First 1)
  if ($window.Count -gt 0) {
    $handle = $window[0].Handle
    [void][NekRSMonitorWindowNative]::ShowWindowAsync($handle, 9)
    [void][NekRSMonitorWindowNative]::SetWindowPos($handle, [IntPtr]::Zero, $left, $top, $desiredWidth, $desiredHeight, 0x0040)
    [void][NekRSMonitorWindowNative]::SetForegroundWindow($handle)
    exit 0
  }
  Start-Sleep -Milliseconds 150
} while ([DateTime]::UtcNow -lt $deadline)

exit 1
