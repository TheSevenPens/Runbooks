#Requires -Version 7.0
<#
.SYNOPSIS
    Installs Claude Code CLI and ensures it is on the user PATH.
.DESCRIPTION
    Prepares a macOS machine to run the runbooks in this repo.
    Installs Claude Code via the official bash installer and adds its
    directory to PATH in the user's shell config. Designed to be idempotent.

    Invoke: pwsh -NoProfile -File scripts/mac/prepare-for-runbooks.ps1
#>

$ErrorActionPreference = 'Stop'

$ClaudeBin = Join-Path $HOME '.local/bin'
$ClaudeExe = Join-Path $ClaudeBin 'claude'
$FailCount = 0

# --- Detect shell and config file ---
$userShell = Split-Path $env:SHELL -Leaf
switch ($userShell) {
    'zsh'  { $shellRc = Join-Path $HOME '.zshrc' }
    'bash' { $shellRc = Join-Path $HOME '.bash_profile' }
    default { $shellRc = Join-Path $HOME '.profile' }
}

# --- Install Claude Code ---
Write-Host "`n--- Claude Code ---" -ForegroundColor Cyan

if (Test-Path $ClaudeExe) {
    $version = & $ClaudeExe --version 2>&1
    Write-Host "SKIP: Claude Code already installed -- $version" -ForegroundColor Green
} else {
    Write-Host "INFO: Installing Claude Code via official installer..." -ForegroundColor Cyan
    try {
        & bash -c 'curl -fsSL https://claude.ai/install.sh | sh' 2>&1
    } catch {
        Write-Host "FAIL: Claude Code install failed -- $_" -ForegroundColor Red
        $FailCount++
    }

    if (Test-Path $ClaudeExe) {
        $version = & $ClaudeExe --version 2>&1
        Write-Host "OK: Claude Code installed -- $version" -ForegroundColor Green
    } elseif ($FailCount -eq 0) {
        Write-Host "FAIL: Installation appeared to succeed but $ClaudeExe was not found" -ForegroundColor Red
        $FailCount++
    }
}

# --- Ensure Claude bin directory is on PATH ---
Write-Host "`n--- PATH ---" -ForegroundColor Cyan

$pathEntries = $env:PATH -split ':'
if ($pathEntries -contains $ClaudeBin) {
    Write-Host "SKIP: $ClaudeBin already on PATH" -ForegroundColor Green
} else {
    Write-Host "INFO: Adding $ClaudeBin to PATH in $shellRc..." -ForegroundColor Cyan

    # Check if already referenced in the rc file (match both expanded and $HOME forms)
    $rcContent = if (Test-Path $shellRc) { Get-Content $shellRc -Raw } else { '' }
    if ($rcContent.Contains('.local/bin')) {
        Write-Host "SKIP: $ClaudeBin already referenced in $shellRc" -ForegroundColor Green
    } else {
        # Write without BOM (critical for bash/zsh files)
        $linesToAppend = "`n# Claude Code CLI`nexport PATH=`"$ClaudeBin`:`$PATH`""
        [System.IO.File]::AppendAllText($shellRc, $linesToAppend)
        Write-Host "OK: PATH updated in $shellRc" -ForegroundColor Green
    }

    # Update current session
    $env:PATH = "${ClaudeBin}:$($env:PATH)"
}

# --- Verify ---
Write-Host "`n--- Verify ---" -ForegroundColor Cyan

if (Test-Path $ClaudeExe) {
    try {
        $version = & $ClaudeExe --version 2>&1
        Write-Host "OK: Claude Code is ready -- $version" -ForegroundColor Green
    } catch {
        Write-Host "WARN: Claude Code is installed but could not be executed -- open a new terminal" -ForegroundColor Yellow
    }
}

# --- Summary ---
Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount failure(s)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: Ready -- open a new terminal and run: claude" -ForegroundColor Green
    exit 0
}
