# macOS Micromamba Debug Runbook

> **Purpose:** Diagnose a machine-specific `libmamba Could not codesign executable: Invalid argument` bug. This runbook is designed to be executed on a **macOS machine where `micromamba create` WORKS**, so we can capture a reference fingerprint and diff it against a broken machine where the same command fails during the linking phase.
>
> **How to use this with Claude Code:** Open Claude Code on the working Mac, point it at this file, and say: *"Follow macos_micromamba_debug_runbook.md end to end. Run every command, fill in the Results blocks in place, and commit the updated runbook. Do not skip sections. If a command needs sudo and I haven't granted it, note that in the Results block and continue."*
>
> **Broken-machine context (for comparison):** On the broken Mac (owner: TheSevenPens), we observed:
> - macOS 26.4 (25E246), Apple Silicon
> - CLT 26.4.0
> - `brew install micromamba` → 2.5.0; `micromamba --version` works; `micromamba shell init` works; `micromamba activate base` works
> - `micromamba create -n node1 -c conda-forge nodejs python gh -y` fails on the very first Mach-O binary during the linking phase with: `critical libmamba Could not codesign executable: Invalid argument`
> - `codesign -s - --force <same-file>` from the shell succeeds with exit 0 on the exact same binary — so the OS `codesign` tool itself works
> - `com.apple.CodeSigningHelper.xpc` is visible in `ps` during the failure — libmamba calls Security.framework APIs directly, not fork/exec of `codesign`
> - Not fixed by: `CONDA_OVERRIDE_OSX`, `CONDA_SOLVER=classic`, OS point update, CLT update, micromamba version change (2.5.0 brew, 1.5.10 standalone)
>
> We want to find **what is different about the working Mac**.

---

## Section 0 — Ground rules for Claude on the working Mac

- Run every command, even ones that look redundant. Diffs between two fingerprints only matter if both sides collected the same fields.
- **Fill in Results blocks in place.** Replace the `<!-- TODO -->` placeholders with actual output. Keep the code fences.
- Truncate output only if it's clearly unbounded (e.g., a multi-MB log). When truncating, mention it explicitly in the Results block.
- Do **not** modify existing micromamba installs, env vars, or shell init files. This runbook is read-only except for creating one throwaway test env named `debug-mm-test`.
- If any command requires sudo and the user hasn't granted it, note "(sudo not granted)" in the Results block and continue. Do not block the whole run on one sudo command.
- At the end, **commit the updated runbook** with a message like `debug: fingerprint from working micromamba mac`.

---

## Section 1 — OS & hardware fingerprint

### 1a. Commands

```bash
sw_vers
uname -a
sysctl -n hw.model hw.machine machdep.cpu.brand_string
system_profiler SPHardwareDataType 2>/dev/null | grep -E "Model|Chip|Identifier|Memory|System Firmware|OS Loader"
csrutil status
```

### 1b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 2 — Xcode Command Line Tools

### 2a. Commands

```bash
xcode-select -p
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables
pkgutil --pkg-info=com.apple.pkg.CLTools_SDK_macOS26 2>/dev/null || echo "no macOS26 SDK pkg"
ls -la /usr/bin/codesign
ls -la /Library/Developer/CommandLineTools/usr/bin/codesign 2>/dev/null || echo "no CLT codesign"
codesign -h 2>&1 | head -5
xcrun -f codesign
xcrun --show-sdk-version 2>&1
xcrun --show-sdk-path 2>&1
```

### 2b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 3 — Homebrew and micromamba install details

### 3a. Commands

```bash
brew --version
brew --prefix
brew config 2>&1 | head -20
brew list --versions micromamba 2>&1 || echo "micromamba not installed via brew"
which -a micromamba
ls -la $(which micromamba)
file $(which micromamba)
shasum -a 256 $(which micromamba)
micromamba --version
micromamba info 2>&1 | head -40
```

### 3b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 4 — Micromamba binary linkage and signature

### 4a. Commands

```bash
otool -L $(which micromamba) 2>&1 | head -40
otool -L $(which micromamba) 2>&1 | grep -iE "security|codesign|solv|archive|curl|ssl"
codesign -dvvv $(which micromamba) 2>&1
codesign -d --entitlements :- $(which micromamba) 2>&1
```

### 4b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 5 — Security framework state

### 5a. Commands

