<#
.SYNOPSIS
    Offline replica of the app's VisualMatcher: "what would AutoPet see in this screenshot?"

.DESCRIPTION
    Runs the app's exact matching semantics -- Java Random(1729) sampling, alpha>200
    sample selection, 240-sample cap, early rejection at 8/24/64, the same search
    regions and tolerances -- against a saved screenshot, without touching the
    emulator. Use it to check a new template before deploying, or to diagnose why the
    script is not recognising a screen.

    Screenshots are scaled to 1600x900 exactly as the app does, so any capture of the
    same aspect ratio works.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\verify-templates.ps1 -Shot .\shots\pet.png
    powershell -ExecutionPolicy Bypass -File tools\verify-templates.ps1 -Shot .\shots\lobby.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Shot,
    [string]$Assets = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not dependable inside a param() default on Windows PowerShell 5.1.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
if ($Assets -eq '') { $Assets = Join-Path $RepoRoot 'app\assets' }

if (-not (Test-Path $Shot))   { Write-Host "ERROR: screenshot not found: $Shot" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Assets)) { Write-Host "ERROR: assets folder not found: $Assets" -ForegroundColor Red; exit 1 }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public class VmTemplate {
    public int width, height;
    public int[] dx, dy, red, green, blue;
    private long seed;
    private void SetSeed(long s) { seed = (s ^ 0x5DEECE66DL) & ((1L << 48) - 1); }
    private int Next(int bits) { seed = (seed * 0x5DEECE66DL + 0xBL) & ((1L << 48) - 1); return (int)((ulong)seed >> (48 - bits)); }
    private int NextInt(int bound) {
        if ((bound & -bound) == bound) return (int)((bound * (long)Next(31)) >> 31);
        int bits, val;
        do { bits = Next(31); val = bits % bound; } while (bits - val + (bound - 1) < 0);
        return val;
    }
    public VmTemplate(int w, int h, int[] px) {
        width = w; height = h;
        SetSeed(1729L);
        List<int> keep = new List<int>();
        for (int i = 0; i < px.Length; i++) if ((int)((uint)px[i] >> 24) > 200) keep.Add(i);
        for (int i = keep.Count; i > 1; i--) { int j = NextInt(i); int t = keep[i - 1]; keep[i - 1] = keep[j]; keep[j] = t; }
        int n = Math.Min(240, keep.Count);
        dx = new int[n]; dy = new int[n]; red = new int[n]; green = new int[n]; blue = new int[n];
        for (int k = 0; k < n; k++) {
            int idx = keep[k];
            dx[k] = idx % w; dy[k] = idx / w;
            int p = px[idx];
            red[k] = (p >> 16) & 255; green[k] = (p >> 8) & 255; blue[k] = p & 255;
        }
    }
}

public class VmMatch { public int x, y; public double error; }

public static class Vm {
    // Templates load at their NATIVE size. Scaling a template would move every sample
    // coordinate it was built from and nothing would ever match.
    public static VmTemplate Load(string path) {
        int w, h; int[] px = LoadPixelsRaw(path, out w, out h);
        return new VmTemplate(w, h, px);
    }

    public static int[] LoadPixelsRaw(string path, out int w, out int h) {
        using (Bitmap b = new Bitmap(path)) {
            w = b.Width; h = b.Height;
            int[] px = new int[w * h];
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
            b.UnlockBits(d);
            return px;
        }
    }

    // Screenshots mirror the app: anything that is not already 1600x900 is scaled to it.
    public static int[] LoadPixels(string path, out int w, out int h) {
        using (Bitmap src = new Bitmap(path)) {
            if (src.Width == 1600 && src.Height == 900) return LoadPixelsRaw(path, out w, out h);
            using (Bitmap b = new Bitmap(1600, 900, PixelFormat.Format32bppArgb)) {
                using (Graphics g = Graphics.FromImage(b)) {
                    g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(src, 0, 0, 1600, 900);
                }
                w = 1600; h = 900;
                int[] px = new int[w * h];
                BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
                b.UnlockBits(d);
                return px;
            }
        }
    }

    public static VmMatch Find(int[] px, int width, int height, VmTemplate t, int x0, int y0, int x1, int y1, double tol) {
        int maxX = Math.Min(width, x1) - t.width;
        int maxY = Math.Min(height, y1) - t.height;
        VmMatch best = null; double bestErr = tol;
        for (int y = Math.Max(0, y0); y <= maxY; y++) {
            for (int x = Math.Max(0, x0); x <= maxX; x++) {
                int total = 0, n = 0; bool broke = false;
                for (int k = 0; k < t.dx.Length; k++) {
                    int idx = (y + t.dy[k]) * width + x + t.dx[k];
                    int p = px[idx];
                    total += Math.Abs(((p >> 16) & 255) - t.red[k]);
                    total += Math.Abs(((p >> 8) & 255) - t.green[k]);
                    total += Math.Abs((p & 255) - t.blue[k]);
                    n++;
                    if (n == 8 || n == 24 || n == 64) {
                        if ((double)total > (double)(n * 3) * (tol + 9.0)) { broke = true; break; }
                    }
                }
                if (broke || n != t.dx.Length) continue;
                double err = (double)total / (n * 3.0);
                if (err < bestErr) { best = new VmMatch { x = x + t.width / 2, y = y + t.height / 2, error = err }; bestErr = err; }
            }
        }
        return best;
    }
}
'@

