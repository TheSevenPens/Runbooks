\# Intro



These instructions for the user to manually perform.



They have to be run so that Claude Code is available to use the runbooks



\# install claude code via PowerShell



&#x20;   irm https://claude.ai/install.ps1 | iex



\# Get Claud Coded on the path



&#x20;   $newPath = "$env:USERPROFILE\\.local\\bin"

&#x20;   \[Environment]::SetEnvironmentVariable("Path", \[Environment]::GetEnvironmentVariable("Path", "User") + ";$newPath", "User")

