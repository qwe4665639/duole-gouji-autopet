<#
.SYNOPSIS
    Build and sign the 宠物自动打工 APK by hand — no Gradle required.

.DESCRIPTION
    Pipeline: aapt2 compile -> aapt2 link (R.java) -> javac -> d8 -> aapt2 link
    (unsigned) -> jar uf (classes.dex) -> zipalign -> apksigner.

    Requires an Android SDK (build-tools 34.0.0 + platforms/android-34) and a
    JDK 17. No Android Studio, no Gradle wrapper, no network access.

.PARAMETER Keystore
    Signing keystore. Create one with:
      keytool -genkeypair -v -keystore debug.keystore -alias androiddebugkey `
              -storepass android -keypass android -keyalg RSA -keysize 2048 `
              -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    The keystore is NOT in this repository on purpose — never commit a signing key.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build.ps1 -AndroidSdk 'D:\Dev\android-sdk' `
              -Jdk 'D:\Dev\jdk-17' -Keystore .\keystore\debug.keystore
#>
[CmdletBinding()]
param(
    [string]$AndroidSdk   = 'D:\Dev\android-sdk',
    [string]$Jdk          = 'D:\Dev\jdk-17',
    [string]$Project      = '',
    [string]$Out          = '',
    [string]$Keystore     = '',
    [string]$KeystorePass = 'android',
    [string]$KeyAlias     = 'androiddebugkey',
    [string]$ApkName      = 'autopet.apk',
    [string]$BuildTools   = '34.0.0',
    [string]$Platform     = 'android-34',
    [int]$MinApi          = 30
)

# NOTE: keep this at Continue. Toolchain programs (javac/d8) write harmless notes to
# stderr, and 'Stop' would turn those into terminating errors.
$ErrorActionPreference = 'Continue'

# $PSScriptRoot is not dependable inside a param() default on Windows PowerShell 5.1,
# so every repo-relative path default is resolved here instead.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
if ($Project  -eq '') { $Project  = Join-Path $RepoRoot 'app' }
if ($Out      -eq '') { $Out      = Join-Path $RepoRoot 'out' }
if ($Keystore -eq '') { $Keystore = Join-Path $RepoRoot 'keystore\debug.keystore' }

$bt   = Join-Path $AndroidSdk "build-tools\$BuildTools"
$plat = Join-Path $AndroidSdk "platforms\$Platform\android.jar"

# ---- preflight: fail with a readable message instead of a cryptic native error ----
$missing = @()
foreach ($p in @(
    @{ n = 'aapt2.exe';      v = (Join-Path $bt 'aapt2.exe') },
    @{ n = 'zipalign.exe';   v = (Join-Path $bt 'zipalign.exe') },
    @{ n = 'd8.bat';         v = (Join-Path $bt 'd8.bat') },
    @{ n = 'apksigner.bat';  v = (Join-Path $bt 'apksigner.bat') },
    @{ n = 'android.jar';    v = $plat },
    @{ n = 'javac.exe';      v = (Join-Path $Jdk 'bin\javac.exe') },
    @{ n = 'jar.exe';        v = (Join-Path $Jdk 'bin\jar.exe') },
    @{ n = 'AndroidManifest.xml'; v = (Join-Path $Project 'AndroidManifest.xml') }
)) {
    if (-not (Test-Path $p.v)) { $missing += "  $($p.n) -> $($p.v)" }
}
if (-not (Test-Path $Keystore)) { $missing += "  keystore -> $Keystore" }
if ($missing.Count -gt 0) {
    Write-Host 'ERROR: required files not found:' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host 'Pass -AndroidSdk / -Jdk / -Keystore explicitly if they live elsewhere.'
    exit 1
}

Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Out, "$Out\gen", "$Out\classes", "$Out\dex" -Force | Out-Null

Write-Host '=== 1/8 aapt2 compile (res) ==='
& "$bt\aapt2.exe" compile --dir "$Project\res" -o "$Out\compiled.zip"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }

Write-Host '=== 2/8 aapt2 link (gen R.java) ==='
& "$bt\aapt2.exe" link -I $plat --manifest "$Project\AndroidManifest.xml" -A "$Project\assets" --java "$Out\gen" -o "$Out\base.apk" "$Out\compiled.zip"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

Write-Host '=== 3/8 javac ==='
$src = (Get-ChildItem "$Project\src" -Recurse -Filter *.java | ForEach-Object FullName)
$gen = (Get-ChildItem "$Out\gen" -Recurse -Filter *.java | ForEach-Object FullName)
& "$Jdk\bin\javac.exe" -encoding UTF-8 -source 11 -target 11 -nowarn -classpath $plat -d "$Out\classes" ($src + $gen)
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }

Write-Host '=== 4/8 d8 (dex) ==='
$classes = (Get-ChildItem "$Out\classes" -Recurse -Filter *.class | ForEach-Object FullName)
& "$bt\d8.bat" --min-api $MinApi --lib $plat --output "$Out\dex" $classes
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }

Write-Host '=== 5/8 aapt2 link (unsigned apk) ==='
& "$bt\aapt2.exe" link -I $plat --manifest "$Project\AndroidManifest.xml" -A "$Project\assets" -o "$Out\unsigned.apk" "$Out\compiled.zip"
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link (unsigned) failed' }

Write-Host '=== 6/8 add classes.dex ==='
Push-Location "$Out\dex"
& "$Jdk\bin\jar.exe" uf "$Out\unsigned.apk" classes.dex
Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'jar update failed' }

Write-Host '=== 7/8 zipalign ==='
& "$bt\zipalign.exe" -f 4 "$Out\unsigned.apk" "$Out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

Write-Host '=== 8/8 apksigner ==='
$apk = Join-Path $Out $ApkName
& "$bt\apksigner.bat" sign --ks $Keystore --ks-pass "pass:$KeystorePass" --ks-key-alias $KeyAlias --out $apk "$Out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }

& "$bt\apksigner.bat" verify --print-certs $apk
Get-Item $apk | Select-Object FullName, @{ n = 'KB'; e = { [math]::Round($_.Length / 1KB, 1) } } | Format-List