```bash
# Is the codesigning XPC helper present on this OS?
ls -la /System/Library/Frameworks/Security.framework/Versions/A/XPCServices/com.apple.CodeSigningHelper.xpc 2>&1
ls -la /System/Library/Frameworks/Security.framework/Versions/A/XPCServices/ 2>&1 | head -20

# Security framework version
defaults read /System/Library/Frameworks/Security.framework/Resources/version 2>/dev/null || echo "no Security version plist"
mdls -name kMDItemVersion /System/Library/Frameworks/Security.framework 2>&1

# Gatekeeper / assessment
spctl --status 2>&1
spctl --assess --verbose $(which micromamba) 2>&1 || true

# AMFI (Apple Mobile File Integrity) — controls ad-hoc signing on Apple Silicon
nvram boot-args 2>&1
```

### 5b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 6 — Shell init and micromamba environment state

### 6a. Commands

```bash
# What micromamba init blocks exist?
grep -n -A 12 "mamba initialize" ~/.zshrc 2>&1 || echo "no mamba block in .zshrc"
grep -n -A 12 "mamba initialize" ~/.bash_profile 2>&1 || echo "no mamba block in .bash_profile"
grep -n -A 12 "conda initialize" ~/.zshrc 2>&1 || echo "no conda block in .zshrc"
grep -n -A 12 "conda initialize" ~/.bash_profile 2>&1 || echo "no conda block in .bash_profile"

# What does the environment look like?
echo "MAMBA_ROOT_PREFIX=$MAMBA_ROOT_PREFIX"
echo "MAMBA_EXE=$MAMBA_EXE"
echo "CONDA_PREFIX=$CONDA_PREFIX"
echo "PATH=$PATH"

# Existing envs
micromamba env list 2>&1
ls -la ${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/ 2>&1
```

### 6b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 7 — Active reproduction: create a disposable env

> This is the most important section. We want to see exactly what the working Mac does during the linking phase so we can compare against the broken Mac's failure point.

### 7a. Prep: clean state for the test env

```bash
# Delete any prior debug test env (should not exist unless a previous run left one)
micromamba env remove -n debug-mm-test -y 2>&1 || true
rm -rf ${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/debug-mm-test
```

### 7b. Create the same env the broken mac fails on, with verbose output

```bash
time micromamba create -n debug-mm-test -c conda-forge nodejs python gh -y -v 2>&1 | tee /tmp/mm-create.log
echo "exit=$?"
```

### 7c. Results (timing + success/failure + last 60 lines of log)

```
<!-- TODO: paste time output, exit code, and `tail -60 /tmp/mm-create.log` here -->
```

### 7d. Results (grep for any codesign / security mentions in the full log)

```bash
grep -niE "codesign|security|sign|entitlement|invalid argument" /tmp/mm-create.log | head -40
```

```
<!-- TODO: paste grep output here -->
```

---

## Section 8 — Post-create binary inspection

> After a successful create, verify what signatures the freshly-linked binaries actually have. The broken mac can do a manual `codesign -s -` on its partially-linked files and it works, but libmamba's internal call fails. So we want to see what the working Mac's result looks like on the same binaries.

### 8a. Commands

```bash
ENV=${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/debug-mm-test

# Pick a few representative files
for f in \
  "$ENV/lib/libffi.8.dylib" \
  "$ENV/lib/libexpat.1.dylib" \
  "$ENV/lib/libuv.1.dylib" \
  "$ENV/bin/node" \
  "$ENV/bin/python3" \
  "$ENV/bin/gh"
do
  echo "=== $f ==="
  if [ -e "$f" ]; then
    ls -la "$f"
    xattr -l "$f" 2>&1 | head
    file "$f" 2>&1
    codesign -dv "$f" 2>&1
    codesign --verify --verbose "$f" 2>&1
    echo
  else
    echo "MISSING"
    echo
  fi
done
```

### 8b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 9 — Process and XPC state during create (optional)

> This section is OPTIONAL because it requires either a second terminal or a background subshell and may need sudo for dtruss. Do what you can without sudo; if nothing is available without sudo, say so.

### 9a. Check whether CodeSigningHelper gets invoked

