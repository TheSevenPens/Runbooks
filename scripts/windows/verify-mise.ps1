# verify-mise.ps1 - Verify mise installation, shell activation, and tool availability
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-mise.ps1
#
# Checks:
#   1. mise is callable
#   2. Shell profiles contain activation lines (PS7, PS5.1)
#   3. Shims directory exists and is on registry PATH (for CMD)
#   4. mise doctor passes in PS7 and PS5.1
#   5. Tools (node, python, gh) are callable in PS7, PS5.1, and CMD
#
# Output: Structured lines prefixed with OK / WARN / FAIL / SKIP
# Exit code: 0 if all pass, 1 if any fail

. (Join-Path $PSScriptRoot '..\shared\string-helpers.ps1')

$ErrorActionPreference = 'Continue'
$FailCount = 0
$Results = @()

# --- Helpers ---

function Test-MiseShell {
    param(
        [string]$ShellName,
        [string]$Executable,
        [string]$Command,
        [string]$SuccessMarker,
        [int]$TimeoutMs = 30000
    )

    $exePath = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $exePath) {
        Write-Host "SKIP: $ShellName - $Executable not found"
        return "SKIP"
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath.Source
        $psi.Arguments = "-Command `"$Command`""
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
            return "FAIL(timeout)"
        }

        $allOutput = "$stdout $stderr"
        if ($allOutput.Contains($SuccessMarker)) {
            return "OK"
        } else {
            $errLine = STRINGOP_FindFirstNonBlankLine -Text $stderr
            if (-not $errLine) { $errLine = STRINGOP_FindFirstNonBlankLine -Text $stdout }
            if ($errLine) { return "FAIL($errLine)" }
            return "FAIL"
        }
    } catch {
        return "FAIL($_)"
    }
}

function Test-CmdTool {
    param(
        [string]$ToolName,
        [string]$VersionFlag = "--version",
        [int]$TimeoutMs = 30000
    )

    $shimDir = Join-Path $env:LOCALAPPDATA 'mise\shims'
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c `"set PATH=$shimDir;%PATH% && $ToolName $VersionFlag`""
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
            return ""
        }

        $version = STRINGOP_FindFirstNonBlankLine -Text $stdout
        if (-not $version) { $version = STRINGOP_FindFirstNonBlankLine -Text $stderr }
        return $version
    } catch {
        return ""
    }
}

# --- Check 1: mise is callable ---

Write-Host "--- mise installation ---"

$miseExe = Get-Command mise -ErrorAction SilentlyContinue
if (-not $miseExe) {
    # Canonical path fallback
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\mise.exe'),
        (Join-Path $env:LOCALAPPDATA 'mise\bin\mise.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $miseExe = Get-Command $c -ErrorAction SilentlyContinue; break }
    }
}

if ($miseExe) {
    $miseVersion = STRINGOP_GetToolVersion -ExePath $miseExe.Source -Flag '--version'
    Write-Host "OK: mise $miseVersion ($($miseExe.Source))"
} else {
    Write-Host "FAIL: mise not found"
    $FailCount++
}

# --- Check 2: Shell profiles contain activation lines ---

Write-Host ""
Write-Host "--- Shell profile activation ---"

$docsDir = [Environment]::GetFolderPath('MyDocuments')

$ps7Profile = Join-Path $docsDir "PowerShell\Microsoft.PowerShell_profile.ps1"
if (Test-Path $ps7Profile) {
    $ps7Content = Get-Content $ps7Profile -Raw
    if ($ps7Content.Contains('mise activate')) {
        Write-Host "OK: PS7 profile contains mise activation"
    } else {
        Write-Host "FAIL: PS7 profile exists but missing mise activation line"
        $FailCount++
    }
} else {
    Write-Host "FAIL: PS7 profile not found at $ps7Profile"
    $FailCount++
}

$ps5Profile = Join-Path $docsDir "WindowsPowerShell\profile.ps1"
if (Test-Path $ps5Profile) {
    $ps5Content = Get-Content $ps5Profile -Raw
    if ($ps5Content.Contains('mise activate')) {
        Write-Host "OK: PS5.1 profile contains mise activation"
    } else {
        Write-Host "FAIL: PS5.1 profile exists but missing mise activation line"
        $FailCount++
    }
} else {
    Write-Host "FAIL: PS5.1 profile not found at $ps5Profile"
    $FailCount++
}

# --- Check 3: Shims directory ---

Write-Host ""
Write-Host "--- CMD shims ---"

$shimDir = Join-Path $env:LOCALAPPDATA 'mise\shims'
if (Test-Path $shimDir) {
    $shimCount = @(Get-ChildItem $shimDir -File -ErrorAction SilentlyContinue).Count
    Write-Host "OK: Shims directory exists ($shimCount files)"
} else {
    Write-Host "WARN: Shims directory not found at $shimDir - CMD tools may not work"
}

$regKey = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
if ($regKey) {
    $pathValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    if ($pathValue.Contains('mise\shims')) {
        Write-Host "OK: Shims directory on registry PATH"
    } else {
        Write-Host "FAIL: Shims directory not on registry PATH - CMD tools will not work"
        $FailCount++
    }
}

