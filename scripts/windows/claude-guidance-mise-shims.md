## mise shims on Windows (installed by Runbooks)

On this machine `python`, `node` and `gh` are managed by mise. Your Bash tool does not load the PowerShell profile, so those names resolve to mise shims, and each call runs as three processes: shim -> mise.exe -> real tool. Windows does not kill child processes when their parent is killed, so when a command times out or a background job is stopped, mise.exe and the real tool keep running. One long session left hundreds of them behind and made the machine unresponsive.

- Call the real binary, not the shim, for anything long-running or repeated. Resolve it once per session and reuse it: `PY="$(mise which python)"; NODE="$(mise which node)"`, then `"$PY" script.py`. For a whole job, `mise exec -- <command>` resolves once for everything it runs.
- Stop process trees, not processes. From Git Bash: `taskkill //PID <pid> //T //F` (double slashes stop MSYS from rewriting the switches). From PowerShell: `taskkill /PID <pid> /T /F`.
- After a command times out or is interrupted, and before ending a long session, check for leftovers and tell the user what you found before stopping anything:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{{RUNBOOKS_DIR}}\scripts\windows\find-orphan-tool-processes.ps1"` (add `-Kill` to stop them).

Background: `{{RUNBOOKS_DIR}}\mise-env-runbook.md`, Section 5.
