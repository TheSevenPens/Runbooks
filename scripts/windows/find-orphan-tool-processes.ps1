# find-orphan-tool-processes.ps1 - Find (and optionally stop) leftover tool processes
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File find-orphan-tool-processes.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File find-orphan-tool-processes.ps1 -Kill
#
# Background:
#   On Windows, each call through a mise shim runs as a chain of three
#   processes: <tool>.exe (shim) -> mise.exe -> <tool>.exe (real). Windows
#   does not kill children when their parent is killed, so when the top of
#   that chain is killed (a timed-out command, a stopped background job),
#   mise.exe and the real tool are orphaned and keep running. Over a long
#   session these pile up into the hundreds. See mise-env-runbook.md
#   "Third-Run Discoveries".
#
# Actions:
#   1. List python/pythonw/mise/node processes and summarize by command line
#   2. Identify orphans: processes whose parent no longer exists (or whose
#      parent PID was reused by a newer process)
#   3. With -Kill: stop each orphan and its descendants (taskkill /T /F)
#
# Parameters:
#   -Names   Process names to inspect (default: python, pythonw, mise, node)
#   -Kill    Stop the orphans found. Without it, the script only reports.
#
# Output: Structured lines prefixed with OK / INFO / WARN / FAIL
# Exit code: 0 if no orphans remain, 1 if orphans remain (report-only run,
#            or some could not be stopped)

param(
    [string[]]$Names = @('python', 'pythonw', 'mise', 'node'),
    [switch]$Kill
)

. (Join-Path $PSScriptRoot '..\shared\process-helpers.ps1')

$ErrorActionPreference = 'Continue'

# --- Step 1: Snapshot processes ---

Write-Host "--- Step 1: Snapshot processes ---"

$all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
if ($all.Count -eq 0) {
    Write-Host "FAIL: Could not read the process list (Get-CimInstance Win32_Process)"
    exit 1
}

$byPid = @{}
foreach ($p in $all) { $byPid[[int]$p.ProcessId] = $p }

$exeNames = @($Names | ForEach-Object { ($_.ToLower()) + '.exe' })
$targets = @($all | Where-Object { $exeNames -contains $_.Name.ToLower() })

if ($targets.Count -eq 0) {
    Write-Host "OK: No $($Names -join '/') processes running"
    exit 0
}

foreach ($g in ($targets | Group-Object Name | Sort-Object Name)) {
    Write-Host "INFO: $($g.Count) x $($g.Name)"
}

Write-Host ""
Write-Host "INFO: Most common command lines:"
$targets | Group-Object CommandLine | Sort-Object Count -Descending | Select-Object -First 10 |
    ForEach-Object {
        $cl = $_.Name
        if ([string]::IsNullOrEmpty($cl)) { $cl = '(command line not readable)' }
        if ($cl.Length -gt 160) { $cl = $cl.Substring(0, 157) + '...' }
        Write-Host ("INFO:   {0,4}  {1}" -f $_.Count, $cl)
    }

# --- Step 2: Find orphans ---

Write-Host ""
Write-Host "--- Step 2: Find orphans ---"

$orphans = @()
foreach ($t in $targets) {
    $parentId = [int]$t.ParentProcessId
    $parent = $byPid[$parentId]
    $isOrphan = $false
    if (-not $parent) {
        $isOrphan = $true
    } elseif ($parent.CreationDate -and $t.CreationDate -and $parent.CreationDate -gt $t.CreationDate) {
        # Parent PID was reused by a process started after this one.
        $isOrphan = $true
    }
    if ($isOrphan) { $orphans += $t }
}

# A shim chain killed at the top leaves mise.exe orphaned; the real tool under
# it still has a live parent (mise.exe), so it is not listed here but is
# stopped with the tree in Step 3.

if ($orphans.Count -eq 0) {
    Write-Host "OK: No orphaned processes ($($targets.Count) running, all have a live parent)"
    exit 0
}

Write-Host "WARN: $($orphans.Count) orphaned process(es) - their parent has exited"
foreach ($o in ($orphans | Sort-Object CreationDate)) {
    $cl = $o.CommandLine
    if ([string]::IsNullOrEmpty($cl)) { $cl = '(command line not readable)' }
    if ($cl.Length -gt 140) { $cl = $cl.Substring(0, 137) + '...' }
    $started = ''
    if ($o.CreationDate) { $started = $o.CreationDate.ToString('yyyy-MM-dd HH:mm') }
    Write-Host ("INFO:   PID {0,-6} {1,-12} started {2}  {3}" -f $o.ProcessId, $o.Name, $started, $cl)
}

# --- Step 3: Stop orphans (optional) ---

Write-Host ""
Write-Host "--- Step 3: Stop orphans ---"

if (-not $Kill) {
    Write-Host "SKIP: Report only. Re-run with -Kill to stop these process trees."
    Write-Host ""
    Write-Host "RESULT: $($orphans.Count) orphaned process(es) found"
    exit 1
}

foreach ($o in $orphans) {
    PROC_StopTree -ProcessId ([int]$o.ProcessId)
}
Start-Sleep -Milliseconds 500

$remaining = 0
foreach ($o in $orphans) {
    $still = Get-Process -Id ([int]$o.ProcessId) -ErrorAction SilentlyContinue
    if ($still) {
        Write-Host "FAIL: Could not stop PID $($o.ProcessId) ($($o.Name))"
        $remaining++
    }
}

Write-Host ""
if ($remaining -gt 0) {
    Write-Host "RESULT: $remaining orphaned process(es) could not be stopped (try an elevated shell)"
    exit 1
} else {
    Write-Host "OK: Stopped $($orphans.Count) orphaned process tree(s)"
    Write-Host "RESULT: No orphans remain"
    exit 0
}
