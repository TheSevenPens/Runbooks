# mise-helpers.ps1 -- Shared mise resolution functions for runbook scripts
#
# Reusable MISE_* functions used across Windows scripts. Locating mise.exe is
# duplicated in several scripts and got it wrong in different ways, so it lives
# here now.
#
# Usage: dot-source this file at the top of any script that needs it:
#   . (Join-Path $PSScriptRoot '..\shared\mise-helpers.ps1')   # from scripts/windows/

function MISE_ResolveExe {
    <#
    .SYNOPSIS
        Locate mise.exe, searching PATH and all known install locations.
    .DESCRIPTION
        Resolution order:
          1. mise on the current session PATH.
          2. mise on the registry PATH (Machine + User). A script running in a
             shell that was started before mise was installed has a stale
             $env:Path, so PATH lookups fail even though mise is installed.
          3. Known install locations on disk:
             - %LOCALAPPDATA%\Microsoft\WinGet\Links\mise.exe  (winget shim)
             - %LOCALAPPDATA%\mise\bin\mise.exe                (mise.run installer)
             - %LOCALAPPDATA%\Microsoft\WinGet\Packages\jdx.mise*\...\mise.exe
               (winget portable install -- the package directory name embeds a
               source hash, so it must be globbed rather than hardcoded)
    .OUTPUTS
        Full path to mise.exe as a string, or empty string if not found.
    .EXAMPLE
        $mise = MISE_ResolveExe
        if (-not $mise) { Write-Host "FAIL: mise not found" }
    #>
    param()

    $cmd = Get-Command mise -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Registry PATH may be newer than this session's PATH.
    $regPath = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
               [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($dir in ($regPath -split ';')) {
        $trimmed = $dir.Trim()
        if ($trimmed -eq '') { continue }
        $candidate = Join-Path ([Environment]::ExpandEnvironmentVariables($trimmed)) 'mise.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\mise.exe'),
        (Join-Path $env:LOCALAPPDATA 'mise\bin\mise.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $pkgRoot) {
        $miseDirs = Get-ChildItem -Path $pkgRoot -Directory -Filter 'jdx.mise*' -ErrorAction SilentlyContinue
        foreach ($d in $miseDirs) {
            $hit = Get-ChildItem -Path $d.FullName -Filter 'mise.exe' -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }

    return ''
}

function MISE_EnsureOnPath {
    <#
    .SYNOPSIS
        Prepend mise's directory to the current session PATH.
    .DESCRIPTION
        Scripts that spawn child pwsh/powershell processes to run
        'mise activate' need mise to be resolvable by name in those children.
        Child processes inherit $env:Path from this process, so putting mise's
        directory on it here is what makes those child commands work when the
        session PATH is stale (e.g. mise was installed after the shell started).

        No-op if the directory is already present.
    .PARAMETER MiseExe
        Full path to mise.exe (typically from MISE_ResolveExe).
    .OUTPUTS
        None. Modifies $env:Path in the calling session.
    .EXAMPLE
        $mise = MISE_ResolveExe
        MISE_EnsureOnPath -MiseExe $mise
    #>
    param([string]$MiseExe)

    if ([string]::IsNullOrEmpty($MiseExe)) { return }
    $miseDir = Split-Path -Parent $MiseExe
    $existing = @($env:Path -split ';' | ForEach-Object { $_.Trim() })
    if ($existing -notcontains $miseDir) {
        $env:Path = $miseDir + ';' + $env:Path
    }
}
