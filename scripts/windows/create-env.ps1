# create-env.ps1 - Create a micromamba environment with specified packages (idempotent)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File create-env.ps1 -Name node1 -Packages nodejs,python,gh
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File create-env.ps1 -Name node1 -Packages nodejs,python,gh -Recreate
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File create-env.ps1 -Name node1 -SpecFile ../../envs/node1.yml
#
# Parameters:
#   -Name       Environment name (required)
#   -Packages   Comma-separated package list (e.g. "nodejs,python,gh")
#   -Channel    Channel to install from (default: conda-forge)
#   -SpecFile   Path to a YAML spec file (overrides -Packages and -Channel)
#   -Recreate   Remove and recreate the environment if it already exists
#
# Actions:
#   1. Locate micromamba binary
#   2. Check if environment already exists (skip or recreate)
#   3. Create environment with specified packages
#   4. Verify each package is installed and report versions
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO / WARN
# Exit code: 0 on success, 1 on failure

param(
    [Parameter(Mandatory=$true)]
    [string]$Name,

    [string]$Packages = "",

    [string]$Channel = "conda-forge",

    [string]$SpecFile = "",

    [switch]$Recreate
)

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- Locate micromamba binary ---

$mmExe = $null
$candidates = @(
    "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe"
)

$mmCmd = Get-Command micromamba -ErrorAction SilentlyContinue
if ($mmCmd -and $mmCmd.Source -match '\.exe$') {
    $candidates += $mmCmd.Source
}

foreach ($path in $candidates) {
    if ((Test-Path $path) -and $path -match '\.exe$') {
        $mmExe = $path
        break
    }
}

if (-not $mmExe) {
    Write-Host "FAIL: micromamba binary not found"
    exit 1
}

Write-Host "INFO: Using micromamba at $mmExe"

# --- Resolve packages ---

$packageList = @()
$channelArg = $Channel

if ($SpecFile -ne "") {
    if (-not (Test-Path $SpecFile)) {
        Write-Host "FAIL: Spec file not found: $SpecFile"
        exit 1
    }
    Write-Host "INFO: Using spec file $SpecFile"
} else {
    if ($Packages -eq "") {
        Write-Host "FAIL: Either -Packages or -SpecFile is required"
        exit 1
    }
    $packageList = $Packages -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    if ($packageList.Count -eq 0) {
        Write-Host "FAIL: No packages specified"
        exit 1
    }
    Write-Host "INFO: Packages: $($packageList -join ', ')"
    Write-Host "INFO: Channel: $channelArg"
}

# --- Check if environment exists ---

Write-Host ""
Write-Host "--- Checking environment ---"

$envExists = $false
$envList = & $mmExe env list 2>$null
if ($envList -match "\b$([regex]::Escape($Name))\b") {
    $envExists = $true
}

if ($envExists) {
    if ($Recreate) {
        Write-Host "INFO: Environment '$Name' exists - removing for recreate"
        $output = & $mmExe env remove -n $Name -y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OK: Removed existing environment '$Name'"
            $envExists = $false
        } else {
            Write-Host "FAIL: Could not remove environment '$Name'"
            Write-Host "  $output"
            exit 1
        }
    } else {
        Write-Host "SKIP: Environment '$Name' already exists (use -Recreate to replace)"

        # Still verify packages even if skipping creation
        Write-Host ""
        Write-Host "--- Verifying packages in existing environment ---"

        # Get installed package names
        $installed = & $mmExe list -n $Name 2>$null
        $verifyPackages = $packageList
        if ($SpecFile -ne "") {
            # Parse package names from spec file
            $verifyPackages = @()
            $inDeps = $false
            foreach ($line in Get-Content $SpecFile) {
                if ($line -match '^\s*dependencies:') { $inDeps = $true; continue }
                if ($inDeps -and $line -match '^\s*-\s*(\S+)') { $verifyPackages += $Matches[1] }
                if ($inDeps -and $line -match '^\S' -and $line -notmatch '^\s*-') { $inDeps = $false }
            }
        }

        foreach ($pkg in $verifyPackages) {
            if ($installed -match "^\s+$([regex]::Escape($pkg))\s") {
                $versionLine = $installed | Where-Object { $_ -match "^\s+$([regex]::Escape($pkg))\s" } | Select-Object -First 1
                Write-Host "OK: $pkg installed ($($versionLine.Trim()))"
            } else {
                Write-Host "WARN: $pkg not found in environment '$Name'"
            }
        }

        Write-Host ""
        Write-Host "RESULT: Environment '$Name' already exists - skipped creation"
        exit 0
    }
}

# --- Create environment ---

Write-Host ""
Write-Host "--- Creating environment '$Name' ---"

if ($SpecFile -ne "") {
    $output = & $mmExe create -n $Name --file $SpecFile -y 2>&1
} else {
    $output = & $mmExe create -n $Name -c $channelArg @packageList -y 2>&1
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: micromamba create failed"
    $output | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "OK: Environment '$Name' created"

# --- Verify environment exists ---

$envList = & $mmExe env list 2>$null
if ($envList -match "\b$([regex]::Escape($Name))\b") {
    Write-Host "OK: Environment '$Name' appears in env list"
} else {
    Write-Host "FAIL: Environment '$Name' not found after creation"
    $FailCount++
}

# --- Verify packages ---

Write-Host ""
Write-Host "--- Verifying packages ---"

$installed = & $mmExe list -n $Name 2>$null

$verifyPackages = $packageList
if ($SpecFile -ne "") {
    $verifyPackages = @()
    $inDeps = $false
    foreach ($line in Get-Content $SpecFile) {
        if ($line -match '^\s*dependencies:') { $inDeps = $true; continue }
        if ($inDeps -and $line -match '^\s*-\s*(\S+)') { $verifyPackages += $Matches[1] }
        if ($inDeps -and $line -match '^\S' -and $line -notmatch '^\s*-') { $inDeps = $false }
    }
}

foreach ($pkg in $verifyPackages) {
    if ($installed -match "^\s+$([regex]::Escape($pkg))\s") {
        $versionLine = $installed | Where-Object { $_ -match "^\s+$([regex]::Escape($pkg))\s" } | Select-Object -First 1
        Write-Host "OK: $pkg installed ($($versionLine.Trim()))"
    } else {
        Write-Host "FAIL: $pkg not found in environment '$Name' after creation"
        $FailCount++
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Environment '$Name' created with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: Environment '$Name' created and verified"
    exit 0
}
