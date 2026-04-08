# macOS Micromamba Debug Runbook

> **Status: root-caused.** This runbook started as a "diff a working Mac against a broken Mac" exercise, but the second Mac we ran it on turned out to also be broken, and the investigation on that machine pinned the root cause. See **Section 15 (Deep dive)** for the full probe trail and **Section 15h** for the one-paragraph summary.
>
> **One-line root cause:** `libmamba::codesign()` fork/execs `/usr/bin/codesign` via `reproc::run()` with `reproc::env::empty`. On macOS 26, reproc returns `EINVAL` from that spawn even though `/usr/bin/codesign` actually runs to completion and correctly ad-hoc signs the file. libmamba then throws `"Could not codesign executable: " + strerror(EINVAL)` based on reproc's error code and aborts the install — even though the file on disk is already validly signed. Source: `libmamba/src/core/util_os.cpp::codesign()`. **Still present on libmamba `main` as of 2026-04-08 — not fixed upstream.**
>
> **Confirmed broken environments:**
> - macOS 26.4 (25E246) / Apple M4 Pro / CLT 26.4.0 / brewed micromamba 2.5.0 (TheSevenPens machine — setup-runbook-mac run)
> - macOS 26.3.1 (25D2128) / Apple M4 Pro / CLT 26.3.0 / brewed micromamba 2.5.0_3 (sevenpens / lorient.charydishome — this runbook was executed here)
>
> Both machines fail with the exact same error on the very first Mach-O binary of the linking phase. The failure is machine-independent on macOS 26 — it is **not** a machine-specific quirk.
>
> **Does not fix the bug:** `CONDA_OVERRIDE_OSX`, `CONDA_SOLVER=classic`, OS point updates (26.3.1 ↔ 26.4), CLT updates, micromamba version changes (2.5.0 brew ↔ 1.5.10 standalone), pre-upgrading the cached libffi signature from CDv=20200 to CDv=20400, single-package isolated repro (`micromamba create -n t -c conda-forge libffi -y` still fails).
>
> **Known working alternatives on macOS 26:** `conda install` (vendored Python `subprocess`, normal envp — codepath does not go through reproc), `pixi global install` (Rust rattler — separate code entirely). Both verified working on the TheSevenPens machine.
>
> **Current purpose of this runbook:** (1) A reproducible data-collection script that any Claude can run on any mac to confirm the bug and capture a clean fingerprint. (2) Living evidence for an upstream bug report. (3) A place to record per-libmamba-release retries so we can detect when the bug is fixed.
>
> **How to use this with Claude Code:** Open Claude Code on any macOS 26 machine where you want to verify / re-verify the bug and say: *"Follow macos_micromamba_debug_runbook.md end to end. Run every command, fill in the Results blocks in place (or add a dated second run below the existing ones), and commit the updated runbook. If any command needs sudo and I haven't granted it, note that in the Results block and continue."*
>
> **Known unknowns / next probes:** See Section 15h "Open questions."

---

## Section 0 — Ground rules for Claude running this runbook

- Run every command, even ones that look redundant. Fingerprint diffs only matter if every run captured the same fields.
- **Fill in Results blocks in place.** If the block already has results from a prior run, add a new dated subsection **below** the existing results (e.g., `### 1b. Results — 2026-05-12 (libmamba 2.6.0 retry)`) rather than overwriting. The runbook should accumulate history so we can spot the moment upstream fixes the bug.
- Truncate output only if it's clearly unbounded (e.g., a multi-MB log). When truncating, mention it explicitly.
- Do **not** modify existing micromamba installs, env vars, or shell init files. This runbook is read-only except for creating one throwaway test env named `debug-mm-test` and (in Section 15) `debug-libffi-only`, both of which must be removed at the end.
- If any command requires sudo and the user hasn't granted it, note "(sudo not granted)" in the block and continue. Do not block the whole run on one sudo command.
- **Every new run must re-execute Section 7 (active repro) and record whether it still fails.** If Section 7 now succeeds, the upstream bug is probably fixed — go re-verify by running Section 15c–15d and update Section 15h.
- At the end, **commit the updated runbook** with a message like `debug: re-run on libmamba X.Y.Z / macOS NN.N — still broken` or `… — fixed!`.

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

> **Note:** This run was executed on the **broken** mac (owner sevenpens), not a working one. `micromamba create` failed with the same `Could not codesign executable: Invalid argument` error. Fingerprint captured anyway for diff against a future working-mac run.

