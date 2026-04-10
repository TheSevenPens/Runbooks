# fix-path-registry.ps1 - Fix PATH registry type and ensure micromamba is on PATH
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File fix-path-registry.ps1
#
# Actions:
#   1. Fix HKCU\Environment\Path type from REG_SZ to REG_EXPAND_SZ if needed
#   2. Remove stale miniconda3 entries
#   2b. Repair entries with missing semicolons (e.g. external installers that
#       concatenate PATH entries without a separator)
#   3. Ensure micromamba's AppData\Local\micromamba directory is on PATH
#
# Output: Structured lines prefixed with OK / WARN / INFO / SKIP
# Exit code: 0 on success, 1 on failure

$ErrorActionPreference = 'Stop'
$Changed = $false

# --- Read current state ---

$regKey = Get-Item 'HKCU:\Environment' -ErrorAction Stop
try {
    $currentType = $regKey.GetValueKind('Path')
} catch {
    # Path value doesn't exist yet -- create it as REG_EXPAND_SZ with empty value
    Write-Host "WARN: HKCU\Environment\Path does not exist -- creating it"
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value '' -Type ExpandString
    $currentType = 'ExpandString'
}
$currentValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')

# --- Step 1: Fix registry type ---

if ($currentType -ne 'ExpandString') {
    Write-Host "WARN: PATH registry type is $currentType - fixing to REG_EXPAND_SZ"
    $Changed = $true
} else {
    Write-Host "OK: PATH registry type is REG_EXPAND_SZ"
}

# --- Step 2: Remove stale miniconda3 entries ---

$parts = $currentValue -split ';' | Where-Object { $_ -ne '' }
$cleanParts = @()
$removedCount = 0

foreach ($entry in $parts) {
    if ($entry.Contains('miniconda3')) {
        Write-Host "INFO: Removing miniconda3 entry: $entry"
        $removedCount++
        $Changed = $true
    } else {
        $cleanParts += $entry
    }
}

if ($removedCount -eq 0) {
    Write-Host "SKIP: No miniconda3 entries found in PATH"
}

# --- Step 2b: Repair entries with missing semicolons ---
# External installers (e.g. micromamba) may concatenate PATH entries without a
# separator, producing entries like "...WindowsAppsC:\Users\...".  Detect drive
# letters (X:\) that appear mid-entry and split them apart.

$repairedParts = @()
foreach ($entry in $cleanParts) {
    # Find positions where a drive-letter pattern (X:\) starts after position 0
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
        $repairedParts += $entry
    } else {
        Write-Host "WARN: Repaired missing semicolon in: $entry"
        $prev = 0
        foreach ($pos in $splitPositions) {
            $part = $entry.Substring($prev, $pos - $prev)
            $repairedParts += $part
            Write-Host "  -> $part"
            $prev = $pos
        }
        $last = $entry.Substring($prev)
        $repairedParts += $last
        Write-Host "  -> $last"
        $Changed = $true
    }
}
$cleanParts = $repairedParts

# --- Step 3: Ensure micromamba directory is on PATH ---

$mmDir = '%USERPROFILE%\AppData\Local\micromamba'
$mmDirExpanded = [Environment]::ExpandEnvironmentVariables($mmDir)

$found = $false
foreach ($entry in $cleanParts) {
    $expanded = [Environment]::ExpandEnvironmentVariables($entry)
    if ($expanded -eq $mmDirExpanded) {
        $found = $true
        break
    }
}

if ($found) {
    Write-Host "OK: micromamba directory already on PATH"
} else {
    Write-Host "INFO: Adding micromamba directory to PATH: $mmDir"
    $cleanParts += $mmDir
    $Changed = $true
}

# --- Write back if changed ---

if ($Changed) {
    $newValue = $cleanParts -join ';'
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newValue -Type ExpandString

    # Verify the write
    $verifyKey = Get-Item 'HKCU:\Environment'
    $verifyType = $verifyKey.GetValueKind('Path')
    if ($verifyType -eq 'ExpandString') {
        Write-Host "OK: PATH registry updated and verified as REG_EXPAND_SZ"
    } else {
        Write-Host "FAIL: PATH registry type is still $verifyType after fix attempt"
        exit 1
    }

    # Broadcast environment change (best-effort)
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinEnv {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
        [UIntPtr]$result = [UIntPtr]::Zero
        [WinEnv]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
        Write-Host "INFO: Environment change broadcast sent"
    } catch {
        Write-Host "WARN: Could not broadcast environment change - open a new terminal for PATH to take effect"
    }
} else {
    Write-Host "SKIP: No changes needed"
}

Write-Host ""
Write-Host "RESULT: PATH registry OK"
exit 0
