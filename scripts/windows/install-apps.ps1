# install-apps.ps1 - Install Windows dev tools via winget (idempotent)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-apps.ps1
#
# Actions:
#   For each app: check if already installed, install if missing, verify afterward.
#
# Apps installed:
#   - Git for Windows (Git.Git)
#   - GitHub Desktop (GitHub.GitHubDesktop)
#   - Visual Studio Code (Microsoft.VisualStudioCode)
#   - Google Chrome (Google.Chrome)
#   - Windows Terminal (Microsoft.WindowsTerminal)
#   - PowerShell 7 (Microsoft.PowerShell)
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

$ErrorActionPreference = 'Continue'
$FailCount = 0

# --- App definitions ---
# Each entry: WingetId, DisplayName, optional VerifyCommand and VerifyFlag

$Apps = @(
    @{ Id = "Git.Git";                    Name = "Git for Windows";   Verify = "git";  VerifyFlag = "--version" },
    @{ Id = "GitHub.GitHubDesktop";       Name = "GitHub Desktop";    Verify = $null },
    @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code"; Verify = "code"; VerifyFlag = "--version" },
    @{ Id = "Google.Chrome.EXE";          Name = "Google Chrome";     Verify = $null },
    @{ Id = "Microsoft.WindowsTerminal";  Name = "Windows Terminal";  Verify = $null },
    @{ Id = "Microsoft.PowerShell";       Name = "PowerShell 7";     Verify = "pwsh";  VerifyFlag = "--version"; VerifyPaths = @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe") }
)

# --- Helpers ---

function Test-WingetInstalled {
    param([string]$WingetId)
    $result = winget list --id $WingetId --exact --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0 -and $result -match $WingetId)
}

# --- Main loop ---

foreach ($app in $Apps) {
    $id   = $app.Id
    $name = $app.Name

    Write-Host ""
    Write-Host "--- $name ($id) ---"

    # Check if already installed
    $alreadyInstalled = $false

    # CLI-verifiable apps: check command first (faster than winget list)
    if ($app.Verify) {
        $exe = Get-Command $app.Verify -ErrorAction SilentlyContinue
        if (-not $exe -and $app.VerifyPaths) {
            foreach ($vp in $app.VerifyPaths) {
                if (Test-Path $vp) { $exe = Get-Command $vp -ErrorAction SilentlyContinue; break }
            }
        }
        if ($exe) {
            $verifyCmd = $exe.Source
            $version = ""
            try {
                $output = & $verifyCmd $app.VerifyFlag 2>&1 | Select-Object -First 1
                $version = "$output".Trim()
            } catch {
                $version = "(version check failed: $_)"
            }
            Write-Host "SKIP: $name already installed - $version"
            $alreadyInstalled = $true
        }
    }

    # Fallback: check winget
    if (-not $alreadyInstalled) {
        if (Test-WingetInstalled $id) {
            Write-Host "SKIP: $name already installed (winget)"
            $alreadyInstalled = $true
        }
    }

    if ($alreadyInstalled) { continue }

    # Install
    Write-Host "INFO: Installing $name..."
    $output = winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: $name installed"
    } else {
        Write-Host "FAIL: $name install failed (exit code $LASTEXITCODE)"
        Write-Host "  $output"
        $FailCount++
        continue
    }

    # Verify (CLI tools only)
    if ($app.Verify) {
        # Refresh PATH in this session so newly installed commands are found
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path    = "$machinePath;$userPath"

        $exe = Get-Command $app.Verify -ErrorAction SilentlyContinue
        if (-not $exe -and $app.VerifyPaths) {
            foreach ($vp in $app.VerifyPaths) {
                if (Test-Path $vp) { $exe = Get-Command $vp -ErrorAction SilentlyContinue; break }
            }
        }
        if ($exe) {
            $verifyCmd = $exe.Source
            $version = ""
            try {
                $output = & $verifyCmd $app.VerifyFlag 2>&1 | Select-Object -First 1
                $version = "$output".Trim()
            } catch {
                $version = "(version check failed: $_)"
            }
            Write-Host "OK: $name verified - $version"
        } else {
            Write-Host "WARN: $name installed but '$($app.Verify)' not found on PATH - reopen terminal to pick it up"
        }
    }
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: $FailCount install(s) failed"
    exit 1
} else {
    Write-Host "RESULT: All apps installed"
    Write-Host "INFO: Reopen your terminal for PATH changes to take effect"
    exit 0
}
