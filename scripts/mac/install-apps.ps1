#Requires -Version 7.0
<#
.SYNOPSIS
    Install macOS dev tools via Homebrew (idempotent).
.DESCRIPTION
    For each app: check if already installed, install if missing, verify afterward.
    Uses the same hashtable-array pattern as the Windows install-apps.ps1.

    Apps installed: Git, GitHub Desktop, Visual Studio Code, Google Chrome, GitHub CLI.

    Invoke: pwsh -NoProfile -File scripts/mac/install-apps.ps1
#>

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- Pre-flight: Homebrew ---
if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
    Write-Host "FAIL: brew not found -- install Homebrew first (see setup-runbook-mac.md)" -ForegroundColor Red
    exit 1
}

# --- Detect Homebrew prefix (Apple Silicon vs Intel) ---
$BrewPrefix = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') {
    '/opt/homebrew'
} else {
    '/usr/local'
}

# --- App definitions ---
# Same pattern as scripts/windows/install-apps.ps1: array of hashtables
$Apps = @(
    @{
        Id            = 'git'
        Name          = 'Git'
        Type          = 'formula'
        Verify        = 'git'
        VerifyFlag    = '--version'
        CanonicalPath = "$BrewPrefix/bin/git"
        AppPath       = ''
    },
    @{
        Id            = 'github'
        Name          = 'GitHub Desktop'
        Type          = 'cask'
        Verify        = ''
        VerifyFlag    = ''
        CanonicalPath = ''
        AppPath       = '/Applications/GitHub Desktop.app'
    },
    @{
        Id            = 'visual-studio-code'
        Name          = 'Visual Studio Code'
        Type          = 'cask'
        Verify        = 'code'
        VerifyFlag    = '--version'
        CanonicalPath = '/usr/local/bin/code'
        AppPath       = '/Applications/Visual Studio Code.app'
    },
    @{
        Id            = 'google-chrome'
        Name          = 'Google Chrome'
        Type          = 'cask'
        Verify        = ''
        VerifyFlag    = ''
        CanonicalPath = ''
        AppPath       = '/Applications/Google Chrome.app'
    },
    @{
        Id            = 'gh'
        Name          = 'GitHub CLI'
        Type          = 'formula'
        Verify        = 'gh'
        VerifyFlag    = '--version'
        CanonicalPath = "$BrewPrefix/bin/gh"
        AppPath       = ''
    }
)

# --- Helpers ---

function Test-BrewInstalled {
    param([string]$Type, [string]$BrewId)
    if ($Type -eq 'cask') {
        & brew list --cask $BrewId 2>$null
    } else {
        & brew list $BrewId 2>$null
    }
    return ($LASTEXITCODE -eq 0)
}

function Resolve-Executable {
    param([string]$Command, [string]$CanonicalPath)
    if ([string]::IsNullOrEmpty($Command)) { return '' }

    $exe = Get-Command $Command -ErrorAction SilentlyContinue
    if ($exe) { return $exe.Source }

    if (-not [string]::IsNullOrEmpty($CanonicalPath) -and (Test-Path $CanonicalPath)) {
        return $CanonicalPath
    }
    return ''
}

function Get-ToolVersion {
    param([string]$ExePath, [string]$Flag)
    if ([string]::IsNullOrEmpty($ExePath) -or [string]::IsNullOrEmpty($Flag)) { return '' }
    try {
        $output = & $ExePath $Flag 2>&1
        return ($output | Select-Object -First 1)
    } catch {
        return ''
    }
}

# --- Main loop ---

foreach ($app in $Apps) {
    $id   = $app.Id
    $name = $app.Name
    $type = $app.Type

    Write-Host "`n--- $name ($type`: $id) ---" -ForegroundColor Cyan

    $alreadyInstalled = $false

    # Check 1: CLI command (fastest)
    if (-not [string]::IsNullOrEmpty($app.Verify)) {
        $exePath = Resolve-Executable -Command $app.Verify -CanonicalPath $app.CanonicalPath
        if (-not [string]::IsNullOrEmpty($exePath)) {
            # For formulas with a canonical path, only accept the brew version.
            # This prevents Apple Git (/usr/bin/git) from shadowing brew git.
            if ($type -eq 'formula' -and
                -not [string]::IsNullOrEmpty($app.CanonicalPath) -and
                $exePath -ne $app.CanonicalPath) {
                $version = Get-ToolVersion -ExePath $exePath -Flag $app.VerifyFlag
                Write-Host "INFO: $name found at $exePath -- $version (not brew version, will install)" -ForegroundColor Yellow
            } else {
                $version = Get-ToolVersion -ExePath $exePath -Flag $app.VerifyFlag
                Write-Host "SKIP: $name already installed -- $version" -ForegroundColor Green
                $alreadyInstalled = $true
            }
        }
    }

    # Check 2: GUI app bundle (catches non-brew installs)
    if (-not $alreadyInstalled -and -not [string]::IsNullOrEmpty($app.AppPath) -and (Test-Path $app.AppPath)) {
        Write-Host "SKIP: $name already installed ($($app.AppPath))" -ForegroundColor Green
        $alreadyInstalled = $true
    }

    # Check 3: brew list fallback
    if (-not $alreadyInstalled -and (Test-BrewInstalled -Type $type -BrewId $id)) {
        Write-Host "SKIP: $name already installed (brew)" -ForegroundColor Green
        $alreadyInstalled = $true
    }

    if ($alreadyInstalled) { continue }

    # Install
    Write-Host "INFO: Installing $name..." -ForegroundColor Cyan
    if ($type -eq 'cask') {
        & brew install --cask $id 2>&1
    } else {
        & brew install $id 2>&1
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: $name installed" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $name install failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        $FailCount++
        continue
    }

    # Verify (CLI tools only)
    if (-not [string]::IsNullOrEmpty($app.Verify)) {
        $exePath = Resolve-Executable -Command $app.Verify -CanonicalPath $app.CanonicalPath
        if (-not [string]::IsNullOrEmpty($exePath)) {
            $version = Get-ToolVersion -ExePath $exePath -Flag $app.VerifyFlag
            Write-Host "OK: $name verified -- $version" -ForegroundColor Green
        } else {
            Write-Host "WARN: $name installed but '$($app.Verify)' not found on PATH -- open a new terminal" -ForegroundColor Yellow
        }
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount install(s) failed" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: All apps installed" -ForegroundColor Green
    Write-Host "INFO: Open a new terminal for PATH changes to take effect" -ForegroundColor Cyan
    exit 0
}