```bash
# Clean up the env again so we can re-run create and watch for the helper
micromamba env remove -n debug-mm-test -y 2>&1 || true
rm -rf ${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/debug-mm-test

# Run create in background; poll ps for the helper during linking
micromamba create -n debug-mm-test -c conda-forge nodejs python gh -y >/tmp/mm-bg.log 2>&1 &
MMPID=$!

# Poll for up to 60 seconds looking for the XPC helper and any codesign children
for i in $(seq 1 60); do
  if ! kill -0 $MMPID 2>/dev/null; then break; fi
  HELPER=$(ps -ax -o pid,ppid,command 2>/dev/null | grep -i "CodeSigningHelper\|codesign" | grep -v grep)
  if [ -n "$HELPER" ]; then
    echo "[t+${i}s] $HELPER"
  fi
  sleep 1
done

wait $MMPID
echo "micromamba exit=$?"
```

### 9b. Results

```
<!-- TODO: paste output here (should show whether CodeSigningHelper.xpc appears during linking) -->
```

### 9c. Optional — dtruss sample (requires sudo)

If the user has granted sudo, run this to capture kernel calls around the codesign moment. Otherwise skip and write "(sudo not granted)".

```bash
# Clean and re-run under dtruss
micromamba env remove -n debug-mm-test -y 2>&1 || true
rm -rf ${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/debug-mm-test
sudo dtruss -f -t csops -t csops_audittoken micromamba create -n debug-mm-test -c conda-forge nodejs python gh -y 2>/tmp/mm-dtruss.log &
sleep 30
tail -100 /tmp/mm-dtruss.log 2>&1
```

```
<!-- TODO: paste output here, or "(sudo not granted)" -->
```

---

## Section 10 — System log capture

### 10a. Commands

```bash
# Capture Security framework / CodeSigningHelper messages from the last few minutes
log show --last 5m --predicate 'subsystem == "com.apple.securityd" OR process == "com.apple.CodeSigningHelper" OR senderImagePath CONTAINS "Security.framework"' 2>&1 | tail -80
```

### 10b. Results

```
<!-- TODO: paste output here -->
```

---

## Section 11 — Cleanup

### 11a. Commands

```bash
micromamba env remove -n debug-mm-test -y 2>&1 || true
rm -rf ${MAMBA_ROOT_PREFIX:-$HOME/micromamba}/envs/debug-mm-test
rm -f /tmp/mm-create.log /tmp/mm-bg.log /tmp/mm-dtruss.log
```

### 11b. Results

```
<!-- TODO: confirm cleanup output -->
```

---

## Section 12 — Fingerprint summary table

> Claude on the working Mac: fill this in from the above sections. The broken-mac owner will diff this against their own machine.

| Field | Value |
|---|---|
| macOS ProductVersion | <!-- TODO --> |
| macOS BuildVersion | <!-- TODO --> |
| Hardware (chip/model) | <!-- TODO --> |
| SIP status | <!-- TODO --> |
| CLT version | <!-- TODO --> |
| Active xcode-select path | <!-- TODO --> |
| `codesign` path & size | <!-- TODO --> |
| Homebrew version | <!-- TODO --> |
| Homebrew prefix | <!-- TODO --> |
| micromamba version | <!-- TODO --> |
| micromamba install source (brew? standalone?) | <!-- TODO --> |
| micromamba binary path | <!-- TODO --> |
| micromamba binary sha256 | <!-- TODO --> |
| micromamba links Security.framework? | <!-- TODO: yes/no from otool -L --> |
| MAMBA_ROOT_PREFIX value | <!-- TODO --> |
| Shell init: micromamba in .zshrc? | <!-- TODO: yes/no --> |
| Shell init: conda in .zshrc? | <!-- TODO: yes/no --> |
| `micromamba create` result | <!-- TODO: success / failure + exit code --> |
| Time to create debug-mm-test | <!-- TODO --> |
| CodeSigningHelper.xpc observed during create? | <!-- TODO: yes/no from Section 9 --> |
| Signature on `$ENV/lib/libffi.8.dylib` after create | <!-- TODO: ad-hoc / embedded / none --> |
| Any unusual xattrs on env binaries? | <!-- TODO --> |

---

## Section 13 — Claude notes (working mac)

> Anything the working-mac Claude noticed that wasn't captured by the structured sections. Surprising output, warnings, non-obvious diffs from the broken-mac description in the header. Keep it short.

```
<!-- TODO: free-form notes from Claude on the working mac -->
```

---

## Section 14 — Commit

Commit the updated runbook so the broken-mac side can pull and compare.

```bash
cd <path to Runbooks repo on this machine>
git add macos_micromamba_debug_runbook.md
git commit -m "debug: fingerprint from working micromamba mac"
git push
```
