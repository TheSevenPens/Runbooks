# remove-conda.ps1 - Remove Miniconda/Anaconda and all artifacts
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File remove-conda.ps1
#
# Actions:
#   1. Back up environments to $env:USERPROFILE\envs-backup
#   2. Uninstall via winget
#   3. Remove leftover miniconda3 directory
#   4. Clean miniconda3 entries from PATH registry
#   5. Clean conda references from CMD AutoRun
#   6. Remove .condarc
#   7. Clean conda init block from .bash_profile
#   8. Clean conda init block from PowerShell profiles
#   9. Clean stale conda entries from .conda\environments.txt
#
# Output: Structured lines prefixed with OK / WARN / SKIP / INFO / FAIL
# Exit code: 0 on success, 1 on failure

$ErrorActionPreference = 'Continue'
$FailCount = 0

$MinicondaDir = "$env:USERPROFILE\miniconda3"
$BackupDir = "$env:USERPROFILE\envs-backup"

# --- Pre-flight: Is conda installed? ---

$condaFound = $false
if (Test-Path "$MinicondaDir\Scripts\conda.exe") { $condaFound = $true }
if (-not $condaFound) {
    $wingetResult = winget list --id Anaconda.Miniconda3 --exact 2>$null
    if ($LASTEXITCODE -eq 0 -and $wingetResult -match 'Miniconda') { $condaFound = $true }
}
if (-not $condaFound -and (Test-Path $MinicondaDir)) { $condaFound = $true }

if (-not $condaFound) {
    Write-Host "SKIP: Conda does not appear to be installed"
    Write-Host ""
    Write-Host "RESULT: Nothing to remove"
    exit 0
}

Write-Host "INFO: Conda installation detected - starting removal"

# --- Step 1: Back up environments ---

Write-Host ""
Write-Host "--- Step 1: Back up environments ---"
$envsDir = "$MinicondaDir\envs"

if (Test-Path $BackupDir) {
    Write-Host "SKIP: $BackupDir already exists - not overwriting previous backup"
} elseif (Test-Path $envsDir) {
    $envCount = (Get-ChildItem $envsDir -Directory).Count
    if ($envCount -gt 0) {
        try {
            Copy-Item -Recurse $envsDir $BackupDir -ErrorAction Stop
            Write-Host "OK: Backed up $envCount environment(s) to $BackupDir"
        } catch {
            Write-Host "WARN: Backup failed - $($_.Exception.Message)"
            Write-Host "  Environments are still in $envsDir"
        }
    } else {
        Write-Host "SKIP: No environments to back up"
    }
} else {
    Write-Host "SKIP: No envs directory found at $envsDir"
}

# --- Step 2: Uninstall via winget ---

Write-Host ""
Write-Host "--- Step 2: Uninstall via winget ---"
$wingetCheck = winget list --id Anaconda.Miniconda3 --exact 2>$null
if ($LASTEXITCODE -eq 0 -and $wingetCheck -match 'Miniconda') {
    $output = winget uninstall --id Anaconda.Miniconda3 --silent 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: Miniconda3 uninstalled via winget"
    } else {
        Write-Host "WARN: winget uninstall returned non-zero - $output"
    }
} else {
    Write-Host "SKIP: Miniconda3 not found in winget"
}

# --- Step 3: Remove leftover directory ---

Write-Host ""
Write-Host "--- Step 3: Remove miniconda3 directory ---"
if (Test-Path $MinicondaDir) {
    try {
        Remove-Item -Recurse -Force $MinicondaDir -ErrorAction Stop
        Write-Host "OK: Removed $MinicondaDir"
    } catch {
        Write-Host "WARN: Could not fully remove $MinicondaDir - files may be locked"
        Write-Host "  Close all terminals and retry, or delete manually"
    }
} else {
    Write-Host "SKIP: $MinicondaDir already removed"
}

# --- Step 4: Clean PATH registry ---

Write-Host ""
Write-Host "--- Step 4: Clean PATH registry ---"
$regKey = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
if ($regKey) {
    $pathValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $parts = $pathValue -split ';' | Where-Object { $_ -ne '' }
    $cleanParts = @()
    $removedCount = 0

    foreach ($entry in $parts) {
        if ($entry -match 'miniconda3') {
            Write-Host "INFO: Removing PATH entry: $entry"
            $removedCount++
        } else {
            $cleanParts += $entry
        }
    }

    if ($removedCount -gt 0) {
        $newPath = $cleanParts -join ';'
        Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
        Write-Host "OK: Removed $removedCount miniconda3 PATH entry/entries"
    } else {
        Write-Host "SKIP: No miniconda3 entries in PATH"
    }
}

# --- Step 5: Clean CMD AutoRun ---

