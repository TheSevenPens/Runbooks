# verify-shell-integration.ps1 - Test micromamba activate across Windows shells
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-shell-integration.ps1
#
# Tests that shell hooks are properly initialized by attempting to activate
# the base environment in each shell. PowerShell tests load the profile
# (no -NoProfile) so the hooks are available.
#
# Output: Structured OK/FAIL lines, then a summary table
# Exit code: 0 if all pass, 1 if any fail

$ErrorActionPreference = 'Continue'
$FailCount = 0
$Results = @()

# --- Helpers ---

function Test-ShellActivate {
    param(
        [string]$ShellName,
        [string]$Executable,
        [string[]]$Arguments,
        [int]$TimeoutMs = 30000
    )

    $exePath = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $exePath) {
        Write-Host "SKIP: $ShellName - $Executable not found"
        $script:Results += [PSCustomObject]@{ Shell = $ShellName; Status = "SKIP" }
        return
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath.Source
        $psi.Arguments = $Arguments -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $exited = $proc.WaitForExit($TimeoutMs)

        if (-not $exited) {
            $proc.Kill()
            Write-Host "FAIL: $ShellName - timed out after ${TimeoutMs}ms"
            $script:Results += [PSCustomObject]@{ Shell = $ShellName; Status = "FAIL" }
            $script:FailCount++
            return
        }

        $allOutput = "$stdout $stderr"
        if ($allOutput -match 'ACTIVATE_OK') {
            Write-Host "OK: $ShellName micromamba-activate"
            $script:Results += [PSCustomObject]@{ Shell = $ShellName; Status = "OK" }
        } else {
            $errLine = ($stderr -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1)
            if (-not $errLine) { $errLine = ($stdout -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1) }
            Write-Host "FAIL: $ShellName micromamba-activate - $errLine"
            $script:Results += [PSCustomObject]@{ Shell = $ShellName; Status = "FAIL" }
            $script:FailCount++
        }
    } catch {
        Write-Host "FAIL: $ShellName - error: $_"
        $script:Results += [PSCustomObject]@{ Shell = $ShellName; Status = "FAIL" }
        $script:FailCount++
    }
}

# --- Tests ---

# PowerShell 5.1 - must NOT use -NoProfile so hooks load
Test-ShellActivate -ShellName "PowerShell 5.1" -Executable "powershell.exe" -Arguments @(
    '-Command', '"micromamba activate base; if ($?) { Write-Output ACTIVATE_OK }"'
)

# PowerShell 7 - optional, skip if not installed
Test-ShellActivate -ShellName "PowerShell 7" -Executable "pwsh.exe" -Arguments @(
    '-Command', '"micromamba activate base; if ($?) { Write-Output ACTIVATE_OK }"'
)

# Git Bash - need to find bash.exe
$gitBashPaths = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe"
)
$bashExe = $null
foreach ($path in $gitBashPaths) {
    if (Test-Path $path) { $bashExe = $path; break }
}
if (-not $bashExe) {
    $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($bashCmd) { $bashExe = $bashCmd.Source }
}

if ($bashExe) {
    Test-ShellActivate -ShellName "Git Bash" -Executable $bashExe -Arguments @(
        '-l', '-i', '-c', '"micromamba activate base && echo ACTIVATE_OK"'
    )
} else {
    Write-Host "SKIP: Git Bash - bash.exe not found"
    $Results += [PSCustomObject]@{ Shell = "Git Bash"; Status = "SKIP" }
}

# CMD - cannot test non-interactively in a reliable way
Write-Host "INFO: CMD requires manual testing - open CMD and run: micromamba activate base"
$Results += [PSCustomObject]@{ Shell = "CMD"; Status = "(manual)" }

# --- Summary table ---

Write-Host ""
Write-Host "| Shell          | micromamba activate |"
Write-Host "|----------------|---------------------|"
foreach ($r in $Results) {
    Write-Host ("| {0,-14} | {1,-19} |" -f $r.Shell, $r.Status)
}

# --- Exit ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount failure(s)"
    exit 1
} else {
    Write-Host "RESULT: All shell integrations working"
    exit 0
}
