# import-apps.ps1 - Import and install apps from a winget JSON export file
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File import-apps.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File import-apps.ps1 -InFile ../../apps/windows.json
#
# Parameters:
#   -InFile    Path to winget JSON file (default: ../../apps/windows.json relative to script)
#
# Actions:
#   1. Read the winget JSON export file
#   2. Check which packages are already installed (skip those)
#   3. Install missing packages via winget import
#   4. Verify each package is installed
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO / WARN
# Exit code: 0 on success, 1 on failure

param(
    [string]$InFile = ""
)

$ErrorActionPreference = 'Continue'
$FailCount = 0

# Default input path: apps/windows.json relative to repo root
if ($InFile -eq "") {
    $repoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
    $InFile = Join-Path $repoRoot "apps\windows.json"
}

if (-not (Test-Path $InFile)) {
    Write-Host "FAIL: Import file not found: $InFile"
    Write-Host "  Run export-apps.ps1 first, or provide a path with -InFile"
    exit 1
}

# --- Parse the JSON ---

Write-Host "INFO: Reading $InFile"
try {
    $importData = Get-Content $InFile -Raw | ConvertFrom-Json
} catch {
    Write-Host "FAIL: Could not parse JSON: $($_.Exception.Message)"
    exit 1
}

$packages = $importData.Sources[0].Packages
if (-not $packages -or $packages.Count -eq 0) {
    Write-Host "FAIL: No packages found in import file"
    exit 1
}

Write-Host "INFO: Found $($packages.Count) packages to install"

# --- Check what's already installed ---

Write-Host ""
Write-Host "--- Checking installed packages ---"

$toInstall = @()
foreach ($pkg in $packages) {
    $id = $pkg.PackageIdentifier
    $result = winget list --id $id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $result -match $id) {
        Write-Host "SKIP: $id already installed"
    } else {
        Write-Host "INFO: $id needs install"
        $toInstall += $id
    }
}

if ($toInstall.Count -eq 0) {
    Write-Host ""
    Write-Host "RESULT: All $($packages.Count) packages already installed"
    exit 0
}

# --- Install missing packages ---

Write-Host ""
Write-Host "--- Installing $($toInstall.Count) package(s) ---"

# Use winget import for bulk install
$output = winget import -i $InFile --accept-package-agreements --accept-source-agreements --ignore-unavailable 2>&1
Write-Host "INFO: winget import completed"

# --- Verify all packages ---

Write-Host ""
Write-Host "--- Verifying packages ---"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path    = "$machinePath;$userPath"

foreach ($pkg in $packages) {
    $id = $pkg.PackageIdentifier
    $result = winget list --id $id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $result -match $id) {
        Write-Host "OK: $id installed"
    } else {
        Write-Host "FAIL: $id not found after import"
        $FailCount++
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Import completed with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: All packages imported and verified"
    Write-Host "INFO: Reopen your terminal for PATH changes to take effect"
    exit 0
}