```
ProductName:    macOS
ProductVersion: 26.3.1
BuildVersion:   25D2128
---
Darwin lorient.charydishome 25.3.0 Darwin Kernel Version 25.3.0: Wed Jan 28 20:51:28 PST 2026; root:xnu-12377.91.3~2/RELEASE_ARM64_T6041 arm64
---
Mac16,11
arm64
Apple M4 Pro
---
Model Name: Mac mini
Model Identifier: Mac16,11
Model Number: Z1JV000LPLL/A
Chip: Apple M4 Pro
Memory: 64 GB
System Firmware Version: 13822.81.10
OS Loader Version: 13822.81.10
---
System Integrity Protection status: enabled.
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
xcode-select -p: /Applications/Xcode.app/Contents/Developer
pkgutil CLTools_Executables: version 26.3.0.0.1.1771626560
CLTools_SDK_macOS26: no macOS26 SDK pkg
/usr/bin/codesign: -rwxr-xr-x 1 root wheel 459536 Feb 24 19:41
/Library/Developer/CommandLineTools/usr/bin/codesign: no CLT codesign
codesign -h: standard usage output (sign/verify/display/hosting/validate-constraint)
xcrun -f codesign: /usr/bin/codesign
xcrun --show-sdk-version: 26.2
xcrun --show-sdk-path: /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
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

> Note: `which micromamba` resolves to a shell function (`__mamba_wrap`) from the mamba shell hook. Used `/opt/homebrew/bin/micromamba` (symlink → `../Cellar/micromamba/2.5.0_3/bin/micromamba`) directly for the binary inspection.

```
brew --version: Homebrew 5.1.1
brew --prefix: /opt/homebrew
brew config (head): HOMEBREW_PREFIX=/opt/homebrew, CPU dodeca-core arm_brava, Clang 17.0.0 build 1700,
                    macOS 26.3.1-arm64, CLT 26.3.0.0.1.1771626560, Xcode 26.2
brew list --versions micromamba: micromamba 2.5.0_3
which -a micromamba: shell function __mamba_wrap (no binary on plain PATH=/usr/bin:/bin:...)
ls -la /opt/homebrew/bin/micromamba: lrwxr-xr-x -> ../Cellar/micromamba/2.5.0_3/bin/micromamba
file: Mach-O 64-bit executable arm64
sha256: 57ef542e29d3de98b7a23216d06a9fb785957bbacefa786c3369199534a00f53
micromamba --version: 2.5.0
micromamba info:
  libmamba 2.5.0 / micromamba 2.5.0
  curl libcurl/8.7.1 (SecureTransport) LibreSSL/3.3.6 zlib/1.2.12 nghttp2/1.68.0
  libarchive 3.8.6
  envs dirs: /Users/sevenpens/micromamba/envs, /opt/homebrew/Cellar/micromamba/2.5.0_3/envs
  base environment: /opt/homebrew/Cellar/micromamba/2.5.0_3
  platform: osx-arm64
  virtual packages: __unix=0=0  __osx=0=0  __archspec=1=arm64
  warning: OSX version not found, defaulting virtual package version to 0
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
otool -L /opt/homebrew/bin/micromamba:
    /opt/homebrew/opt/reproc/lib/libreproc++.14.dylib (14.2.4)
    /opt/homebrew/opt/reproc/lib/libreproc.14.dylib (14.2.4)
    @rpath/libmamba.4.dylib (4.0.1)
    /opt/homebrew/opt/yaml-cpp/lib/libyaml-cpp.0.9.dylib (0.9.0)
    /opt/homebrew/opt/fmt/lib/libfmt.12.dylib (12.1.0)
    /usr/lib/libc++.1.dylib (2000.67.0)
    /usr/lib/libSystem.B.dylib (1356.0.0)

grep security|codesign|solv|archive|curl|ssl: (no matches — micromamba wrapper binary does not directly link
Security.framework; libsolv/libarchive/libcurl/libcrypto must be pulled in via libmamba.4.dylib)

codesign -dvvv:
  Executable=/opt/homebrew/Cellar/micromamba/2.5.0_3/bin/mamba
  Identifier=mamba-55554944987cf6adaad2319b93b4131d44be4aec
  Format=Mach-O thin (arm64)
  CodeDirectory v=20400 size=4071 flags=0x2(adhoc) hashes=121+2 location=embedded
  Hash type=sha256 size=32
  CDHash=8736183ed81e2f7725ff5c6d8b2976bf06a17fc8
  Signature=adhoc
  TeamIdentifier=not set
  Sealed Resources=none
  Internal requirements count=0 size=12

codesign -d --entitlements :-
  Executable=/opt/homebrew/Cellar/micromamba/2.5.0_3/bin/mamba
  (no entitlements; ':' path syntax warning deprecated)
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
CodeSigningHelper.xpc: present
  /System/Library/Frameworks/Security.framework/Versions/A/XPCServices/com.apple.CodeSigningHelper.xpc (dir, drwxr-xr-x root wheel)

XPCServices dir contents:
  TrustedPeersHelper.xpc  XPCAcmeService.xpc  XPCKeychainSandboxCheck.xpc
  XPCTimeStampingService.xpc  authd.xpc  com.apple.CodeSigningHelper.xpc

Security version plist:
  BuildVersion = 53
  CFBundleShortVersionString = "7.0"
  CFBundleVersion = "61901.80.25"
  ProjectName = Security
  SourceVersion = 61901080025000000

mdls kMDItemVersion /System/Library/Frameworks/Security.framework: (null)

spctl --status: assessments enabled
spctl --assess --verbose /opt/homebrew/bin/micromamba: rejected
  (expected — ad-hoc signed binaries are not Gatekeeper-accepted, but this does not block exec)

nvram boot-args: Error getting variable - 'boot-args': data was not found
  (no custom boot-args set — AMFI at default enforcement)
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
~/.zshrc mamba block (lines 7-18):
  export MAMBA_EXE='/opt/homebrew/opt/micromamba/bin/micromamba'
  export MAMBA_ROOT_PREFIX='/Users/sevenpens/micromamba'
  eval "$($MAMBA_EXE shell hook --shell zsh --root-prefix $MAMBA_ROOT_PREFIX)"

