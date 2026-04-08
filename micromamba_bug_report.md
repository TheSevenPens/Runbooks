# Draft comment for mamba #1758

> **Status:** Draft. Not a new issue. Intended as a comment to add to [`mamba-org/mamba#1758` — "could not find macOS version by calling sw_vers"](https://github.com/mamba-org/mamba/issues/1758), which is the already-existing (since 2022) OPEN issue tracking the user-visible mamba/micromamba symptom of the reproc `ulimit -n` bug.
>
> **Context for us:** reading #1758 carefully, the thread already has the root cause (`ulimit -n unlimited` → reproc can't spawn), the workaround (`ulimit -n` to a finite value), cross-references to [reproc#82](https://github.com/DaanDeMeyer/reproc/issues/82), and at least one report from 2024 saying the workaround "doesn't always work on M2 Macs." The thread doesn't appear to have (a) a fresh macOS 26 data point, (b) a specific recommended ulimit value with a principled basis, or (c) a discussion of defense-in-depth changes libmamba could make on its own side even before reproc is fixed. Those three things are what this comment adds.
>
> This file holds the draft comment text. Polish and post when ready.

---

## Draft comment for mamba#1758

Hi — adding a fresh data point and a couple of small suggestions. I went through this exact debugging rabbit hole earlier today (as a first-time macOS user on 26 coming from Miniconda on Windows) and found this thread only after I'd convinced myself the problem was in `codesign()`, then in `env::empty`, then in `posix_spawn`, then finally in `get_max_fd()` — at which point I discovered #1758 and [reproc#82](https://github.com/DaanDeMeyer/reproc/issues/82) already had the answer. A few things I can contribute:

### Still broken on macOS 26 (Tahoe)

In case it's useful for confirming the scope of the bug across recent macOS versions:

- Reproduced on macOS 26.3.1 (25D2128) and 26.4 (25E246).
- Apple M4 Pro, two independent machines.
- Fresh zsh with Oh My Zsh. `ulimit -n` is **unlimited** by default on macOS 26 — this seems to be a new default, and is probably why the symptom has become much more visible recently.
- `brew install micromamba` → 2.5.0.
- `micromamba create -n foo -c conda-forge libffi -y` fails every time with `critical libmamba Could not codesign executable: Invalid argument`. (A single-package transaction with just `libffi` is enough — no need for a full `nodejs python gh` set.)
- Not fixed by macOS point updates, Xcode CLT updates, `CONDA_OVERRIDE_OSX`, or `CONDA_SOLVER=classic`.

### The specific `ulimit -n` value that works

The thread mentions `ulimit -n 1000000` as a workaround. That number works, but I think it's worth noting where it comes from: reproc's `process.posix.c` has `MAX_FD_LIMIT = 1024 * 1024 = 1,048,576`, and the guard is `if (max_fd > MAX_FD_LIMIT) r = -EMFILE`. So any value **≤ 1,048,576** slips under the check. `1,000,000` works by coincidence — it's less than `1 << 20`. If someone in the future bumps the `MAX_FD_LIMIT` constant, the `1000000` workaround might silently stop being sufficient (well, it'd become stricter than needed, not looser, so it'd be fine — but it's worth knowing the actual boundary).

**`ulimit -n 1024` is the most conservative workaround I'd recommend** for docs or for hardcoding into wrapper scripts. It's comfortably below the cap, it's a round number, and it's close to the historical macOS default. On my machine it makes `micromamba create -n foo -c conda-forge libffi -y` succeed end to end, producing a correctly signed `libffi.8.dylib`:

```
CodeDirectory v=20400 size=1127 flags=0x2(adhoc) hashes=30+2 location=embedded
Signature=adhoc
```

### Note on `@mathbunnyru`'s "workaround doesn't always work on M2 Macs" report

I'm on M4 Pro, not M2, and the `ulimit -n 1024` workaround is 100% reliable for me on both of my machines. If anyone reading this is still hitting the failure after `ulimit -n 1024`, I'd be interested to know what the actual `ulimit -n` value reports *inside* the failing shell (some shell plugins or Oh My Zsh themes can reset it after `.zshrc` runs, and what you set in `.zshenv` or `.zprofile` isn't always what's active when the command runs).

### One finding that doesn't seem to be in the existing threads

The error message everyone sees is `"Invalid argument"` (EINVAL = 22). But the actual failure reproc hits is `-EMFILE` (24) — reproc refuses to spawn because `get_max_fd()` returns `INT_MAX` for `RLIM_INFINITY`, which exceeds the `MAX_FD_LIMIT = 1,048,576` guard. The reason the parent sees EINVAL instead of EMFILE is that reproc's child-side `finish:` handler writes `errno` (not `-r`) to the parent's error pipe, and `errno` at that point is stale from an intentionally-ignored `sigaction(signal=0)` call in the same function (which deliberately returns `EINVAL`). So the real error is `EMFILE`, but the value that reaches the parent is `EINVAL`. That's why this bug has been so frustrating to debug for so many people: the error message is pointing at the wrong thing.

