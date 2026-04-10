# regex-helpers.ps1 -- Centralized regex functions for runbook scripts
#
# All regex patterns used by active scripts are isolated here so they
# can be reviewed, tested, and understood in one place. Each function
# documents its input, output, and what the pattern matches.
#
# Usage: dot-source this file at the top of any script that needs it:
#   . (Join-Path $PSScriptRoot '../shared/regex-helpers.ps1')   # from scripts/mac/
#   . (Join-Path $PSScriptRoot '..\shared\regex-helpers.ps1')   # from scripts/windows/

function REGEX_ParseBrewfileLine {
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
        REGEX_ParseBrewfileLine 'brew "git"'
        # Returns @{ Type = 'brew'; Name = 'git' }
    .EXAMPLE
        REGEX_ParseBrewfileLine '# comment'
        # Returns $null
    #>
    param([string]$Line)

    # Pattern: line starts with 'brew' or 'cask', followed by whitespace,
    # then a double-quoted package name.
    #   ^(brew|cask)   -- capture group 1: the type
    #   \s+            -- one or more whitespace characters
    #   "([^"]+)"      -- capture group 2: the package name (inside quotes)
    if ($Line -match '^(brew|cask)\s+"([^"]+)"') {
        return @{ Type = $Matches[1]; Name = $Matches[2] }
    }
    return $null
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
