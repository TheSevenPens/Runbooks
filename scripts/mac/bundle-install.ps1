#Requires -Version 7.0
<#
.SYNOPSIS
    Install macOS dev tools via Homebrew Bundle (Brewfile).
.DESCRIPTION
    Declarative alternative to install-apps.ps1. Both install the same apps:
      - install-apps.ps1: per-app structured output, verify-after-install
      - bundle-install.ps1: one-shot declarative install via Brewfile

    Invoke: pwsh -NoProfile -File scripts/mac/bundle-install.ps1
            pwsh -NoProfile -File scripts/mac/bundle-install.ps1 -Brewfile ../../apps/Brewfile
#>

param(
    [string]$Brewfile = ''
)

. (Join-Path $PSScriptRoot '../shared/regex-helpers.ps1')

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- Default Brewfile path ---
if ([string]::IsNullOrEmpty($Brewfile)) {
    $scriptDir = Split-Path $PSCommandPath -Parent
    $Brewfile = Join-Path $scriptDir '../../apps/Brewfile'
}

$Brewfile = (Resolve-Path $Brewfile -ErrorAction SilentlyContinue).Path
if (-not $Brewfile -or -not (Test-Path $Brewfile)) {
    Write-Host "FAIL: Brewfile not found: $Brewfile" -ForegroundColor Red
    exit 1
}

Write-Host "INFO: Using Brewfile at $Brewfile" -ForegroundColor Cyan

# --- Pre-flight ---
if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
    Write-Host "FAIL: brew not found -- install Homebrew first" -ForegroundColor Red
    exit 1
}

# --- Helpers ---

function Get-BrewfileEntries {
    param([string]$Path)
    $entries = @()
    foreach ($line in (Get-Content $Path)) {
        $line = $line.Trim()
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
        $parsed = STRINGOP_ParseBrewfileLine -Line $line
        if ($parsed) {
            $entries += $parsed
        }
    }
    return $entries
}

function Test-BrewPackage {
    param([string]$Type, [string]$Name)
    if ($Type -eq 'cask') {
        & brew list --cask $Name 2>$null | Out-Null
    } else {
        & brew list $Name 2>$null | Out-Null
    }
    return ($LASTEXITCODE -eq 0)
}

function Get-BrewVersion {
    param([string]$Name)
    $output = & brew list $Name --versions 2>$null
    if ($output) { return ($output | Select-Object -First 1) }
    return ''
}

# --- Check what's already installed ---

Write-Host "`n--- Checking installed packages ---" -ForegroundColor Cyan

$checkOutput = & brew bundle check --file=$Brewfile 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "SKIP: All packages already installed" -ForegroundColor Green

    # Still verify each entry
    Write-Host "`n--- Verifying packages ---" -ForegroundColor Cyan
    foreach ($entry in (Get-BrewfileEntries -Path $Brewfile)) {
        if (Test-BrewPackage -Type $entry.Type -Name $entry.Name) {
            if ($entry.Type -eq 'cask') {
                Write-Host "OK: $($entry.Name) (cask)" -ForegroundColor Green
            } else {
                $version = Get-BrewVersion -Name $entry.Name
                Write-Host "OK: $($entry.Name) ($version)" -ForegroundColor Green
            }
        } else {
            Write-Host "WARN: $($entry.Name) not found" -ForegroundColor Yellow
        }
    }

    Write-Host "`nRESULT: All packages already installed" -ForegroundColor Green
    exit 0
}

Write-Host "INFO: Some packages need installation" -ForegroundColor Cyan
Write-Host "  $checkOutput"

# --- Install ---

Write-Host "`n--- Installing via brew bundle ---" -ForegroundColor Cyan

& brew bundle --file=$Brewfile 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: brew bundle completed" -ForegroundColor Green
} else {
    Write-Host "WARN: brew bundle completed with issues" -ForegroundColor Yellow
}

# --- Verify ---

Write-Host "`n--- Verifying packages ---" -ForegroundColor Cyan

foreach ($entry in (Get-BrewfileEntries -Path $Brewfile)) {
    if (Test-BrewPackage -Type $entry.Type -Name $entry.Name) {
        if ($entry.Type -eq 'cask') {
            Write-Host "OK: $($entry.Name) (cask)" -ForegroundColor Green
        } else {
            $version = Get-BrewVersion -Name $entry.Name
            Write-Host "OK: $($entry.Name) ($version)" -ForegroundColor Green
        }
    } else {
        Write-Host "FAIL: $($entry.Name) not installed after bundle" -ForegroundColor Red
        $FailCount++
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Bundle install completed with $FailCount issue(s)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: All packages installed and verified" -ForegroundColor Green
    Write-Host "INFO: Open a new terminal for PATH changes to take effect" -ForegroundColor Cyan
    exit 0
}
