# verify-prerequisites.ps1 - Check Windows dev tool prerequisites
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-prerequisites.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-prerequisites.ps1 -Env node1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-prerequisites.ps1 -ToolManager mise
#
# Output: Structured lines prefixed with OK / WARN / FAIL / SKIP
# Exit code: 0 if all required tools present, 1 if any FAIL

param(
    [string]$Env = "",
    [ValidateSet('auto', 'micromamba', 'mise')]
    [string]$ToolManager = "auto"
)

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- Resolve tool manager ---
# Auto-detect: check for mise first (newer), then micromamba (legacy)
if ($ToolManager -eq 'auto') {
    $hasMise = (Get-Command mise -ErrorAction SilentlyContinue) -ne $null
    if (-not $hasMise) {
        $miseCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\mise.exe'),
            (Join-Path $env:LOCALAPPDATA 'mise\bin\mise.exe')
        )
        foreach ($c in $miseCandidates) {
            if (Test-Path $c) { $hasMise = $true; break }
        }
    }
    $hasMamba = (Test-Path "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe") -or
                ((Get-Command micromamba -ErrorAction SilentlyContinue) -ne $null)

    if ($hasMise) { $ToolManager = 'mise' }
    elseif ($hasMamba) { $ToolManager = 'micromamba' }
    else { $ToolManager = 'none' }
}
Write-Host "INFO: Tool manager: $ToolManager"

# --- OneDrive Documents redirection check ---
$docsDir = [Environment]::GetFolderPath('MyDocuments')
$defaultDocsDir = Join-Path $env:USERPROFILE "Documents"
if ($docsDir -ne $defaultDocsDir) {
    Write-Host "WARN: Documents folder is redirected to $docsDir"
    Write-Host "  PowerShell profiles, shell hooks, and other config files live there instead of $defaultDocsDir"
    Write-Host '  Scripts that hardcode $env:USERPROFILE\Documents will look in the wrong place'
}

# --- BOM check on bash files ---
# Removed: Git Bash is no longer a supported shell on Windows.
# The BOM check is still relevant on macOS (see scripts/mac/verify-prerequisites.sh).

# --- Non-ASCII check on .ps1 files ---
# PS5.1 cannot parse multi-byte UTF-8 (em-dash, smart quotes, etc.) in files
# without a BOM.  Since these scripts must work under PS5.1, they must be
# ASCII-only.  Scan all .ps1 files in the scripts directory for offenders.

$scriptRoot = Join-Path $PSScriptRoot ""  # normalize trailing separator
if (Test-Path $scriptRoot) {
    $ps1Files = Get-ChildItem $scriptRoot -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($f in $ps1Files) {
        $raw = [System.IO.File]::ReadAllBytes($f.FullName)
        for ($i = 0; $i -lt $raw.Length; $i++) {
            if ($raw[$i] -gt 127) {
                # Skip BOM at position 0-2 (harmless in .ps1)
                if ($i -le 2 -and $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) {
                    $i = 2  # skip past BOM
                    continue
                }
                # Find approximate line number
                $lineNum = 1
                for ($j = 0; $j -lt $i; $j++) { if ($raw[$j] -eq 10) { $lineNum++ } }
                $hexByte = '0x{0:X2}' -f $raw[$i]
                Write-Host "WARN: $($f.Name) contains non-ASCII byte $hexByte at line $lineNum - PS5.1 may fail to parse"
                break  # one warning per file is enough
            }
        }
    }
}

# --- Resolve winget ---
# winget is an AppX execution alias that may not be on PATH (especially in
# Git Bash or after a PATH refresh from the registry).  Resolve it once up
# front so Test-WingetPackage can call it by full path.

$WingetExe = (Get-Command winget -ErrorAction SilentlyContinue).Source
if (-not $WingetExe) {
    $appxDir = (Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue).InstallLocation
    if ($appxDir) {
        $candidate = Join-Path $appxDir 'winget.exe'
        if (Test-Path $candidate) { $WingetExe = $candidate }
    }
}
if ($WingetExe) {
    Write-Host "INFO: Using winget at $WingetExe"
} else {
    Write-Host "WARN: winget not found - GUI-app checks will be skipped"
}

# --- Helpers ---

function Test-CliTool {
    param(
        [string]$Name,
        [string]$Command,
        [string]$VersionFlag = "--version",
        [bool]$Required = $true
    )

    $exe = Get-Command $Command -ErrorAction SilentlyContinue
    if ($exe) {
        $version = ""
        try {
            $output = & $Command $VersionFlag 2>&1 | Select-Object -First 1
            $version = "$output".Trim()
        } catch {
            $version = "(version unknown)"
        }
        Write-Host "OK: $Name $version ($($exe.Source))"
    } else {
        if ($Required) {
            Write-Host "FAIL: $Name not found"
            $script:FailCount++
        } else {
            Write-Host "SKIP: $Name not installed (optional)"
        }
    }
}

