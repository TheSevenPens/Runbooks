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
    # winget list can return exit code 0 even when the package isn't found on some
    # Windows versions. Check both exit code AND that the package ID appears in output.
    $result = winget list --id $id --exact --accept-source-agreements 2>$null
    $resultStr = ($result | Out-String)
    if ($LASTEXITCODE -eq 0 -and $resultStr.Contains($id)) {
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
$importExitCode = $LASTEXITCODE

# Report what happened during import
$outputStr = ($output | Out-String)
$successLines = @($output | Where-Object { "$_".Contains('Successfully installed') })
$failLines = @($output | Where-Object { $_ -match 'failed|error' -and -not "$_".Contains('ignore') })

if ($successLines.Count -gt 0) {
    Write-Host "INFO: winget import installed $($successLines.Count) package(s)"
}
if ($failLines.Count -gt 0) {
    Write-Host "WARN: winget import reported $($failLines.Count) failure(s):"
    foreach ($line in $failLines) { Write-Host "  $line" }
}
if ($importExitCode -ne 0) {
    Write-Host "WARN: winget import exited with code $importExitCode"
} else {
    Write-Host "INFO: winget import completed"
}

# --- Verify all packages ---

Write-Host ""
Write-Host "--- Verifying packages ---"

# Refresh PATH, repairing entries concatenated without semicolons
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
$rawParts    = "$machinePath;$userPath" -split ';' | Where-Object { $_ -ne '' }
$fixedParts  = @()
foreach ($entry in $rawParts) {
    $splits = @()
    for ($ci = 1; $ci -lt $entry.Length - 2; $ci++) {
        $ch = $entry[$ci]
        if ((($ch -ge 'A') -and ($ch -le 'Z')) -or (($ch -ge 'a') -and ($ch -le 'z'))) {
            if (($entry[$ci + 1] -eq ':') -and ($entry[$ci + 2] -eq '\')) {
                $splits += $ci
            }
        }
    }
    if ($splits.Count -eq 0) {
        $fixedParts += $entry
    } else {
        $prev = 0
        foreach ($pos in $splits) {
            $fixedParts += $entry.Substring($prev, $pos - $prev)
            $prev = $pos
        }
        $fixedParts += $entry.Substring($prev)
    }
}
$env:Path = $fixedParts -join ';'

foreach ($pkg in $packages) {
    $id = $pkg.PackageIdentifier
    $result = winget list --id $id --exact --accept-source-agreements 2>$null
    $resultStr = ($result | Out-String)
    if ($LASTEXITCODE -eq 0 -and $resultStr.Contains($id)) {
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
