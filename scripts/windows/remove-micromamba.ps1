# remove-micromamba.ps1 - Remove micromamba and all artifacts
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File remove-micromamba.ps1
#
# Actions:
#   0. Stop processes using micromamba files (prevents locked-file failures)
#   1. Remove micromamba binary directory (AppData\Local\micromamba)
#   2. Remove micromamba root prefix (~/micromamba) including all environments
#   3. Clean micromamba entries from PATH registry
#   4. Clean mamba references from CMD AutoRun
#   5. Clean mamba init blocks from PowerShell profiles
#   6. Broadcast WM_SETTINGCHANGE for PATH update
#
# Output: Structured lines prefixed with OK / WARN / SKIP / INFO / FAIL
# Exit code: 0 on success, 1 on failure

$ErrorActionPreference = 'Continue'
$FailCount = 0

$MambaBinDir = "$env:USERPROFILE\AppData\Local\micromamba"
$MambaRootPrefix = "$env:USERPROFILE\micromamba"

# --- Pre-flight: Is micromamba installed? ---

$mambaFound = $false
if (Test-Path "$MambaBinDir\micromamba.exe") { $mambaFound = $true }
if (-not $mambaFound -and (Test-Path $MambaRootPrefix)) { $mambaFound = $true }
if (-not $mambaFound) {
    # Check PATH for micromamba entries
    $pathVal = (Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    if ($pathVal -and $pathVal.Contains('micromamba')) { $mambaFound = $true }
}
if (-not $mambaFound) {
    # Check CMD AutoRun for mamba_hook
    $autoRun = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Command Processor' -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
    if ($autoRun -and $autoRun.Contains('mamba_hook')) { $mambaFound = $true }
}
if (-not $mambaFound) {
    # Check PowerShell profiles for mamba init blocks
    $docsDir = [Environment]::GetFolderPath('MyDocuments')
    $profilesToScan = @(
        (Join-Path $docsDir "WindowsPowerShell\profile.ps1"),
        (Join-Path $docsDir "PowerShell\Microsoft.PowerShell_profile.ps1")
    )
    foreach ($p in $profilesToScan) {
        if (Test-Path $p) {
            $c = Get-Content $p -Raw
            if ($c.Contains('mamba')) { $mambaFound = $true; break }
        }
    }
}

if (-not $mambaFound) {
    Write-Host "SKIP: Micromamba does not appear to be installed"
    Write-Host ""
    Write-Host "RESULT: Nothing to remove"
    exit 0
}

Write-Host "INFO: Micromamba installation detected - starting removal"

# --- Step 0: Stop processes using micromamba files ---

Write-Host ""
Write-Host "--- Step 0: Stop processes using micromamba files ---"

$dirsToCheck = @($MambaBinDir, $MambaRootPrefix) | Where-Object { Test-Path $_ }
if ($dirsToCheck.Count -gt 0) {
    $lockedProcs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $_.Path
        if ($p) {
            foreach ($d in $dirsToCheck) {
                if ($p.StartsWith($d, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
        }
        return $false
    })
    if ($lockedProcs.Count -gt 0) {
        Write-Host "WARN: $($lockedProcs.Count) process(es) using micromamba files:"
        foreach ($proc in $lockedProcs) {
            Write-Host "  PID $($proc.Id): $($proc.ProcessName) ($($proc.Path))"
        }
        Write-Host "INFO: Stopping processes to release file locks"
        foreach ($proc in $lockedProcs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Host "OK: Stopped PID $($proc.Id) ($($proc.ProcessName))"
            } catch {
                Write-Host "WARN: Could not stop PID $($proc.Id) ($($proc.ProcessName)): $_"
            }
        }
        # Wait for handles to release
        Start-Sleep -Seconds 2
    } else {
        Write-Host "OK: No processes using micromamba files"
    }
} else {
    Write-Host "SKIP: No micromamba directories to check"
}

# --- Step 1: Remove micromamba binary directory ---

Write-Host ""
Write-Host "--- Step 1: Remove micromamba binary directory ---"

if ([string]::IsNullOrWhiteSpace($MambaBinDir)) {
    Write-Host "FAIL: MambaBinDir is empty - refusing to delete"
    $FailCount++
} elseif (Test-Path $MambaBinDir) {
    # Verify it looks like a micromamba install
    if (Test-Path "$MambaBinDir\micromamba.exe") {
        try {
            Remove-Item -Recurse -Force $MambaBinDir -ErrorAction Stop
            Write-Host "OK: Removed $MambaBinDir"
        } catch {
            Write-Host "FAIL: Could not remove $MambaBinDir - files may still be locked"
            Write-Host "  $_"
            $FailCount++
        }
    } else {
        Write-Host "WARN: $MambaBinDir exists but does not contain micromamba.exe - skipping"
    }
} else {
    Write-Host "SKIP: $MambaBinDir already removed"
}

# --- Step 2: Remove micromamba root prefix ---

Write-Host ""
Write-Host "--- Step 2: Remove micromamba root prefix ---"

$expectedRootPrefix = "$env:USERPROFILE\micromamba"
if ($MambaRootPrefix -ne $expectedRootPrefix) {
    Write-Host "FAIL: MambaRootPrefix ($MambaRootPrefix) does not match expected path ($expectedRootPrefix)"
    Write-Host "  Refusing to delete - this is a safety check against accidental deletion"
    $FailCount++
} elseif ([string]::IsNullOrWhiteSpace($MambaRootPrefix)) {
    Write-Host "FAIL: MambaRootPrefix is empty - refusing to delete"
    $FailCount++
} elseif (Test-Path $MambaRootPrefix) {
    # Verify it looks like a micromamba root prefix
    $looksLikeMamba = (Test-Path "$MambaRootPrefix\condabin") -or
                      (Test-Path "$MambaRootPrefix\pkgs") -or
                      (Test-Path "$MambaRootPrefix\envs")
    if (-not $looksLikeMamba) {
        Write-Host "FAIL: $MambaRootPrefix exists but does not look like a micromamba root prefix"
        Write-Host "  Expected to find condabin, pkgs, or envs directory"
        Write-Host "  Refusing to delete - inspect the directory manually"
        $FailCount++
    } else {
        # List environments being removed
        $envsDir = "$MambaRootPrefix\envs"
        if (Test-Path $envsDir) {
            $envDirs = @(Get-ChildItem $envsDir -Directory -ErrorAction SilentlyContinue)
            if ($envDirs.Count -gt 0) {
                Write-Host "INFO: Removing $($envDirs.Count) environment(s): $($envDirs.Name -join ', ')"
            }
        }
        try {
            Remove-Item -Recurse -Force $MambaRootPrefix -ErrorAction Stop
            Write-Host "OK: Removed $MambaRootPrefix"
        } catch {
            Write-Host "FAIL: Could not remove $MambaRootPrefix - files may still be locked"
            Write-Host "  $_"
            $FailCount++
        }
    }
} else {
    Write-Host "SKIP: $MambaRootPrefix already removed"
}

# --- Step 3: Clean PATH registry ---

Write-Host ""
Write-Host "--- Step 3: Clean PATH registry ---"
$regKey = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
if ($regKey) {
    $pathValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $parts = $pathValue -split ';' | Where-Object { $_ -ne '' }
    $cleanParts = @()
    $removedCount = 0

    foreach ($entry in $parts) {
        if ($entry.Contains('micromamba')) {
            Write-Host "INFO: Removing PATH entry: $entry"
            $removedCount++
        } else {
            $cleanParts += $entry
        }
    }

    if ($removedCount -gt 0) {
        $newPath = $cleanParts -join ';'
        Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
        Write-Host "OK: Removed $removedCount micromamba PATH entry/entries"
    } else {
        Write-Host "SKIP: No micromamba entries in PATH"
    }
}

# --- Step 4: Clean CMD AutoRun ---

Write-Host ""
Write-Host "--- Step 4: Clean CMD AutoRun ---"
$autoRunKey = 'HKCU:\Software\Microsoft\Command Processor'
try {
    $autoRun = Get-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop | Select-Object -ExpandProperty AutoRun
    if ($autoRun.Contains('mamba_hook')) {
        # If AutoRun ONLY has mamba stuff (no other commands), remove it entirely
        # If it has other commands mixed in, try to remove just the mamba part
        $parts = $autoRun -split '&' | ForEach-Object { $_.Trim() } | Where-Object { -not $_.Contains('mamba_hook') -and $_ -ne '' }
        if ($parts.Count -eq 0) {
            Remove-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop
            Write-Host "OK: Removed CMD AutoRun (was mamba-only)"
        } else {
            $newAutoRun = $parts -join ' & '
            Set-ItemProperty -Path $autoRunKey -Name AutoRun -Value $newAutoRun
            Write-Host "OK: Removed mamba_hook from CMD AutoRun, kept other entries"
        }
    } else {
        Write-Host "SKIP: CMD AutoRun does not reference mamba"
    }
} catch [System.Management.Automation.ItemNotFoundException] {
    Write-Host "SKIP: CMD AutoRun registry key does not exist"
} catch [System.Management.Automation.PSArgumentException] {
    Write-Host "SKIP: CMD AutoRun property not set"
} catch {
    Write-Host "SKIP: CMD AutoRun not found"
}

# --- Step 5: Clean PowerShell profiles ---

Write-Host ""
Write-Host "--- Step 5: Clean mamba from PowerShell profiles ---"
$docsDir2 = [Environment]::GetFolderPath('MyDocuments')
$psProfiles = @(
    (Join-Path $docsDir2 "WindowsPowerShell\profile.ps1"),
    (Join-Path $docsDir2 "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path $docsDir2 "PowerShell\profile.ps1"),
    (Join-Path $docsDir2 "PowerShell\Microsoft.PowerShell_profile.ps1")
)

foreach ($profilePath in $psProfiles) {
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content.Contains('mamba')) {
            # Remove mamba init region (#region mamba initialize ... #endregion)
            $cleaned = $content -replace '(?s)#region mamba initialize.*?#endregion\r?\n?', ''
            # Also remove any standalone mamba hook lines
            $cleaned = $cleaned -replace '(?m)^.*mamba[-_]hook.*$\r?\n?', ''
            # Remove MAMBA_ROOT_PREFIX and MAMBA_EXE lines that may be outside the region block
            $cleaned = $cleaned -replace '(?m)^.*MAMBA_ROOT_PREFIX.*$\r?\n?', ''
            $cleaned = $cleaned -replace '(?m)^.*MAMBA_EXE.*$\r?\n?', ''
            # Trim leading/trailing whitespace but keep a trailing newline
            $cleaned = $cleaned.Trim()
            if ($cleaned -eq '') {
                # Profile is now empty - remove the file
                Remove-Item $profilePath -Force
                Write-Host "OK: Removed empty profile $profilePath"
            } else {
                Set-Content -Path $profilePath -Value ($cleaned + "`n") -NoNewline -Encoding UTF8
                Write-Host "OK: Cleaned mamba references from $profilePath"
            }
        } else {
            Write-Host "SKIP: $profilePath has no mamba references"
        }
    }
}

