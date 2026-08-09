#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ProcessName = 'genericim',
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WindowCaptureNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint flags
    );

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@

Add-Type -AssemblyName System.Drawing

# GetWindowRect and PrintWindow otherwise return DPI-virtualized bounds from
# the PowerShell host. The Flutter window renders at the monitor's physical
# scale, so opt the capture process into per-monitor DPI awareness first.
$dpiAware = [WindowCaptureNative]::SetProcessDpiAwarenessContext([IntPtr](-4))
if (-not $dpiAware) {
    [void][WindowCaptureNative]::SetProcessDPIAware()
}

$process = Get-Process -Name $ProcessName -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1
if ($null -eq $process) {
    throw "No visible $ProcessName window was found."
}

# The Flutter test window can open with its right edge outside the physical
# desktop at high DPI. Keep its native bounds so PrintWindow captures the
# complete surface without screen-coordinate clipping.
[void][WindowCaptureNative]::SetWindowPos(
    $process.MainWindowHandle,
    [IntPtr]::Zero,
    0,
    0,
    0,
    0,
    0x0001 -bor 0x0004 -bor 0x0010
)

$rect = [WindowCaptureNative+RECT]::new()
if (-not [WindowCaptureNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
    throw "GetWindowRect failed for process $($process.Id)."
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
    throw "Invalid window bounds: ${width}x${height}."
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) | Out-Null
$bitmap = [Drawing.Bitmap]::new($width, $height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $windowHdc = $graphics.GetHdc()
    try {
        $printed = [WindowCaptureNative]::PrintWindow(
            $process.MainWindowHandle,
            $windowHdc,
            0x00000002
        )
    } finally {
        $graphics.ReleaseHdc($windowHdc)
    }
    if (-not $printed) {
        $graphics.CopyFromScreen(
            [Drawing.Point]::new($rect.Left, $rect.Top),
            [Drawing.Point]::Empty,
            [Drawing.Size]::new($width, $height)
        )
    }
    $bitmap.Save($resolvedOutput, [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

[pscustomobject]@{
    ProcessId = $process.Id
    OutputPath = $resolvedOutput
    Width = $width
    Height = $height
}
