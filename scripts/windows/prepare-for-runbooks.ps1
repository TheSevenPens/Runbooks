#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Claude Code CLI and ensures it is on the user PATH.
.DESCRIPTION
    This script prepares a Windows machine to run the runbooks in this repo.
    It installs Claude Code via the official installer and adds its directory
    to the user PATH if not already present. Designed to be idempotent.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Ensure execution policy allows local scripts ---
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'Undefined') {
    Write-Host "Setting execution policy to RemoteSigned for CurrentUser (was: $currentPolicy)..." -ForegroundColor Cyan
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host "Execution policy set to RemoteSigned." -ForegroundColor Green
} else {
    Write-Host "Execution policy is already '$currentPolicy' - OK." -ForegroundColor Green
}

$ClaudeBin = Join-Path $env:USERPROFILE '.local\bin'
$ClaudeExe = Join-Path $ClaudeBin 'claude.exe'

# --- Install Claude Code ---
if (Test-Path $ClaudeExe) {
    Write-Host "Claude Code already installed at $ClaudeExe" -ForegroundColor Green
} else {
    Write-Host "Installing Claude Code..." -ForegroundColor Cyan
    try {
        $installScript = Invoke-RestMethod https://claude.ai/install.ps1
        if ([string]::IsNullOrWhiteSpace($installScript)) {
            Write-Error "Downloaded install script is empty -- network issue or URL may have changed"
            exit 1
        }
        # Basic sanity check: the script should contain PowerShell-like content
        if ($installScript -notmatch 'param|function|Install|claude' ) {
            Write-Error "Downloaded content does not look like a PowerShell install script -- URL may have changed"
            exit 1
        }
        $installScript | Invoke-Expression
    } catch {
        Write-Error "Failed to install Claude Code: $_"
        exit 1
    }

    if (-not (Test-Path $ClaudeExe)) {
        Write-Error "Installation appeared to succeed but $ClaudeExe was not found."
        exit 1
    }
    Write-Host "Claude Code installed successfully." -ForegroundColor Green
}

# --- Ensure Claude bin directory is on the user PATH ---
$currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $currentUserPath) {
    $currentUserPath = ''
}

# Split, trim, and filter empties for reliable comparison
$pathEntries = $currentUserPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

$alreadyOnPath = $pathEntries | Where-Object { $_ -ieq $ClaudeBin }

if ($alreadyOnPath) {
    Write-Host "$ClaudeBin is already on the user PATH." -ForegroundColor Green
} else {
    Write-Host "Adding $ClaudeBin to user PATH..." -ForegroundColor Cyan

    # Rebuild a clean path string (deduped, no trailing semicolons)
    $pathEntries += $ClaudeBin
    $newPath = ($pathEntries -join ';')

    # Verify the registry key type is REG_EXPAND_SZ (not REG_SZ)
    $regKey = 'HKCU:\Environment'
    $regProp = Get-ItemProperty -Path $regKey -Name 'Path' -ErrorAction SilentlyContinue

    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true).SetValue(
        'Path', $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString
    )

    # Broadcast WM_SETTINGCHANGE so new shells pick up the change
    if (-not ('Win32.NativeMethods' -as [type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero,
        'Environment', 2, 5000, [ref]$result
    ) | Out-Null

    Write-Host "PATH updated. New terminals will see the change." -ForegroundColor Green
}

# --- Verify claude is callable ---
$env:Path = "$ClaudeBin;$env:Path"
try {
    $version = & $ClaudeExe --version 2>&1
    Write-Host "Claude Code is ready: $version" -ForegroundColor Green
} catch {
    Write-Warning "Claude Code is installed but could not be executed. You may need to open a new terminal."
}

Write-Host "`nDone. Open a new terminal and run a runbook with: claude" -ForegroundColor Cyan
