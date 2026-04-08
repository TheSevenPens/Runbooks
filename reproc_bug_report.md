# Draft comment for reproc #82 / PR #103

> **Status:** Draft. Not a new issue. Intended as a comment to add to existing upstream work:
>
> - **Primary target:** [`DaanDeMeyer/reproc#82` — "run fails when ulimit is set over 1024²"](https://github.com/DaanDeMeyer/reproc/issues/82). The bug is already identified there; this comment adds fresh macOS 26 confirmation, a one-file C++ reproducer, and a separate stale-errno finding.
> - **Secondary target:** [`DaanDeMeyer/reproc#103` — "Only close open file descriptors"](https://github.com/DaanDeMeyer/reproc/pull/103). If (after reading the PR) the change looks like it would fix our reproducer, the more useful action is to test the PR against our repro and post the result there as a "confirmed fix" data point to help it get merged.
> - **Separate novel issue:** If the stale-errno mechanism (described below in the second part of this draft) isn't already in the thread, it's a distinct bug that's been masking #82 by producing `EINVAL` instead of `EMFILE` in every report. It may deserve its own focused issue once #82 is resolved, so the two stories don't get entangled.
>
> This file holds the draft comment text. Polish and post when ready.

---

## Part 1 — Comment for reproc#82: fresh macOS 26 data point and a self-contained reproducer

Hi — long-time Miniconda user on Windows, trying micromamba on macOS for the first time, and I hit exactly this on a fresh macOS 26 install. I spent a while on the wrong hypothesis (I initially thought it was a `codesign` / `env::empty` / `posix_spawn` issue, since the surface symptom in libmamba is `"Could not codesign executable: Invalid argument"`) before I found this issue and realized the bug has been known for years. A few pieces of new-ish information that might be useful:

### Still broken on macOS 26 (Tahoe)

Confirmed on two independent machines:
- macOS 26.3.1 (build 25D2128) and 26.4 (build 25E246)
- Apple M4 Pro (arm64)
- Default shell is `zsh` with Oh My Zsh
- **`ulimit -n` is `unlimited` out of the box** — this appears to be the new default on macOS 26. Earlier macOS versions had a modest default, which is why the bug became much more visible on 26.
- reproc 14.2.5 from Homebrew, and also built from `main` (which is at `v14.2.5`). Both reproduce identically.
- Xcode Command Line Tools 26.3.0 and 26.4.0 both reproduce.

### Minimal reproducer (no libmamba, no conda, no codesign)

About 30 lines of C++ against reproc14. All it does is call `reproc::run({"/bin/echo", "hello"})` a few times:

```cpp
// repro.cpp
// build: clang++ -std=c++17 repro.cpp \
//          -I/opt/homebrew/include -L/opt/homebrew/lib \
//          -lreproc++ -lreproc -o repro

#include <reproc++/run.hpp>
#include <reproc++/reproc.hpp>
#include <iostream>
#include <vector>
#include <string>

static void try_run(const char *label, std::vector<std::string> cmd,
                    reproc::env::type behavior)
{
    reproc::options options;
    options.env.behavior = behavior;
    auto [status, ec] = reproc::run(cmd, options);
    std::cout << label
              << " → status=" << status
              << ", ec=" << ec.value()
              << " (" << ec.message() << ")\n";
}

int main()
{
    std::vector<std::string> echo = {"/bin/echo", "hello"};
    std::vector<std::string> t    = {"/usr/bin/true"};

    try_run("echo / env::extend", echo, reproc::env::extend);
    try_run("echo / env::empty ", echo, reproc::env::empty);
    try_run("true / env::extend", t,    reproc::env::extend);
    try_run("true / env::empty ", t,    reproc::env::empty);
    return 0;
}
```

On a default macOS 26 shell (`ulimit -n` = unlimited):

```
echo / env::extend → status=-1, ec=22 (Invalid argument)
echo / env::empty  → status=-1, ec=22 (Invalid argument)
true / env::extend → status=-1, ec=22 (Invalid argument)
true / env::empty  → status=-1, ec=22 (Invalid argument)
```

With `ulimit -n 1024` beforehand:

```
echo / env::extend → status=0, ec=0 (Success)
echo / env::empty  → status=0, ec=0 (Success)
true / env::extend → status=0, ec=0 (Success)
true / env::empty  → status=0, ec=0 (Success)
```

I also tested the lower-level `reproc::process::start()` API directly (same 4 combinations): all 8 variations fail at `process::start()` itself, so the failure is well before any drain/read step. `env::empty` vs `env::extend` makes no difference. Command (`echo` vs `true`) makes no difference.

As an additional sanity check, I wrote a plain C program using `posix_spawn` directly (not reproc) against `/bin/echo` with the same envp variants: it works perfectly on macOS 26. So the underlying OS spawn syscalls are healthy — this is strictly about how reproc's fork-based child cleanup code path interacts with `RLIMIT_NOFILE = RLIM_INFINITY`.

### What I'd like to help with

I don't know the reproc codebase well enough to send a PR myself, but:

- If **PR #103 ("Only close open file descriptors")** would fix this, I'm happy to test it against the reproducer above on both of my macOS 26 machines and post the result back here or on that PR. Is that useful? If the PR is close to mergeable, a confirmed-fix data point from a fresh macOS 26 setup might help nudge it across the line.
- If a different direction is preferred (e.g., clamping `get_max_fd()` return value to `min(soft, 16384)` when `RLIM_INFINITY` is reported, or `close_range(2)` where available), I can test that too.

Thanks for reproc — and apologies for adding to a three-year-old thread. I figured fresh macOS 26 data and a clean standalone reproducer might be more useful than opening a duplicate issue.

---

## Part 2 — Draft for a possibly separate issue: stale `errno` in `process_fork()`'s `finish:` path produces misleading error messages

> **Target:** probably a new issue on `DaanDeMeyer/reproc`, once #82 is resolved (or a separate comment on #82 if a maintainer prefers). This is a distinct bug from the fd-limit one, but it's been masking #82 in every user-visible report by reporting `EINVAL` instead of the real `EMFILE`. I don't want to entangle the two, so I'm holding this draft until #82 moves.
>
> **Suggested title:** `process_fork() finish: writes stale errno (often EINVAL from sigaction(0)) instead of -r, producing misleading error messages`

### Summary

When anything in the child side of `process_fork()` (in `src/process.posix.c`) sets `r < 0` and jumps to `finish:`, the child reports `errno` — not the negated `-r` — to the parent over the error pipe. In most failure paths, `errno` at that point is stale from an intentionally-ignored `sigaction(signal=0)` call earlier in the same function. The net effect is that parents consistently see `EINVAL ("Invalid argument")` regardless of what actually went wrong.

This is why reproc#82 (which is actually an `EMFILE` / "we refuse to iterate over INT_MAX file descriptors" issue) has been surfacing as "Invalid argument" for years, misleading everyone who's tried to debug it — including me, for most of today.

### The code path

In `process_fork()`, the child process resets all signal handlers:

```c
for (int signal = 0; signal < 32; signal++) {
    r = sigaction(signal, &action, NULL);
    if (r < 0 && errno != EINVAL) {
        r = -errno;
        goto finish;
    }
}
```

`sigaction(signal=0, ...)` returns `-1` with `errno = EINVAL` because signal 0 isn't a valid signal number. The loop specifically ignores `EINVAL`, which is fine — but `errno` stays set to `EINVAL` after the loop, because nothing clears it.

Then later, when (for example) the `get_max_fd() > MAX_FD_LIMIT` check fires:

```c
if (max_fd > MAX_FD_LIMIT) {
    r = -EMFILE;
    goto finish;
}
```

`r` is set to `-EMFILE` (24), but `errno` is still `EINVAL` (22) from the earlier ignored sigaction call. The `finish:` handler writes `errno`, not `-r`, to the parent's error pipe:

```c
finish:
    if (r < 0) {
        (void) !write(pipe.write, &errno, sizeof(errno));
        _exit(EXIT_FAILURE);
    }
```

So the parent reads `22 (EINVAL / "Invalid argument")` instead of the real `24 (EMFILE / "Too many open files")`. Every downstream reproc user sees a misleading error.

### Suggested fix

Use `-r` (or a local `int err = -r`) instead of `errno` at the `finish:` write, so the value reported to the parent reflects the actual reason the child decided to fail:

```c
finish:
    if (r < 0) {
        int err = -r;
        (void) !write(pipe.write, &err, sizeof(err));
        _exit(EXIT_FAILURE);
    }
```

This is a small, low-risk change that would have dramatically shortened a lot of downstream debugging sessions, including #82 itself and probably [conda-forge/miniforge#324](https://github.com/conda-forge/miniforge/issues/324) (which has been OPEN since 2022 with the same misleading "Invalid argument" symptom).

### Caveats

I haven't patched reproc locally to confirm this specific change produces the expected value at the parent side. The stale-errno explanation is my reading of the code rather than a patched-build confirmation. I'd appreciate a sanity check on that specific mechanism from anyone familiar with the fork-pipe error protocol.

---

## Appendix: environment details

Shared context for both parts above:

| | |
|---|---|
| OS | macOS 26.3.1 (build 25D2128) and 26.4 (build 25E246) — both reproduce |
| Kernel | Darwin 25.3.0 (`xnu-12377.91.3`) |
| Hardware | Apple M4 Pro (arm64), two machines tested |
| Default shell | zsh with Oh My Zsh |
| `ulimit -n` (soft) | `unlimited` — macOS 26 default |
| `ulimit -n` (hard) | `unlimited` |
| reproc from Homebrew | formula 14.2.5, dylib soname 14.2.4 |
| reproc built from `main` | `git describe --tags` → `v14.2.5` — same failure |
| Xcode CLT | 26.3.0 and 26.4.0 — both reproduce |
