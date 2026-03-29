# micromamba-shell-init.ps1 - Run micromamba shell init for all Windows shells
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File micromamba-shell-init.ps1
#
# Actions:
#   1. Locate micromamba binary
#   2. Run shell init for powershell, bash, cmd.exe
#   3. Verify CMD AutoRun registry value
#   4. Verify .bash_profile and PowerShell profile were modified
#
# Output: Structured lines prefixed with OK / FAIL / INFO
# Exit code: 0 on success, 1 on failure

$ErrorActionPreference = 'Continue'
$FailCount = 0
$RootPrefix = "$env:USERPROFILE\micromamba"

# --- Locate micromamba binary ---

$mmExe = $null
$candidates = @(
    "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe"
)

# Also check PATH
$mmCmd = Get-Command micromamba -ErrorAction SilentlyContinue
if ($mmCmd) { $candidates += $mmCmd.Source }

foreach ($path in $candidates) {
    if (Test-Path $path) {
        $mmExe = $path
        break
    }
}

if (-not $mmExe) {
    Write-Host "FAIL: micromamba binary not found"
    Write-Host "  Checked: $($candidates -join ', ')"
    exit 1
}

Write-Host "INFO: Using micromamba at $mmExe"

# --- Shell init: PowerShell ---

Write-Host ""
Write-Host "--- Initializing PowerShell ---"
$output = & $mmExe shell init -s powershell -r $RootPrefix 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: micromamba shell init -s powershell"
} else {
    Write-Host "FAIL: micromamba shell init -s powershell"
    Write-Host "  $output"
    $FailCount++
}

# --- Shell init: bash ---

Write-Host ""
Write-Host "--- Initializing bash ---"
$output = & $mmExe shell init -s bash -r $RootPrefix 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: micromamba shell init -s bash"
} else {
    Write-Host "FAIL: micromamba shell init -s bash"
    Write-Host "  $output"
    $FailCount++
}

# --- Shell init: cmd.exe ---

Write-Host ""
Write-Host "--- Initializing cmd.exe ---"
$output = & $mmExe shell init -s cmd.exe -r $RootPrefix 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: micromamba shell init -s cmd.exe"
} else {
    Write-Host "FAIL: micromamba shell init -s cmd.exe"
    Write-Host "  $output"
    $FailCount++
}

# --- Verify CMD AutoRun ---

Write-Host ""
Write-Host "--- Verifying CMD AutoRun ---"
$autoRunKey = 'HKCU:\Software\Microsoft\Command Processor'
$autoRun = $null
try {
    $autoRun = Get-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop | Select-Object -ExpandProperty AutoRun
} catch {
    # Property doesn't exist
}

if ($autoRun) {
    $expectedBat = "$RootPrefix\condabin\mamba_hook.bat"
    if ($autoRun -match 'mamba_hook\.bat') {
        if (Test-Path $expectedBat) {
            Write-Host "OK: CMD AutoRun references mamba_hook.bat"
            Write-Host "  Value: $autoRun"
            Write-Host "  File exists: $expectedBat"
        } else {
            Write-Host "FAIL: CMD AutoRun references mamba_hook.bat but file not found at $expectedBat"
            $FailCount++
        }
    } else {
        Write-Host "FAIL: CMD AutoRun does not reference mamba_hook.bat"
        Write-Host "  Value: $autoRun"
        $FailCount++
    }
} else {
    Write-Host "FAIL: CMD AutoRun registry key not set"
    $FailCount++
}

# --- Verify .bash_profile ---

Write-Host ""
Write-Host "--- Verifying .bash_profile ---"
$bashProfile = "$env:USERPROFILE\.bash_profile"
if (Test-Path $bashProfile) {
    $content = Get-Content $bashProfile -Raw
    if ($content -match 'mamba initialize') {
        Write-Host "OK: .bash_profile contains micromamba init block"
    } else {
        Write-Host "FAIL: .bash_profile exists but has no micromamba init block"
        $FailCount++
    }
} else {
    Write-Host "FAIL: .bash_profile not found at $bashProfile"
    $FailCount++
}

# --- Verify PowerShell profile ---

Write-Host ""
Write-Host "--- Verifying PowerShell profile ---"
$psProfiles = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\profile.ps1"
)

foreach ($profilePath in $psProfiles) {
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -match 'MAMBA_EXE|micromamba|mamba_hook') {
            Write-Host "OK: $profilePath contains micromamba hooks"
        } else {
            Write-Host "WARN: $profilePath exists but has no micromamba hooks"
        }
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount issue(s) - close and reopen all terminals after fixing"
    exit 1
} else {
    Write-Host "RESULT: All shell inits completed - close and reopen all terminals"
    exit 0
}
