# One-shot ELEVATED helper: ensure the BuildTools VS instance has C++ ATL so
# `flutter build windows` works without the CL/LINK shim.
# Strategy: try the official VS Installer component add; if it doesn't land,
# replicate the atlmfc folder from a VS instance that DOES have ATL (same MSVC
# toolset version => byte-identical headers/libs). Logs everything for the
# parent process to read.
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:TEMP 'atl_install_result.log'
"START $(Get-Date -Format o)" | Set-Content $log -Encoding utf8
function L($m) { $m | Add-Content $log -Encoding utf8; Write-Host $m }

$bt   = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools'
$btMsvc = Join-Path $bt 'VC\Tools\MSVC'

function Has-Atl($root) {
    if (-not (Test-Path $root)) { return $false }
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'atlmfc\include\atlstr.h') } |
        ForEach-Object { return $true }
    return ((Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'atlmfc\include\atlstr.h') }).Count -gt 0)
}

if (Has-Atl $btMsvc) { L 'ALREADY-PRESENT: BuildTools already has ATL.'; L 'DONE-OK'; exit 0 }

# --- Attempt 1: official VS Installer component add (quiet) ---
$setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
L "Trying official installer add (quiet)..."
try {
    $p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList @(
        'modify','--installPath',$bt,
        '--add','Microsoft.VisualStudio.Component.VC.ATL',
        '--quiet','--norestart'
    )
    L "installer exit=$($p.ExitCode)"
} catch { L "installer threw: $($_.Exception.Message)" }

if (Has-Atl $btMsvc) { L 'SUCCESS via official installer.'; L 'DONE-OK'; exit 0 }

# --- Attempt 2: replicate atlmfc from an ATL-equipped instance ---
L 'Official add did not land; replicating atlmfc from an ATL-equipped instance.'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$srcInstall = & $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath 2>$null | Select-Object -First 1
if (-not $srcInstall) { L 'NO-SOURCE: no VS instance with ATL to copy from.'; L 'DONE-FAIL'; exit 2 }
$srcMsvc = Join-Path $srcInstall 'VC\Tools\MSVC'

# Match the SAME toolset version BuildTools has (header/lib ABI must match).
$btVersions = (Get-ChildItem $btMsvc -Directory -ErrorAction SilentlyContinue).Name
$copied = $false
foreach ($v in $btVersions) {
    $srcAtl = Join-Path $srcMsvc "$v\atlmfc"
    $dstAtl = Join-Path $btMsvc  "$v\atlmfc"
    if ((Test-Path (Join-Path $srcAtl 'include\atlstr.h')) -and -not (Test-Path (Join-Path $dstAtl 'include\atlstr.h'))) {
        L "Copying $srcAtl -> $dstAtl (toolset $v)"
        $r = robocopy $srcAtl $dstAtl /E /NFL /NDL /NJH /NJS /NP
        L "robocopy exit=$LASTEXITCODE"   # robocopy <8 == success
        $copied = $true
    }
}
if (-not $copied) { L 'NO-MATCH: no matching toolset version present in both instances.'; L 'DONE-FAIL'; exit 3 }

if (Has-Atl $btMsvc) { L 'SUCCESS via atlmfc replication.'; L 'DONE-OK'; exit 0 }
L 'STILL-MISSING after copy.'; L 'DONE-FAIL'; exit 4
