#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap a fresh Windows machine to run the Runbooks repo.
.DESCRIPTION
    Installs Git and Claude Code, then clones the Runbooks repo.
    Designed to be run as a one-liner from a raw GitHub URL:

      irm https://raw.githubusercontent.com/TheSevenPens/Runbooks/master/bootstrap/bootstrap-windows.ps1 | iex

    Each step is idempotent -already-installed tools are skipped.
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

# Inline copies from scripts/shared/regex-helpers.ps1
# (bootstrap runs before the repo is cloned, so it cannot dot-source the shared file)
function STRINGOP_TestContainsAnyWord {
    param([string]$Text, [string[]]$Words)
    foreach ($word in $Words) {
        if ($Text.Contains($word)) { return $true }
    }
    return $false
}
function STRINGOP_TestLooksLikePowerShellScript {
    param([string]$Content)
    return (STRINGOP_TestContainsAnyWord -Text $Content -Words @('param', 'function', 'Install', 'claude'))
}

function Repair-PathEntries {
    <#
    .SYNOPSIS
        Split PATH entries that were concatenated without a semicolon.
    .DESCRIPTION
        External installers (e.g. micromamba) may join PATH entries without a
        separator, producing values like "...WindowsAppsC:\Users\...".  This
        scans each entry for drive-letter patterns (X:\) appearing mid-string
        and splits them into separate entries.
    #>
    param([string[]]$Entries)
    $repaired = @()
    foreach ($entry in $Entries) {
        $splitPositions = @()
        for ($i = 1; $i -lt $entry.Length - 2; $i++) {
            $c = $entry[$i]
            if ((($c -ge 'A') -and ($c -le 'Z')) -or (($c -ge 'a') -and ($c -le 'z'))) {
                if (($entry[$i + 1] -eq ':') -and ($entry[$i + 2] -eq '\')) {
                    $splitPositions += $i
                }
            }
        }
        if ($splitPositions.Count -eq 0) {
            $repaired += $entry
        } else {
            $prev = 0
            foreach ($pos in $splitPositions) {
                $repaired += $entry.Substring($prev, $pos - $prev)
                $prev = $pos
            }
            $repaired += $entry.Substring($prev)
        }
    }
    return $repaired
}

function Refresh-SessionPath {
    <#
    .SYNOPSIS
        Reload the user and machine PATH into the current session.
    .DESCRIPTION
        After a winget install, the new tool is on the registry PATH but not
        in the running shell. This reads both sources and rebuilds $env:Path
        so subsequent commands find the new tool without restarting.
        Also repairs entries that were concatenated without semicolons.
    #>
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $raw = "$machinePath;$userPath" -split ';' | Where-Object { $_ -ne '' }
    $env:Path = (Repair-PathEntries $raw) -join ';'
}

# ---------------------------------------------------------------------------
# Step 1 -Git
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
# Step 2 -Claude Code (official installer)
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
        } elseif (-not (STRINGOP_TestLooksLikePowerShellScript -Content $installScript)) {
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
        $claudeVer = & $ClaudeExe --version 2>&1
        Write-Host "Claude Code installed: $claudeVer" -ForegroundColor Green
    } elseif ($FailCount -eq 0) {
        Write-Error "Installation appeared to succeed but $ClaudeExe was not found."
        $FailCount++
    }
}

# Ensure Claude bin directory is on the user PATH permanently (registry)
# and in the current session. The official installer puts the binary in
# ~/.local/bin but doesn't always add it to PATH.
if (Test-Path $ClaudeExe) {
    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $currentUserPath) { $currentUserPath = '' }
    $pathEntries = $currentUserPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    $pathEntries = @(Repair-PathEntries $pathEntries)

    if ($pathEntries | Where-Object { $_ -ieq $ClaudeBin }) {
        Write-Host "$ClaudeBin is already on the user PATH." -ForegroundColor Green
    } else {
        Write-Host "Adding $ClaudeBin to user PATH (registry)..." -ForegroundColor Cyan
        $pathEntries += $ClaudeBin
        $newPath = ($pathEntries -join ';')

        [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true).SetValue(
            'Path', $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString
        )

        # Broadcast WM_SETTINGCHANGE so new shells pick up the change
        if (-not ('Win32.NativeMethods' -as [type])) {
            Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        }
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1a
        $result = [UIntPtr]::Zero
        [Win32.NativeMethods]::SendMessageTimeout(
            $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero,
            'Environment', 2, 5000, [ref]$result
        ) | Out-Null

        Write-Host "PATH updated permanently. New terminals will find 'claude'." -ForegroundColor Green
    }

    # Also fix the current session
    if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $ClaudeBin })) {
        $env:Path = "$ClaudeBin;$env:Path"
    }

    # Verify: re-read the registry PATH and confirm the Claude bin dir is there
    $verifyPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $verifyPath) { $verifyPath = '' }
    $verifyEntries = $verifyPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    if (-not ($verifyEntries | Where-Object { $_ -ieq $ClaudeBin })) {
        Write-Warning "$ClaudeBin is NOT on the user PATH registry after update. claude may not be found in new terminals."
        $FailCount++
    }

    # Verify: spawn a fresh powershell to confirm claude.exe is reachable
    $probeOutput = & powershell.exe -NoProfile -Command "
        `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
        if (Get-Command claude -ErrorAction SilentlyContinue) { 'FOUND' } else { 'NOTFOUND' }
    " 2>&1
    if ($probeOutput.Contains('FOUND')) {
        Write-Host "Verified: a new shell can find claude on PATH." -ForegroundColor Green
    } else {
        Write-Warning "A new shell cannot find 'claude' on PATH. You may need to sign out and back in."
        $FailCount++
    }
}

# ---------------------------------------------------------------------------
# Step 3 -Clone the repo
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
    return
} else {
    Write-Host "Bootstrap complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  cd $CloneDir" -ForegroundColor White

    # Show the right claude command depending on whether it's on PATH
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        $claudeCmd = 'claude'
    } elseif (Test-Path $ClaudeExe) {
        $claudeCmd = $ClaudeExe
        Write-Host ""
        Write-Host "  Note: 'claude' is not on PATH yet. Using the full path below." -ForegroundColor Yellow
        Write-Host "  To fix permanently, add $ClaudeBin to your user PATH via:" -ForegroundColor Yellow
        Write-Host "    System Properties > Environment Variables > User PATH > New > $ClaudeBin" -ForegroundColor Yellow
    } else {
        Write-Host "  claude" -ForegroundColor White
        Write-Host ""
        Write-Host "Then tell Claude: ""Follow the setup runbook at setup-runbook-windows.md""" -ForegroundColor White
        return
    }

    Write-Host "  $claudeCmd" -ForegroundColor White
    Write-Host ""
    Write-Host "Then tell Claude: ""Follow the setup runbook at setup-runbook-windows.md""" -ForegroundColor White
    return
}
