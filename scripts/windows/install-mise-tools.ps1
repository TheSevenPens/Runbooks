# install-mise-tools.ps1 - Install global tools via mise (idempotent)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-mise-tools.ps1
#
# Actions:
#   1. Verify mise is installed
#   2. Install node@lts, python@3.12, gh@latest via mise use -g (from activated PS7)
#   3. Run mise install as safety net (catches registration issue)
#   4. Regenerate shims for CMD
#   5. Verify tools are callable
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

. (Join-Path $PSScriptRoot '..\shared\string-helpers.ps1')
. (Join-Path $PSScriptRoot '..\shared\mise-helpers.ps1')
. (Join-Path $PSScriptRoot '..\shared\process-helpers.ps1')

$ErrorActionPreference = 'Continue'
$FailCount = 0

$ToolSpec = 'node@lts python@3.12 gh@latest'

# --- Step 1: Verify mise ---

Write-Host "--- Step 1: Verify mise ---"

$miseExePath = MISE_ResolveExe
if (-not $miseExePath) {
    Write-Host "FAIL: mise not found - run install-mise.ps1 first"
    exit 1
}

# The child pwsh processes below invoke 'mise' by name, so it must be on the
# PATH they inherit from us.  It may not be if mise was installed after this
# shell started.
MISE_EnsureOnPath -MiseExe $miseExePath

$miseVersion = STRINGOP_GetToolVersion -ExePath $miseExePath -Flag '--version'
Write-Host "OK: mise $miseVersion ($miseExePath)"

# --- Step 2: Install tools via activated PS7 ---

Write-Host ""
Write-Host "--- Step 2: Install tools ---"

# Always run through pwsh to ensure profile loads and activation is live.
# This avoids the "installed but missing in mise doctor" issue.
$pwshExe = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshExe) {
    $pwshCandidates = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    )
    foreach ($c in $pwshCandidates) {
        if (Test-Path $c) { $pwshExe = Get-Command $c -ErrorAction SilentlyContinue; break }
    }
}

if (-not $pwshExe) {
    Write-Host "FAIL: PowerShell 7 not found - needed for activated mise session"
    $FailCount++
} else {
    Write-Host "INFO: Running mise use -g $ToolSpec via activated PS7"
    # Explicitly activate mise before running commands (profile may not activate in non-interactive spawn)
    $activateAndRun = "mise activate pwsh | Out-String | Invoke-Expression; mise use -g $ToolSpec 2>&1 | ForEach-Object { Write-Host `$_ }"
    $r = PROC_Invoke -FilePath $pwshExe.Source -Arguments "-NoProfile -Command `"$activateAndRun`"" -TimeoutMs 300000  # 5 min for downloads

    if ($r.TimedOut) {
        Write-Host "FAIL: mise use -g timed out after 5 minutes (process tree stopped)"
        $FailCount++
    } else {
        # Check for installed markers in output
        $allOutput = "$($r.StdOut) $($r.StdErr)"
        if ($allOutput.Contains('installed') -or $allOutput.Contains('config.toml')) {
            Write-Host "OK: Tools installed"
        } else {
            # May have already been installed (no output)
            Write-Host "INFO: mise use -g completed (tools may already be installed)"
        }
    }
}

# --- Step 3: Safety net - mise install ---

Write-Host ""
Write-Host "--- Step 3: Re-register tools (safety net) ---"

if ($pwshExe) {
    $r = PROC_Invoke -FilePath $pwshExe.Source -Arguments '-NoProfile -Command "mise activate pwsh | Out-String | Invoke-Expression; mise install 2>&1 | ForEach-Object { Write-Host $_ }"' -TimeoutMs 300000
    if ($r.TimedOut) {
        Write-Host "FAIL: mise install timed out after 5 minutes (process tree stopped)"
        $FailCount++
    } else {
        Write-Host "OK: mise install completed"
    }
}

# --- Step 4: Regenerate shims ---

Write-Host ""
Write-Host "--- Step 4: Regenerate shims ---"

if ($pwshExe) {
    $r = PROC_Invoke -FilePath $pwshExe.Source -Arguments '-NoProfile -Command "mise activate pwsh | Out-String | Invoke-Expression; mise reshim 2>&1"' -TimeoutMs 60000
    if ($r.TimedOut) {
        Write-Host "FAIL: mise reshim timed out after 60 seconds (process tree stopped)"
        $FailCount++
    } else {
        Write-Host "OK: Shims regenerated"
    }
}

# --- Step 5: Verify tools ---

Write-Host ""
Write-Host "--- Step 5: Verify tools ---"

$tools = @(
    @{ Name = "node"; Flag = "--version" },
    @{ Name = "python"; Flag = "--version" },
    @{ Name = "gh"; Flag = "--version" }
)

if ($pwshExe) {
    foreach ($tool in $tools) {
        try {
            $r = PROC_Invoke -FilePath $pwshExe.Source -Arguments "-NoProfile -Command `"mise activate pwsh | Out-String | Invoke-Expression; $($tool.Name) $($tool.Flag) 2>&1 | Select-Object -First 1`"" -TimeoutMs 30000
            $version = ''
            if (-not $r.TimedOut) { $version = STRINGOP_FindFirstNonBlankLine -Text $r.StdOut }
            if ($version) {
                Write-Host "OK: $($tool.Name) $version"
            } elseif ($r.TimedOut) {
                Write-Host "FAIL: $($tool.Name) --version timed out (process tree stopped)"
                $FailCount++
            } else {
                Write-Host "FAIL: $($tool.Name) not callable after install"
                $FailCount++
            }
        } catch {
            Write-Host "FAIL: $($tool.Name) verification error: $_"
            $FailCount++
        }
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Completed with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: All tools installed and verified"
    exit 0
}