function Test-WingetPackage {
    param(
        [string]$Name,
        [string]$WingetId
    )

    if (-not $script:WingetExe) {
        Write-Host "SKIP: $Name - winget not available"
        return
    }
    $result = & $script:WingetExe list --id $WingetId --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and ($result | Out-String).Contains($WingetId)) {
        Write-Host "OK: $Name (winget: $WingetId)"
    } else {
        Write-Host "FAIL: $Name not found (winget: $WingetId)"
        $script:FailCount++
    }
}

# --- CLI Tools ---

Test-CliTool -Name "git" -Command "git"
Test-CliTool -Name "code" -Command "code"
Test-CliTool -Name "pwsh" -Command "pwsh" -Required $false

# --- Tool manager checks ---

if ($ToolManager -eq 'mise') {
    # --- mise checks ---

    $miseCmd = Get-Command mise -ErrorAction SilentlyContinue
    if (-not $miseCmd) {
        $miseCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\mise.exe'),
            (Join-Path $env:LOCALAPPDATA 'mise\bin\mise.exe')
        )
        foreach ($c in $miseCandidates) {
            if (Test-Path $c) { $miseCmd = Get-Command $c -ErrorAction SilentlyContinue; break }
        }
    }
    if ($miseCmd) {
        $miseVer = & $miseCmd.Source --version 2>$null | Select-Object -First 1
        Write-Host "OK: mise $miseVer ($($miseCmd.Source))"
    } else {
        Write-Host "FAIL: mise not found"
        $FailCount++
    }

    # Check shell profiles for activation
    $docsDir = [Environment]::GetFolderPath('MyDocuments')
    $ps7Prof = Join-Path $docsDir "PowerShell\Microsoft.PowerShell_profile.ps1"
    if ((Test-Path $ps7Prof) -and (Get-Content $ps7Prof -Raw).Contains('mise activate')) {
        Write-Host "OK: PS7 profile contains mise activation"
    } else {
        Write-Host "WARN: PS7 profile missing mise activation - run install-mise.ps1"
    }

    $ps5Prof = Join-Path $docsDir "WindowsPowerShell\profile.ps1"
    if ((Test-Path $ps5Prof) -and (Get-Content $ps5Prof -Raw).Contains('mise activate')) {
        Write-Host "OK: PS5.1 profile contains mise activation"
    } else {
        Write-Host "WARN: PS5.1 profile missing mise activation - run install-mise.ps1"
    }

    # Check shims on PATH
    $regKey2 = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
    if ($regKey2) {
        $pv = $regKey2.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if ($pv.Contains('mise\shims')) {
            Write-Host "OK: mise shims on registry PATH"
        } else {
            Write-Host "WARN: mise shims not on registry PATH - CMD tools may not work"
        }
    }

    # Check global config exists
    $miseConfig = Join-Path $env:USERPROFILE '.config\mise\config.toml'
    if (Test-Path $miseConfig) {
        Write-Host "OK: mise global config exists"
    } else {
        Write-Host "WARN: mise global config not found - run install-mise-tools.ps1"
    }

} elseif ($ToolManager -eq 'micromamba') {
    # --- Micromamba (check canonical path first) ---

    $mmCanonical = "$env:USERPROFILE\AppData\Local\micromamba\micromamba.exe"
    $mmExe = $null

    if (Test-Path $mmCanonical) {
        $mmExe = $mmCanonical
    } else {
        $mmCmd = Get-Command micromamba -ErrorAction SilentlyContinue
        if ($mmCmd) { $mmExe = $mmCmd.Source }
    }

    if ($mmExe) {
        $mmVersion = & $mmExe --version 2>$null | Select-Object -First 1
        Write-Host "OK: micromamba $mmVersion ($mmExe)"
    } else {
        Write-Host "FAIL: micromamba not found"
        $FailCount++
    }

    # --- MAMBA_EXE consistency check ---
    $mambaExeRefs = @{}
    $docsDir = [Environment]::GetFolderPath('MyDocuments')
    $psProfilesToScan = @(
        @{ Name = "PS 5.1 profile"; Path = Join-Path $docsDir "WindowsPowerShell\profile.ps1" },
        @{ Name = "PS 7 profile";   Path = Join-Path $docsDir "PowerShell\Microsoft.PowerShell_profile.ps1" }
    )
    foreach ($entry in $psProfilesToScan) {
        if (Test-Path $entry.Path) {
            $c = Get-Content $entry.Path -Raw
            if ($c -match '\$Env:MAMBA_EXE\s*=\s*"([^"]+)"') {
                $mambaExeRefs[$entry.Name] = $Matches[1]
            }
        }
    }

    $batPath = "$env:USERPROFILE\micromamba\condabin\micromamba.bat"
    if (Test-Path $batPath) {
        $c = Get-Content $batPath -Raw
        if ($c -match 'MAMBA_EXE=(.+)$') {
            $mambaExeRefs[".bat wrapper"] = $Matches[1].Trim().Trim('"')
        }
    }

    if ($mambaExeRefs.Count -gt 0) {
        function ConvertTo-WindowsPath {
            param([string]$Path)
            $p = $Path -replace '/', '\'
            if ($p -match '^\\([a-zA-Z])\\') {
                $p = "$($Matches[1].ToUpper()):\$($p.Substring(3))"
            } elseif ($p -match '^\\mnt\\([a-zA-Z])\\') {
                $p = "$($Matches[1].ToUpper()):\$($p.Substring(6))"
            }
            return $p
        }

        $normalizedRefs = @{}
        foreach ($entry in $mambaExeRefs.GetEnumerator()) {
            $normalizedRefs[$entry.Key] = ConvertTo-WindowsPath $entry.Value
        }

        $uniquePaths = $normalizedRefs.Values | Select-Object -Unique
        $allExist = $true
        $allMatch = ($uniquePaths.Count -le 1)

        foreach ($entry in $normalizedRefs.GetEnumerator()) {
            if (-not (Test-Path $entry.Value)) {
                $origPath = $mambaExeRefs[$entry.Key]
                $normNote = if ($origPath -ne $entry.Value) { " (normalized: $($entry.Value))" } else { "" }
                Write-Host "FAIL: MAMBA_EXE in $($entry.Key) points to non-existent ${origPath}${normNote}"
                $FailCount++
                $allExist = $false
            }
        }

        if (-not $allMatch) {
            Write-Host "WARN: MAMBA_EXE paths differ across shell configs:"
            foreach ($entry in $mambaExeRefs.GetEnumerator()) {
                Write-Host "  $($entry.Key): $($entry.Value)"
            }
            Write-Host "  Run micromamba-shell-init.ps1 to fix"
        } elseif ($allExist) {
            Write-Host "OK: MAMBA_EXE consistent across all shell configs"
        }
    }
} else {
    Write-Host "FAIL: No tool manager found (neither mise nor micromamba)"
    $FailCount++
}

