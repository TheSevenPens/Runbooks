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
# Only accept the real .exe, never a .bat wrapper (the wrapper delegates to
# MAMBA_EXE which may point to a stale location).

$mmExe = $null
$candidates = @(
    "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe"
)

# Also check PATH, but skip .bat wrappers
$mmCmd = Get-Command micromamba -ErrorAction SilentlyContinue
if ($mmCmd -and $mmCmd.Source -match '\.exe$') {
    $candidates += $mmCmd.Source
}

foreach ($path in $candidates) {
    if ((Test-Path $path) -and $path -match '\.exe$') {
        $mmExe = $path
        break
    }
}

if (-not $mmExe) {
    # Provide a clear message if only .bat was found
    if ($mmCmd -and $mmCmd.Source -match '\.bat$') {
        Write-Host "FAIL: Only found .bat wrapper at $($mmCmd.Source) -- the actual micromamba.exe is missing"
        Write-Host "  The .bat wrapper delegates to MAMBA_EXE which may be stale."
        Write-Host "  Reinstall micromamba: Invoke-Expression ((Invoke-WebRequest -Uri https://micro.mamba.pm/install.ps1 -UseBasicParsing).Content)"
    } else {
        Write-Host "FAIL: micromamba binary not found"
        Write-Host "  Checked: $($candidates -join ', ')"
    }
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

# --- PowerShell 7 profile ---
# micromamba shell init -s powershell only writes to the 5.1 profile path.
# If pwsh 7 is installed, copy the init block to its profile too.
# IMPORTANT: Always overwrite the PS7 block to ensure MAMBA_EXE is current.

Write-Host ""
Write-Host "--- PowerShell 7 profile ---"
$pwshExe = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshExe -and (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe")) {
    $pwshExe = Get-Item "$env:ProgramFiles\PowerShell\7\pwsh.exe"
}
if ($pwshExe) {
    # Use the actual Documents folder (respects OneDrive redirection)
    $docsDir    = [Environment]::GetFolderPath('MyDocuments')
    $ps5Profile = Join-Path $docsDir "WindowsPowerShell\profile.ps1"
    $ps7Profile = Join-Path $docsDir "PowerShell\Microsoft.PowerShell_profile.ps1"
    $ps7Dir     = Join-Path $docsDir "PowerShell"

    # Extract the mamba init block from the 5.1 profile (freshly written by shell init above)
    $initBlock = $null
    if (Test-Path $ps5Profile) {
        $content = Get-Content $ps5Profile -Raw
        if ($content -match '(?s)(#region mamba initialize.*?#endregion)') {
            $initBlock = $Matches[1]
        }
    }

    if ($initBlock) {
        if (-not (Test-Path $ps7Dir)) {
            New-Item -ItemType Directory -Path $ps7Dir -Force | Out-Null
        }

        # Always replace the mamba block in PS7 profile to keep MAMBA_EXE in sync
        if (Test-Path $ps7Profile) {
            $ps7Content = Get-Content $ps7Profile -Raw
            if ($ps7Content -match '(?s)#region mamba initialize.*?#endregion') {
                # Replace existing block
                $ps7Content = $ps7Content -replace '(?s)#region mamba initialize.*?#endregion', $initBlock
                Set-Content -Path $ps7Profile -Value $ps7Content -NoNewline -Encoding UTF8
                Write-Host "OK: Updated micromamba init block in $ps7Profile"
            } else {
                # No existing block -- append
                Add-Content -Path $ps7Profile -Value "`n$initBlock`n" -Encoding UTF8
                Write-Host "OK: Added micromamba init block to $ps7Profile"
            }
        } else {
            Set-Content -Path $ps7Profile -Value "$initBlock`n" -Encoding UTF8
            Write-Host "OK: Created $ps7Profile with micromamba init block"
        }
    } else {
        Write-Host "WARN: Could not find mamba init block in $ps5Profile to copy"
    }
} else {
    Write-Host "SKIP: pwsh not installed - no PowerShell 7 profile to configure"
}

# --- Verify MAMBA_EXE in all profiles ---
# Don't just check for presence -- validate that MAMBA_EXE points to the binary we used.

Write-Host ""
Write-Host "--- Verifying MAMBA_EXE paths in profiles ---"
$docsDir2 = [Environment]::GetFolderPath('MyDocuments')
$psProfiles = @(
    (Join-Path $docsDir2 "WindowsPowerShell\profile.ps1"),
    (Join-Path $docsDir2 "PowerShell\Microsoft.PowerShell_profile.ps1")
)

foreach ($profilePath in $psProfiles) {
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -match '\$Env:MAMBA_EXE\s*=\s*"([^"]+)"') {
            $profileMambaExe = $Matches[1]
            if ($profileMambaExe -eq $mmExe) {
                Write-Host "OK: $profilePath MAMBA_EXE matches binary ($mmExe)"
            } elseif (Test-Path $profileMambaExe) {
                Write-Host "WARN: $profilePath MAMBA_EXE is $profileMambaExe (differs from $mmExe but exists)"
            } else {
                Write-Host "FAIL: $profilePath MAMBA_EXE points to non-existent $profileMambaExe"
                # Auto-fix: replace with the known-good path.
                # Use .Replace() instead of -replace to avoid regex special chars in both
                # the old path (backslashes) and new path (potential $ in usernames).
                $content = $content.Replace($profileMambaExe, $mmExe)
                Set-Content -Path $profilePath -Value $content -NoNewline -Encoding UTF8
                Write-Host "  FIXED: Updated to $mmExe"
                $FailCount++
            }
        } elseif ($content -match 'MAMBA_EXE|micromamba|mamba_hook') {
            Write-Host "OK: $profilePath contains micromamba hooks"
        } else {
            Write-Host "WARN: $profilePath exists but has no micromamba hooks"
        }
    }
}

# Verify .bash_profile MAMBA_EXE too
$bashProfile = "$env:USERPROFILE\.bash_profile"
if (Test-Path $bashProfile) {
    $bashContent = Get-Content $bashProfile -Raw
    if ($bashContent -match 'export MAMBA_EXE="([^"]+)"') {
        $bashMambaExe = $Matches[1]
        # Convert bash path to Windows path for comparison
        $bashMambaExeWin = $bashMambaExe -replace '/', '\'
        if ($bashMambaExeWin -match '^\\([a-zA-Z])\\') {
            $bashMambaExeWin = "$($Matches[1]):\$($bashMambaExeWin.Substring(3))"
        }
        if (Test-Path $bashMambaExeWin) {
            Write-Host "OK: .bash_profile MAMBA_EXE points to existing binary"
        } else {
            Write-Host "FAIL: .bash_profile MAMBA_EXE points to non-existent $bashMambaExe"
            $FailCount++
        }
    }
}

# Verify .bat wrapper MAMBA_EXE
$batWrapper = "$RootPrefix\condabin\micromamba.bat"
if (Test-Path $batWrapper) {
    $batContent = Get-Content $batWrapper -Raw
    if ($batContent -match 'MAMBA_EXE=(.+)$') {
        $batMambaExe = $Matches[1].Trim().Trim('"')
        if ($batMambaExe -eq $mmExe) {
            Write-Host "OK: .bat wrapper MAMBA_EXE matches binary ($mmExe)"
        } elseif (Test-Path $batMambaExe) {
            Write-Host "WARN: .bat wrapper MAMBA_EXE is $batMambaExe (differs from $mmExe but exists)"
        } else {
            Write-Host "FAIL: .bat wrapper MAMBA_EXE points to non-existent $batMambaExe"
            $FailCount++
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
