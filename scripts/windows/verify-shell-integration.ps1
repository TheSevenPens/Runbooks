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
            $proc.WaitForExit(5000)
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
# Check canonical install path as fallback since pwsh may not be on PATH yet after a fresh install
$pwsh7Path = $null
$pwsh7Cmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh7Cmd) {
    $pwsh7Path = $pwsh7Cmd.Source
} else {
    # Search common install locations as fallback (pwsh may not be on PATH yet)
    $pwsh7Candidates = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    foreach ($candidate in $pwsh7Candidates) {
        if (Test-Path $candidate) { $pwsh7Path = $candidate; break }
    }
}
if ($pwsh7Path) {
    Test-ShellActivate -ShellName "PowerShell 7" -Executable $pwsh7Path -Arguments @(
        '-Command', '"micromamba activate base; if ($?) { Write-Output ACTIVATE_OK }"'
    )
} else {
    Write-Host "SKIP: PowerShell 7 - pwsh.exe not found"
    $Results += [PSCustomObject]@{ Shell = "PowerShell 7"; Status = "SKIP" }
}

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

# CMD - test via cmd.exe /c which triggers the AutoRun hook automatically
$autoRunKey = 'HKCU:\Software\Microsoft\Command Processor'
$autoRun = $null
try {
    $autoRun = Get-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop |
        Select-Object -ExpandProperty AutoRun
} catch {}

if ($autoRun -and $autoRun -match 'mamba_hook\.bat') {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = '/c "micromamba activate base && echo ACTIVATE_OK"'
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $cmdTimeout = 30000
        $exited = $proc.WaitForExit($cmdTimeout)

        if (-not $exited) {
            $proc.Kill()
            $proc.WaitForExit(5000)
            Write-Host "FAIL: CMD - timed out after ${cmdTimeout}ms"
            $Results += [PSCustomObject]@{ Shell = "CMD"; Status = "FAIL" }
            $FailCount++
        } elseif ("$stdout $stderr" -match 'ACTIVATE_OK') {
            Write-Host "OK: CMD micromamba-activate"
            $Results += [PSCustomObject]@{ Shell = "CMD"; Status = "OK" }
        } else {
            $errLine = ($stderr -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1)
            if (-not $errLine) { $errLine = ($stdout -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1) }
            Write-Host "FAIL: CMD micromamba-activate - $errLine"
            $Results += [PSCustomObject]@{ Shell = "CMD"; Status = "FAIL" }
            $FailCount++
        }
    } catch {
        Write-Host "FAIL: CMD - error: $_"
        $Results += [PSCustomObject]@{ Shell = "CMD"; Status = "FAIL" }
        $FailCount++
    }
} else {
    Write-Host "SKIP: CMD - AutoRun hook not configured (mamba_hook.bat not found in registry)"
    $Results += [PSCustomObject]@{ Shell = "CMD"; Status = "SKIP" }
}

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
