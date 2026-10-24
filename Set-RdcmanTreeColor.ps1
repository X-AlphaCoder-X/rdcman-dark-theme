<#
  Set-RdcmanTreeColor.ps1  (full-window version)

  Recolors ALL of RDCMan: server tree, menu bar and its dropdowns, right-click
  menus, title bar, borders, status/side panels, scrollbars, dialogs, and the
  empty area around a session that is smaller than the window (e.g. 800x600).
  The RDP session itself (the remote screen) is never touched.

  HOW IT WORKS
  Colors of the menu bar and panels are drawn inside RDCMan, so they cannot be
  changed from outside. This script therefore STARTS RDCMan itself (inside this
  PowerShell window) and recolors it from the inside, skipping every RDP control.
  -> Close RDCMan first; open it through this script from now on.
  -> Keep this window open: closing it closes RDCMan too.
  -> The script restarts itself as Administrator automatically (UAC prompt).

  RDCMan LOCATION
  Default is C:\Tools\RDCMan (change $DefaultRdcmanPath below), or use menu
  option P to set another folder/exe; your choice is remembered. If RDCMan
  cannot be found, the script asks for it.

  Examples:
    .\Set-RdcmanTreeColor.ps1                      (menu)
    .\Set-RdcmanTreeColor.ps1 -Choice 2
    .\Set-RdcmanTreeColor.ps1 -BackColor '#3B3F46'
    .\Set-RdcmanTreeColor.ps1 -RdcmanPath 'C:\Tools\RDCMan'

  Shortcut that hides this window (closing RDCMan ends it):
    powershell.exe -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\Set-RdcmanTreeColor.ps1" -Choice 2

  IF THE SERVER LIST STILL BLINKS WHEN FOCUS MOVES BETWEEN IT AND A SESSION
    1. Start with  -Trace  (or press T in the menu). Click the session, the server
       list, the session again a few times, then close RDCMan.
    2. The recording is %TEMP%\rdcman-color-trace.txt - send that file.
    Optional switches live in  %APPDATA%\rdcman-color-options.txt  (words separated by
    spaces or new lines; the file does not exist until you create it):
      stopanim      cut off the theme's selection/hover animation on the server list
      nodouble      turn off double buffering on the server list
      keeptreefill  go back to the old behavior (guard fills the list background itself)
      keephot       leave hot-tracking alone      keepfade   leave expander fading alone
      selectcolors  swap the system selected-row colors for theme colors (no visible effect on the
                    tested machine: the tree draws its selection through the dark theme)
      freezefocus   experiment: while the server list handles gaining/losing focus its painting is
                    paused, so RDCMan's own color calls (UpdateColors) cannot trigger repaints; only the
                    selected row is repainted afterwards
      nocolorskip   pass every tree color message on (the old behavior) instead of ignoring ones that change nothing
      sessionguard  also paint the area behind each RDP session in the theme color (this was always on
                    before; off now because it paints at the very moment focus moves into a session)
      trace         same as -Trace
#>

# ===================== safety wrapper (runs first, do not edit) ===============
# Runs the main script (inside the comment block below) and catches EVERY error -
# a wrong parameter, a broken line, anything - shows it, saves it, and waits for
# Enter. The window can never close on an error.
$ErrorActionPreference = 'Stop'
$RdcScriptFile = $PSCommandPath
if (-not $RdcScriptFile) { $RdcScriptFile = $MyInvocation.MyCommand.Path }
$RdcErrorLog = Join-Path $env:TEMP 'rdcman-color-error.txt'
$global:RdcIsChild = $false
$RdcFailed = $false
try {
    $RdcText  = [IO.File]::ReadAllText($RdcScriptFile)
    $RdcStart = $RdcText.IndexOf("`n<#" + '__RDC_MAIN_START__')
    $RdcEnd   = $RdcText.LastIndexOf("`n" + '__RDC_MAIN_END__' + '#>')
    if ($RdcStart -lt 0 -or $RdcEnd -lt $RdcStart) { throw 'The main part of the script is missing or damaged.' }
    $RdcStart = $RdcText.IndexOf("`n", $RdcStart + 1) + 1
    $RdcMain  = [ScriptBlock]::Create($RdcText.Substring($RdcStart, $RdcEnd - $RdcStart))
    & $RdcMain @args
}
catch {
    $RdcFailed = $true
    $RdcErr = $_
    $RdcMsg = ($RdcErr | Out-String)
    if ($RdcErr.ScriptStackTrace) { $RdcMsg += "`r`nAt: " + $RdcErr.ScriptStackTrace }
    if ($RdcErr.Exception -and $RdcErr.Exception.InnerException) { $RdcMsg += "`r`nInner: " + $RdcErr.Exception.InnerException.ToString() }
    Write-Host ''
    Write-Host 'ERROR:' -ForegroundColor Red
    Write-Host $RdcMsg -ForegroundColor Red
    try { Add-Content -LiteralPath $RdcErrorLog -Value ("[{0}] {1}`r`n" -f (Get-Date), $RdcMsg) } catch { }
    Write-Host "Saved to $RdcErrorLog" -ForegroundColor Yellow
}
finally {
    if ($RdcFailed) {
        if ($global:RdcIsChild) { exit 1 }          # helper process: the main window shows it
        try { [void](Read-Host 'Press Enter to close') } catch { Start-Sleep -Seconds 3600 }
    }
}
return

<#__RDC_MAIN_START__  (main script - read and run by the wrapper above)
[CmdletBinding()]
param(
    [int]$Choice = 0,
    [string]$BackColor,
    [string]$TextColor,
    [string]$LineColor,
    [string]$RdcmanPath,
    [int]$PollMs = 500,
    [string]$SessionBackground = '',   # color the empty area around a small session (On/Off); remembered
    [switch]$NoElevate,
    [switch]$Trace,         # record what the window does on a focus change (%TEMP%\rdcman-color-trace.txt)
    [switch]$HostChild      # internal: the child process that actually runs RDCMan
)

$ErrorActionPreference = 'Stop'

# Errors are caught and shown by the safety wrapper at the top of the file.
$logFile = Join-Path $env:TEMP 'rdcman-color-error.txt'
$global:RdcIsChild = [bool]$HostChild

# Default RDCMan location - change this line if you move RDCMan (folder or full .exe path).
$DefaultRdcmanPath = 'C:\Tools\RDCMan'

# ------------------------------------------ restart as Administrator + STA ---
$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$scriptPath = $RdcScriptFile
$scriptDir  = Split-Path -LiteralPath $scriptPath
$bound = @{}
foreach ($k in $PSBoundParameters.Keys) { $bound[$k] = $PSBoundParameters[$k] }
if ($bound.ContainsKey('RdcmanPath') -and (Test-Path -LiteralPath $RdcmanPath)) {
    $bound['RdcmanPath'] = (Resolve-Path -LiteralPath $RdcmanPath).Path
}

# Every restart of this script goes through -EncodedCommand, so spaces, quotes,
# & or brackets in the script path, the RDCMan path or any value can never break it.
function ConvertTo-PsLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }

function Get-RelaunchArgs([hashtable]$Params, [switch]$NoExit, [switch]$PassExitCode) {
    $cmd = 'Set-Location -LiteralPath ' + (ConvertTo-PsLiteral $scriptDir) + '; & ' + (ConvertTo-PsLiteral $scriptPath)
    foreach ($k in $Params.Keys) {
        $v = $Params[$k]
        if ($v -is [System.Management.Automation.SwitchParameter] -or $v -is [bool]) { if ($v) { $cmd += " -$k" } }
        else { $cmd += " -$k " + (ConvertTo-PsLiteral "$v") }
    }
    if ($PassExitCode) { $cmd += '; exit $LASTEXITCODE' }
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $list = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass')
    if ($NoExit) { $list += '-NoExit' }
    $list += @('-EncodedCommand', $enc)
    return ,$list
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin) -and -not $NoElevate) {
    # -NoExit: the admin window stays open no matter what happens inside it.
    $relaunch = Get-RelaunchArgs $bound -NoExit
    try {
        Start-Process -FilePath $psExe -ArgumentList ($relaunch -join ' ') -Verb RunAs
        Write-Host 'Opened the Administrator window - continue there.' -ForegroundColor Green
        [void](Read-Host 'Press Enter to close this one')
        return
    }
    catch {
        Write-Host 'Administrator rights were declined; continuing without them.' -ForegroundColor Yellow
    }
}

