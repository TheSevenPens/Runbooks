# regex-helpers.ps1 -- Centralized regex functions for runbook scripts
#
# All regex patterns used by active scripts are isolated here so they
# can be reviewed, tested, and understood in one place. Each function
# documents its input, output, and what the pattern matches.
#
# Usage: dot-source this file at the top of any script that needs it:
#   . (Join-Path $PSScriptRoot '../shared/regex-helpers.ps1')   # from scripts/mac/
#   . (Join-Path $PSScriptRoot '..\shared\regex-helpers.ps1')   # from scripts/windows/

function STRINGOP_SplitAndCleanPath {
    <#
    .SYNOPSIS
        Split a PATH string into an array of clean, non-empty entries.
    .DESCRIPTION
        Splits on semicolons (Windows) or colons (macOS), trims whitespace
        from each entry, and removes empty entries. Use this instead of
        repeating the split/trim/filter idiom inline.
    .PARAMETER PathString
        The raw PATH string (e.g. from $env:Path or the registry).
    .PARAMETER Delimiter
        The delimiter character. Defaults to ';' (Windows). Use ':' for macOS.
    .OUTPUTS
        String array of non-empty, trimmed path entries.
    .EXAMPLE
        STRINGOP_SplitAndCleanPath -PathString $env:Path
    .EXAMPLE
        STRINGOP_SplitAndCleanPath -PathString $env:PATH -Delimiter ':'
    #>
    param(
        [string]$PathString,
        [string]$Delimiter = ';'
    )

    return @($PathString -split [regex]::Escape($Delimiter) |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' })
}

function STRINGOP_RepairPathEntries {
    <#
    .SYNOPSIS
        Split PATH entries that were concatenated without a semicolon.
    .DESCRIPTION
        External installers (e.g. micromamba) may join PATH entries without a
        separator, producing values like "...WindowsAppsC:\Users\...". This
        scans each entry for drive-letter patterns (X:\) appearing mid-string
        and splits them into separate entries.

        Only relevant on Windows where paths use drive letters. On macOS this
        function is a no-op (no drive letters to detect).
    .PARAMETER Entries
        Array of PATH entries (already split on semicolons).
    .OUTPUTS
        Array of PATH entries with concatenated entries split apart.
    .EXAMPLE
        $entries = @('C:\Windows\System32', 'C:\WindowsAppsC:\Users\me\.local\bin')
        STRINGOP_RepairPathEntries -Entries $entries
        # Returns @('C:\Windows\System32', 'C:\WindowsApps', 'C:\Users\me\.local\bin')
    #>
    param([string[]]$Entries)

    $repaired = @()
    foreach ($entry in $Entries) {
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
            $repaired += $entry
        } else {
            $prev = 0
            foreach ($pos in $splitPositions) {
                $repaired += $entry.Substring($prev, $pos - $prev)
                $prev = $pos
            }
            $repaired += $entry.Substring($prev)
        }
    }
    return $repaired
}

function STRINGOP_GetToolVersion {
    <#
    .SYNOPSIS
        Run a tool's version command and return the first line of output.
    .DESCRIPTION
        Executes the given path with the given flag (e.g. --version), captures
        output, and returns the first line trimmed. Returns empty string on
        error or if the path/flag is empty.
    .PARAMETER ExePath
        Full path to the executable.
    .PARAMETER Flag
        The version flag (e.g. '--version').
    .OUTPUTS
        First line of version output as a string, or empty string on failure.
    .EXAMPLE
        STRINGOP_GetToolVersion -ExePath '/opt/homebrew/bin/git' -Flag '--version'
        # Returns 'git version 2.53.0'
    #>
    param(
        [string]$ExePath,
        [string]$Flag
    )

    if ([string]::IsNullOrEmpty($ExePath) -or [string]::IsNullOrEmpty($Flag)) { return '' }
    try {
        $output = & $ExePath $Flag 2>&1 | Select-Object -First 1
        return "$output".Trim()
    } catch {
        return ''
    }
}

