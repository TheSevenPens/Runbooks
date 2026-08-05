# install-mise.ps1 - Install mise and configure shell activation (idempotent)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-mise.ps1
#
# Actions:
#   1. Install mise via winget (if not already installed)
#   2. Add activation line to PowerShell 7 profile
#   3. Add activation line to PowerShell 5.1 profile
#   4. Add shims directory to user PATH for CMD
#   5. Broadcast WM_SETTINGCHANGE
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

. (Join-Path $PSScriptRoot '..\shared\mise-helpers.ps1')

$ErrorActionPreference = 'Continue'
$FailCount = 0

$MiseActivationLine = 'mise activate pwsh | Out-String | Invoke-Expression'

# --- Resolve winget ---

$WingetExe = (Get-Command winget -ErrorAction SilentlyContinue).Source
if (-not $WingetExe) {
    $appxDir = (Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue).InstallLocation
    if ($appxDir) {
        $candidate = Join-Path $appxDir 'winget.exe'
        if (Test-Path $candidate) { $WingetExe = $candidate }
    }
}

# --- Step 1: Install mise ---

Write-Host "--- Step 1: Install mise ---"

$miseExePath = MISE_ResolveExe

if ($miseExePath) {
    $version = & $miseExePath --version 2>$null | Select-Object -First 1
    Write-Host "SKIP: mise already installed ($version)"
} else {
    if (-not $WingetExe) {
        Write-Host "FAIL: winget not available - cannot install mise"
        $FailCount++
    } else {
        Write-Host "INFO: Installing mise via winget"
        & $WingetExe install jdx.mise --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAIL: winget install jdx.mise failed (exit code $LASTEXITCODE)"
            $FailCount++
        } else {
            # Refresh PATH for this session
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path', 'User')
            $miseExePath = MISE_ResolveExe
            if ($miseExePath) {
                $version = & $miseExePath --version 2>$null | Select-Object -First 1
                Write-Host "OK: mise installed ($version) at $miseExePath"
            } else {
                Write-Host "FAIL: mise installed but not found on PATH"
                $FailCount++
            }
        }
    }
}

# --- Step 2: PowerShell 7 profile ---

Write-Host ""
Write-Host "--- Step 2: PowerShell 7 profile ---"

$docsDir = [Environment]::GetFolderPath('MyDocuments')
$ps7Dir = Join-Path $docsDir "PowerShell"
$ps7Profile = Join-Path $ps7Dir "Microsoft.PowerShell_profile.ps1"

if (Test-Path $ps7Profile) {
    $content = Get-Content $ps7Profile -Raw
    if ($content.Contains('mise activate')) {
        Write-Host "SKIP: PS7 profile already contains mise activation"
    } else {
        Add-Content -Path $ps7Profile -Value "`n$MiseActivationLine"
        Write-Host "OK: Appended mise activation to PS7 profile"
    }
} else {
    if (-not (Test-Path $ps7Dir)) { New-Item -ItemType Directory -Path $ps7Dir -Force | Out-Null }
    Set-Content -Path $ps7Profile -Value $MiseActivationLine
    Write-Host "OK: Created PS7 profile with mise activation"
}

# --- Step 3: PowerShell 5.1 profile ---

Write-Host ""
Write-Host "--- Step 3: PowerShell 5.1 profile ---"

$ps5Dir = Join-Path $docsDir "WindowsPowerShell"
$ps5Profile = Join-Path $ps5Dir "profile.ps1"

if (Test-Path $ps5Profile) {
    $content = Get-Content $ps5Profile -Raw
    if ($content.Contains('mise activate')) {
        Write-Host "SKIP: PS5.1 profile already contains mise activation"
    } else {
        Add-Content -Path $ps5Profile -Value "`n$MiseActivationLine"
        Write-Host "OK: Appended mise activation to PS5.1 profile"
    }
} else {
    if (-not (Test-Path $ps5Dir)) { New-Item -ItemType Directory -Path $ps5Dir -Force | Out-Null }
    Set-Content -Path $ps5Profile -Value $MiseActivationLine
    Write-Host "OK: Created PS5.1 profile with mise activation"
}

# --- Step 4: CMD shims on PATH ---

Write-Host ""
Write-Host "--- Step 4: CMD shims on PATH ---"

$regKey = Get-Item 'HKCU:\Environment' -ErrorAction SilentlyContinue
if ($regKey) {
    $pathValue = $regKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $shimsEntry = '%LOCALAPPDATA%\mise\shims'
    if ($pathValue.Contains('mise\shims')) {
        Write-Host "SKIP: Shims directory already on PATH"
    } else {
        $newPath = $shimsEntry + ';' + $pathValue
        Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type ExpandString
        Write-Host "OK: Added shims directory to user PATH"
    }
} else {
    Write-Host "FAIL: Could not read HKCU:\Environment registry key"
    $FailCount++
}

# --- Step 5: Broadcast WM_SETTINGCHANGE ---

Write-Host ""
Write-Host "--- Step 5: Broadcast environment change ---"
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$result) | Out-Null
    Write-Host "OK: Broadcast WM_SETTINGCHANGE"
} catch {
    Write-Host "WARN: Could not broadcast WM_SETTINGCHANGE - new terminals may not pick up PATH changes"
}

# --- Summary ---

Write-Host ""
if ($FailCount -gt 0) {
    Write-Host "RESULT: Completed with $FailCount issue(s)"
    exit 1
} else {
    Write-Host "RESULT: mise installed and shell activation configured"
    Write-Host "INFO: Close and reopen your terminal for activation to take effect"
    exit 0
}