I've filed a separate note on reproc#82 about the stale-errno reporting (it's a distinct bug from the fd-limit one, but it's been masking it in every downstream report). If that cosmetic fix lands, future debugging sessions for reproc-on-macOS issues should be significantly shorter.

### A few defensive things libmamba could consider

These are offered as questions, not as firm asks. The root cause is upstream in reproc and the real fix is [reproc PR #103](https://github.com/DaanDeMeyer/reproc/pull/103). But there are things libmamba could do on its own side that would insulate users from this class of reproc bug, even before (or regardless of) the upstream fix shipping. In rough priority order:

**1. A more actionable error message.** Right now `codesign()` in `util_os.cpp` throws with the raw reproc `ec.message()`, which is the literal string `"Invalid argument"`. That tells a user nothing about what went wrong or how to fix it. Could libmamba's `codesign()` wrap the error with something like:

```
Failed to codesign <path>: <reproc_message>.
On macOS, this can happen when `ulimit -n` is unlimited.
See https://github.com/DaanDeMeyer/reproc/issues/82 and try:
    ulimit -n 1024
before running this command.
```

The `ulimit` hint could be gated on `target_platform == osx-arm64 && getrlimit(RLIMIT_NOFILE).rlim_cur == RLIM_INFINITY`, so it only appears when it's actually relevant. Would a PR in this direction be welcome?

**2. Temporarily lower `RLIMIT_NOFILE` around the reproc call.** Since libmamba knows it's about to call reproc, and reproc has this known interaction with unlimited `RLIMIT_NOFILE`, libmamba could temporarily cap the limit around the call:

```cpp
void codesign(const fs::u8path& path, bool verbose)
{
    struct rlimit original;
    getrlimit(RLIMIT_NOFILE, &original);
    if (original.rlim_cur == RLIM_INFINITY || original.rlim_cur > 1024 * 1024) {
        struct rlimit capped = original;
        capped.rlim_cur = 1024;
        setrlimit(RLIMIT_NOFILE, &capped);
    }

    // ... existing reproc call ...

    setrlimit(RLIMIT_NOFILE, &original);  // restore
}
```

This is a belt-and-suspenders fix that would route around the reproc bug entirely without depending on an upstream release. I'm not sure whether mutating `RLIMIT_NOFILE` inside a library call is considered polite in libmamba's style — there may be good reasons not to touch the process-wide limit. Thoughts?

**3. A known-issues entry in the docs.** Users on existing libmamba releases are going to keep hitting this for a while. A docs entry — even just a short "if you see `Could not codesign executable: Invalid argument` on macOS, run `ulimit -n 1024`" — would save people the same debugging session.

### In summary

- Confirming this is still live on macOS 26.
- `ulimit -n 1024` is a clean principled value for the workaround.
- Flagging a separate stale-errno finding on reproc#82 that explains why the error message has been so misleading.
- Asking whether any of the defense-in-depth suggestions above would be welcome PRs.

Thanks for mamba — and apologies for landing on an old thread. Happy to test any patch against my reproducer setup.

---

## Context for us (not for posting)

### Reproducer (micromamba level)

```bash
brew install micromamba
micromamba shell init -s zsh -r ~/micromamba
# open a new terminal
micromamba create -n repro -c conda-forge libffi -y
# → fails: critical libmamba Could not codesign executable: Invalid argument
```

Workaround:

```bash
ulimit -n 1024
micromamba create -n repro2 -c conda-forge libffi -y
# → Transaction finished
```

### Environment details

| | |
|---|---|
| OS | macOS 26.3.1 (25D2128) and 26.4 (25E246) |
| Hardware | Apple M4 Pro (arm64), two machines |
| Default shell | zsh with Oh My Zsh |
| `ulimit -n` (default on macOS 26) | `unlimited` |
| micromamba | 2.5.0 from Homebrew, 1.5.10 standalone — both reproduce |
| libmamba | tag `2.5.0` and current `main` |
| reproc | dynamically linked from `/opt/homebrew/opt/reproc`, formula 14.2.5, dylib soname 14.2.4 |

### Cross-references

- Upstream root cause: [`DaanDeMeyer/reproc#82`](https://github.com/DaanDeMeyer/reproc/issues/82) (OPEN)
- Upstream fix in progress: [`DaanDeMeyer/reproc#103` — "Only close open file descriptors"](https://github.com/DaanDeMeyer/reproc/pull/103) (OPEN, not merged)
- Related long-running symptom thread: [`conda-forge/miniforge#324`](https://github.com/conda-forge/miniforge/issues/324) (OPEN since 2022)
- Our draft for reproc#82: `reproc_bug_report.md` in this repo
- Our full investigation: `macos_micromamba_debug_runbook.md` Section 15