Write-Host ""
Write-Host "--- Step 5: Clean CMD AutoRun ---"
$autoRunKey = 'HKCU:\Software\Microsoft\Command Processor'
try {
    $autoRun = Get-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop | Select-Object -ExpandProperty AutoRun
    if ($autoRun -match 'conda_hook') {
        # If AutoRun ONLY has conda stuff (no other commands), remove it entirely
        # If it has other commands mixed in, try to remove just the conda part
        $parts = $autoRun -split '&' | ForEach-Object { $_.Trim() } | Where-Object { $_ -notmatch 'conda_hook' -and $_ -ne '' }
        if ($parts.Count -eq 0) {
            Remove-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction Stop
            Write-Host "OK: Removed CMD AutoRun (was conda-only)"
        } else {
            $newAutoRun = $parts -join ' & '
            Set-ItemProperty -Path $autoRunKey -Name AutoRun -Value $newAutoRun
            Write-Host "OK: Removed conda_hook from CMD AutoRun, kept other entries"
        }
    } else {
        Write-Host "SKIP: CMD AutoRun does not reference conda"
    }
} catch [System.Management.Automation.ItemNotFoundException] {
    Write-Host "SKIP: CMD AutoRun registry key does not exist"
} catch [System.Management.Automation.PSArgumentException] {
    Write-Host "SKIP: CMD AutoRun property not set"
} catch {
    Write-Host "SKIP: CMD AutoRun not found"
}

# --- Step 6: Remove .condarc ---

Write-Host ""
Write-Host "--- Step 6: Remove .condarc ---"
$condarc = "$env:USERPROFILE\.condarc"
if (Test-Path $condarc) {
    Remove-Item $condarc -Force
    Write-Host "OK: Removed $condarc"
} else {
    Write-Host "SKIP: .condarc not found"
}

# --- Step 7: Clean .bash_profile ---

Write-Host ""
Write-Host "--- Step 7: Clean conda from .bash_profile ---"
$bashProfile = "$env:USERPROFILE\.bash_profile"
if (Test-Path $bashProfile) {
    $content = Get-Content $bashProfile -Raw
    if ($content -match '# >>> conda initialize >>>') {
        $cleaned = $content -replace '(?s)# >>> conda initialize >>>.*?# <<< conda initialize <<<\r?\n?', ''
        Set-Content -Path $bashProfile -Value $cleaned -NoNewline
        Write-Host "OK: Removed conda init block from .bash_profile"
    } else {
        Write-Host "SKIP: .bash_profile has no conda init block"
    }
} else {
    Write-Host "SKIP: .bash_profile not found"
}

# --- Step 8: Clean PowerShell profiles ---

Write-Host ""
Write-Host "--- Step 8: Clean conda from PowerShell profiles ---"
$psProfiles = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1",
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)

foreach ($profilePath in $psProfiles) {
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -match '#region conda initialize|conda') {
            # Remove conda init region if it uses #region/#endregion
            $cleaned = $content -replace '(?s)#region conda initialize.*?#endregion\r?\n?', ''
            # Also remove any standalone conda hook lines
            $cleaned = $cleaned -replace '(?m)^.*conda[-_]hook.*$\r?\n?', ''
            Set-Content -Path $profilePath -Value $cleaned -NoNewline
            Write-Host "OK: Cleaned conda references from $profilePath"
        } else {
            Write-Host "SKIP: $profilePath has no conda references"
        }
    }
}

# --- Step 9: Clean stale entries from environments.txt ---

Write-Host ""
Write-Host "--- Step 9: Clean stale conda entries from environments.txt ---"
$envsTxt = "$env:USERPROFILE\.conda\environments.txt"
if (Test-Path $envsTxt) {
    $lines = Get-Content $envsTxt
    $cleanLines = $lines | Where-Object { $_ -notmatch 'miniconda|anaconda' }
    $removedCount = $lines.Count - $cleanLines.Count
    if ($removedCount -gt 0) {
        Set-Content -Path $envsTxt -Value $cleanLines
        Write-Host "OK: Removed $removedCount stale conda entry/entries from $envsTxt"
    } else {
        Write-Host "SKIP: No conda entries in $envsTxt"
    }
} else {
    Write-Host "SKIP: $envsTxt not found"
}

# --- Step 10: Verify ---

Write-Host ""
Write-Host "--- Verification ---"
$condaStillExists = Get-Command conda -ErrorAction SilentlyContinue
if ($condaStillExists) {
    Write-Host "WARN: conda command still resolves to $($condaStillExists.Source) - may need a new terminal"
} else {
    Write-Host "OK: conda command no longer available"
}

if (Test-Path $MinicondaDir) {
    Write-Host "WARN: $MinicondaDir still exists - may have locked files"
} else {
    Write-Host "OK: $MinicondaDir removed"
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Removal completed with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: Conda removal complete"
    exit 0
}
