<#
.SYNOPSIS
  Build the Bigfoot Trailers Flutter app as a native Windows .exe.

.DESCRIPTION
  Wraps `flutter build windows` and works around a host-toolchain gap:

  CMake (driven by Flutter) compiles with whichever VS 2022 instance it
  selects via the Setup COM API. On this machine that is the *Build Tools*
  instance, which does NOT ship the C++ ATL component. One plugin —
  flutter_secure_storage_windows — includes <atlstr.h>, so the build fails
  with `error C1083: Cannot open include file: 'atlstr.h'`.

  The permanent fix is to install "C++ ATL for latest v143 build tools" into
  the instance CMake uses (see PERMANENT FIX below). Until then, this script
  locates any installed VS instance that DOES have ATL, of the SAME MSVC
  toolset version, and feeds its atlmfc include/lib paths to cl.exe / link.exe
  through the `CL` and `LINK` environment variables (which the MSVC tools read
  directly, independent of which VS instance CMake picked). The headers are
  byte-identical across instances of the same toolset version, so this is
  safe.

  PERMANENT FIX (one-time, needs admin / a UAC approval), after which plain
  `flutter build windows` works and this shim is unnecessary:

    & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" `
        modify --passive --norestart `
        --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" `
        --add Microsoft.VisualStudio.Component.VC.ATL

.PARAMETER Mode
  --debug (default), --profile, or --release. Passed through to flutter.

.EXAMPLE
  pwsh tool/build_windows.ps1
  pwsh tool/build_windows.ps1 --release
#>
param(
    [string]$Mode = "--debug"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Find-AtlPaths {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $null }

    # Prefer an instance that actually has the ATL component installed.
    $atlInstall = & $vswhere -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.ATL `
        -property installationPath 2>$null | Select-Object -First 1

    if (-not $atlInstall) { return $null }

    # Pick the newest MSVC toolset under that install that has atlmfc.
    $msvcRoot = Join-Path $atlInstall "VC\Tools\MSVC"
    if (-not (Test-Path $msvcRoot)) { return $null }

    $toolset = Get-ChildItem $msvcRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "atlmfc\include\atlstr.h") } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $toolset) { return $null }

    return [pscustomobject]@{
        Include = Join-Path $toolset.FullName "atlmfc\include"
        Lib     = Join-Path $toolset.FullName "atlmfc\lib\x64"
    }
}

Push-Location $projectRoot
try {
    $atl = Find-AtlPaths
    if ($atl) {
        Write-Host "Injecting ATL paths from a VS instance that has the ATL component:" -ForegroundColor Cyan
        Write-Host "  include: $($atl.Include)"
        Write-Host "  lib:     $($atl.Lib)"
        # cl.exe and link.exe read these env vars directly and prepend them,
        # regardless of which VS instance CMake/MSBuild selected.
        $env:CL   = "/I`"$($atl.Include)`""
        $env:LINK = "/LIBPATH:`"$($atl.Lib)`""
    } else {
        Write-Warning "No VS instance with the ATL component found. If the build fails on atlstr.h, install 'C++ ATL for latest v143 build tools' (see PERMANENT FIX in this script's header)."
    }

    Write-Host "flutter build windows $Mode" -ForegroundColor Green
    & flutter build windows $Mode
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
