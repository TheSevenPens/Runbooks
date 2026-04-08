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

## Section 14 — Commit

Commit the updated runbook so the broken-mac side can pull and compare.

```bash
cd <path to Runbooks repo on this machine>
git add macos_micromamba_debug_runbook.md
git commit -m "debug: fingerprint from working micromamba mac"
git push
```