# Needs Windows PowerShell 5.1 in STA mode (RDCMan is a .NET Framework app).
if ($PSVersionTable.PSEdition -eq 'Core' -or
    [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $p2 = @{} + $bound
    $p2['NoElevate'] = $true
    $relaunch = Get-RelaunchArgs $p2
    & $psExe @relaunch
    if (-not $HostChild) { [void](Read-Host 'Press Enter to close') }
    return
}

# ------------------------------------------------------------ color helpers ---
function Test-Hex([string]$Hex) { return ($Hex -match '^#?[0-9A-Fa-f]{6}$') }

function Get-Rgb([string]$Hex) {
    if (-not (Test-Hex $Hex)) { throw "Bad color '$Hex'. Use the form #RRGGBB, for example #3B3F46." }
    $h = $Hex.TrimStart('#')
    return ,@([Convert]::ToInt32($h.Substring(0, 2), 16),
              [Convert]::ToInt32($h.Substring(2, 2), 16),
              [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Format-RdcHex([string]$Hex) {
    $c = Get-Rgb $Hex
    return ('#{0:X2}{1:X2}{2:X2}' -f $c[0], $c[1], $c[2])
}

function Get-AutoText([string]$BackHex) {
    $c = Get-Rgb $BackHex
    $lum = 0.299 * $c[0] + 0.587 * $c[1] + 0.114 * $c[2]
    if ($lum -gt 140) { return '#111111' } else { return '#F0F0F0' }
}

function Get-Blend([string]$A, [string]$B) {
    $x = Get-Rgb $A; $y = Get-Rgb $B
    return ('#{0:X2}{1:X2}{2:X2}' -f [int](($x[0] + $y[0]) / 2), [int](($x[1] + $y[1]) / 2), [int](($x[2] + $y[2]) / 2))
}

function New-Theme([string]$Name, [string]$Back, [string]$Text, [string]$Line) {
    $b = Format-RdcHex $Back
    $t = if ($Text) { Format-RdcHex $Text } else { Get-AutoText $b }
    $l = if ($Line) { Format-RdcHex $Line } else { Get-Blend $b $t }
    return [pscustomobject]@{ Name = $Name; Back = $b; Text = $t; Line = $l }
}

# --------------------------------------------------- find RDCMan.exe ---
$savedPathFile = Join-Path $env:APPDATA 'rdcman-color-path.txt'

# ---- optional recorder for the focus-change blink (default OFF, this run only) ----
$script:traceOn = [bool]$Trace
$traceLog = Join-Path $env:TEMP 'rdcman-color-trace.txt'

# ---- remembered option: color the empty area around a small session (default OFF) ----
$sessionBgFile = Join-Path $env:APPDATA 'rdcman-color-sessionbg.txt'
$script:sessionBg = $false
try { if ((Get-Content -LiteralPath $sessionBgFile -ErrorAction Stop | Select-Object -First 1) -eq 'On') { $script:sessionBg = $true } } catch { }
if ($SessionBackground -and $SessionBackground -notmatch '^(On|Off)$') {
    Write-Host "Ignoring -SessionBackground '$SessionBackground' (use On or Off)." -ForegroundColor Yellow
}
if ($SessionBackground -eq 'On')  { $script:sessionBg = $true }
if ($SessionBackground -eq 'Off') { $script:sessionBg = $false }

function Save-SessionBg {
    $v = if ($script:sessionBg) { 'On' } else { 'Off' }
    try { Set-Content -LiteralPath $sessionBgFile -Value $v -Encoding UTF8 } catch { }
}
function Get-SessionBgText { if ($script:sessionBg) { 'ON' } else { 'OFF' } }

# Accepts a folder (adds RDCMan.exe) or a full .exe path; returns the exe or $null.
function Resolve-RdcmanExe([string]$PathIn) {
    if (-not $PathIn) { return $null }
    $p = $PathIn.Trim().Trim('"').TrimEnd('\')
    if (-not $p) { return $null }
    if (Test-Path -LiteralPath $p -PathType Container) { $p = Join-Path $p 'RDCMan.exe' }
    if ((Test-Path -LiteralPath $p -PathType Leaf) -and $p -like '*.exe') {
        return (Resolve-Path -LiteralPath $p).Path
    }
    return $null
}

# Looks everywhere without asking: -RdcmanPath, saved choice, default, running RDCMan, common places.
function Find-Rdcman {
    $e = Resolve-RdcmanExe $RdcmanPath
    if ($e) { return $e }
    if (Test-Path $savedPathFile) {
        $e = Resolve-RdcmanExe (Get-Content $savedPathFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($e) { return $e }
    }
    $e = Resolve-RdcmanExe $DefaultRdcmanPath
    if ($e) { return $e }
    $p = Get-Process -Name RDCMan -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { return $p.Path }
    $candidates = @(
        $scriptDir,
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop",
        "$env:ProgramFiles\Microsoft\Remote Desktop Connection Manager",
        "${env:ProgramFiles(x86)}\Microsoft\Remote Desktop Connection Manager"
    )
    foreach ($c in $candidates) { $e = Resolve-RdcmanExe $c; if ($e) { return $e } }
    return $null
}

# Asks for the folder or exe; blank keeps the current one (if any).
function Read-RdcmanPath([string]$Current) {
    while ($true) {
        $hint = if ($Current) { 'blank = keep current' } else { 'e.g. C:\Tools\RDCMan' }
        $in = (Read-Host "RDCMan folder or full path to RDCMan.exe ($hint)").Trim()
        if (-not $in -and $Current) { return $Current }
        $e = Resolve-RdcmanExe $in
        if ($e) {
            try { Set-Content -Path $savedPathFile -Value $e -Encoding UTF8 } catch { }
            Write-Host "RDCMan location set: $e" -ForegroundColor Green
            return $e
        }
        Write-Host 'RDCMan.exe not found there, try again.' -ForegroundColor Yellow
    }
}

$script:exe = Find-Rdcman

# ------------------------------------------------------------------- menu ---
$themes = @(
    (New-Theme 'Grey'         '#4A4A4A' '#F0F0F0' '#8A8A8A'),
    (New-Theme 'Dark'         '#1E1E1E' '#DCDCDC' '#6E6E6E'),
    (New-Theme 'Light grey'   '#C8C8C8' '#111111' '#7F7F7F'),
    (New-Theme 'Slate'        '#3B4252' '#ECEFF4' '#6C7A96'),
    (New-Theme 'Midnight'     '#14213D' '#E5E5E5' '#5C6F9C'),
    (New-Theme 'Forest'       '#1F2A22' '#DDEBDD' '#5E7A62')
)

function Read-CustomTheme {
    while ($true) {
        $b = (Read-Host 'Background color as #RRGGBB (blank = back to menu)').Trim()
        if (-not $b) { return $null }
        if (-not (Test-Hex $b)) { Write-Host 'That is not a valid #RRGGBB color.' -ForegroundColor Yellow; continue }
        $t = (Read-Host 'Text color as #RRGGBB (blank = automatic)').Trim()
        if ($t -and -not (Test-Hex $t)) { Write-Host 'That is not a valid #RRGGBB color.' -ForegroundColor Yellow; continue }
        return (New-Theme 'Custom' $b $t $null)
    }
}

function Select-Theme {
    while ($true) {
        Write-Host ''
        Write-Host '  RDCMan window color' -ForegroundColor Cyan
        Write-Host '  -------------------'
        $loc = if ($script:exe) { $script:exe } else { 'NOT FOUND - choose P to set it' }
        $locColor = if ($script:exe) { 'Gray' } else { 'Yellow' }
        Write-Host "  RDCMan: $loc" -ForegroundColor $locColor
        $adminText = if (Test-Admin) { 'yes' } else { 'no' }
        Write-Host "  Administrator: $adminText" -ForegroundColor Gray
        Write-Host ''
        for ($i = 0; $i -lt $themes.Count; $i++) {
            Write-Host ('  {0}  {1,-11} back {2}   text {3}' -f ($i + 1), $themes[$i].Name, $themes[$i].Back, $themes[$i].Text)
        }
        Write-Host ('  {0}  Custom      (type your own hex colors)' -f ($themes.Count + 1))
        Write-Host '  P  Change RDCMan location'
        Write-Host ('  B  Background around a small session: {0}  (press B to switch)' -f (Get-SessionBgText))
        $trText = if ($script:traceOn) { 'ON' } else { 'OFF' }
        Write-Host ('  T  Record a blink trace (this run only): {0}  (press T to switch)' -f $trText)
        Write-Host '  Q  Quit'
        Write-Host ''
        $in = (Read-Host ('Choose 1-{0}' -f ($themes.Count + 1))).Trim()
        if ($in -match '^[Qq]$') { return $null }
        if ($in -match '^[Pp]$') { $script:exe = Read-RdcmanPath $script:exe; continue }
        if ($in -match '^[Bb]$') {
            $script:sessionBg = -not $script:sessionBg
            Save-SessionBg
            Write-Host ('Background around a small session is now {0}.' -f (Get-SessionBgText)) -ForegroundColor Green
            continue
        }
        if ($in -match '^[Tt]$') {
            $script:traceOn = -not $script:traceOn
            $trNow = if ($script:traceOn) { 'ON' } else { 'OFF' }
            Write-Host ('Blink trace is now {0} for this run.' -f $trNow) -ForegroundColor Green
            continue
        }
        $n = 0
        if ([int]::TryParse($in, [ref]$n)) {
            if ($n -ge 1 -and $n -le $themes.Count) { return $themes[$n - 1] }
            if ($n -eq $themes.Count + 1) { $c = Read-CustomTheme; if ($c) { return $c }; continue }
        }
        Write-Host 'Not a valid choice, try again.' -ForegroundColor Yellow
    }
}

# --------------------------------------------- recolor code (runs inside RDCMan) ---
$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class RdcPaint
{
    static Color CBack, CText, CLine, CAccent;
    static bool Dark;
    static System.Threading.Timer timer;
    static int busy;
    static bool started;
    static ToolStripRenderer renderer;
    static readonly HashSet<IntPtr> themed = new HashSet<IntPtr>();
    static readonly Dictionary<IntPtr, string> captioned = new Dictionary<IntPtr, string>();

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    static extern int SetWindowTheme(IntPtr h, string app, string id);

    [DllImport("user32.dll")]
    static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    static extern bool RedrawWindow(IntPtr h, IntPtr rect, IntPtr rgn, uint flags);

    [DllImport("user32.dll")]
    static extern int GetWindowLong(IntPtr h, int index);

    const int GWL_STYLE = -16;
    const int WS_SCROLLBARS = 0x00100000 | 0x00200000;   // WS_HSCROLL | WS_VSCROLL
    static readonly Dictionary<IntPtr, int> scrollState = new Dictionary<IntPtr, int>();

    // ---- background around a small session (inside the RDP control) ----
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from, IntPtr to, ref RECT r, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern int FillRect(IntPtr hdc, ref RECT r, IntPtr brush);
    [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr h, IntPtr rect, bool erase);
    [DllImport("gdi32.dll")] static extern int ExcludeClipRect(IntPtr hdc, int l, int t, int r, int b);
    [DllImport("gdi32.dll")] static extern int SaveDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool RestoreDC(IntPtr hdc, int n);
    [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(int color);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr hdc);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("uxtheme.dll")] static extern int BufferedPaintStopAllAnimations(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetUpdateRect(IntPtr h, out RECT r, bool erase);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong(IntPtr h, int index, int value);
    [DllImport("gdi32.dll")] static extern int GetClipBox(IntPtr hdc, out RECT r);
    [DllImport("gdi32.dll")] static extern int GetPixel(IntPtr hdc, int x, int y);

    // ---- react the moment RDCMan creates or shows a window (no waiting for the timer) ----
    delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    [DllImport("user32.dll")]
    static extern IntPtr SetWinEventHook(uint evMin, uint evMax, IntPtr mod, WinEventProc proc, uint pid, uint tid, uint flags);
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
    const uint EVENT_OBJECT_CREATE = 0x8000, EVENT_OBJECT_SHOW = 0x8002, WINEVENT_OUTOFCONTEXT = 0;
    static WinEventProc winEventProc;      // kept alive for the lifetime of RDCMan
    static IntPtr winEventHook;

    static readonly HashSet<Control> watched = new HashSet<Control>();
    static readonly HashSet<IntPtr> smoothTrees = new HashSet<IntPtr>();
    const int TVM_SETEXTENDEDSTYLE = 0x112C, TVS_EX_DOUBLEBUFFER = 0x0004;

    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    const uint GW_HWNDNEXT = 2, GW_CHILD = 5;
    const int WM_ERASEBKGND = 0x0014;
    const int WM_PAINT = 0x000F;
    const int WM_NCACTIVATE = 0x0086;

    // The session picture and keyboard/mouse windows: never hooked, never sent anything.
    static readonly string[] SessionClasses = { "OPWindowClass", "IHWindowClass" };
    // Container windows of the RDP control that only paint the empty background around the session.
    static readonly string[] BackgroundClasses = { "UIMainClass", "UIContainerClass", "OPContainerClass" };

    static readonly Dictionary<IntPtr, EraseHook> bgHooks = new Dictionary<IntPtr, EraseHook>();
    static readonly HashSet<IntPtr> bgLogged = new HashSet<IntPtr>();
    static IntPtr bgBrush;
    public static string LogPath;

    // SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED
    const uint SWP_REFRESH_FRAME = 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020;
    // RDW_INVALIDATE | RDW_FRAME | RDW_UPDATENOW | RDW_ALLCHILDREN is not used: only this control's own frame.
    const uint RDW_FRAME_NOW = 0x0001 | 0x0400 | 0x0100;

    static void Log(string msg)
    {
        if (string.IsNullOrEmpty(LogPath)) return;
        try { System.IO.File.AppendAllText(LogPath, DateTime.Now.ToString("s") + " " + msg + Environment.NewLine); } catch { }
    }

    static string ClassOf(IntPtr h) { StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, sb.Capacity); return sb.ToString(); }

    static bool InList(string cls, string[] list)
    {
        foreach (string x in list) if (string.Equals(cls, x, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    // Subclass that answers only WM_ERASEBKGND: fills the empty area with the theme color,
    // with every child window (the session picture) cut out. Everything else passes through.
    class EraseHook : NativeWindow
    {
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_ERASEBKGND)
            {
                bool done = false;
                try { done = FillBackground(m.HWnd, m.WParam); } catch { }
                if (done) { m.Result = (IntPtr)1; return; }
            }
            base.WndProc(ref m);
            if (m.Msg == WM_PAINT)
            {
                // The RDP window paints its grey here; paint the empty area again in our
                // color afterwards. Child windows (the session) are cut out, never covered.
                try
                {
                    IntPtr hdc = GetDC(m.HWnd);
                    if (hdc != IntPtr.Zero)
                    {
                        try { FillBackground(m.HWnd, hdc); }
                        finally { ReleaseDC(m.HWnd, hdc); }
                    }
                }
                catch { }
            }
        }
    }

    // ---- sticky guard (no polling, no delay) ----------------------------------------
    // Sits on the window itself, in front of RDCMan's own window procedure. Whatever RDCMan or
    // WinForms tries (reset BackColor, TVM_SETBKCOLOR, plain erase), the background is painted in
    // the theme color and the tree color messages are rewritten to the theme colors before they
    // are processed - so there is no frame in which the window can be white.
    // To switch it off: create an empty file  %APPDATA%\rdcman-color-noguard.txt
    const int TVM_SETBKCOLOR = 0x111D, TVM_SETTEXTCOLOR = 0x111E, TVM_SETLINECOLOR = 0x1128;
    const int TVM_GETBKCOLOR = 0x111F, TVM_GETTEXTCOLOR = 0x1120, TVM_GETLINECOLOR = 0x1129, TVM_GETEXTENDEDSTYLE = 0x112D;
    const int TVS_EX_FADEINOUTEXPANDOS = 0x0040, TVS_TRACKSELECT = 0x0200;
    const int WM_SETFOCUS = 0x0007, WM_KILLFOCUS = 0x0008, WM_REFLECT_NOTIFY = 0x204E;
    static bool GuardOn = true;
    static bool animStopBroken;
    static readonly Dictionary<IntPtr, Guard> guards = new Dictionary<IntPtr, Guard>();
    static readonly HashSet<IntPtr> hardenedTrees = new HashSet<IntPtr>();
    static int fixCount, fixWindowStart;

    // ---- optional switches: %APPDATA%\rdcman-color-options.txt (words; see the top of the script) ----
    static readonly HashSet<string> opts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    static void LoadOptions()
    {
        try
        {
            string p = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "rdcman-color-options.txt");
            if (!System.IO.File.Exists(p)) return;
            string[] words = System.IO.File.ReadAllText(p).Split(new char[] { ' ', '\t', '\r', '\n', ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string w in words) opts.Add(w.Trim());
        }
        catch { }
    }

    static bool Opt(string name) { return opts.Contains(name); }

    // ---- selected-row colors ---------------------------------------------------------------------
    // What the recording showed: the tree paints its selected row with SYSTEM colors - white text on the
    // bright system blue while the tree has focus, black text on near-white (#F0F0F0) the instant it loses
    // focus. Every move between the server list and a session flips the row between those two, and that
    // flip is the blink. Here exactly those two system colors are swapped for theme colors inside the
    // custom-draw notification, before the row is painted. Switch ON with the word  selectcolors  in
    // %APPDATA%\rdcman-color-options.txt.
    [DllImport("user32.dll")] static extern uint GetSysColor(int index);
    const int COLOR_HIGHLIGHT = 13, COLOR_BTNFACE = 15;
    static bool rowFixLogged;

    static void TweakRow(ref Message m)
    {
        IntPtr lp = m.LParam;
        if (lp == IntPtr.Zero) return;
        int p = IntPtr.Size;
        if (Marshal.ReadInt32(lp, p * 2) != -12) return;                 // NM_CUSTOMDRAW
        int stage = Marshal.ReadInt32(lp, (p == 8) ? 24 : 12);
        if (stage != 0x10001) return;                                    // CDDS_ITEMPREPAINT (one row)
        int clrOff = (p == 8) ? 80 : 48;                                 // NMTVCUSTOMDRAW.clrText / clrTextBk
        int bk = Marshal.ReadInt32(lp, clrOff + 4) & 0xFFFFFF;
        int hi = (int)(GetSysColor(COLOR_HIGHLIGHT) & 0xFFFFFF);
        int face = (int)(GetSysColor(COLOR_BTNFACE) & 0xFFFFFF);
        int newBk;
        if (bk == hi) newBk = Ref(Mix(CBack, CText, 0.40));              // selected row, tree has focus
        else if (bk == face) newBk = Ref(CAccent);                       // selected row, tree lost focus
        else return;
        Marshal.WriteInt32(lp, clrOff, Ref(CText));
        Marshal.WriteInt32(lp, clrOff + 4, newBk);
        m.Result = (IntPtr)(m.Result.ToInt64() | 0x2);                   // CDRF_NEWFONT: use these colors
        if (!rowFixLogged) { rowFixLogged = true; Log("server tree: selected-row colors replaced by theme colors"); }
    }

    [DllImport("user32.dll", EntryPoint = "InvalidateRect")] static extern bool InvalidateRectR(IntPtr h, ref RECT r, bool erase);
    const int WM_SETREDRAW = 0x000B;

    // Text rectangle of the tree's selected row in client coordinates; false when nothing is selected or the
    // row is scrolled out of view.
    static bool SelectedRowRect(IntPtr h, out RECT r)
    {
        r = new RECT();
        IntPtr item = SendMessage(h, 0x110A, (IntPtr)9, IntPtr.Zero);          // TVM_GETNEXTITEM, TVGN_CARET
        if (item == IntPtr.Zero) return false;
        IntPtr buf = Marshal.AllocHGlobal(32);
        try
        {
            Marshal.WriteIntPtr(buf, 0, item);                                  // in: the item handle
            if (SendMessage(h, 0x1104, (IntPtr)1, buf) == IntPtr.Zero) return false;   // TVM_GETITEMRECT, text only
            r.L = Marshal.ReadInt32(buf, 0); r.T = Marshal.ReadInt32(buf, 4);
            r.R = Marshal.ReadInt32(buf, 8); r.B = Marshal.ReadInt32(buf, 12);
            return true;
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    // Repaints just the selected row (full width) - the only thing a focus change really alters.
    static void InvalidateSelectedRow(IntPtr h)
    {
        RECT sr, cr;
        if (!SelectedRowRect(h, out sr) || !GetClientRect(h, out cr)) return;
        sr.L = 0; sr.R = cr.R; sr.T -= 1; sr.B += 1;
        InvalidateRectR(h, ref sr, false);
    }

    // Trace only: writes the managed call chain that led here, so the recording names the RDCMan / WinForms
    // method that changes the tree's colors (the first 24 times). Method names only - no data.
    static int whoCount;
    static void TraceWho(string what, string value)
    {
        if (!TraceOn || whoCount >= 24) return;
        whoCount++;
        try
        {
            System.Diagnostics.StackTrace st = new System.Diagnostics.StackTrace(2, false);
            StringBuilder sb = new StringBuilder();
            int n = 0;
            foreach (System.Diagnostics.StackFrame f in st.GetFrames())
            {
                System.Reflection.MethodBase mb = f.GetMethod();
                if (mb == null || mb.DeclaringType == null) continue;
                sb.Append("\r\n            at ").Append(mb.DeclaringType.FullName).Append('.').Append(mb.Name);
                if (++n >= 16) break;
            }
            Trace("WHO  " + what + "  " + value + sb.ToString());
        }
        catch { }
    }

    class Guard : NativeWindow
    {
        public IntPtr Owner;
        public bool IsTree;
        public bool Passive;            // recorder only: changes nothing
        public string Label = "";

        protected override void WndProc(ref Message m)
        {
            int msg = m.Msg;
            bool rec = false;
            RECT upd = new RECT();
            if (TraceOn && TraceWanted(msg))
            {
                if (msg == WM_SETFOCUS || msg == WM_KILLFOCUS)
                {
                    Arm();
                    rec = true;
                    if (IsTree) DumpInventory("focus change on the server tree");
                }
                else rec = Armed();
                if (rec && msg == WM_PAINT) { try { GetUpdateRect(m.HWnd, out upd, false); } catch { } }
            }

            string note = "";
            if (!Passive)
            {
                if (msg == WM_ERASEBKGND)
                {
                    // A tree that already holds our background color paints that color itself, double
                    // buffered. Filling the SCREEN here first clears the rows for a moment before the
                    // buffered paint lands - that is a visible blink on every focus change. So the tree
                    // is only filled while it still has some other color (e.g. right after creation).
                    bool leave = IsTree && !Opt("keeptreefill") && TreeBackIsOurs(m.HWnd);
                    bool done = false;
                    if (!leave) { try { done = FillBackground(m.HWnd, m.WParam); } catch { } }
                    if (done)
                    {
                        m.Result = (IntPtr)1;
                        if (rec) TraceAfter(this, ref m, upd, "guard filled the screen");
                        return;
                    }
                    if (leave) note = "left to the tree";
                }
                else if (IsTree)
                {
                    if (msg == TVM_SETBKCOLOR || msg == TVM_SETTEXTCOLOR || msg == TVM_SETLINECOLOR)
                    {
                        int want = (msg == TVM_SETBKCOLOR) ? Ref(CBack) : (msg == TVM_SETTEXTCOLOR) ? Ref(CText) : Ref(CLine);
                        int raw = (int)(m.LParam.ToInt64() & 0xFFFFFF);
                        if (TraceOn && raw != (want & 0xFFFFFF))
                            TraceWho(MsgName(msg) + " asked for", "0x" + raw.ToString("X6") + "  (ours is 0x" + (want & 0xFFFFFF).ToString("X6") + ")");
                        int getMsg = (msg == TVM_SETBKCOLOR) ? TVM_GETBKCOLOR : (msg == TVM_SETTEXTCOLOR) ? TVM_GETTEXTCOLOR : TVM_GETLINECOLOR;
                        int cur = (int)(SendMessage(m.HWnd, getMsg, IntPtr.Zero, IntPtr.Zero).ToInt64() & 0xFFFFFF);
                        if (cur == (want & 0xFFFFFF) && !Opt("nocolorskip"))
                        {
                            // The tree already has exactly our color: whatever was asked for, there is nothing
                            // to change, so the message is not passed on and the tree is not told to repaint.
                            m.Result = (IntPtr)cur;
                            if (rec) Trace(Label + "  " + MsgName(msg) + " ignored (tree already has our color)");
                            return;
                        }
                        m.LParam = (IntPtr)want;
                    }
                    else if (msg == WM_PAINT && Opt("stopanim") && !animStopBroken)
                    {
                        // Opt-in: a theme animation that started on the previous paint ends here and the
                        // final look is drawn directly.
                        try { BufferedPaintStopAllAnimations(m.HWnd); }
                        catch { animStopBroken = true; }
                    }
                }
            }
            if (IsTree && !Passive && (msg == WM_SETFOCUS || msg == WM_KILLFOCUS) && Opt("freezefocus"))
            {
                // Experiment. While the tree processes the focus change (this is where RDCMan runs
                // UpdateColors), painting is paused: repaint requests made meanwhile are dropped. Afterwards
                // painting resumes and only the selected row is repainted.
                SendMessage(m.HWnd, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
                try { base.WndProc(ref m); }
                finally
                {
                    SendMessage(m.HWnd, WM_SETREDRAW, (IntPtr)1, IntPtr.Zero);
                    try { InvalidateSelectedRow(m.HWnd); } catch { }
                }
                if (rec) TraceAfter(this, ref m, upd, "focus handled with painting paused");
                return;
            }
            base.WndProc(ref m);
            if (IsTree && !Passive && msg == WM_REFLECT_NOTIFY && Opt("selectcolors")) { try { TweakRow(ref m); } catch { } }
            if (rec) TraceAfter(this, ref m, upd, note);
        }

        protected override void OnHandleChange()
        {
            if (Handle == IntPtr.Zero && Owner != IntPtr.Zero) { guards.Remove(Owner); Owner = IntPtr.Zero; }
        }
    }

    static string LabelOf(Control c)
    {
        return c.GetType().Name + "@" + c.Handle.ToInt64().ToString("X");
    }

    static void Protect(Control c, bool tree)
    {
        if (!GuardOn || c.IsDisposed || !c.IsHandleCreated) return;
        IntPtr h = c.Handle;
        FixClass(h);
        if (guards.ContainsKey(h)) return;
        Guard g = new Guard();
        g.Owner = h;
        g.IsTree = tree;
        g.Label = LabelOf(c);
        try { g.AssignHandle(h); } catch { return; }
        guards[h] = g;
        if (tree) Log("guard on server tree 0x" + h.ToInt64().ToString("X"));
        if (tree && TraceOn) Trace("guard installed on tree " + g.Label);
    }

    // Recorder only (trace mode): watch any other control too, so whatever the server list really is
    // shows up in the recording. Changes nothing.
    static void ProtectPassive(Control c)
    {
        if (!TraceOn || c.IsDisposed || !c.IsHandleCreated || IsRdp(c) || guards.Count > 300) return;
        IntPtr h = c.Handle;
        if (guards.ContainsKey(h)) return;
        Guard g = new Guard();
        g.Owner = h;
        g.Passive = true;
        g.Label = LabelOf(c);
        try { g.AssignHandle(h); } catch { return; }
        guards[h] = g;
    }

    // True when the tree control already uses our background color.
    static bool TreeBackIsOurs(IntPtr h)
    {
        try
        {
            IntPtr r = SendMessage(h, TVM_GETBKCOLOR, IntPtr.Zero, IntPtr.Zero);
            return (int)(r.ToInt64() & 0xFFFFFF) == (Ref(CBack) & 0xFFFFFF);
        }
        catch { return false; }
    }

    // Once per tree window: take away the themed extras that animate or light up while focus and the
    // mouse move around (hover highlight, expander fade), and apply the optional double-buffer switch.
    static void HardenTree(TreeView tv)
    {
        IntPtr h = tv.Handle;
        if (hardenedTrees.Contains(h)) return;
        hardenedTrees.Add(h);
        if (!Opt("keephot"))
        {
            int st = GetWindowLong(h, GWL_STYLE);
            if ((st & TVS_TRACKSELECT) != 0)
            {
                SetWindowLong(h, GWL_STYLE, st & ~TVS_TRACKSELECT);
                Log("server tree: hover highlight (hot tracking) switched off");
            }
        }
        if (!Opt("keepfade")) SendMessage(h, TVM_SETEXTENDEDSTYLE, (IntPtr)TVS_EX_FADEINOUTEXPANDOS, IntPtr.Zero);
        if (Opt("nodouble")) SendMessage(h, TVM_SETEXTENDEDSTYLE, (IntPtr)TVS_EX_DOUBLEBUFFER, IntPtr.Zero);
    }

    // ---- recorder (off unless -Trace / the T menu key / "trace" in the options file) ------------------
    // Writes %TEMP%\rdcman-color-trace.txt. Any focus change on a watched window arms it for ~0.8 s; during
    // that time every erase / paint / custom-draw / tree message of the watched windows is written with its
    // timing, the area involved and the pixel color after painting (WHITE is flagged). No server names are
    // written.
    public static bool TraceOn;
    public static string TracePath;
    static int traceStart, traceArmedUntil, traceLines, inventoryRuns;
    static readonly object traceLock = new object();
    const int TraceMaxLines = 3000;

    static void Trace(string msg)
    {
        if (!TraceOn || string.IsNullOrEmpty(TracePath)) return;
        lock (traceLock)
        {
            if (traceLines > TraceMaxLines) return;
            traceLines++;
            string line = traceLines > TraceMaxLines
                ? "-- trace file is full; start again with trace on to record more --"
                : (Environment.TickCount - traceStart).ToString().PadLeft(8) + " ms  " + msg;
            try { System.IO.File.AppendAllText(TracePath, line + Environment.NewLine); } catch { }
        }
    }

    static bool Armed() { return TraceOn && (traceArmedUntil - Environment.TickCount) > 0; }
    static void Arm() { traceArmedUntil = Environment.TickCount + 800; }

    static bool TraceWanted(int m)
    {
        switch (m)
        {
            case 0x0007: case 0x0008: case 0x000B: case 0x000F: case 0x0014:
            case 0x007D: case 0x0085: case 0x0127: case 0x0128: case 0x031A:
            case 0x204E:
            case 0x1102: case 0x1109: case 0x110B: case 0x110D: case 0x1114:
            case 0x111D: case 0x111E: case 0x1125: case 0x1128: case 0x112C: case 0x113F:
                return true;
        }
        return false;
    }

    static string Hx(int v) { return "0x" + v.ToString("X"); }
    static string RectText(RECT r) { return r.L + "," + r.T + " - " + r.R + "," + r.B; }

    static string RefText(int c)
    {
        if (c == -1 || c == unchecked((int)0xFF000000)) return "default";
        return "#" + (c & 255).ToString("X2") + ((c >> 8) & 255).ToString("X2") + ((c >> 16) & 255).ToString("X2");
    }

    static string MsgName(int m)
    {
        switch (m)
        {
            case 0x0007: return "WM_SETFOCUS";
            case 0x0008: return "WM_KILLFOCUS";
            case 0x000B: return "WM_SETREDRAW";
            case 0x000F: return "WM_PAINT";
            case 0x0014: return "WM_ERASEBKGND";
            case 0x007D: return "WM_STYLECHANGED";
            case 0x0085: return "WM_NCPAINT";
            case 0x0127: return "WM_CHANGEUISTATE";
            case 0x0128: return "WM_UPDATEUISTATE";
            case 0x031A: return "WM_THEMECHANGED";
            case 0x204E: return "WM_NOTIFY(reflected)";
            case 0x111D: return "TVM_SETBKCOLOR";
            case 0x111E: return "TVM_SETTEXTCOLOR";
            case 0x1128: return "TVM_SETLINECOLOR";
            case 0x110B: return "TVM_SELECTITEM";
            case 0x112C: return "TVM_SETEXTENDEDSTYLE";
        }
        if (m >= 0x1100 && m < 0x1200) return "TVM_" + Hx(m);
        return Hx(m);
    }

    static string FlagsText(int state)
    {
        StringBuilder sb = new StringBuilder();
        if ((state & 0x1) != 0) sb.Append("SELECTED ");
        if ((state & 0x2) != 0) sb.Append("GRAYED ");
        if ((state & 0x4) != 0) sb.Append("DISABLED ");
        if ((state & 0x8) != 0) sb.Append("CHECKED ");
        if ((state & 0x10) != 0) sb.Append("FOCUS ");
        if ((state & 0x40) != 0) sb.Append("HOT ");
        if ((state & 0x80) != 0) sb.Append("MARKED ");
        return sb.ToString().Trim();
    }

    static string PixelText(IntPtr h, int x, int y)
    {
        IntPtr hdc = GetDC(h);
        if (hdc == IntPtr.Zero) return "?";
        try
        {
            int c = GetPixel(hdc, x, y);
            if (c == -1) return "?";
            string s = RefText(c);
            if ((c & 255) >= 0xF8 && ((c >> 8) & 255) >= 0xF8 && ((c >> 16) & 255) >= 0xF8) s += " WHITE";
            else if ((c & 255) >= 0xD8 && ((c >> 8) & 255) >= 0xD8 && ((c >> 16) & 255) >= 0xD8) s += " LIGHT";
            return s;
        }
        finally { ReleaseDC(h, hdc); }
    }

    // NM_CUSTOMDRAW (-12): draw stage, item state, what the control answered and the colors it chose.
    static string NotifyText(ref Message m)
    {
        if (m.LParam == IntPtr.Zero) return "";
        int p = IntPtr.Size;
        int code = Marshal.ReadInt32(m.LParam, p * 2);
        if (code != -12)
        {
            if (code == -2) return " NM_CLICK";
            if (code == -3) return " NM_DBLCLK";
            if (code == -7) return " NM_SETFOCUS";
            if (code == -8) return " NM_KILLFOCUS";
            if (code == -450) return " TVN_SELCHANGING";
            if (code == -451) return " TVN_SELCHANGED";
            return null;                       // everything else is noise
        }
        int stage = Marshal.ReadInt32(m.LParam, p * 3);
        int state = Marshal.ReadInt32(m.LParam, 6 * p + 16);
        if ((stage & 0x10000) != 0 && (state & (0x1 | 0x10 | 0x40)) == 0) return null;   // other rows: skip
        string s = " NM_CUSTOMDRAW stage " + Hx(stage) + " state [" + FlagsText(state) + "] answer " + Hx(unchecked((int)m.Result.ToInt64()));
        if ((stage & 0x10000) != 0)
        {
            int sz = (p == 8) ? 80 : 48;
            s += " text " + RefText(Marshal.ReadInt32(m.LParam, sz)) + " textbk " + RefText(Marshal.ReadInt32(m.LParam, sz + 4));
        }
        return s;
    }

    static void TraceAfter(Guard g, ref Message m, RECT upd, string note)
    {
        try
        {
            int msg = m.Msg;
            string s = g.Label + "  " + MsgName(msg);
            if (msg == WM_PAINT)
            {
                s += "  area " + RectText(upd);
                if (upd.R > upd.L && upd.B > upd.T)
                {
                    int cy = (upd.T + upd.B) / 2;
                    s += "  left " + PixelText(m.HWnd, upd.L + 2, cy) + "  middle " + PixelText(m.HWnd, (upd.L + upd.R) / 2, cy);
                }
                if (g.IsTree)
                {
                    // What the selected row really looks like on screen right after this paint: inside its
                    // highlight (left / right padding) and just outside it (the list background).
                    RECT sr;
                    if (SelectedRowRect(m.HWnd, out sr))
                    {
                        int sy = (sr.T + sr.B) / 2;
                        s += "  || SELECTED ROW " + RectText(sr) + ": inside-left " + PixelText(m.HWnd, sr.L + 2, sy)
                           + "  inside-right " + PixelText(m.HWnd, sr.R - 3, sy) + "  outside-right " + PixelText(m.HWnd, sr.R + 12, sy);
                    }
                }
            }
            else if (msg == WM_ERASEBKGND)
            {
                RECT cb;
                if (m.WParam != IntPtr.Zero && GetClipBox(m.WParam, out cb) > 0) s += "  area " + RectText(cb);
            }
            else if (msg == WM_REFLECT_NOTIFY)
            {
                string nt = NotifyText(ref m);
                if (nt == null) return;
                s += nt;
            }
            else if (msg >= 0x1100 && msg < 0x1200) s += "  w=" + m.WParam.ToInt64().ToString("X") + " l=" + m.LParam.ToInt64().ToString("X");
            if (note.Length > 0) s += "   [" + note + "]";
            Trace(s);
        }
        catch { }
    }

    static void DumpInventory(string why)
    {
        if (!TraceOn || inventoryRuns >= 3) return;
        inventoryRuns++;
        Trace("==== control inventory (" + why + ") ====");
        List<Form> forms = new List<Form>();
        try { foreach (Form f in Application.OpenForms) forms.Add(f); } catch { }
        foreach (Form f in forms)
        {
            try { if (!f.IsDisposed && f.IsHandleCreated) InventoryOf(f, 0); } catch { }
        }
        Trace("==== end of inventory ====");
    }

    static void InventoryOf(Control c, int depth)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append(new string(' ', depth * 2));
        Type t = c.GetType();
        sb.Append(t.FullName);
        Type b = t.BaseType;
        int n = 0;
        while (b != null && b != typeof(Control) && n++ < 8) { sb.Append(" : ").Append(b.Name); b = b.BaseType; }
        try { if (!string.IsNullOrEmpty(c.Name)) sb.Append("  name=").Append(c.Name); } catch { }
        try { sb.Append("  ").Append(c.Bounds.Width).Append('x').Append(c.Bounds.Height).Append(" visible=").Append(c.Visible).Append(" dock=").Append(c.Dock); } catch { }
        if (IsRdp(c)) { sb.Append("  (RDP session - not entered)"); Trace(sb.ToString()); return; }
        IntPtr h = IntPtr.Zero;
        if (c.IsHandleCreated)
        {
            h = c.Handle;
            sb.Append("  class=").Append(ClassOf(h));
            try { sb.Append("  style=").Append(Hx(GetWindowLong(h, GWL_STYLE))).Append(" exstyle=").Append(Hx(GetWindowLong(h, -20))); } catch { }
        }
        try
        {
            System.Reflection.PropertyInfo db = typeof(Control).GetProperty("DoubleBuffered", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            if (db != null) sb.Append("  DoubleBuffered=").Append(db.GetValue(c, null));
        }
        catch { }
        TreeView tv = c as TreeView;
        if (tv != null)
        {
            try
            {
                sb.Append("  [TreeView DrawMode=").Append(tv.DrawMode).Append(" HideSelection=").Append(tv.HideSelection)
                  .Append(" HotTracking=").Append(tv.HotTracking).Append(" FullRowSelect=").Append(tv.FullRowSelect)
                  .Append(" ShowLines=").Append(tv.ShowLines).Append(" Focused=").Append(tv.Focused).Append("]");
            }
            catch { }
            if (tv.IsHandleCreated)
            {
                try
                {
                    sb.Append("  treeExStyle=").Append(Hx((int)SendMessage(h, TVM_GETEXTENDEDSTYLE, IntPtr.Zero, IntPtr.Zero).ToInt64()))
                      .Append(" treeBack=").Append(RefText((int)SendMessage(h, TVM_GETBKCOLOR, IntPtr.Zero, IntPtr.Zero).ToInt64()))
                      .Append(" treeText=").Append(RefText((int)SendMessage(h, TVM_GETTEXTCOLOR, IntPtr.Zero, IntPtr.Zero).ToInt64()));
                }
                catch { }
            }
            try
            {
                TreeNode sn = tv.SelectedNode;
                if (sn != null) sb.Append("  selectedNode back=").Append(sn.BackColor).Append(" fore=").Append(sn.ForeColor);
            }
            catch { }
        }
        ListView lv = c as ListView;
        if (lv != null)
        {
            try { sb.Append("  [ListView View=").Append(lv.View).Append(" OwnerDraw=").Append(lv.OwnerDraw).Append(" FullRowSelect=").Append(lv.FullRowSelect).Append(" HideSelection=").Append(lv.HideSelection).Append("]"); } catch { }
        }
        ListBox lb = c as ListBox;
        if (lb != null)
        {
            try { sb.Append("  [ListBox DrawMode=").Append(lb.DrawMode).Append("]"); } catch { }
        }
        Trace(sb.ToString());
        Control[] kids = new Control[c.Controls.Count];
        c.Controls.CopyTo(kids, 0);
        foreach (Control k in kids) InventoryOf(k, depth + 1);
    }

    // Safety valve: if some code keeps fighting us, stop correcting events (the sweep still runs).
    static bool CanFix()
    {
        int now = Environment.TickCount;
        if (now - fixWindowStart > 1000 || now < fixWindowStart) { fixWindowStart = now; fixCount = 0; }
        return ++fixCount < 400;
    }

    static void WatchAx(AxHost ax)
    {
        if (watched.Contains(ax)) return;
        watched.Add(ax);
        ax.HandleCreated += delegate (object sender, EventArgs e) { try { if (Opt("sessionguard")) Protect((Control)sender, false); } catch { } };
        ax.Disposed += delegate (object sender, EventArgs e) { watched.Remove((Control)sender); };
    }

    // ---- window class brush + creation hook -------------------------------------------
    // Windows paints a brand-new (or just-invalidated) window with its CLASS background brush
    // before anyone gets a say - that is the white frame. So the class brush of every WinForms
    // window class is swapped to the theme color, and a WH_CBT hook (runs synchronously inside
    // CreateWindowEx, on RDCMan's UI thread) does it for a class the moment its first window is
    // created, i.e. before that window can ever be drawn.
    // Only plain WinForms windows ("WindowsForms10.Window.*": forms, panels, drop-downs, the RDP
    // wrapper) are touched - never the RDP control's own windows or native dialogs.
    delegate IntPtr CbtProc(int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint = "SetWindowsHookExW")] static extern IntPtr SetWindowsHookEx(int idHook, CbtProc fn, IntPtr hMod, uint threadId);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", EntryPoint = "SetClassLongPtrW")] static extern IntPtr SetClassLongPtr64(IntPtr h, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint = "SetClassLongW")] static extern IntPtr SetClassLong32(IntPtr h, int index, IntPtr value);

    const int WH_CBT = 5, HCBT_CREATEWND = 3, GCLP_HBRBACKGROUND = -10;
    static CbtProc cbtProc;
    static readonly Dictionary<uint, IntPtr> cbtHooks = new Dictionary<uint, IntPtr>();
    static readonly HashSet<string> fixedClasses = new HashSet<string>();

    static void EnsureBgBrush()
    {
        if (bgBrush == IntPtr.Zero) bgBrush = CreateSolidBrush(Ref(CBack));
    }

    // Installs the creation hook on the calling thread (must be RDCMan's UI thread; called again
    // from the sweep, which always runs there, in case the first call came from another thread).
    static void EnsureCbt()
    {
        if (!GuardOn) return;
        try
        {
            uint tid = GetCurrentThreadId();
            lock (cbtHooks)
            {
                if (cbtHooks.ContainsKey(tid)) return;
                if (cbtProc == null) cbtProc = OnCbt;
                IntPtr hk = SetWindowsHookEx(WH_CBT, cbtProc, IntPtr.Zero, tid);
                cbtHooks[tid] = hk;
                Log("window-creation hook " + (hk != IntPtr.Zero ? "installed" : "NOT installed") + " on thread " + tid);
            }
        }
        catch { }
    }

    static IntPtr OnCbt(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode == HCBT_CREATEWND) { try { FixClass(wParam); } catch { } }
        return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    static void FixClass(IntPtr h)
    {
        if (!GuardOn || h == IntPtr.Zero) return;
        string cls = ClassOf(h);
        if (cls.IndexOf("WindowsForms10.Window.", StringComparison.OrdinalIgnoreCase) != 0) return;
        lock (fixedClasses) { if (!fixedClasses.Add(cls)) return; }
        EnsureBgBrush();
        if (IntPtr.Size == 8) SetClassLongPtr64(h, GCLP_HBRBACKGROUND, bgBrush);
        else SetClassLong32(h, GCLP_HBRBACKGROUND, bgBrush);
        if (fixedClasses.Count <= 12) Log("class brush set: " + cls);
    }

    static bool FillBackground(IntPtr h, IntPtr hdc)
    {
        if (hdc == IntPtr.Zero) return false;
        EnsureBgBrush();
        RECT rc;
        if (!GetClientRect(h, out rc)) return false;
        int saved = SaveDC(hdc);
        for (IntPtr k = GetWindow(h, GW_CHILD); k != IntPtr.Zero; k = GetWindow(k, GW_HWNDNEXT))
        {
            if (!IsWindowVisible(k)) continue;
            RECT kr;
            GetWindowRect(k, out kr);
            MapWindowPoints(IntPtr.Zero, h, ref kr, 2);
            ExcludeClipRect(hdc, kr.L, kr.T, kr.R, kr.B);
        }
        FillRect(hdc, ref rc, bgBrush);
        RestoreDC(hdc, saved);
        return true;
    }

    static void CollectBackgroundWindows(IntPtr parent, List<IntPtr> found, StringBuilder tree, int depth)
    {
        for (IntPtr k = GetWindow(parent, GW_CHILD); k != IntPtr.Zero; k = GetWindow(k, GW_HWNDNEXT))
        {
            string cls = ClassOf(k);
            RECT r; GetWindowRect(k, out r);
            bool session = InList(cls, SessionClasses);
            bool bg = !session && InList(cls, BackgroundClasses);
            if (tree != null)
                tree.AppendFormat("  {0}{1}  {2}x{3}  visible={4}{5}{6}",
                    new string(' ', depth * 2), cls, r.R - r.L, r.B - r.T, IsWindowVisible(k),
                    session ? "  (session - never touched)" : (bg ? "  (background recolored)" : ""), Environment.NewLine);
            if (session) continue;                  // never look inside the session windows
            if (bg) found.Add(k);
            CollectBackgroundWindows(k, found, tree, depth + 1);
        }
    }

    static void HookRdpBackground(AxHost ax)
    {
        if (!ax.IsHandleCreated) return;
        IntPtr root = ax.Handle;
        StringBuilder tree = bgLogged.Contains(root) ? null : new StringBuilder();
        List<IntPtr> found = new List<IntPtr>();
        CollectBackgroundWindows(root, found, tree, 0);
        if (tree != null)
        {
            bgLogged.Add(root);
            Log("RDP control " + ax.GetType().Name + " windows:" + Environment.NewLine + tree.ToString().TrimEnd());
        }
        foreach (IntPtr h in found)
        {
            if (bgHooks.ContainsKey(h)) continue;
            EraseHook hook = new EraseHook();
            hook.AssignHandle(h);
            bgHooks[h] = hook;
            InvalidateRect(h, IntPtr.Zero, true);   // repaint only this container's empty area
        }
    }

    static void CleanBackgroundHooks()
    {
        List<IntPtr> dead = new List<IntPtr>();
        foreach (IntPtr h in bgHooks.Keys) if (!IsWindow(h)) dead.Add(h);
        foreach (IntPtr h in dead) bgHooks.Remove(h);
        if (bgLogged.Count > 500) bgLogged.Clear();
    }

    static Color Hex(string s)
    {
        s = (s ?? "").Trim().TrimStart('#');
        int v = Convert.ToInt32(s, 16);
        return Color.FromArgb(255, (v >> 16) & 255, (v >> 8) & 255, v & 255);
    }

    public static bool SessionBg;   // color the empty area around a small session

    public static void Begin(string back, string text, string line, int pollMs)
    {
        if (started) return;
        started = true;
        try { GuardOn = !System.IO.File.Exists(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "rdcman-color-noguard.txt")); } catch { }
        LoadOptions();
        if (Opt("trace")) TraceOn = true;
        if (TraceOn)
        {
            if (string.IsNullOrEmpty(TracePath)) TracePath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "rdcman-color-trace.txt");
            traceStart = Environment.TickCount;
            traceArmedUntil = traceStart - 1;
            try
            {
                System.IO.File.WriteAllText(TracePath, "RDCMan color trace  " + DateTime.Now.ToString("s") + Environment.NewLine
                    + "runtime " + Environment.Version + "  os " + Environment.OSVersion.VersionString + "  pointer " + IntPtr.Size + " bytes" + Environment.NewLine
                    + "guard " + GuardOn + "  options [" + string.Join(" ", new List<string>(opts).ToArray()) + "]" + Environment.NewLine
                    + "colors back " + back + " text " + text + " line " + line + Environment.NewLine
                    + "How to read this: a focus change arms the recorder for 0.8 s; lines after it are what the windows did." + Environment.NewLine);
            }
            catch { }
        }
        CBack = Hex(back);
        CText = Hex(text);
        CLine = Hex(line);
        CAccent = Mix(CBack, CText, 0.25);
        Dark = (0.299 * CBack.R + 0.587 * CBack.G + 0.114 * CBack.B) < 140;
        EnsureCbt();
        // Begin runs on RDCMan's UI thread, so these events arrive there, right as windows appear.
        try
        {
            winEventProc = OnWinEvent;
            winEventHook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_SHOW, IntPtr.Zero,
                                           winEventProc, GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
        }
        catch { }
        // Backup sweep in case anything was missed.
        timer = new System.Threading.Timer(Tick, null, 300, Math.Max(250, pollMs));
    }

    static Color Mix(Color a, Color b, double t)
    {
        return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
    }

    static int Ref(Color c) { return c.R | (c.G << 8) | (c.B << 16); }

    static void Tick(object state)
    {
        if (Interlocked.CompareExchange(ref busy, 1, 0) != 0) return;
        List<Form> forms = new List<Form>();
        try { foreach (Form f in Application.OpenForms) forms.Add(f); } catch { }
        Form host = null;
        foreach (Form f in forms) { if (f.IsHandleCreated && !f.IsDisposed) { host = f; break; } }
        if (host == null) { Interlocked.Exchange(ref busy, 0); return; }
        try { host.BeginInvoke(new MethodInvoker(delegate { PaintAll(forms); })); }
        catch { Interlocked.Exchange(ref busy, 0); }
    }

    static void PaintAll(List<Form> forms)
    {
        try
        {
            EnsureCbt();
            if (TraceOn && inventoryRuns == 0 && Environment.TickCount - traceStart > 4000) DumpInventory("4 s after start");
            if (themed.Count > 5000) themed.Clear();
            if (scrollState.Count > 5000) scrollState.Clear();
            if (smoothTrees.Count > 1000) smoothTrees.Clear();
            CleanBackgroundHooks();
            if (captioned.Count > 1000) captioned.Clear();
            if (renderer == null) renderer = new Renderer();
            if (ToolStripManager.Renderer != renderer) ToolStripManager.Renderer = renderer;
            foreach (Form f in forms)
            {
                if (f.IsDisposed || !f.IsHandleCreated || f.InvokeRequired) continue;
                Caption(f);
                Walk(f);
            }
        }
        catch { }
        finally { Interlocked.Exchange(ref busy, 0); }
    }

    // Title bar + border (color on Windows 11; dark/light title on Windows 10).
    static void CaptionAttrs(IntPtr h)
    {
        try
        {
            int dark = Dark ? 1 : 0;
            if (DwmSetWindowAttribute(h, 20, ref dark, 4) != 0) DwmSetWindowAttribute(h, 19, ref dark, 4);
            int cap = Ref(CBack), txt = Ref(CText), brd = Ref(CLine);
            DwmSetWindowAttribute(h, 35, ref cap, 4);   // caption color  (Windows 11)
            DwmSetWindowAttribute(h, 36, ref txt, 4);   // title text     (Windows 11)
            DwmSetWindowAttribute(h, 34, ref brd, 4);   // border         (Windows 11)
        }
        catch { }
    }

    // Title bar colors are normally set the moment the window is created (before it is
    // ever drawn), so there is nothing to redraw and nothing flickers. Only a window that
    // was already on screen when first seen gets one frame repaint.
    static void Caption(Form f)
    {
        IntPtr h = f.Handle;
        string title = f.Text ?? "";
        string last;
        bool seen = captioned.TryGetValue(h, out last);
        if (seen && last == title) return;
        captioned[h] = title;
        CaptionAttrs(h);
        if (!seen && IsWindowVisible(h))
        {
            try { RedrawWindow(h, IntPtr.Zero, IntPtr.Zero, RDW_FRAME_NOW); } catch { }
        }
    }

    static void OnWinEvent(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        if (idObject != 0 || idChild != 0 || hwnd == IntPtr.Zero) return;   // whole windows only
        try
        {
            Control c = Control.FromHandle(hwnd);          // only RDCMan's own WinForms windows
            if (c == null || c.IsDisposed) return;
            if (renderer == null) renderer = new Renderer();
            if (ToolStripManager.Renderer != renderer) ToolStripManager.Renderer = renderer;
            Form f = c as Form;
            if (ev == EVENT_OBJECT_CREATE)
            {
                if (f != null && !captioned.ContainsKey(hwnd))
                {
                    CaptionAttrs(hwnd);
                    captioned[hwnd] = "\u0000";             // seen; title not recorded yet
                }
                return;
            }
            if (f != null) Caption(f);
            Walk(c);
        }
        catch { }
    }

    // New controls are colored the moment they are added, before they are drawn.
    static void Watch(Control c)
    {
        if (watched.Contains(c)) return;
        watched.Add(c);
        c.ControlAdded += delegate (object sender, ControlEventArgs e) { try { Walk(e.Control); } catch { } };
        c.HandleCreated += delegate (object sender, EventArgs e) { try { Style((Control)sender); } catch { } };
        // The moment something changes a color, put ours back (before the next paint, not on the next sweep).
        c.BackColorChanged += delegate (object sender, EventArgs e)
        {
            try { Control x = (Control)sender; if (!x.IsDisposed && !IsRdp(x) && x.BackColor != CBack) { if (TraceOn && x is TreeView) TraceWho("BackColor property set to", x.BackColor.Name); if (CanFix()) x.BackColor = CBack; } } catch { }
        };
        c.ForeColorChanged += delegate (object sender, EventArgs e)
        {
            try { Control x = (Control)sender; if (!x.IsDisposed && !IsRdp(x) && x.ForeColor != CText) { if (TraceOn && x is TreeView) TraceWho("ForeColor property set to", x.ForeColor.Name); if (CanFix()) x.ForeColor = CText; } } catch { }
        };
        c.Disposed += delegate (object sender, EventArgs e) { watched.Remove((Control)sender); };
    }

    // RDP session controls (the remote screen) and everything inside them are skipped.
    static bool IsRdp(Control c)
    {
        if (c is AxHost) return true;
        string n = c.GetType().FullName ?? "";
        return n.IndexOf("MsRdp", StringComparison.OrdinalIgnoreCase) >= 0
            || n.IndexOf("MsTsc", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    static void Walk(Control c)
    {
        if (c.IsDisposed) return;
        if (IsRdp(c))
        {
            // Only the empty background around the session; the session itself is untouched.
            AxHost ax = c as AxHost;
            if (ax != null)
            {
                WatchAx(ax);
                try { if (Opt("sessionguard")) Protect(ax, false); } catch { }      // opt-in: wrapper window behind the session
                if (SessionBg) { try { HookRdpBackground(ax); } catch { } }
            }
            return;
        }
        Watch(c);
        Style(c);
        if (c.ContextMenuStrip != null) Strip(c.ContextMenuStrip);
        ToolStrip ts = c as ToolStrip;
        if (ts != null) Strip(ts);
        Control[] kids = new Control[c.Controls.Count];
        c.Controls.CopyTo(kids, 0);
        foreach (Control k in kids) Walk(k);
    }

    static void Style(Control c)
    {
        try
        {
            if (c.IsHandleCreated && !(c is ToolStrip))
            {
                if (c is TreeView) Protect(c, true);
                else if (c is ScrollableControl) Protect(c, false);   // forms, panels, split panels, tab pages ...
                else if (TraceOn) ProtectPassive(c);                  // recorder only
            }
            if (c.BackColor != CBack) c.BackColor = CBack;
            if (c.ForeColor != CText) c.ForeColor = CText;
            TreeView tv = c as TreeView;
            if (tv != null && tv.LineColor != CLine) tv.LineColor = CLine;
            if (tv != null && tv.IsHandleCreated && !smoothTrees.Contains(tv.Handle))
            {
                smoothTrees.Add(tv.Handle);
                SendMessage(tv.Handle, TVM_SETEXTENDEDSTYLE, (IntPtr)TVS_EX_DOUBLEBUFFER, (IntPtr)TVS_EX_DOUBLEBUFFER);
            }
            if (tv != null && tv.IsHandleCreated) HardenTree(tv);
            if (c is TreeView || c is ListView || c is ListBox || c is TextBoxBase || c is ScrollableControl)
            {
                Theme(c, Dark ? "DarkMode_Explorer" : "Explorer");
                FrameOnScrollChange(c);
            }
            else if (c is ComboBox)
                Theme(c, Dark ? "DarkMode_CFD" : "CFD");
        }
        catch { }
    }

    // When a scrollbar appears or disappears (e.g. a group is expanded), repaint the frame
    // so the scrollbars and the corner square between them get the theme color right away.
    static void FrameOnScrollChange(Control c)
    {
        if (!c.IsHandleCreated) return;
        IntPtr h = c.Handle;
        int bars = GetWindowLong(h, GWL_STYLE) & WS_SCROLLBARS;
        int last;
        if (scrollState.TryGetValue(h, out last) && last == bars) return;
        scrollState[h] = bars;
        SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, SWP_REFRESH_FRAME);
        RedrawWindow(h, IntPtr.Zero, IntPtr.Zero, RDW_FRAME_NOW);
    }

    // Scrollbars and selection highlight follow the light/dark theme.
    static void Theme(Control c, string name)
    {
        if (!c.IsHandleCreated) return;
        IntPtr h = c.Handle;
        if (themed.Contains(h)) return;
        themed.Add(h);
        try
        {
            SetWindowTheme(h, name, null);
            // Repaint the frame now (scrollbars and the small corner square between them);
            // otherwise it only updates after the control is resized.
            SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, SWP_REFRESH_FRAME);
            RedrawWindow(h, IntPtr.Zero, IntPtr.Zero, RDW_FRAME_NOW);
        }
        catch { }
    }

    static void Strip(ToolStrip s)
    {
        try
        {
            if (s.Renderer != renderer) s.Renderer = renderer;
            if (s.BackColor != CBack) s.BackColor = CBack;
            if (s.ForeColor != CText) s.ForeColor = CText;
            ToolStripItem[] items = new ToolStripItem[s.Items.Count];
            s.Items.CopyTo(items, 0);
            foreach (ToolStripItem i in items) Item(i);
        }
        catch { }
    }

    static void Item(ToolStripItem i)
    {
        if (i.ForeColor != CText) i.ForeColor = CText;
        ToolStripDropDownItem d = i as ToolStripDropDownItem;
        if (d != null && d.HasDropDownItems) Strip(d.DropDown);
    }

    class Renderer : ToolStripProfessionalRenderer
    {
        public Renderer() : base(new Table()) { RoundedEdges = false; }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? CText : CLine;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = CText;
            base.OnRenderArrow(e);
        }
    }

    class Table : ProfessionalColorTable
    {
        public override Color MenuStripGradientBegin { get { return CBack; } }
        public override Color MenuStripGradientEnd { get { return CBack; } }
        public override Color ToolStripDropDownBackground { get { return CBack; } }
        public override Color ImageMarginGradientBegin { get { return CBack; } }
        public override Color ImageMarginGradientMiddle { get { return CBack; } }
        public override Color ImageMarginGradientEnd { get { return CBack; } }
        public override Color MenuItemSelected { get { return CAccent; } }
        public override Color MenuItemSelectedGradientBegin { get { return CAccent; } }
        public override Color MenuItemSelectedGradientEnd { get { return CAccent; } }
        public override Color MenuItemPressedGradientBegin { get { return CAccent; } }
        public override Color MenuItemPressedGradientMiddle { get { return CAccent; } }
        public override Color MenuItemPressedGradientEnd { get { return CAccent; } }
        public override Color MenuItemBorder { get { return CLine; } }
        public override Color MenuBorder { get { return CLine; } }
        public override Color SeparatorDark { get { return CLine; } }
        public override Color SeparatorLight { get { return CBack; } }
        public override Color ToolStripGradientBegin { get { return CBack; } }
        public override Color ToolStripGradientMiddle { get { return CBack; } }
        public override Color ToolStripGradientEnd { get { return CBack; } }
        public override Color ToolStripBorder { get { return CBack; } }
        public override Color StatusStripGradientBegin { get { return CBack; } }
        public override Color StatusStripGradientEnd { get { return CBack; } }
        public override Color ToolStripContentPanelGradientBegin { get { return CBack; } }
        public override Color ToolStripContentPanelGradientEnd { get { return CBack; } }
        public override Color ToolStripPanelGradientBegin { get { return CBack; } }
        public override Color ToolStripPanelGradientEnd { get { return CBack; } }
        public override Color OverflowButtonGradientBegin { get { return CBack; } }
        public override Color OverflowButtonGradientMiddle { get { return CBack; } }
        public override Color OverflowButtonGradientEnd { get { return CBack; } }
        public override Color ButtonSelectedHighlight { get { return CAccent; } }
        public override Color ButtonSelectedGradientBegin { get { return CAccent; } }
        public override Color ButtonSelectedGradientMiddle { get { return CAccent; } }
        public override Color ButtonSelectedGradientEnd { get { return CAccent; } }
        public override Color ButtonSelectedBorder { get { return CLine; } }
        public override Color ButtonPressedGradientBegin { get { return CAccent; } }
        public override Color ButtonPressedGradientMiddle { get { return CAccent; } }
        public override Color ButtonPressedGradientEnd { get { return CAccent; } }
        public override Color ButtonCheckedGradientBegin { get { return CAccent; } }
        public override Color ButtonCheckedGradientMiddle { get { return CAccent; } }
        public override Color ButtonCheckedGradientEnd { get { return CAccent; } }
        public override Color CheckBackground { get { return CAccent; } }
        public override Color CheckSelectedBackground { get { return CAccent; } }
        public override Color CheckPressedBackground { get { return CAccent; } }
        public override Color GripDark { get { return CLine; } }
        public override Color GripLight { get { return CBack; } }
    }
}

// RDCMan 2.x (.NET Framework): created inside RDCMan's AppDomain by this script.
public class RdcColorizer : MarshalByRefObject
{
    public override object InitializeLifetimeService() { return null; }
    public void Start(string back, string text, string line, int pollMs, bool sessionBg, bool trace, string tracePath)
    {
        RdcPaint.SessionBg = sessionBg;
        RdcPaint.TraceOn = trace;
        RdcPaint.TracePath = tracePath;
        RdcPaint.Begin(back, text, line, pollMs);
    }
}

// RDCMan 3.x (.NET 8, single exe): .NET loads this inside RDCMan at startup
// because the script sets DOTNET_STARTUP_HOOKS when it launches RDCMan.exe.
internal class StartupHook
{
    public static void Initialize()
    {
        string log = Environment.GetEnvironmentVariable("RDCMAN_COLOR_LOG");
        try
        {
            string back = Environment.GetEnvironmentVariable("RDCMAN_COLOR_BACK");
            string text = Environment.GetEnvironmentVariable("RDCMAN_COLOR_TEXT");
            string line = Environment.GetEnvironmentVariable("RDCMAN_COLOR_LINE");
            int poll;
            if (!int.TryParse(Environment.GetEnvironmentVariable("RDCMAN_COLOR_POLL"), out poll) || poll <= 0) poll = 1000;
            // Do not pass the hook on to anything RDCMan starts.
            Environment.SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", null);
            if (string.IsNullOrEmpty(back)) { Log(log, "loaded, but no colors were given"); return; }
            RdcPaint.LogPath = log;
            RdcPaint.SessionBg = Environment.GetEnvironmentVariable("RDCMAN_COLOR_SESSIONBG") == "1";
            RdcPaint.TraceOn = Environment.GetEnvironmentVariable("RDCMAN_COLOR_TRACE") == "1";
            RdcPaint.TracePath = Environment.GetEnvironmentVariable("RDCMAN_COLOR_TRACELOG");
            RdcPaint.Begin(back, text, line, poll);
            Log(log, "loaded inside RDCMan");
        }
        catch (Exception e) { Log(log, "ERROR " + e); }
    }

    static void Log(string path, string msg)
    {
        if (string.IsNullOrEmpty(path)) return;
        try { System.IO.File.AppendAllText(path, DateTime.Now.ToString("s") + " " + msg + Environment.NewLine); } catch { }
    }
}
'@

# Compile once per code version (hash in the name, so edits never reuse old code).
function Get-ColorDll {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source))).Replace('-', '').Substring(0, 10)
    $script:typeName = "RdcColorizer_$hash"
    $dll = Join-Path $env:TEMP "$($script:typeName).dll"
    if (-not (Test-Path $dll)) {
        Add-Type -TypeDefinition $source.Replace('RdcColorizer', $script:typeName) `
                 -ReferencedAssemblies System.Windows.Forms, System.Drawing `
                 -OutputAssembly $dll -OutputType Library
    }
    return $dll
}

# ------------------------------------------------------------ pick a theme ---
if ($BackColor) { $theme = New-Theme 'Custom' $BackColor $TextColor $LineColor }
elseif ($Choice -ge 1 -and $Choice -le $themes.Count) { $theme = $themes[$Choice - 1] }
else { $theme = Select-Theme }
if (-not $theme) {
    Write-Host 'Cancelled.'
    if (-not $HostChild) { [void](Read-Host 'Press Enter to close') }
    return
}

# Not found anywhere (and not set in the menu): ask for it.
if (-not $script:exe) {
    Write-Host ''
    Write-Host 'RDCMan.exe was not found.' -ForegroundColor Yellow
    $script:exe = Read-RdcmanPath $null
}
$exe = $script:exe

# =================== which RDCMan is this? ===================================
# RDCMan 2.x is a plain .NET Framework exe (loaded inside the script).
# RDCMan 3.x is one big .NET 8 exe (started normally, color code loaded via startup hook).
function Test-ManagedExe([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try { [void][Reflection.AssemblyName]::GetAssemblyName($Path); return $true } catch { return $false }
}

# =================== RDCMan 3.x: launch with the startup hook ================
function Show-TraceHint {
    if (-not $script:traceOn) { return }
    Write-Host ''
    if (Test-Path -LiteralPath $traceLog) {
        $n = @(Get-Content -LiteralPath $traceLog -ErrorAction SilentlyContinue).Count
        Write-Host "Blink trace saved: $traceLog  ($n lines)" -ForegroundColor Cyan
        Write-Host 'Attach or paste that file when reporting the blink.' -ForegroundColor Cyan
    }
    else { Write-Host 'No trace file was written (the color code may not have loaded).' -ForegroundColor Yellow }
}

function Invoke-HookMode($Theme, [string]$Exe) {
    $dll = Get-ColorDll
    $hookLog = Join-Path $env:TEMP 'rdcman-color-hook.txt'
    $vars = 'DOTNET_STARTUP_HOOKS', 'RDCMAN_COLOR_BACK', 'RDCMAN_COLOR_TEXT', 'RDCMAN_COLOR_LINE', 'RDCMAN_COLOR_POLL', 'RDCMAN_COLOR_LOG', 'RDCMAN_COLOR_SESSIONBG', 'RDCMAN_COLOR_TRACE', 'RDCMAN_COLOR_TRACELOG'

    while ($true) {
        Remove-Item -LiteralPath $hookLog -Force -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host ('Using "{0}": back {1}, text {2}, lines {3}' -f $Theme.Name, $Theme.Back, $Theme.Text, $Theme.Line) -ForegroundColor Green
        Write-Host ('Background around a small session: {0}' -f (Get-SessionBgText))
        Write-Host "Starting $Exe (RDCMan 3.x)"

        $env:DOTNET_STARTUP_HOOKS = $dll
        $env:RDCMAN_COLOR_BACK = $Theme.Back
        $env:RDCMAN_COLOR_TEXT = $Theme.Text
        $env:RDCMAN_COLOR_LINE = $Theme.Line
        $env:RDCMAN_COLOR_POLL = "$PollMs"
        $env:RDCMAN_COLOR_SESSIONBG = if ($script:sessionBg) { '1' } else { '0' }
        $env:RDCMAN_COLOR_LOG  = $hookLog
        $env:RDCMAN_COLOR_TRACE = if ($script:traceOn) { '1' } else { '0' }
        $env:RDCMAN_COLOR_TRACELOG = $traceLog
        if ($script:traceOn) { Write-Host "Blink trace is ON - recording to $traceLog" -ForegroundColor Cyan }
        try { $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -LiteralPath $Exe) -PassThru }
        finally { foreach ($v in $vars) { Remove-Item -Path "Env:$v" -ErrorAction SilentlyContinue } }

        # Wait up to 30 s for the color code to report in from inside RDCMan.
        $loaded = $false
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Milliseconds 500
            $txt = if (Test-Path -LiteralPath $hookLog) { Get-Content -LiteralPath $hookLog -Raw } else { '' }
            if ($txt -match 'loaded inside RDCMan') { $loaded = $true; break }
            if ($txt -match 'ERROR') { break }
            if ($proc.HasExited) { break }
        }

        if (-not $loaded) {
            Write-Host ''
            Write-Host 'The color code did not load inside RDCMan.' -ForegroundColor Yellow
            if (Test-Path -LiteralPath $hookLog) { Get-Content -LiteralPath $hookLog | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }
            if ($proc.HasExited) {
                Write-Host "RDCMan exited right away (exit code $($proc.ExitCode))." -ForegroundColor Yellow
                $again = (Read-Host 'Press R + Enter to try again, or just Enter to close').Trim()
                if ($again -match '^[Rr]$') { continue }
                return
            }
            Write-Host 'RDCMan is running normally; switching to outside mode (tree + title bar).' -ForegroundColor Yellow
            Invoke-OutsideMode $Theme
            return
        }

        Write-Host 'Colors are applied inside RDCMan (everything except the remote screens).' -ForegroundColor Green
        Write-Host 'RDCMan runs on its own now - closing this window does NOT close RDCMan.'
        Write-Host "Details (incl. the window layout of each connected session) are logged to $hookLog"
        Write-Host 'Waiting for RDCMan to close ...'
        $proc.WaitForExit()

        Write-Host ''
        Write-Host "RDCMan closed (exit code $($proc.ExitCode))." -ForegroundColor Green
        Show-TraceHint
        $errs = @(Get-Content -LiteralPath $hookLog -ErrorAction SilentlyContinue | Where-Object { $_ -match 'ERROR' })
        if ($errs.Count) { $errs | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }
        $again = (Read-Host 'Press R + Enter to start RDCMan again, or just Enter to close').Trim()
        if ($again -notmatch '^[Rr]$') { return }
    }
}

# =================== outside mode (fallback): wait for RDCMan, recolor tree + title bar ===
$outsideSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class RdcOutside
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr hWnd, IntPtr rect, bool erase);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeoutMs, out IntPtr result);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);

    private const uint TVM_SETBKCOLOR = 0x111D, TVM_SETTEXTCOLOR = 0x111E, TVM_GETBKCOLOR = 0x111F,
                       TVM_GETTEXTCOLOR = 0x1120, TVM_SETLINECOLOR = 0x1128;

    private static string ClassOf(IntPtr h) { StringBuilder sb = new StringBuilder(256); GetClassName(h, sb, sb.Capacity); return sb.ToString(); }

    private static List<IntPtr> AllWindows(uint pid)
    {
        List<IntPtr> all = new List<IntPtr>();
        EnumWindows(delegate (IntPtr top, IntPtr l1) {
            uint p; GetWindowThreadProcessId(top, out p);
            if (p == pid) { all.Add(top); EnumChildWindows(top, delegate (IntPtr c, IntPtr l2) { all.Add(c); return true; }, IntPtr.Zero); }
            return true;
        }, IntPtr.Zero);
        return all;
    }

    private static readonly string[] RdpHints = { "UIMainClass", "UIContainerClass", "TscShell", "IHWindowClass", "OPContainerClass", "OPWindowClass", "MsRdp", "ATL:" };
    private static bool IsRdp(string cls) { foreach (string h in RdpHints) if (cls.IndexOf(h, StringComparison.OrdinalIgnoreCase) >= 0) return true; return false; }

    private static bool InsideRdp(IntPtr h, IntPtr main)
    {
        IntPtr cur = h; int g = 0;
        while (cur != IntPtr.Zero && g++ < 64) { if (IsRdp(ClassOf(cur))) return true; if (cur == main) break; cur = GetParent(cur); }
        return false;
    }

    private static bool IsTree(IntPtr h, IntPtr main)
    {
        return h != main && ClassOf(h).IndexOf("TreeView", StringComparison.OrdinalIgnoreCase) >= 0 && !InsideRdp(h, main);
    }

    public static List<IntPtr> FindTrees(uint pid, IntPtr main)
    {
        List<IntPtr> t = new List<IntPtr>();
        foreach (IntPtr h in AllWindows(pid)) if (IsTree(h, main)) t.Add(h);
        return t;
    }

    public static string[] Dump(uint pid, IntPtr main)
    {
        List<string> lines = new List<string>();
        foreach (IntPtr h in AllWindows(pid))
        {
            int d = 0; IntPtr cur = GetParent(h); while (cur != IntPtr.Zero && d < 32) { d++; cur = GetParent(cur); }
            string cls = ClassOf(h), tag = "";
            if (h == main) tag = "   <== TITLE BAR / BORDER WILL BE RECOLORED";
            else if (IsTree(h, main)) tag = "   <== WILL BE RECOLORED";
            else if (InsideRdp(h, main)) tag = "   (RDP session - never touched)";
            lines.Add(string.Format("{0}0x{1:X}  {2}{3}", new string(' ', d * 2), h.ToInt64(), cls, tag));
        }
        return lines.ToArray();
    }

    private static bool Send(IntPtr h, uint msg, int l, out uint res)
    {
        IntPtr r; IntPtr ok = SendMessageTimeout(h, msg, IntPtr.Zero, new IntPtr(l), 2, 500, out r);
        res = (uint)(r.ToInt64() & 0xFFFFFFFFL); return ok != IntPtr.Zero;
    }

    public static int Apply(IntPtr tree, int back, int text, int line)
    {
        uint cb, ct, ig;
        if (!Send(tree, TVM_GETBKCOLOR, 0, out cb) || !Send(tree, TVM_GETTEXTCOLOR, 0, out ct)) return -1;
        if (cb == (uint)back && ct == (uint)text) return 0;
        Send(tree, TVM_SETBKCOLOR, back, out ig); Send(tree, TVM_SETTEXTCOLOR, text, out ig); Send(tree, TVM_SETLINECOLOR, line, out ig);
        InvalidateRect(tree, IntPtr.Zero, true);
        return 1;
    }

    public static void ApplyCaption(IntPtr main, int back, int text, int line, bool dark)
    {
        int d = dark ? 1 : 0;
        if (DwmSetWindowAttribute(main, 20, ref d, 4) != 0) DwmSetWindowAttribute(main, 19, ref d, 4);
        int a = back, b = text, c = line;
        DwmSetWindowAttribute(main, 35, ref a, 4); DwmSetWindowAttribute(main, 36, ref b, 4); DwmSetWindowAttribute(main, 34, ref c, 4);
    }
}
'@