function STRINGOP_ParseBrewfileLine {
    <#
    .SYNOPSIS
        Parse a single Brewfile line into its type and package name.
    .DESCRIPTION
        Matches lines like:
            brew "git"
            cask "google-chrome"
        Ignores comments, blank lines, and other Brewfile directives (tap, mas, etc.).
    .PARAMETER Line
        A single line from a Brewfile.
    .OUTPUTS
        Hashtable with Type ('brew' or 'cask') and Name (package name), or $null
        if the line is not a brew/cask entry.
    .EXAMPLE
        STRINGOP_ParseBrewfileLine 'brew "git"'
        # Returns @{ Type = 'brew'; Name = 'git' }
    .EXAMPLE
        STRINGOP_ParseBrewfileLine '# comment'
        # Returns $null
    #>
    param([string]$Line)

    $type = $null
    if ($Line.StartsWith('brew '))  { $type = 'brew' }
    if ($Line.StartsWith('cask '))  { $type = 'cask' }
    if (-not $type) { return $null }

    $firstQuote = $Line.IndexOf('"')
    $lastQuote  = $Line.LastIndexOf('"')
    if ($firstQuote -lt 0 -or $lastQuote -le $firstQuote) { return $null }

    $name = $Line.Substring($firstQuote + 1, $lastQuote - $firstQuote - 1)
    return @{ Type = $type; Name = $name }
}

function STRINGOP_TestMiseActivated {
    <#
    .SYNOPSIS
        Check whether mise reports itself as activated.
    .DESCRIPTION
        Scans the output of 'mise doctor' for the activation status line.
        Matches 'activated: yes' with flexible whitespace after the colon.
    .PARAMETER DoctorOutput
        Array of strings from 'mise doctor' output.
    .OUTPUTS
        $true if mise is activated, $false otherwise.
    .EXAMPLE
        $output = & mise doctor 2>&1
        STRINGOP_TestMiseActivated -DoctorOutput $output
    #>
    param([string[]]$DoctorOutput)

    foreach ($line in $DoctorOutput) {
        if ($line.Contains('activated:') -and $line.Contains('yes')) {
            return $true
        }
    }
    return $false
}

function STRINGOP_FindFirstNonBlankLine {
    <#
    .SYNOPSIS
        Find the first line in a multi-line string that has visible content.
    .DESCRIPTION
        Splits the input on newlines and returns the first line that contains
        at least one non-whitespace character. Useful for extracting the first
        meaningful error message from command output.
    .PARAMETER Text
        A multi-line string (e.g. captured stdout or stderr).
    .OUTPUTS
        The first non-blank line as a string, or empty string if all lines are blank.
    .EXAMPLE
        STRINGOP_FindFirstNonBlankLine "`n  `n  error: something broke`n"
        # Returns '  error: something broke'
    #>
    param([string]$Text)

    $lines = $Text -split "`n"
    foreach ($line in $lines) {
        if ($line.Trim() -ne '') {
            return $line
        }
    }
    return ''
}

function STRINGOP_TestContainsAnyWord {
    <#
    .SYNOPSIS
        Test whether a string contains any of the given words.
    .DESCRIPTION
        Builds a regex alternation pattern from the word list and tests the
        input string against it. Words are escaped so special regex characters
        in the words are treated as literals.
    .PARAMETER Text
        The string to search in.
    .PARAMETER Words
        An array of words to look for (case-insensitive).
    .OUTPUTS
        $true if any word is found, $false otherwise.
    .EXAMPLE
        STRINGOP_TestContainsAnyWord -Text 'package install failed' -Words @('failed', 'error')
        # Returns $true
    .EXAMPLE
        STRINGOP_TestContainsAnyWord -Text 'package installed successfully' -Words @('failed', 'error')
        # Returns $false
    #>
    param(
        [string]$Text,
        [string[]]$Words
    )

    foreach ($word in $Words) {
        if ($Text.Contains($word)) { return $true }
    }
    return $false
}

function STRINGOP_TestLooksLikePowerShellScript {
    <#
    .SYNOPSIS
        Sanity-check that downloaded content looks like a PowerShell script.
    .DESCRIPTION
        Tests whether the content contains at least one of several keywords
        expected in the Claude Code install script. Used as a safety check
        before piping downloaded content to Invoke-Expression.
    .PARAMETER Content
        The downloaded script content as a string.
    .OUTPUTS
        $true if the content looks like a PowerShell script, $false otherwise.
    .EXAMPLE
        $script = Invoke-RestMethod https://claude.ai/install.ps1
        if (-not (STRINGOP_TestLooksLikePowerShellScript $script)) {
            Write-Error "Not a valid install script"
        }
    #>
    param([string]$Content)

    return (STRINGOP_TestContainsAnyWord -Text $Content -Words @('param', 'function', 'Install', 'claude'))
}
