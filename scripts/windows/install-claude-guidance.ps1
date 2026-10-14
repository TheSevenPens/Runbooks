# install-claude-guidance.ps1 - Add Runbooks guidance to the user-level Claude Code memory (idempotent)
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-claude-guidance.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File install-claude-guidance.ps1 -Remove
#
# Why: the repo's CLAUDE.md is only read when Claude Code works inside this
# repo. Guidance that matters in every project on the machine (e.g. how to
# call mise-managed tools without leaving orphaned processes) has to live in
# the user-level memory file, %USERPROFILE%\.claude\CLAUDE.md.
#
# Actions:
#   1. Load the guidance template (claude-guidance-mise-shims.md next to this
#      script) and fill in this machine's Runbooks path
#   2. Insert it into %USERPROFILE%\.claude\CLAUDE.md between BEGIN/END
#      markers: append if absent, replace if changed, skip if identical.
#      Everything outside the markers is left untouched.
#   3. Verify the file now contains exactly the expected block
#   With -Remove: delete the marked block instead.
#
# Output: Structured lines prefixed with OK / SKIP / FAIL / INFO
# Exit code: 0 on success, 1 on any failure

param(
    [switch]$Remove
)

$ErrorActionPreference = 'Continue'

$BeginMarker = '<!-- BEGIN runbooks:mise-shims (managed by install-claude-guidance.ps1; edits inside are overwritten) -->'
$EndMarker   = '<!-- END runbooks:mise-shims -->'

$RunbooksDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TemplatePath = Join-Path $PSScriptRoot 'claude-guidance-mise-shims.md'
$ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
$MemoryPath   = Join-Path $ClaudeDir 'CLAUDE.md'
$Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)

function Get-MarkedBlockRange {
    # Returns @(start, endExclusive) of the marked block in $Text, or $null.
    param([string]$Text)
    $start = $Text.IndexOf($BeginMarker)
    if ($start -lt 0) { return $null }
    $endMarkerAt = $Text.IndexOf($EndMarker, $start)
    if ($endMarkerAt -lt 0) { return $null }
    return @($start, ($endMarkerAt + $EndMarker.Length))
}

# --- Step 1: Load template ---

Write-Host "--- Step 1: Load guidance template ---"

if ($Remove) {
    Write-Host "SKIP: -Remove given, template not needed"
    $block = ''
} elseif (-not (Test-Path $TemplatePath)) {
    Write-Host "FAIL: Template not found: $TemplatePath"
    exit 1
} else {
    $body = [System.IO.File]::ReadAllText($TemplatePath).Replace("`r`n", "`n").TrimEnd()
    $body = $body.Replace('{{RUNBOOKS_DIR}}', $RunbooksDir)
    $block = $BeginMarker + "`n" + $body + "`n" + $EndMarker
    Write-Host "OK: Template loaded (Runbooks path: $RunbooksDir)"
}

# --- Step 2: Update user-level CLAUDE.md ---

Write-Host ""
Write-Host "--- Step 2: Update $MemoryPath ---"

$existing = ''
$fileExists = Test-Path $MemoryPath
if ($fileExists) {
    $existing = [System.IO.File]::ReadAllText($MemoryPath)
}
$useCrlf = $existing.Contains("`r`n")
$normalized = $existing.Replace("`r`n", "`n")
$range = Get-MarkedBlockRange -Text $normalized

if ($Remove) {
    if (-not $range) {
        Write-Host "SKIP: No managed block present"
        $newText = $null
    } else {
        $before = $normalized.Substring(0, $range[0]).TrimEnd()
        $after = $normalized.Substring($range[1]).TrimStart()
        if ($before -and $after) { $newText = $before + "`n`n" + $after }
        else { $newText = $before + $after }
        if ($newText) { $newText = $newText.TrimEnd() + "`n" }
        Write-Host "INFO: Removing managed block"
    }
} elseif (-not $range) {
    if ($normalized.Trim()) {
        $newText = $normalized.TrimEnd() + "`n`n" + $block + "`n"
        Write-Host "INFO: Appending managed block to existing file"
    } else {
        $newText = $block + "`n"
        Write-Host "INFO: Creating file with managed block"
    }
} else {
    $current = $normalized.Substring($range[0], $range[1] - $range[0])
    if ($current -eq $block) {
        Write-Host "SKIP: Managed block already up to date"
        $newText = $null
    } else {
        $newText = $normalized.Substring(0, $range[0]) + $block + $normalized.Substring($range[1])
        Write-Host "INFO: Replacing outdated managed block"
    }
}

if ($null -ne $newText) {
    if ($useCrlf) { $newText = $newText.Replace("`n", "`r`n") }
    try {
        if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null }
        [System.IO.File]::WriteAllText($MemoryPath, $newText, $Utf8NoBom)
        Write-Host "OK: Wrote $MemoryPath"
    } catch {
        Write-Host "FAIL: Could not write $MemoryPath : $_"
        exit 1
    }
}

# --- Step 3: Verify ---

Write-Host ""
Write-Host "--- Step 3: Verify ---"

$check = ''
if (Test-Path $MemoryPath) {
    $check = [System.IO.File]::ReadAllText($MemoryPath).Replace("`r`n", "`n")
}
$checkRange = Get-MarkedBlockRange -Text $check

if ($Remove) {
    if ($checkRange) {
        Write-Host "FAIL: Managed block still present"
        exit 1
    }
    Write-Host "OK: Managed block absent"
    Write-Host ""
    Write-Host "RESULT: Guidance removed from user-level CLAUDE.md"
    exit 0
}

if (-not $checkRange) {
    Write-Host "FAIL: Managed block not found after write"
    exit 1
}
$written = $check.Substring($checkRange[0], $checkRange[1] - $checkRange[0])
if ($written -ne $block) {
    Write-Host "FAIL: Managed block does not match the template"
    exit 1
}
Write-Host "OK: Managed block present and current"
Write-Host ""
Write-Host "RESULT: Guidance installed in user-level CLAUDE.md"
Write-Host "INFO: Takes effect in new Claude Code sessions"
exit 0