# --- Step 6: Broadcast WM_SETTINGCHANGE ---

Write-Host ""
Write-Host "--- Step 6: Broadcast environment change ---"
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $HWND_BROADCAST = [IntPtr]0xFFFF
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', $SMTO_ABORTIFHUNG, 5000, [ref]$result) | Out-Null
    Write-Host "OK: Broadcast WM_SETTINGCHANGE"
} catch {
    Write-Host "WARN: Could not broadcast WM_SETTINGCHANGE - new terminals may not pick up PATH changes"
}

# --- Verification ---

Write-Host ""
Write-Host "--- Verification ---"
$mambaStillExists = Get-Command micromamba -ErrorAction SilentlyContinue
if ($mambaStillExists) {
    Write-Host "WARN: micromamba command still resolves to $($mambaStillExists.Source) - may need a new terminal"
} else {
    Write-Host "OK: micromamba command no longer available"
}

if (Test-Path $MambaBinDir) {
    Write-Host "FAIL: $MambaBinDir still exists - processes may still hold locks"
    $FailCount++
} else {
    Write-Host "OK: $MambaBinDir removed"
}

if (Test-Path $MambaRootPrefix) {
    Write-Host "FAIL: $MambaRootPrefix still exists - processes may still hold locks"
    $FailCount++
} else {
    Write-Host "OK: $MambaRootPrefix removed"
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Removal completed with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: Micromamba removal complete"
    Write-Host "INFO: Close and reopen all terminals for changes to take effect"
    exit 0
}
