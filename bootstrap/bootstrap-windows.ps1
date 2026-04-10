#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a fresh Windows machine to run the Runbooks repo.
.DESCRIPTION
    Installs Git and Claude Code, then clones the Runbooks repo.
    Designed to be run as a one-liner from a raw GitHub URL:

      irm https://raw.githubusercontent.com/TheSevenPens/Runbooks/master/bootstrap/bootstrap-windows.ps1 | iex

    Each step is idempotent — already-installed tools are skipped.
    Requires winget (ships with Windows 11).

    Claude Code is installed via the official installer (https://claude.ai/install.ps1),
    matching the method used by scripts/windows/prepare-for-runbooks.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl   = 'https://github.com/TheSevenPens/Runbooks.git'
$CloneDir  = Join-Path $HOME 'Documents\GitHub\Runbooks'
$ClaudeBin = Join-Path $HOME '.local\bin'
$ClaudeExe = Join-Path $ClaudeBin 'claude.exe'
$FailCount = 0

function Refresh-SessionPath {
    <#
    .SYNOPSIS
        Reload the user and machine PATH into the current session.
    .DESCRIPTION
        After a winget install, the new tool is on the registry PATH but not
        in the running shell. This reads both sources and rebuilds $env:Path
        so subsequent commands find the new tool without restarting.
    #>
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"
}

# ---------------------------------------------------------------------------
# Step 1 — Git
# ---------------------------------------------------------------------------
Write-Host "`n--- Step 1: Git ---" -ForegroundColor Cyan

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVer = & git --version 2>&1
    Write-Host "Git already installed: $gitVer" -ForegroundColor Green
} else {
    Write-Host "Installing Git via winget..." -ForegroundColor Cyan
    winget install --id Git.Git --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Error "winget install Git failed (exit code $LASTEXITCODE)"
        $FailCount++
    }
    Refresh-SessionPath

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVer = & git --version 2>&1
        Write-Host "Git installed: $gitVer" -ForegroundColor Green
    } else {
        Write-Warning "Git was installed but 'git' is not on PATH in this session. Checking known locations..."
        $gitCandidates = @(
            "$env:ProgramFiles\Git\cmd",
            "${env:ProgramFiles(x86)}\Git\cmd"
        )
        foreach ($dir in $gitCandidates) {
            if (Test-Path "$dir\git.exe") {
                $env:Path = "$dir;$env:Path"
                Write-Host "Found git at $dir -- added to session PATH." -ForegroundColor Green
                break
            }
        }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Error "Cannot find git.exe after install. Open a new terminal and re-run this script."
            $FailCount++
        }
    }
}

# ---------------------------------------------------------------------------
# Step 2 — Claude Code (official installer)
# ---------------------------------------------------------------------------
Write-Host "`n--- Step 2: Claude Code ---" -ForegroundColor Cyan

if (Test-Path $ClaudeExe) {
    $claudeVer = & $ClaudeExe --version 2>&1
    Write-Host "Claude Code already installed: $claudeVer" -ForegroundColor Green
} else {
    Write-Host "Installing Claude Code via official installer..." -ForegroundColor Cyan
    try {
        $installScript = Invoke-RestMethod https://claude.ai/install.ps1
        if ([string]::IsNullOrWhiteSpace($installScript)) {
            Write-Error "Downloaded install script is empty -- network issue or URL may have changed"
            $FailCount++
        } elseif ($installScript -notmatch 'param|function|Install|claude') {
            Write-Error "Downloaded content does not look like a PowerShell install script -- URL may have changed"
            $FailCount++
        } else {
            $installScript | Invoke-Expression
        }
    } catch {
        Write-Error "Failed to install Claude Code: $_"
        $FailCount++
    }

    if (Test-Path $ClaudeExe) {
        # Ensure the bin directory is on PATH for this session
        if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $ClaudeBin })) {
            $env:Path = "$ClaudeBin;$env:Path"
        }
        $claudeVer = & $ClaudeExe --version 2>&1
        Write-Host "Claude Code installed: $claudeVer" -ForegroundColor Green
    } elseif ($FailCount -eq 0) {
        Write-Error "Installation appeared to succeed but $ClaudeExe was not found."
        $FailCount++
    }
}

# ---------------------------------------------------------------------------
# Step 3 — Clone the repo
# ---------------------------------------------------------------------------
Write-Host "`n--- Step 3: Clone Runbooks repo ---" -ForegroundColor Cyan

if (Test-Path (Join-Path $CloneDir '.git')) {
    Write-Host "Repo already cloned at $CloneDir" -ForegroundColor Green
} else {
    # Ensure parent directory exists
    $parentDir = Split-Path $CloneDir -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Write-Host "Cloning $RepoUrl to $CloneDir..." -ForegroundColor Cyan
    Write-Host "(The repo is private -- Git Credential Manager will open a browser window for GitHub auth)" -ForegroundColor Yellow

    # git writes progress to stderr, which PowerShell treats as an error
    # under $ErrorActionPreference = 'Stop'. Temporarily relax it.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git clone $RepoUrl $CloneDir 2>&1
    $cloneExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($cloneExit -ne 0) {
        Write-Error "git clone failed (exit code $cloneExit)"
        $FailCount++
    } elseif (Test-Path (Join-Path $CloneDir '.git')) {
        Write-Host "Repo cloned successfully." -ForegroundColor Green
    } else {
        Write-Error "git clone appeared to succeed but .git directory not found."
        $FailCount++
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "$FailCount step(s) failed. Review the errors above, then re-run." -ForegroundColor Red
    exit 1
} else {
    Write-Host "Bootstrap complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  cd $CloneDir" -ForegroundColor White
    Write-Host "  claude" -ForegroundColor White
    Write-Host ""
    Write-Host "Then tell Claude: ""Follow the setup runbook at setup-runbook-windows.md""" -ForegroundColor White
    exit 0
}