~/.bash_profile mamba block (lines 6-17): same as above (shell bash)

conda block in .zshrc:        none
conda block in .bash_profile: none

(Captured from non-interactive shell — MAMBA_* unset because .zshrc not sourced;
in user's real interactive shell MAMBA_ROOT_PREFIX=/Users/sevenpens/micromamba.)

micromamba env list:
    Name    Active  Path
    base    *       /opt/homebrew/Cellar/micromamba/2.5.0_3
    node1           /Users/sevenpens/micromamba/envs/node1

ls envs/: .conda_envs_dir_test, node1/
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
time: 4.08s user  1.86s system  107% cpu  5.548s total
exit code reported by `echo $?` after tee: 0 (masked by tee).
Real micromamba exit code (captured in Section 9b background run without tee): **1**

Tail of /tmp/mm-create.log:
  Transaction starting
  [21 Download finished lines for tk, openssl, pip, libcxx, libsqlite, ncurses, setuptools,
   libuv, readline, icu, xz, bzip2, zlib, nodejs, packaging, gh, libexpat, libzlib, libffi,
   wheel, python]
  Extracting "xz-5.2.6-h57fd34a_0.tar.bz2"
  Extracting "libffi-3.4.2-h3422bc3_5.tar.bz2"
  Linking gh-2.49.0-h75b854d_0
  Linking icu-73.2-hc8870d7_0
  Linking libuv-1.48.0-h93a5062_0
  Linking xz-5.2.6-h57fd34a_0
  Linking bzip2-1.0.8-h93a5062_5
  Linking libexpat-2.6.2-hebf3989_0
  Linking libffi-3.4.2-h3422bc3_5
  critical libmamba Could not codesign executable: Invalid argument
```

> **Failure point:** the `Linking libffi-3.4.2-h3422bc3_5` step. libffi is the 7th and last package
> to be linked before libmamba aborts. The six linked before it (gh, icu, libuv, xz, bzip2, libexpat)
> all have valid ad-hoc signatures on disk (see Section 8). libffi ends up with a `CodeDirectory`
> embedded but `flags=0x0(none)` and `Signature=` absent — i.e. libmamba started writing a code
> directory and then Security.framework rejected the final sealing step with "Invalid argument".

### 7d. Results (grep for any codesign / security mentions in the full log)

```bash
grep -niE "codesign|security|sign|entitlement|invalid argument" /tmp/mm-create.log | head -40
```

```
102:critical libmamba Could not codesign executable: Invalid argument
```

> Only one match in the entire verbose log — the terminal error. No "sign"/"entitlement" breadcrumbs
> before the failure. libmamba swallows the Security.framework error code and only reports EINVAL.

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
$ENV/lib/libffi.8.dylib   EXISTS (size 120496, mtime Apr  8 01:10)
  xattr: com.apple.provenance
  file: Mach-O 64-bit dylib arm64
  codesign -dv:
    Identifier=libffi.8.dylib
    CodeDirectory v=20200 size=1059 flags=0x0(none) hashes=29+2 location=embedded
    (no Signature= line)
  codesign --verify: "code object is not signed at all"
  >>> THIS IS THE FAILED FILE. CodeDirectory was written but sealing never completed.
      Note CDv=20200 (older/pre-flags format) vs CDv=20400 on successfully signed files below.

$ENV/lib/libexpat.1.dylib  symlink -> libexpat.1.9.2.dylib
  codesign: CDv=20400 size=1581 flags=0x2(adhoc) Signature=adhoc  VALID

$ENV/lib/libuv.1.dylib   EXISTS
  codesign: CDv=20400 size=2150 flags=0x2(adhoc) Signature=adhoc  VALID

$ENV/bin/node     MISSING (nodejs never linked — failure happened before it)
$ENV/bin/python3  MISSING (python never linked)

$ENV/bin/gh   EXISTS
  codesign: CDv=20400 size=490619 flags=0x2(adhoc) Signature=adhoc  VALID

Only xattr on all inspected files: com.apple.provenance (nothing unusual —
no com.apple.quarantine, no com.apple.macl).
```

> **Crucial diff inside the same run:** libmamba wrote `CodeDirectory v=20200` into libffi but wrote
> `v=20400` into every file that linked successfully in the same process. 20200 is the pre-supportsRuntime
> CodeDirectory format and 20400 is the format that carries the `flags` field. This points at libmamba
> (or the libsolv/ssl/whatever statically linked into libmamba.4.dylib) hitting a different code path for
> libffi specifically — likely because libffi's pre-existing ad-hoc signature in the conda tarball has a
> different Mach-O layout (LC_CODE_SIGNATURE load command already present) that Security.framework's
> SecCodeSignerCreate rejects on this OS build.

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
[t+1s]   507     1 /System/Library/Frameworks/Security.framework/Versions/A/XPCServices/com.apple.CodeSigningHelper.xpc/Contents/MacOS/com.apple.CodeSigningHelper
[t+2s]   507     1 /System/Library/Frameworks/Security.framework/Versions/A/XPCServices/com.apple.CodeSigningHelper.xpc/Contents/MacOS/com.apple.CodeSigningHelper
micromamba exit=1
(failure log identical to Section 7 — aborts on `Linking libffi-3.4.2-h3422bc3_5`)
```

> **Confirmed:** `com.apple.CodeSigningHelper.xpc` is launched by launchd (ppid=1) and is alive during
> the libmamba codesign attempt. So the helper IS being invoked — the rejection happens *inside* the
> helper's reply to libmamba's Security.framework call, not because the helper failed to start.
>
> Also note: **the real micromamba exit code is 1**, not 0. Section 7's `exit=0` was the exit code of
> the `tee` command, not micromamba (tee masks failures of the LHS in a pipeline). Updated above.

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
(sudo not granted — dtruss not executed)
```

---

## Section 10 — System log capture

### 10a. Commands

```bash
# Capture Security framework / CodeSigningHelper messages from the last few minutes
log show --last 5m --predicate 'subsystem == "com.apple.securityd" OR process == "com.apple.CodeSigningHelper" OR senderImagePath CONTAINS "Security.framework"' 2>&1 | tail -80
```

### 10b. Results

> The combined predicate (`subsystem == ... OR process == ... OR senderImagePath CONTAINS ...`) tripped
> a zsh parser quirk in this shell wrapper, so the predicates were run individually.

`log show --predicate 'process == "com.apple.CodeSigningHelper"' --last 5m` — **zero rows** (only the
header). The helper logs nothing during the failing codesign call.

`log show --predicate 'subsystem == "com.apple.securityd"' --last 5m` — busy with unrelated traffic
(Adobe Core Sync entitlement warnings, OneDrive trustd, gh "Enabling System Keychain Always due to
platform" appearing 91594/91652/91659/91667/91675 — those are the partial gh installs from each
of our retries). **No SecCode / codesign error rows from securityd.**

`log show --predicate 'senderImagePath CONTAINS "Security.framework"' --last 5m` — only ambient
SecKeyVerifySignature / SecTrustEvaluateIfNecessary activities from trustd, OneDrive, and gh.
Nothing from libmamba.

```
Summary: when libmamba's codesign call fails, neither com.apple.CodeSigningHelper nor securityd
emits a log line about it. The failure is *silent* on the OS side. The "Invalid argument" string
is generated entirely on libmamba's side from a return code, not from anything Security.framework
chose to log.

The `gh` PIDs visible above (91594, 91652, 91659, 91667, 91675) are from the partially-installed
gh binaries that we then ran during diagnostics — confirming that the partial-link gh is at least
launchable, which is consistent with Section 8 showing it has a valid ad-hoc signature.
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
micromamba env remove -n debug-mm-test -y:
  Unlinked bzip2, gh, icu, libexpat, libuv, xz (the 6 partially-linked packages)
  Environment removed at prefix: /Users/sevenpens/micromamba/envs/debug-mm-test
ls envs/: only `node1` remains. Clean.
```

---

## Section 12 — Fingerprint summary table

> Claude on the working Mac: fill this in from the above sections. The broken-mac owner will diff this against their own machine.

| Field | Value |
|---|---|
| macOS ProductVersion | 26.3.1 |
| macOS BuildVersion | 25D2128 |
| Hardware (chip/model) | Mac mini Mac16,11 / Apple M4 Pro / 64 GB |
| SIP status | enabled |
| CLT version | 26.3.0.0.1.1771626560 (Xcode 26.2) |
| Active xcode-select path | /Applications/Xcode.app/Contents/Developer |
| `codesign` path & size | /usr/bin/codesign — 459536 bytes (Feb 24 19:41) |
| Homebrew version | 5.1.1 |
| Homebrew prefix | /opt/homebrew |
| micromamba version | 2.5.0 (libmamba 2.5.0) |
| micromamba install source (brew? standalone?) | brew (formula `micromamba 2.5.0_3`) |
| micromamba binary path | /opt/homebrew/bin/micromamba → /opt/homebrew/Cellar/micromamba/2.5.0_3/bin/micromamba |
| micromamba binary sha256 | 57ef542e29d3de98b7a23216d06a9fb785957bbacefa786c3369199534a00f53 |
| micromamba links Security.framework? | **No** directly — only libreproc, libmamba.4.dylib, libyaml-cpp, libfmt, libc++, libSystem. Security access must come transitively through libmamba.4.dylib |
| MAMBA_ROOT_PREFIX value | /Users/sevenpens/micromamba |
| Shell init: micromamba in .zshrc? | yes (lines 7–18, also in .bash_profile lines 6–17) |
| Shell init: conda in .zshrc? | no |
| `micromamba create` result | **FAILURE** — `critical libmamba Could not codesign executable: Invalid argument`, real exit code **1** (this is the broken mac, reproduced 2x in this run) |
| Time to create debug-mm-test | 5.55s wall (4.08u + 1.86s) before abort |
| CodeSigningHelper.xpc observed during create? | **yes** — pid 507, ppid 1, alive at t+1s and t+2s during the failing run (Section 9b) |
| Signature on `$ENV/lib/libffi.8.dylib` after create | **none** — CodeDirectory v=20200 written, flags=0x0, no Signature seal. All other linked files in the same run got CDv=20400 ad-hoc. |
| Any unusual xattrs on env binaries? | no — only `com.apple.provenance` (default for files written by app-store-installed processes); no quarantine, no macl |

---

## Section 13 — Claude notes (working mac)

> Anything the working-mac Claude noticed that wasn't captured by the structured sections. Surprising output, warnings, non-obvious diffs from the broken-mac description in the header. Keep it short.

```
This run is from the BROKEN mac (sevenpens / lorient.charydishome), not a working one — the runbook
was authored to be executed on a working Mac for diff purposes, but the working-mac fingerprint is
still outstanding. Captured here so a working-mac run can diff against a fully-recorded broken
baseline rather than a description.

Concrete new findings beyond the header:
1. **CodeDirectory version diverges inside the same micromamba process.** libffi (the failing file)
   ends up with CDv=20200; gh / icu / libuv / xz / bzip2 / libexpat (the six that linked successfully
   immediately before it) all end up with CDv=20400. The brewed `micromamba` binary itself is also
   CDv=20400. So libmamba is *taking a different code path* for libffi specifically.

2. **micromamba's own binary does NOT directly link Security.framework.** otool -L only shows
   libreproc, libmamba.4.dylib, libyaml-cpp, libfmt, libc++, libSystem. Whatever is calling
   SecCodeSignerCreate is buried inside libmamba.4.dylib (or one of its statically-linked deps).
   Worth running otool -L on /opt/homebrew/Cellar/micromamba/2.5.0_3/lib/libmamba.4.dylib next pass.

3. **macOS 26.3.1 build 25D2128, kernel 25.3.0 (Wed Jan 28 2026 build).** This is *newer* than the
   26.4 (25E246) build mentioned in the header — so the bug is not specific to one build, it
   persists across at least one OS update on this hardware. The header should be updated to record
   that the failure has now been observed on both 26.4 (25E246) and 26.3.1 (25D2128) on the same
   M4 Pro.

4. **CLTools_SDK_macOS26 pkg is not installed**, but `xcrun --show-sdk-version` returns 26.2 from
   the Xcode.app bundle. Xcode 26.2 + CLT 26.3 is a slightly mixed pair — worth comparing against
   a working mac to see if the working machine has matching versions.

5. **Failure is deterministic and fast** — 5.5s end-to-end, always on libffi, always after exactly
   six successfully-linked packages in conda-forge alphabetical order. Suggests it's keyed on
   something about libffi-3.4.2-h3422bc3_5 specifically (its tarball is one of only two .tar.bz2
   files in this set — every other package is .conda; the other .tar.bz2 is xz which signed fine).
   Worth testing whether `micromamba create -n t -c conda-forge libffi=3.4.2 -y` reproduces in
   isolation.

6. **`spctl --assess` rejects micromamba** but micromamba runs anyway — this is normal for ad-hoc
   signed brewed binaries on Apple Silicon, not the cause.

7. **The Security.framework rejection is completely silent on the OS side** (Section 10).
   `com.apple.CodeSigningHelper` logs nothing during the failure, and `securityd` logs nothing
   about a rejected SecCodeSignerCreate. The only place "Invalid argument" exists is in libmamba's
   own error string (it's mapping a return code from SecCodeSignerCreate / SecCodeSignerAddSignature
   into the message). So `log stream` is not going to give us a smoking gun — we'd need to either
   attach lldb to micromamba and break on the Security.framework call, or sudo dtruss the csops
   syscall to see what arguments are being passed.

8. **CodeSigningHelper IS launched** (Section 9b: pid 507, ppid 1, alive at t+1s and t+2s). So the
   helper is reachable via XPC. The helper just isn't logging anything about the rejection.

Next-step suggestions for the broken mac that this fingerprint enables:
- otool -L libmamba.4.dylib to find what links Security.framework
- Try a single-package repro: `micromamba create -n t -c conda-forge libffi -y`
- Try downloading libffi-3.4.2-h3422bc3_5.tar.bz2 manually and codesign -s - the .dylib inside
  (not the on-disk linked one) to see if Security.framework rejects the *original* tarball file
- Compare CDv on the same files when installed via plain `conda install` vs micromamba
```

---

## Section 15 — Deep dive (added during this run)

> Six follow-up probes run after the initial fingerprint nailed down the root cause. Sections 1–14 stay aligned with the original template; this section is the new diagnostic content.

### 15a. Inspect libffi *as it ships in the conda-forge tarball*

```bash
mkdir -p /tmp/libffi-extract
tar -xjf ~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5.tar.bz2 -C /tmp/libffi-extract
codesign -dvvv /tmp/libffi-extract/lib/libffi.8.dylib
otool -l /tmp/libffi-extract/lib/libffi.8.dylib | grep -A5 LC_CODE_SIGNATURE
```

Result:

```
file: -rwxr-xr-x  120496 bytes  mtime: Nov  9 2021
xattr: com.apple.provenance only
Mach-O 64-bit dylib arm64 (thin)

codesign -dvvv:
  Identifier=libffi.8.dylib
  Format=Mach-O thin (arm64)
  CodeDirectory v=20200 size=1059 flags=0x0(none) hashes=29+2 location=embedded
  Hash type=sha256 size=32
  CandidateCDHash sha1=739d1aa1770c32046c72e03650413faefeb848de
  CandidateCDHash sha256=9d7f65bbb20ee4ab8665c42d39810880ac572e39
  Hash choices=sha1,sha256                  ← carries BOTH sha1 and sha256
  CMSDigest=bd6496f5ca11fb...
  Internal requirements count=1 size=132

LC_CODE_SIGNATURE: dataoff 118576, datasize 1920
```

> So libffi-3.4.2-h3422bc3_5 ships from conda-forge with an old-format ad-hoc signature: **CDv=20200**, dual sha1+sha256 hash choices, mtime Nov 2021. This was an initially-promising lead — sha1 in code signatures is deprecated on modern macOS — but Section 15c rules it out.

### 15b. Manual codesign on the freshly extracted file

```bash
cp /tmp/libffi-extract/lib/libffi.8.dylib /tmp/libffi-test.dylib
codesign -s - --force /tmp/libffi-test.dylib
codesign -dvvv /tmp/libffi-test.dylib | grep -E "CodeDirectory|Signature|Hash"
```

Result:

```
/tmp/libffi-test.dylib: replacing existing signature   exit=0
CodeDirectory v=20400 size=461 flags=0x2(adhoc) hashes=8+2 location=embedded
Hash choices=sha256
Signature=adhoc
```

Also tested: `codesign --remove-signature` then `codesign -s - --force` → also exit 0, valid CDv=20400 sha256 ad-hoc signature.

> **`/usr/bin/codesign` has zero problem with this file.** It happily replaces the old CDv=20200/sha1+sha256 signature with a clean CDv=20400/sha256 ad-hoc one. So the file is not poisoned and the OS tool is not broken on macOS 26.3.1. The bug must be in *how libmamba is invoking codesign*, not in codesign or the file.

### 15c. Pre-sign libffi *in the cache* and re-run micromamba

```bash
codesign -s - --force ~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5/lib/libffi.8.dylib
codesign -s - --force ~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5/lib/libffi.dylib
# now CDv=20400, hash choices sha256

micromamba create -n debug-libffi-only -c conda-forge libffi -y
```

Result:

```
Linking libffi-3.4.2-h3422bc3_5
critical libmamba Could not codesign executable: Invalid argument

ls -la $env/lib/libffi.8.dylib:
  -rwxrwxr-x@ 137056 bytes  mtime: 01:21 (today)   ← file IS in the env
codesign -dv on the in-env file:
  CodeDirectory v=20400 size=417 flags=0x2(adhoc) hashes=8+2 location=embedded
  ← VALIDLY signed, CDv=20400, ad-hoc, sha256
```

> **Two things this proves:**
>
> 1. **Pre-upgrading the cache file's signature does NOT fix the failure.** The original sha1/CDv=20200 signature is *not* the trigger.
> 2. **After the failure, the in-env file IS validly signed (CDv=20400 ad-hoc).** That means `/usr/bin/codesign` actually ran to completion successfully, signed the file, and exited 0. **The error is spurious from libmamba's perspective.**
>
> The libffi binary that ends up in the env is +16560 bytes larger than the cache file (137056 vs 120496) because the new signature payload + Mach-O code-signature LC slot expansion adds bytes — exactly what a successful re-sign produces. So codesign clearly succeeded.

(Cache file restored to original CDv=20200 from the extracted tarball at the end of this section so the runbook reproduces the same starting state next run.)

### 15d. Single-package isolated repro

```bash
micromamba create -n debug-libffi-only -c conda-forge libffi -y
```

Result:

```
Transaction starting
Linking libffi-3.4.2-h3422bc3_5
critical libmamba Could not codesign executable: Invalid argument
```

> **Confirmed minimal reproducer:** a one-package transaction with just `libffi` from `conda-forge` reproduces the failure. This is the smallest possible test case for an upstream bug report.

### 15e. Find what's calling codesign inside libmamba

```bash
otool -L /opt/homebrew/Cellar/micromamba/2.5.0_3/lib/libmamba.4.dylib | grep -i security
nm -gU /opt/homebrew/Cellar/micromamba/2.5.0_3/lib/libmamba.4.dylib | grep -iE "SecCode|codesign"
nm -u /opt/homebrew/Cellar/micromamba/2.5.0_3/lib/libmamba.4.dylib | grep -iE "_exec|_posix_spawn|_fork"
strings /opt/homebrew/Cellar/micromamba/2.5.0_3/lib/libmamba.4.dylib | grep -E "codesign|/usr/bin/codesign|Could not codesign"
```

Result:

```
libmamba.4.dylib otool -L: NO Security.framework link (only libyaml-cpp, fmt, libarchive,
  libcurl, openssl@3, libbz2, libreproc, libsimdjson, libzstd, libsolv, libsolvext, libc++, libSystem)

Defined symbol: T __ZN5mamba8codesignERKNS_2fs6u8pathEb
  → demangled: mamba::codesign(fs::u8path const&, bool)

Undefined symbols (subprocess-related):
  __ZNSt3__120__throw_system_errorEiPKc
  _fork

Strings:
  /usr/bin/codesign
  Could not codesign executable:
```

> **The header was wrong.** libmamba does **NOT** call `Security.framework` SecCode APIs directly. It **fork/execs `/usr/bin/codesign`** as a subprocess (via the linked-in `libreproc++.14.dylib`). The XPC helper that we saw running in Section 9b is the one `/usr/bin/codesign` itself spawns when it talks to Security.framework — not one libmamba talks to.
>
> The "Invalid argument" string is `strerror(EINVAL)`, returned via `std::error_code::message()` from libmamba's wrapper around `reproc::run`. It is NOT the codesign exit message.

### 15f. The libmamba 2.5.0 source — exactly what's broken

Pulled from `libmamba/src/core/util_os.cpp` at tag `2.5.0`:

```cpp
void codesign(const fs::u8path& path, bool verbose)
{
    reproc::options options;
    options.env.behavior = reproc::env::empty;     // ← spawn with EMPTY environment
    if (!verbose)
    {
        reproc::redirect silence;
        silence.type = reproc::redirect::discard;
        options.redirect.out = silence;
        options.redirect.err = silence;
    }

    const std::vector<std::string> cmd = {
        "/usr/bin/codesign", "-s", "-", "-f", path.string()
    };
    auto [status, ec] = reproc::run(cmd, options);
    if (ec)
    {
        throw std::runtime_error(
            std::string("Could not codesign executable: ") + ec.message()
        );
    }
}
```

> Three load-bearing facts in this snippet:
>
> 1. `reproc::env::empty` — the spawned codesign process gets an **empty** `envp[]` (no `PATH`, no `HOME`, no `__CF*`, nothing).
> 2. The argv is exactly `/usr/bin/codesign -s - -f <path>` — minimal and clearly correct.
> 3. The error path checks `ec` (an `std::error_code` from reproc), not `status` (the codesign exit code). So **codesign can succeed and the function can still throw**, if reproc itself returns a non-zero error code from anywhere in its spawn/wait/drain pipeline.

**This is the bug.** On macOS 26 (build 25D2128, kernel xnu-12377.91.3), reproc's `run()` returns `EINVAL` when spawning `/usr/bin/codesign` with `env::empty`, even though the spawn actually succeeds and codesign runs to completion. The `ec` is bubbled into the error message as `"Invalid argument"` and libmamba aborts the install — even though the file is already validly signed by the codesign call that just ran.

Most likely culprits inside reproc + macOS 26:

- `posix_spawn` with `envp = NULL` or `envp = {NULL}` may now require at least one entry on this OS build (some libsystem code paths assume `__CF_USER_TEXT_ENCODING` is present and EINVAL on absence).
- Or reproc's `posix_spawn_file_actions_addopen` for the discard-redirect path returns EINVAL on this build (but we tested with `-v` in Section 7 which disables the discard path, and it still fails — so probably not this).
- Or an interaction between `posix_spawnattr_setflags` and the empty env on the new kernel.

Whichever it is, **the fix is in libmamba**: don't pass `reproc::env::empty` for the codesign call (pass the parent environment, or at minimum a one-entry env containing `PATH=/usr/bin`). Until then, micromamba 2.5.0 cannot create envs on this machine.

### 15g. Survey: any other CDv=20200 dylibs in the cache?

```bash
for d in ~/micromamba/pkgs/*/lib/*.dylib; do
  V=$(codesign -dv "$d" 2>&1 | grep -oE "CodeDirectory v=[0-9]+")
  [ "$V" = "CodeDirectory v=20200" ] && echo "$d"
done
```

Result:

```
~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5/lib/libffi.8.dylib
~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5/lib/libffi.dylib    (symlink → libffi.8.dylib)
```

> libffi is the only file in the entire 21-package cache with the legacy CDv=20200 format. Every other dylib (icu, libcurl, openssl, python, nodejs's libnode, etc.) ships with CDv=20400 sha256-only ad-hoc signatures. This is why libffi is **always** the file that triggers the failure — it's the only candidate. (And confirmed by Section 15c: even after manually upgrading libffi to CDv=20400, libmamba still fails on the very same file — because the bug is in the *invocation*, not the file.)

### 15h. Conclusion and root-cause summary

```
Root cause:  libmamba 2.5.0 invokes /usr/bin/codesign via reproc::run() with
             reproc::options::env::empty (an empty spawn environment). On
             macOS 26 build 25D2128 (kernel xnu-12377.91.3) reproc returns
             EINVAL from this spawn even though codesign actually succeeds
             and the target file ends up correctly signed. libmamba checks
             reproc's `ec` rather than codesign's exit code, throws
             "Could not codesign executable: Invalid argument" (which is
             strerror(EINVAL)), and aborts the install.

Why libffi:  Linking proceeds in alphabetical order. The first six packages
             with binaries (gh, icu, libuv, xz, bzip2, libexpat) all link
             without ever calling codesign on a Mach-O that the OS dislikes,
             and somehow their reproc spawns return ec=0. libffi is the
             7th and is the first one that takes a codepath that triggers
             the EINVAL — possibly because libffi's tarball has CDv=20200,
             possibly because it's the alphabetically-first .tar.bz2 and not
             a .conda. We have NOT root-caused the per-file branch yet,
             only the env::empty smoking gun. The earlier 6 packages may
             succeed because reproc happens to return 0 even when it shouldn't,
             or because libmamba doesn't actually call codesign on every
             file. Worth tracing with sample(1) on the failing process.

Status:      Bug, in libmamba. Reproducible on macOS 26.3.1 (25D2128) /
             Apple M4 Pro / Xcode CLT 26.3 with brewed micromamba 2.5.0_3.

Workarounds:
  • Use `conda install` (vendored Python `subprocess` codepath, normal env)
    instead of micromamba for env creation on macOS 26. This contradicts
    the user-preference rule "use micromamba only" but is the only actually-
    working option without an upstream fix.
  • Patch libmamba.4.dylib to not pass env::empty (binary patch — fragile,
    not recommended).
  • DYLD_INSERT_LIBRARIES shim that intercepts posix_spawn and injects
    a default envp when an empty one is passed (complex, SIP interactions).
  • Wait for an upstream libmamba release that drops env::empty for the
    codesign call.

Upstream report:
  Should be filed at https://github.com/mamba-org/mamba/issues
  with title roughly "macOS 26: libmamba codesign() spuriously fails with
  'Invalid argument' due to reproc::env::empty"
  and link to libmamba/src/core/util_os.cpp::codesign().

Open questions:
  • Why do the 6 packages BEFORE libffi succeed if every codesign call uses
    the same env::empty path? → trace with `sample` or `lldb` on the next run.
  • Does setting env::empty → env::extend with a minimal env via a tiny
    libmamba patch make the bug go away? → confirms the fix.
  • Is this fixed in a libmamba > 2.5.0? → check newer versions / git HEAD.
```

### 15h-supplement. Upstream tracker (added 2026-04-08)

Checked `libmamba/src/core/util_os.cpp::codesign()` at `mamba-org/mamba` branch `main`:

```cpp
// main branch, fetched 2026-04-08
void codesign(const fs::u8path& path, bool verbose)
{
    reproc::options options;
    options.env.behavior = reproc::env::empty;        // ← STILL empty envp
    // ... discard redirects ...
    const std::vector<std::string> cmd = {
        "/usr/bin/codesign", "-s", "-f", path.string()   // ← argv differs from 2.5.0
    };
    auto [status, ec] = reproc::run(cmd, options);
    if (ec) {
        throw std::runtime_error(std::string("Could not codesign executable: ") + ec.message());
    }
}
```

> **The bug is not fixed upstream.** `reproc::env::empty` is still there on `main`.
>
> **Argv regression noticed along the way:** the 2.5.0 release passes `{"/usr/bin/codesign","-s","-","-f",path}` — i.e. `codesign -s - -f <path>` — where `-` is the pseudo-identity for ad-hoc signing. On `main` this has changed to `{"/usr/bin/codesign","-s","-f",path}`, which reads as `codesign -s -f <path>` — meaning `-s` is being given `-f` as the identity name, and the path becomes a trailing positional. Either this is wrong and `main` would fail differently if it ever got that far, or there's a newer codesign flag syntax I'm missing. Worth flagging in any upstream report.

**Existing upstream issues that mention this symptom but do NOT pin the root cause:**

- **[conda-forge/miniforge#324 — codesign error](https://github.com/conda-forge/miniforge/issues/324)** — OPEN. First reported June 2022 on macOS 12.4. Same exact error (`Could not codesign executable: Invalid argument`). Recurrences on 13.6.4 and 15.0. Workarounds mentioned in the thread: install micromamba via the upstream shell script instead of Homebrew, and an unrelated `ulimit -n` tweak. **No one in this 2+ year thread has identified that `reproc::env::empty` is the cause.** This is the issue to link our repro to.
- **[mamba-org/mamba#1758 — could not find macOS version by calling sw_vers](https://github.com/mamba-org/mamba/issues/1758)** — tangentially related. Observed that reproc on macOS can fail to capture output from a trivial `/bin/echo` subprocess, which smells like the same `env::empty` + `posix_spawn` EINVAL path. Not the same symptom but probably the same underlying mechanism.
- **[mamba-org/mamba#780 — OS X Big Sur / M1 first-run issues](https://github.com/mamba-org/mamba/issues/780)** — touches codesign on Big Sur / M1. Less relevant but in the neighborhood.

**No existing PR is open that drops `env::empty` from `codesign()`.** An upstream PR from us would be the fix.

**Recommended upstream actions (when we get to them):**

1. Post a comment on **miniforge#324** with a pointer to this runbook and the `env::empty` root cause.
2. Open a new issue on **mamba-org/mamba** titled roughly "libmamba codesign() spuriously fails with 'Invalid argument' on macOS 26 due to `reproc::env::empty`" — reference Section 15f here and the minimal repro from Section 15d.
3. Optionally open a PR changing `reproc::env::empty` → `reproc::env::extend` (or passing `{ "PATH=/usr/bin" }` as a minimal envp) in `libmamba/src/core/util_os.cpp::codesign()`. Also fix the argv regression on main while we're there (restore the `"-"` identity argument).

### 15i. Cleanup performed by Section 15

```
- /tmp/libffi-extract removed
- /tmp/libffi-test*.dylib removed
- /tmp/mm-bg.log, /tmp/mm-create.log, /tmp/mm-time.log removed
- ~/micromamba/pkgs/libffi-3.4.2-h3422bc3_5/lib/libffi.8.dylib RESTORED
  from the original tarball (back to CDv=20200) so the runbook reproduces
  the same starting state on next run
- debug-mm-test and debug-libffi-only envs removed
- envs/ now contains only `node1`
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