# Regions and tolerances copied from PetAccessibilityService.analyze().
# name = asset; X0/Y0/X1/Y1 = search window in 1600x900 space; tol = mean RGB error ceiling.
$REGIONS = @(
    @{ n = 'relogin.png';         x0 = 300;  y0 = 500; x1 = 1300; y1 = 790; tol = 24.0 },
    @{ n = 'signin_close.png';    x0 = 1150; y0 = 10;  x1 = 1500; y1 = 180; tol = 24.0 },
    @{ n = 'wechat_login.png';    x0 = 450;  y0 = 660; x1 = 1180; y1 = 800; tol = 24.0 },
    @{ n = 'agree_unchecked.png'; x0 = 250;  y0 = 760; x1 = 950;  y1 = 870; tol = 24.0; gate = 'wechat_login.png' },
    @{ n = 'pet_home_entry.png';  x0 = 740;  y0 = 600; x1 = 1030; y1 = 780; tol = 24.0 },
    @{ n = 'pet_work_entry.png';  x0 = 0;    y0 = 380; x1 = 220;  y1 = 580; tol = 24.0 },
    @{ n = 'work2.png';           x0 = 380;  y0 = 380; x1 = 1280; y1 = 800; tol = 24.0 },
    @{ n = 'clock.png';           x0 = 570;  y0 = 150; x1 = 725;  y1 = 270; tol = 24.0 },
    @{ n = 'claim.png';           x0 = 160;  y0 = 120; x1 = 1550; y1 = 700; tol = 27.0 }
)

$w = 0; $h = 0
$px = [Vm]::LoadPixels($Shot, [ref]$w, [ref]$h)
$orig = [System.Drawing.Image]::FromFile((Resolve-Path $Shot).Path)
Write-Host ("screenshot {0}  ({1}x{2} -> analysed at {3}x{4})" -f (Split-Path $Shot -Leaf), $orig.Width, $orig.Height, $w, $h)
$orig.Dispose()
Write-Host ''

$hits = @{}
foreach ($r in $REGIONS) {
    $tplPath = Join-Path $Assets $r.n
    if (-not (Test-Path $tplPath)) { Write-Host ("  MISSING TEMPLATE {0}" -f $r.n) -ForegroundColor Red; continue }
    $t = [Vm]::Load($tplPath)
    if ($r.gate -and -not $hits.ContainsKey($r.gate)) {
        Write-Host ("  {0,-22} skipped (gate {1} not matched)" -f $r.n, $r.gate) -ForegroundColor DarkGray
        continue
    }
    $m = [Vm]::Find($px, $w, $h, $t, $r.x0, $r.y0, $r.x1, $r.y1, $r.tol)
    if ($m) {
        $hits[$r.n] = $m
        Write-Host ("  HIT   {0,-22} centre=({1},{2})  err={3:N2}  (tol {4})  tpl {5}x{6}" -f `
            $r.n, $m.x, $m.y, $m.error, $r.tol, $t.width, $t.height) -ForegroundColor Green
    } else {
        Write-Host ("  miss  {0,-22} region={1},{2},{3},{4}  tol {5}  tpl {6}x{7}" -f `
            $r.n, $r.x0, $r.y0, $r.x1, $r.y1, $r.tol, $t.width, $t.height)
    }
}

Write-Host ''
if ($hits.Count -eq 0) {
    Write-Host 'nothing recognised in this screenshot' -ForegroundColor Yellow
} else {
    Write-Host ("recognised: " + (($hits.Keys | Sort-Object) -join ', ')) -ForegroundColor Cyan
}

# The action the state machine would take, mirroring AutoFlow.next() priority order.
$order = @('relogin.png', 'signin_close.png', 'wechat_login.png', 'claim.png', 'clock.png', 'work2.png', 'pet_work_entry.png', 'pet_home_entry.png')
$action = 'WAIT (nothing actionable)'
foreach ($k in $order) {
    if (-not $hits.ContainsKey($k)) { continue }
    if ($k -eq 'claim.png' -and -not $hits.ContainsKey('pet_work_entry.png')) { continue }
    $action = switch ($k) {
        'relogin.png'        { 'CLICK_RELOGIN (disconnect dialog)' }
        'signin_close.png'   { 'CLICK_SIGNIN_CLOSE (close the sign-in panel)' }
        'wechat_login.png'   { if ($hits.ContainsKey('agree_unchecked.png')) { 'CLICK_AGREE (tick the user agreement)' } else { 'CLICK_WECHAT' } }
        'claim.png'          { 'CLICK_CLAIM (collect one reward)' }
        'clock.png'          { 'NONE (working - wait for the countdown)' }
        'work2.png'          { 'CLICK_WORK2 (start as gardener)' }
        'pet_work_entry.png' { 'CLICK_PET_WORK (open the work panel)' }
        'pet_home_entry.png' { 'CLICK_PET_HOME (enter the pet home)' }
    }
    break
}
Write-Host ("next action: {0}" -f $action) -ForegroundColor Cyan
