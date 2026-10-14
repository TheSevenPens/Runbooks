# process-helpers.ps1 -- Shared child-process functions for runbook scripts
#
# Reusable PROC_* functions for scripts that spawn child shells and capture
# their output. Works under PowerShell 5.1 and 7.
#
# Why this exists: the old pattern in these scripts was
#
#     $stdout = $proc.StandardOutput.ReadToEnd()
#     $exited = $proc.WaitForExit($TimeoutMs)
#     if (-not $exited) { $proc.Kill() }
#
# which has two problems on Windows:
#   1. ReadToEnd() blocks until the pipe closes, so the timeout never fires if
#      the child hangs. The pipe also stays open while any grandchild that
#      inherited it is alive -- e.g. the real python.exe behind a mise shim.
#   2. Process.Kill() kills only that one process. Windows does not kill
#      children with their parent, so grandchildren (mise.exe, python.exe,
#      node.exe) are orphaned and keep running.
# See mise-env-runbook.md "Third-Run Discoveries" for the incident.
#
# Usage: dot-source this file at the top of any script that needs it:
#   . (Join-Path $PSScriptRoot '..\shared\process-helpers.ps1')   # from scripts/windows/

function PROC_StopTree {
    <#
    .SYNOPSIS
        Forcefully stop a process and all of its descendants.
    .DESCRIPTION
        Uses taskkill /T, which walks the parent-PID chain, so the whole tree
        goes down even on PowerShell 5.1 (.NET Framework has no Kill(true)).
        Errors (e.g. the process already exited) are ignored.
    .PARAMETER ProcessId
        PID of the root of the tree to stop.
    .OUTPUTS
        None.
    .EXAMPLE
        PROC_StopTree -ProcessId $proc.Id
    #>
    param([int]$ProcessId)

    if ($ProcessId -le 0) { return }
    & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
}

function PROC_Invoke {
    <#
    .SYNOPSIS
        Run a process with a timeout, capturing stdout/stderr, and kill its
        whole tree if it times out.
    .DESCRIPTION
        Output is read asynchronously so the timeout always fires, even if the
        child hangs or a grandchild keeps the output pipe open. On timeout the
        entire process tree is stopped with PROC_StopTree. After the process
        exits, output collection waits at most 5 seconds more so a lingering
        grandchild holding the pipe cannot block the caller.
    .PARAMETER FilePath
        Executable to run (full path or a name resolvable on PATH).
    .PARAMETER Arguments
        Argument string passed to the executable.
    .PARAMETER TimeoutMs
        Milliseconds to wait for exit before stopping the tree. Default 30000.
    .OUTPUTS
        PSCustomObject with TimedOut (bool), ExitCode (int, -1 if timed out or
        unknown), StdOut (string), StdErr (string).
    .EXAMPLE
        $r = PROC_Invoke -FilePath 'pwsh' -Arguments '-NoProfile -Command "node --version"' -TimeoutMs 15000
        if ($r.TimedOut) { Write-Host "FAIL: timed out" }
    #>
    param(
        [string]$FilePath,
        [string]$Arguments,
        [int]$TimeoutMs = 30000
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $timedOut = -not $proc.WaitForExit($TimeoutMs)
    if ($timedOut) {
        PROC_StopTree -ProcessId $proc.Id
        $proc.WaitForExit(5000) | Out-Null
    }

    # One shared 5s deadline for both streams. If a grandchild still holds the
    # pipe, that stream's output is dropped rather than blocking the caller.
    [System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask), 5000) | Out-Null
    $stdout = ''
    $stderr = ''
    if ($outTask.IsCompleted) { $stdout = $outTask.Result }
    if ($errTask.IsCompleted) { $stderr = $errTask.Result }

    $exitCode = -1
    if (-not $timedOut -and $proc.HasExited) {
        try { $exitCode = $proc.ExitCode } catch { $exitCode = -1 }
    }
    $proc.Dispose()

    return [PSCustomObject]@{
        TimedOut = $timedOut
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}