# --- Check 4: mise doctor in activated shells ---

Write-Host ""
Write-Host "--- mise doctor ---"

# PS7
$ps7Doctor = Test-MiseShell -ShellName "PS7" -Executable "pwsh" `
    -Command 'mise doctor 2>&1 | Out-String; if (((mise doctor 2>&1 | Out-String) -match \"No problems found\")) { Write-Output DOCTOR_OK }' `
    -SuccessMarker "DOCTOR_OK"
if ($ps7Doctor -eq "OK") {
    Write-Host "OK: mise doctor passes in PowerShell 7"
} elseif ($ps7Doctor -eq "SKIP") {
    # already printed
} else {
    Write-Host "FAIL: mise doctor failed in PowerShell 7 - $ps7Doctor"
    $FailCount++
}

# PS5.1
$ps5Doctor = Test-MiseShell -ShellName "PS5.1" -Executable "powershell.exe" `
    -Command 'mise doctor 2>&1 | Out-String; if (((mise doctor 2>&1 | Out-String) -match \"No problems found\")) { Write-Output DOCTOR_OK }' `
    -SuccessMarker "DOCTOR_OK"
if ($ps5Doctor -eq "OK") {
    Write-Host "OK: mise doctor passes in PowerShell 5.1"
} elseif ($ps5Doctor -eq "SKIP") {
    # already printed
} else {
    Write-Host "FAIL: mise doctor failed in PowerShell 5.1 - $ps5Doctor"
    $FailCount++
}

# --- Check 5: Tool versions in all shells ---

Write-Host ""
Write-Host "--- Tool versions ---"

$tools = @('node', 'python', 'gh')
$shells = @(
    @{ Name = "PowerShell 7"; Exe = "pwsh"; Method = "activation" },
    @{ Name = "PowerShell 5.1"; Exe = "powershell.exe"; Method = "activation" },
    @{ Name = "CMD"; Exe = "cmd.exe"; Method = "shims" }
)

foreach ($shell in $shells) {
    foreach ($tool in $tools) {
        if ($shell.Name -eq "CMD") {
            $version = Test-CmdTool -ToolName $tool
        } else {
            $result = ""
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = (Get-Command $shell.Exe -ErrorAction SilentlyContinue).Source
                # For PS5.1: suppress chpwd warning via env var before activation
                # For PS7: profile loads normally
                if ($shell.Name -eq "PowerShell 5.1") {
                    $psi.Arguments = "-NoProfile -Command `"`$env:MISE_PWSH_CHPWD_WARNING='0'; mise activate pwsh | Out-String | Invoke-Expression; $tool --version 2>&1 | Select-Object -First 1`""
                } else {
                    $psi.Arguments = "-Command `"$tool --version 2>&1 | Select-Object -First 1`""
                }
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true

                $proc = [System.Diagnostics.Process]::Start($psi)
                $stdout = $proc.StandardOutput.ReadToEnd()
                $proc.WaitForExit(15000) | Out-Null
                $version = STRINGOP_FindFirstNonBlankLine -Text $stdout
            } catch {
                $version = ""
            }
        }

        if ($version) {
            Write-Host "OK: $($shell.Name) $tool $version"
            $Results += [PSCustomObject]@{ Shell = $shell.Name; Tool = $tool; Version = $version; Status = "OK" }
        } else {
            Write-Host "FAIL: $($shell.Name) $tool not callable"
            $Results += [PSCustomObject]@{ Shell = $shell.Name; Tool = $tool; Version = "-"; Status = "FAIL" }
            $FailCount++
        }
    }
}

# --- Summary table ---

Write-Host ""
Write-Host "| Shell          | method     | mise doctor | node      | python    | gh        |"
Write-Host "|----------------|------------|-------------|-----------|-----------|-----------|"

foreach ($shell in $shells) {
    $doctor = if ($shell.Name -eq "CMD") { "N/A" }
              elseif ($shell.Name -eq "PowerShell 7") { $ps7Doctor }
              else { $ps5Doctor }
    $nodeR = ($Results | Where-Object { $_.Shell -eq $shell.Name -and $_.Tool -eq 'node' }).Status
    $pyR = ($Results | Where-Object { $_.Shell -eq $shell.Name -and $_.Tool -eq 'python' }).Status
    $ghR = ($Results | Where-Object { $_.Shell -eq $shell.Name -and $_.Tool -eq 'gh' }).Status
    if (-not $nodeR) { $nodeR = "SKIP" }
    if (-not $pyR) { $pyR = "SKIP" }
    if (-not $ghR) { $ghR = "SKIP" }
    Write-Host ("| {0,-14} | {1,-10} | {2,-11} | {3,-9} | {4,-9} | {5,-9} |" -f $shell.Name, $shell.Method, $doctor, $nodeR, $pyR, $ghR)
}

# --- Exit ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount issue(s) found"
    exit 1
} else {
    Write-Host "RESULT: All mise checks passed"
    exit 0
}
