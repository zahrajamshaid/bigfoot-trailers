<#
.SYNOPSIS
  Generate the BigfootTrailers.appinstaller from the template.

.DESCRIPTION
  Fills {{VERSION}} (normalized to a 4-part MSIX version) and {{BASE_URL}} into
  windows/packaging/BigfootTrailers.appinstaller.template and writes the result.
  Used both locally (to stage dist/) and by the windows-release CI workflow.

.PARAMETER Version
  Release version. Accepts 1.0.1, v1.0.1, or 1.0.1.0 — normalized to 4 parts.

.PARAMETER BaseUrl
  Stable base URL the published assets live under. Defaults to the public
  releases repo's "latest" path so the file never needs per-release edits.

.PARAMETER OutFile
  Destination path. Defaults to dist/BigfootTrailers.appinstaller.

.EXAMPLE
  powershell -File tool/make_appinstaller.ps1 -Version 1.0.1
#>
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BaseUrl = "https://github.com/zahrajamshaid/bigfoot-trailers-releases/releases/latest/download",
    [string]$OutFile
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $projectRoot "windows\packaging\BigfootTrailers.appinstaller.template"
if (-not (Test-Path $template)) { throw "Template not found: $template" }

if (-not $OutFile) { $OutFile = Join-Path $projectRoot "dist\BigfootTrailers.appinstaller" }

# Normalize to a 4-part version (MSIX/AppInstaller require Major.Minor.Build.Rev).
$parts = $Version.TrimStart('v').Split('.')
$nums = for ($i = 0; $i -lt 4; $i++) {
    $n = 0
    if ($i -lt $parts.Count) { [int]::TryParse($parts[$i], [ref]$n) | Out-Null }
    $n
}
$ver = ($nums -join '.')

$xml = (Get-Content $template -Raw).Replace('{{VERSION}}', $ver).Replace('{{BASE_URL}}', $BaseUrl)

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
[IO.File]::WriteAllText($OutFile, $xml)
Write-Host "Wrote $OutFile (version $ver, base $BaseUrl)"
