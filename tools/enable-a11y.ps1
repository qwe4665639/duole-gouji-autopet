<#
.SYNOPSIS
    Re-arm the accessibility service the way the MuMu ROM requires.

.DESCRIPTION
    Symptom: after the emulator restarts (or the app is reinstalled) the service
    shows as 已开启 in Settings but is NOT actually bound -- `dumpsys accessibility`
    reports "Bound services: {}" and PetAccessibilityService.instance stays null.
    Writing the secure setting over adb does NOT fix it. Only opening the service's
    detail page and toggling the switch OFF and then ON again makes it bind for real.

    tools\autopet-a11y-watch.ps1 does this automatically, once per Android boot.

.NOTES
    Invoke with UTF-8 decoding, otherwise the Chinese label below is mangled by the
    console codepage:
      & ([scriptblock]::Create((Get-Content <this file> -Raw -Encoding UTF8)))

.EXAMPLE
    pwsh -File tools\enable-a11y.ps1
#>
[CmdletBinding()]
param(
    [string]$Adb    = 'D:\Program Files\Netease\MuMu\nx_main\adb.exe',
    [int]$Port      = 5038,
    [string]$Serial = 'emulator-5554',
    [string]$Label  = '宠物自动打工服务',
    [string]$Tmp    = (Join-Path $env:TEMP 'autopet-ui.xml')
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Adb)) { Write-Host "ERROR: adb not found: $Adb" -ForegroundColor Red; exit 1 }

function Dump-Ui {
    & $Adb -P $Port -s $Serial shell "uiautomator dump /sdcard/ui-tmp.xml" 2>&1 | Out-Null
    & $Adb -P $Port -s $Serial pull /sdcard/ui-tmp.xml $Tmp 2>&1 | Out-Null
    return (Get-Content $Tmp -Raw -Encoding UTF8)
}

function Get-SwitchBounds([string]$xml) {
    # The detail page carries more than one Switch (a master toggle sits above ours).
    # Ours is the bottom-most one, and it is not always flagged clickable, so accept
    # any Switch node and return only the lowest.
    $out = @()
    foreach ($m in [regex]::Matches($xml, '<node[^>]*>')) {
        $n = $m.Value
        if ($n -match 'class="android.widget.Switch"') {
            $b = [regex]::Match($n, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
            if ($b.Success) {
                $out += , @{
                    x       = [int]((([int]$b.Groups[1].Value) + ([int]$b.Groups[3].Value)) / 2)
                    y       = [int]((([int]$b.Groups[2].Value) + ([int]$b.Groups[4].Value)) / 2)
                    checked = ($n -match 'checked="true"')
                }
            }
        }
    }
    $sorted = @($out | Sort-Object { $_.y })
    if ($sorted.Count -gt 0) { return @($sorted[-1]) }
    return @()
}

Write-Host '=== open accessibility settings ==='
& $Adb -P $Port -s $Serial shell "am start -a android.settings.ACCESSIBILITY_SETTINGS" 2>&1 | Out-Null
Start-Sleep -Seconds 4

$xml = Dump-Ui
if ($xml -notmatch [regex]::Escape($Label)) {
    Write-Host '  service row not visible, scrolling...'
    & $Adb -P $Port -s $Serial shell "input swipe 800 700 800 300 300" 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $xml = Dump-Ui
}
$row = [regex]::Match($xml, '<node[^>]*text="' + [regex]::Escape($Label) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
if (-not $row.Success) { Write-Host 'FAIL: could not find the service row'; exit 1 }
$rowY = [int]((([int]$row.Groups[2].Value) + ([int]$row.Groups[4].Value)) / 2)
Write-Host "  service row y=$rowY -> opening detail page"
& $Adb -P $Port -s $Serial shell input tap 600 $rowY 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Host '=== toggle OFF ==='
# Wrap in @() : a PowerShell function returning a single object unrolls it, so without
# this $sw would be the hashtable itself and $sw[0] would be a key lookup returning $null.
$sw = @(Get-SwitchBounds (Dump-Ui))
if ($sw.Count -eq 0) { Write-Host 'FAIL: no clickable switch on the detail page'; exit 1 }
Write-Host ("  switch at ({0},{1}) checked={2}" -f $sw[0].x, $sw[0].y, $sw[0].checked)
& $Adb -P $Port -s $Serial shell input tap $sw[0].x $sw[0].y 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Host '=== toggle ON ==='
$sw2 = @(Get-SwitchBounds (Dump-Ui))
if ($sw2.Count -eq 0) { Write-Host 'FAIL: switch disappeared'; exit 1 }
Write-Host ("  switch at ({0},{1}) checked={2}" -f $sw2[0].x, $sw2[0].y, $sw2[0].checked)
& $Adb -P $Port -s $Serial shell input tap $sw2[0].x $sw2[0].y 2>&1 | Out-Null
Start-Sleep -Seconds 4

Write-Host '=== verify ==='
$bind = & $Adb -P $Port -s $Serial shell "dumpsys accessibility" 2>&1 | Out-String
$bound = ($bind -split "`n" | Where-Object { $_ -match 'Bound services' }) -join "`n"
Write-Host $bound
Write-Host ("  app process: " + (& $Adb -P $Port -s $Serial shell "ps -A | grep dagong" 2>&1 | Out-String).Trim())
& $Adb -P $Port -s $Serial shell input keyevent 4 2>&1 | Out-Null

if ($bound -match [regex]::Escape($Label)) {
    Write-Host 'OK: service is bound' -ForegroundColor Green
    exit 0
}
Write-Host 'WARNING: service still not bound' -ForegroundColor Yellow
exit 1