function ConvertTo-ColorRef([string]$Hex) { $c = Get-Rgb $Hex; return [int]($c[0] -bor ($c[1] -shl 8) -bor ($c[2] -shl 16)) }

function Invoke-OutsideMode($Theme) {
    $h = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($outsideSource))).Replace('-', '').Substring(0, 10)
    $tn = "RdcOutside_$h"
    if (-not ($tn -as [type])) { Add-Type -TypeDefinition $outsideSource.Replace('RdcOutside', $tn) }
    $O = $tn -as [type]
    $back = ConvertTo-ColorRef $Theme.Back; $text = ConvertTo-ColorRef $Theme.Text; $line = ConvertTo-ColorRef $Theme.Line
    $rgb = Get-Rgb $Theme.Back
    $dark = ((0.299 * $rgb[0] + 0.587 * $rgb[1] + 0.114 * $rgb[2]) -lt 140)

    Write-Host ''
    Write-Host 'OUTSIDE MODE: the real RDCMan program could not be loaded into the script,' -ForegroundColor Yellow
    Write-Host 'so only the server tree and the title bar / border can be recolored.' -ForegroundColor Yellow
    Write-Host ('Using "{0}": back {1}, text {2}, lines {3}' -f $Theme.Name, $Theme.Back, $Theme.Text, $Theme.Line) -ForegroundColor Green
    Write-Host 'Waiting for RDCMan ... (Ctrl+C to stop; this window stays open)'

    $lastPid = 0; $capPid = 0; $warnedNoTree = $false; $warnedAccess = $false
    while ($true) {
        $p = Get-Process -Name RDCMan -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
        if (-not $p) {
            if ($lastPid -ne 0) { Write-Host 'RDCMan closed. Waiting for it to start again ...'; $lastPid = 0; $capPid = 0; $warnedNoTree = $false; $warnedAccess = $false }
        }
        else {
            if ($p.Id -ne $lastPid) { Write-Host "RDCMan found (PID $($p.Id))."; $lastPid = $p.Id }
            if ($p.Id -ne $capPid) {
                try { $O::ApplyCaption([IntPtr]$p.MainWindowHandle, $back, $text, $line, $dark); Write-Host 'Recolored title bar / border.' } catch { }
                $capPid = $p.Id
            }
            $trees = $O::FindTrees([uint32]$p.Id, [IntPtr]$p.MainWindowHandle)
            if ($trees.Count -eq 0) {
                if (-not $warnedNoTree) {
                    Write-Host 'No tree control found yet (RDCMan may still be loading). Windows RDCMan owns (first 40):'
                    $O::Dump([uint32]$p.Id, [IntPtr]$p.MainWindowHandle) | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }
                    $warnedNoTree = $true
                }
            }
            else {
                $warnedNoTree = $false
                foreach ($t in $trees) {
                    $r = $O::Apply($t, $back, $text, $line)
                    if ($r -eq 1) { Write-Host ('Recolored tree 0x{0:X}' -f $t.ToInt64()) }
                    elseif ($r -lt 0 -and -not $warnedAccess) { Write-Warning "Could not send messages to RDCMan's window."; $warnedAccess = $true }
                }
            }
        }
        Start-Sleep -Milliseconds 1500
    }
}

