# export-apps.ps1 - Export installed winget packages to a JSON file
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File export-apps.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File export-apps.ps1 -OutFile ../../apps/windows.json
#
# Parameters:
#   -OutFile    Output path (default: ../../apps/windows.json relative to script)
#
# Actions:
#   1. Export the runbook app list to a winget JSON file using winget export
#   2. Verify the exported file is valid
#
# Output: Structured lines prefixed with OK / FAIL / INFO
# Exit code: 0 on success, 1 on failure

param(
    [string]$OutFile = ""
)

$ErrorActionPreference = 'Continue'

# Default output path: apps/windows.json relative to repo root
if ($OutFile -eq "") {
    $repoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
    $OutFile = Join-Path $repoRoot "apps\windows.json"
}

$outDir = Split-Path $OutFile
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Host "INFO: Created directory $outDir"
}

# --- The canonical app list from install-apps.ps1 ---

$AppIds = @(
    "Git.Git",
    "GitHub.GitHubDesktop",
    "Microsoft.VisualStudioCode",
    "Google.Chrome.EXE",
    "Microsoft.WindowsTerminal",
    "Microsoft.PowerShell"
)

# --- Build winget export JSON ---
# winget export produces a JSON with Sources[].Packages[].PackageIdentifier.
# We build this directly to include only our managed apps, not everything on the machine.

$packages = @()
foreach ($id in $AppIds) {
    $packages += @{ PackageIdentifier = $id }
}

$exportJson = @{
    '$schema'    = 'https://aka.ms/winget-packages.schema.2.0.json'
    CreationDate = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fff')
    Sources      = @(
        @{
            Packages       = $packages
            SourceDetails  = @{
                Argument   = 'https://cdn.winget.microsoft.com/cache'
                Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'
                Name       = 'winget'
                Type       = 'Microsoft.PreIndexed.Package'
            }
        }
    )
    WinGetVersion = '0.0.0'
} | ConvertTo-Json -Depth 5

Set-Content -Path $OutFile -Value $exportJson -Encoding UTF8
Write-Host "OK: Exported $($AppIds.Count) packages to $OutFile"

# --- Verify ---

if (Test-Path $OutFile) {
    try {
        $parsed = Get-Content $OutFile -Raw | ConvertFrom-Json
        $pkgCount = $parsed.Sources[0].Packages.Count
        Write-Host "OK: File is valid JSON with $pkgCount packages"
    } catch {
        Write-Host "FAIL: Exported file is not valid JSON"
        exit 1
    }
} else {
    Write-Host "FAIL: Export file not created"
    exit 1
}

Write-Host ""
Write-Host "RESULT: Export complete"
Write-Host "INFO: To import on another machine: winget import -i `"$OutFile`" --accept-package-agreements --accept-source-agreements"
exit 0
