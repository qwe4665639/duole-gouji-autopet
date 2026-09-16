<#
.SYNOPSIS
    Install the freshly built APK onto the MuMu instance and re-arm it.

.DESCRIPTION
    Uninstalls any previous copy first: the original APK was signed with a key we
    do not have, so a signature change cannot be applied as an in-place upgrade.
    Rollback = uninstall + install the backup APK you kept beforehand.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Adb 'D:\Program Files\Netease\MuMu\nx_main\adb.exe'
#>
[CmdletBinding()]
param(
    [string]$Adb    = 'D:\Program Files\Netease\MuMu\nx_main\adb.exe',
    [int]$Port      = 5038,
    [string]$Serial = 'emulator-5554',
    [string]$Apk    = '',
    [string]$Package = 'com.dagong.autopet',
    [string]$Backup = ''
)

$ErrorActionPreference = 'Continue'

# $PSScriptRoot is not dependable inside a param() default on Windows PowerShell 5.1.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
if ($Apk -eq '') { $Apk = Join-Path $RepoRoot 'out\autopet.apk' }

if (-not (Test-Path $Adb)) { Write-Host "ERROR: adb not found: $Adb" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Apk)) { Write-Host "ERROR: apk not found: $Apk (run tools\build.ps1 first)" -ForegroundColor Red; exit 1 }

$SVC = "$Package/$Package.PetAccessibilityService"

function Run([string]$label, [scriptblock]$body) {
    Write-Host "=== $label ==="
    & $body
}

Run 'devices'        { & $Adb -P $Port devices }
Run 'before'         { & $Adb -P $Port -s $Serial shell "dumpsys package $Package | grep -E 'versionName|lastUpdateTime'" }
Run 'uninstall old'  { & $Adb -P $Port -s $Serial uninstall $Package }
Run 'install new'    { & $Adb -P $Port -s $Serial install -r $Apk }
Run 'verify'         { & $Adb -P $Port -s $Serial shell "dumpsys package $Package | grep -E 'versionName|lastUpdateTime|codePath'" }

# Writing the secure setting is enough to REGISTER the service, but on this ROM the
# service still is not really bound -- tools\enable-a11y.ps1 does the toggle that
# actually binds it. Run that afterwards.
Run 'register service' {
    & $Adb -P $Port -s $Serial shell "settings put secure enabled_accessibility_services $SVC"
    & $Adb -P $Port -s $Serial shell "settings put secure accessibility_enabled 1"
    & $Adb -P $Port -s $Serial shell "settings get secure enabled_accessibility_services"
}

if ($Backup -ne '') {
    Write-Host "rollback: & '$Adb' -P $Port -s $Serial uninstall $Package ; & '$Adb' -P $Port -s $Serial install `"$Backup`""
}
Write-Host 'next: pwsh -File tools\enable-a11y.ps1   (the toggle that makes the service actually bind)'