# --- GUI Apps (winget only) ---

Test-WingetPackage -Name "GitHub Desktop" -WingetId "GitHub.GitHubDesktop"
Test-WingetPackage -Name "Google Chrome" -WingetId "Google.Chrome.EXE"
Test-WingetPackage -Name "Windows Terminal" -WingetId "Microsoft.WindowsTerminal"

# --- PATH Registry Check ---

$regKey = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
if ($regKey) {
    $pathType = $regKey.GetValueKind('Path')
    if ($pathType -eq 'ExpandString') {
        Write-Host "OK: PATH registry type is REG_EXPAND_SZ"
    } else {
        Write-Host "WARN: PATH registry type is $pathType (should be REG_EXPAND_SZ) - run fix-path-registry.ps1"
    }
}

# --- Optional: Environment packages (micromamba only) ---

if ($Env -ne "" -and $ToolManager -eq 'micromamba' -and $mmExe) {
    Write-Host ""
    Write-Host "--- Environment: $Env ---"

    $envPath = "$env:USERPROFILE\micromamba\envs\$Env"
    if (Test-Path $envPath) {
        Write-Host "OK: environment '$Env' found at $envPath"

        $tools = @(
            @{ Name = "node"; Exe = "node.exe" },
            @{ Name = "python"; Exe = "python.exe" },
            @{ Name = "gh"; Exe = "Scripts\gh.exe" }
        )

        foreach ($tool in $tools) {
            $toolPath = Join-Path $envPath $tool.Exe
            if (Test-Path $toolPath) {
                $toolVersion = & $toolPath --version 2>$null | Select-Object -First 1
                Write-Host "OK: $($tool.Name) $toolVersion ($toolPath)"
            } else {
                Write-Host "FAIL: $($tool.Name) not found in $Env"
                $FailCount++
            }
        }
    } else {
        # Check if micromamba lists it elsewhere
        $envList = & $mmExe env list 2>$null
        if (($envList | Out-String).Contains($Env)) {
            $line = $envList | Where-Object { "$_".Contains($Env) } | Select-Object -First 1
            Write-Host "OK: environment '$Env' found (not at default path)"
        } else {
            Write-Host "FAIL: environment '$Env' not found"
            $FailCount++
        }
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount issue(s) found"
    exit 1
} else {
    Write-Host "RESULT: All checks passed"
    exit 0
}