# =================== main window: start RDCMan in a child process and wait ===
# RDCMan runs in its own PowerShell process, so even if it crashes or exits hard
# this window is NOT closed - it shows what happened and waits for you.
if (-not $HostChild) {
    try { Set-Content -Path $savedPathFile -Value $exe -Encoding UTF8 } catch { }

    # RDCMan must be started by this script; a copy opened normally cannot be recolored fully.
    while (Get-Process -Name RDCMan -ErrorAction SilentlyContinue) {
        Write-Host ''
        Write-Host 'RDCMan is already open. Close it (sessions reconnect when it reopens here),' -ForegroundColor Yellow
        [void](Read-Host 'then press Enter')
    }

    # RDCMan 3.x (single .NET 8 exe): launch it normally with the startup hook.
    if (-not (Test-ManagedExe $exe)) {
        Invoke-HookMode $theme $exe
        return
    }
    $hostExe = $exe

    while ($true) {
        Write-Host ''
        Write-Host ('Using "{0}": back {1}, text {2}, lines {3}' -f $theme.Name, $theme.Back, $theme.Text, $theme.Line) -ForegroundColor Green
        Write-Host ('Background around a small session: {0}' -f (Get-SessionBgText))
        if ($script:traceOn) { Write-Host "Blink trace is ON - recording to $traceLog" -ForegroundColor Cyan }
        Write-Host "Starting $hostExe"
        Write-Host 'Everything except the remote screens is recolored. Keep this window open.'

        $childParams = @{
            NoElevate = $true; HostChild = $true; Trace = [bool]$script:traceOn
            BackColor = $theme.Back; TextColor = $theme.Text; LineColor = $theme.Line
            RdcmanPath = $hostExe; PollMs = $PollMs
            SessionBackground = $(if ($script:sessionBg) { 'On' } else { 'Off' })
        }
        $childArgs = Get-RelaunchArgs $childParams -PassExitCode
        & $psExe @childArgs
        $code = $LASTEXITCODE

        Write-Host ''
        if ($code -eq 0) { Write-Host 'RDCMan closed.' -ForegroundColor Green }
        else { Write-Host "RDCMan stopped with exit code $code. Details are above and in $logFile" -ForegroundColor Yellow }

        Show-TraceHint
        $again = (Read-Host 'Press R + Enter to start RDCMan again, or just Enter to close').Trim()
        if ($again -notmatch '^[Rr]$') { break }
    }
    return
}

