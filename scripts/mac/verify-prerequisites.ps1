#Requires -Version 7.0
<#
.SYNOPSIS
    Check macOS dev tool prerequisites (mise-based).
.DESCRIPTION
    Verifies that required system tools are installed and reports their
    versions and sources. Updated for mise (no conda/micromamba checks).

    Checks: Homebrew, Git (with source detection), mise, mise-managed
    tools (node, python, gh).

    Invoke: pwsh -NoProfile -File scripts/mac/verify-prerequisites.ps1
#>

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- Detect Homebrew prefix ---
$BrewPrefix = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') {
    '/opt/homebrew'
} else {
    '/usr/local'
}

# --- Helpers ---

function Get-GitSource {
    param([string]$Path)
    switch -Wildcard ($Path) {
        "$BrewPrefix/bin/git"  { return 'homebrew' }
        '/usr/bin/git'         { return 'apple' }
        default                { return 'unknown' }
    }
}

function Test-CliTool {
    param(
        [string]$Name,
        [string]$Command,
        [string]$VersionFlag = '--version'
    )
    $exe = Get-Command $Command -ErrorAction SilentlyContinue
    if ($exe) {
        $version = try { & $exe.Source $VersionFlag 2>&1 | Select-Object -First 1 } catch { 'unknown' }
        Write-Host "OK: $Name -- $version ($($exe.Source))" -ForegroundColor Green
        return $true
    } else {
        Write-Host "FAIL: $Name not found" -ForegroundColor Red
        $script:FailCount++
        return $false
    }
}

# --- Check: Homebrew ---

Write-Host "--- System tools ---" -ForegroundColor Cyan

$brewExe = Get-Command brew -ErrorAction SilentlyContinue
if ($brewExe) {
    $brewVersion = & brew --version 2>$null | Select-Object -First 1
    $brewVersion = $brewVersion.Replace('Homebrew ', '')
    Write-Host "OK: brew $brewVersion ($($brewExe.Source))" -ForegroundColor Green
} else {
    Write-Host "FAIL: brew not found -- install from https://brew.sh" -ForegroundColor Red
    $FailCount++
}

# --- Check: Git ---

$gitExe = Get-Command git -ErrorAction SilentlyContinue
if ($gitExe) {
    $gitVersion = & git --version 2>$null | Select-Object -First 1
    $gitVersion = $gitVersion.Replace('git version ', '')
    $gitSource = Get-GitSource -Path $gitExe.Source

    if ($gitSource -eq 'apple') {
        Write-Host "WARN: git $gitVersion ($($gitExe.Source)) [$gitSource] -- brew version recommended" -ForegroundColor Yellow
    } else {
        Write-Host "OK: git $gitVersion ($($gitExe.Source)) [$gitSource]" -ForegroundColor Green
    }
} else {
    Write-Host "FAIL: git not found" -ForegroundColor Red
    $FailCount++
}

# --- Check: PowerShell 7 ---

$pwshVersion = $PSVersionTable.PSVersion
Write-Host "OK: PowerShell $pwshVersion ($($PSCommandPath ? 'running' : 'unknown'))" -ForegroundColor Green

# --- Check: mise ---

Write-Host "`n--- mise ---" -ForegroundColor Cyan

$miseExe = Get-Command mise -ErrorAction SilentlyContinue
if ($miseExe) {
    $miseVersion = & mise --version 2>$null | Select-Object -First 1
    Write-Host "OK: mise $miseVersion ($($miseExe.Source))" -ForegroundColor Green

    # Check mise activation
    $miseDoctor = & mise doctor 2>&1
    $activated = ($miseDoctor | Select-String 'activated:\s*yes')
    if ($activated) {
        Write-Host "OK: mise is activated" -ForegroundColor Green
    } else {
        Write-Host "WARN: mise is not activated in this shell -- check shell config" -ForegroundColor Yellow
    }
} else {
    Write-Host "FAIL: mise not found -- install with: brew install mise" -ForegroundColor Red
    $FailCount++
}

# --- Check: mise-managed tools ---

Write-Host "`n--- mise-managed tools ---" -ForegroundColor Cyan

$miseTools = @(
    @{ Name = 'Node.js'; Command = 'node' },
    @{ Name = 'Python';  Command = 'python' },
    @{ Name = 'GitHub CLI'; Command = 'gh' }
)

foreach ($tool in $miseTools) {
    $exe = Get-Command $tool.Command -ErrorAction SilentlyContinue
    if ($exe) {
        $version = try { & $exe.Source --version 2>&1 | Select-Object -First 1 } catch { 'unknown' }
        $source = if ($exe.Source.Contains('mise')) { 'mise' } else { 'other' }
        if ($source -eq 'mise') {
            Write-Host "OK: $($tool.Name) -- $version ($($exe.Source))" -ForegroundColor Green
        } else {
            Write-Host "WARN: $($tool.Name) -- $version ($($exe.Source)) [not managed by mise]" -ForegroundColor Yellow
        }
    } else {
        Write-Host "FAIL: $($tool.Name) ($($tool.Command)) not found -- run: mise use -g $($tool.Command)@latest" -ForegroundColor Red
        $FailCount++
    }
}

# --- Check: mise global config ---

$miseConfig = Join-Path $HOME '.config/mise/config.toml'
if (Test-Path $miseConfig) {
    Write-Host "`nOK: mise global config exists at $miseConfig" -ForegroundColor Green
} else {
    Write-Host "`nWARN: no mise global config at $miseConfig -- tools may not be configured" -ForegroundColor Yellow
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount issue(s) found" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: All checks passed" -ForegroundColor Green
    exit 0
}
