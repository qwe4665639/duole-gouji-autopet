<#
.SYNOPSIS
    Host-side watchdog for AutoPet. Two jobs, both things the in-game app cannot do.

.DESCRIPTION
    1) Re-arm the MuMu accessibility service once per Android boot, so the service
       never has to be toggled by hand again. Android does not let an app grant
       itself an accessibility service, and this ROM restores the "enabled" setting
       across a VM restart without ever binding it (Settings shows 已开启 while
       `dumpsys accessibility` shows "Bound services: {}").

    2) Recover the game when it is stuck on the account login screen. The proven
       manual fix is: close the game, start it again -- it logs straight back in and
       lands in the lobby. An AccessibilityService cannot kill another app, but the
       host can, so that job lives here. The app is the sensor: it logs
       "检测到登录界面" when it sees that screen, and this script watches the log and
       performs the restart.

.NOTES
    This file MUST keep its UTF-8 BOM (first three bytes EF BB BF): `powershell.exe
    -File` decodes a BOM-less script with the console ANSI codepage, which turns the
    Chinese literals below into mojibake and silently breaks the stuck detection.
    The same trap applies to the adb output this script parses, hence the explicit
    UTF-8 console setup below.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\autopet-a11y-watch.ps1
    Start it silently at logon with autopet-a11y-watch.vbs (put a shortcut to it in
    shell:startup).
#>
[CmdletBinding()]
param(
    [string]$Adb        = 'D:\Program Files\Netease\MuMu\nx_main\adb.exe',
    [int]$Port          = 5038,
    [string]$Serial     = 'emulator-5554',
    [string]$Game       = 'com.k7k7.goujihd',
    [string]$App        = 'com.dagong.autopet',
    [string]$Helper     = '',
    [string]$StateFile  = (Join-Path $env:LOCALAPPDATA 'autopet-watch-state.txt'),
    [string]$LogFile    = (Join-Path $env:LOCALAPPDATA 'autopet-watch.log'),
    [int]$RestartCooldownSec = 120,
    [int]$LoadWaitSec   = 20,
    # Centre of the "2 · 开始并返回游戏" button in the app panel (1600x900).
    [int]$ReArmTapX     = 800,
    [int]$ReArmTapY     = 434,
    [switch]$NoReArm
)

$ErrorActionPreference = 'Continue'

# adb writes UTF-8, but PowerShell 5.1 decodes the output of native commands using
# the console's OEM code page, so every Chinese character came back as mojibake and
# the stuck-detection literals below could never match. Force UTF-8 in both directions.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# $PSScriptRoot is not dependable inside a param() default on Windows PowerShell 5.1.
if ($Helper -eq '') { $Helper = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'enable-a11y.ps1' }

$LOGIN_MARKER = '检测到登录界面'
$STUCK_MARKER = '长时间未识别到可操作画面'

function Write-Log([string]$m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

if (-not (Test-Path $Adb)) { Write-Host "ERROR: adb not found: $Adb" -ForegroundColor Red; exit 1 }

Write-Log 'watchdog started'

& $Adb -P $Port start-server 2>&1 | Out-Null
$lastRestart = [datetime]::MinValue

while ($true) {
    try {
        $devices = (& $Adb -P $Port devices 2>&1 | Out-String)
        if ($devices -match [regex]::Escape($Serial) + '\s+device') {

            # ---- job 1: re-arm accessibility once per Android boot ----
            $bootId = ((& $Adb -P $Port -s $Serial shell "cat /proc/sys/kernel/random/boot_id" 2>&1 | Out-String).Trim())
            # Must look like a real UUID. If adb itself fails, its error text ("error: closed")
            # would otherwise pass a naive length check and be mistaken for a fresh boot id,
            # which then sends us off to re-arm accessibility on whatever screen is showing.
            if ($bootId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                $last = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { '' }
                if ($bootId -ne $last) {
                    if ($NoReArm) {
                        Write-Log "new Android boot detected ($bootId) -> -NoReArm, skipping"
                    } else {
                        Write-Log "new Android boot detected ($bootId) -> re-arming accessibility"
                        # The helper must be read as UTF-8 or its Chinese service label is mangled.
                        $sb = [scriptblock]::Create((Get-Content $Helper -Raw -Encoding UTF8))
                        & $sb *>&1 | ForEach-Object { Write-Log "  $_" }
                        Write-Log 're-arm finished'
                    }
                    Set-Content -LiteralPath $StateFile -Value $bootId -Encoding UTF8
                    continue
                }
            }

            # ---- job 2: any stuck state -> full game restart (the proven manual fix) ----
            $elapsed = ((Get-Date) - $lastRestart).TotalSeconds
            if ($elapsed -gt $RestartCooldownSec) {
                # Filter by tag: a plain "-t 250" window mixes every tag the system emits and
                # our AutoPet lines get pushed out of it, which is why this never fired.
                # Kept on ONE line on purpose: PowerShell 5.1 has no trailing-pipe continuation.
                $recent = (& $Adb -P $Port -s $Serial logcat -d -s AutoPet:I 2>&1 | Select-Object -Last 25 | Out-String)
                $stuck = ($recent -match [regex]::Escape($LOGIN_MARKER)) -or
                         ($recent -match [regex]::Escape($STUCK_MARKER))
                if ($stuck) {
                    Write-Log 'helper is stuck (login screen or unrecognised screen) -> full game restart'
                    & $Adb -P $Port -s $Serial shell "am force-stop $Game" 2>&1 | Out-Null
                    Start-Sleep -Seconds 3
                    & $Adb -P $Port -s $Serial shell "monkey -p $Game -c android.intent.category.LAUNCHER 1" 2>&1 | Out-Null
                    $lastRestart = Get-Date
                    Write-Log '  game relaunched, waiting for it to load back into the lobby'
                    Start-Sleep -Seconds $LoadWaitSec
                    # The helper pauses itself when it gets stuck, so re-arm it through its own
                    # panel: launching MainActivity and tapping "2 · 开始并返回游戏" calls
                    # setRunning(true) and sends the game back to the foreground.
                    & $Adb -P $Port -s $Serial shell "am start -n $App/.MainActivity" 2>&1 | Out-Null
                    Start-Sleep -Seconds 4
                    & $Adb -P $Port -s $Serial shell "input tap $ReArmTapX $ReArmTapY" 2>&1 | Out-Null
                    Start-Sleep -Seconds 6
                    # clear the buffer so these stale lines cannot trigger another restart
                    & $Adb -P $Port -s $Serial logcat -c 2>&1 | Out-Null
                    Write-Log '  automation re-armed; it will close the sign-in panel and enter the pet home'
                }
            }
        }
    } catch {
        Write-Log "error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 30
}