# =================== child process: host RDCMan with the recolor code ========
$dll = Get-ColorDll
$typeName = $script:typeName

# A downloaded RDCMan.exe is marked "from the internet"; .NET refuses to host it until unblocked.
try { Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue } catch { }

$setup = New-Object AppDomainSetup
$setup.ApplicationBase = Split-Path -LiteralPath $exe
if (Test-Path -LiteralPath "$exe.config") { $setup.ConfigurationFile = "$exe.config" }
$domain = [AppDomain]::CreateDomain('RDCMan', [AppDomain]::CurrentDomain.Evidence, $setup)

$failed = $false
try {
    # PowerShell only sees the cross-domain object as a plain MarshalByRefObject,
    # so call Start through reflection on the real type (loaded here too).
    $colorizer = $domain.CreateInstanceFromAndUnwrap($dll, $typeName)
    $colorType = [Reflection.Assembly]::LoadFrom($dll).GetType($typeName, $true)
    $startArgs = [object[]]@([string]$theme.Back, [string]$theme.Text, [string]$theme.Line, [int]$PollMs, [bool]$script:sessionBg, [bool]$script:traceOn, [string]$traceLog)
    [void]$colorType.GetMethod('Start').Invoke($colorizer, $startArgs)
    [void]$domain.ExecuteAssembly($exe)     # blocks until RDCMan is closed
}
catch {
    $failed = $true
    $msg = $_.Exception.ToString()
    Write-Host ''
    Write-Host 'RDCMan could not be started from the script:' -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
    try { Add-Content -Path $logFile -Value ("[{0}] {1}`r`n" -f (Get-Date), $msg) } catch { }
}
finally {
    try { [AppDomain]::Unload($domain) } catch { }
}
if ($failed) { exit 1 } else { exit 0 }
__RDC_MAIN_END__#>