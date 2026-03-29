# verify-installed.ps1 - Check Windows dev tool prerequisites
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-installed.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File verify-installed.ps1 -Env node1
#
# Output: Structured lines prefixed with OK / WARN / FAIL / SKIP
# Exit code: 0 if all required tools present, 1 if any FAIL

param(
    [string]$Env = ""
)

$ErrorActionPreference = 'Continue'
$FailCount = 0

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

    $result = winget list --id $WingetId --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $result -match $WingetId) {
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

# --- Optional: Environment packages ---

if ($Env -ne "" -and $mmExe) {
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
        if ($envList -match $Env) {
            $line = $envList | Where-Object { $_ -match $Env } | Select-Object -First 1
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
