# Bug report draft: reproc refuses to spawn on macOS 26 because default unlimited `RLIMIT_NOFILE` trips `get_max_fd()` → `MAX_FD_LIMIT` guard

> **Status:** Draft. File against `DaanDeMeyer/reproc`.
>
> **Target repo:** https://github.com/DaanDeMeyer/reproc/issues
>
> **Suggested title:** `macOS 26 default ulimit breaks reproc: get_max_fd() returns INT_MAX for RLIM_INFINITY, process_fork() rejects via MAX_FD_LIMIT with -EMFILE, child reports stale EINVAL to parent`
>
> **Follow-up repo (after reproc):** I should probably also post a short note on [`conda-forge/miniforge#324`](https://github.com/conda-forge/miniforge/issues/324), because that 2+ year old thread has the same symptom and one of the commenters found the `ulimit -n` workaround by accident — now we'd know why it worked.

---

## Context

I'm a long-time Miniconda user on Windows and was experimenting with micromamba as a lighter drop-in alternative. I'm now starting to use macOS and hit a persistent failure on `micromamba create` with an error about being unable to codesign an executable. After some debugging the codesign framing turned out to be a red herring — the real issue is in reproc. I'm not a reproc contributor and this is the first time I've read the reproc source, so I may be off on some details, but I've narrowed the behavior down pretty concretely and have a clean reproducer.

## One-paragraph summary

On macOS 26 (Tahoe), the default shell has `ulimit -n` set to **unlimited** (`RLIM_INFINITY`). When reproc's `get_max_fd()` sees that, it returns `INT_MAX`. The next check in `process_fork()` then rejects anything above `MAX_FD_LIMIT = 1024 * 1024` and sets `r = -EMFILE`, so reproc refuses to spawn any process at all. As a secondary issue, the error that ends up in the parent's error pipe isn't `EMFILE` — it's `EINVAL`, because the child writes stale `errno` (left set to `EINVAL` by an intentionally-ignored `sigaction(signal=0)` call earlier in the same function) rather than `-r`. The visible result is that every `reproc::run` / `reproc::process::start` call on a fresh macOS 26 user account returns `ec = 22 (Invalid argument)`, and downstream consumers of reproc like micromamba break in confusing ways. Lowering `ulimit -n` to 1024 (or any value ≤ 1,048,576) before running the affected program is a complete workaround.

## Downstream impact

I originally found this through `micromamba` (mamba-org's standalone package manager, which links reproc dynamically for its codesign step during package linking). On a fresh macOS 26 user account, `micromamba create -n foo -c conda-forge libffi -y` fails with:

```
critical libmamba Could not codesign executable: Invalid argument
```

…which is actually libmamba's `codesign()` function calling `reproc::run("/usr/bin/codesign", ...)`, reproc refusing to spawn, and libmamba surfacing the reproc-reported `EINVAL` message verbatim in the exception it throws. With `ulimit -n 1024` set in the shell, the same `micromamba create` command succeeds and produces a correctly signed output:

```
CodeDirectory v=20400 size=1127 flags=0x2(adhoc) hashes=30+2 location=embedded
Signature=adhoc
```

So the ulimit workaround is also a complete workaround for the downstream symptom.

Several symptoms in [conda-forge/miniforge#324](https://github.com/conda-forge/miniforge/issues/324) (OPEN since June 2022, same exact error message) look like the same bug — including a comment from one user who reported that dropping `ulimit -n` from unlimited to 1,000,000 fixed the error for them. That user landed on the workaround by coincidence: 1,000,000 happens to be less than `MAX_FD_LIMIT = 1,048,576` and so slips under the check.

Once this is fixed in reproc, I'll ping that thread so the miniforge folks can close it.

## Environment

| | |
|---|---|
| OS | macOS 26.3.1 (build 25D2128) and 26.4 (build 25E246) — both reproduce |
| Kernel | Darwin 25.3.0 (`xnu-12377.91.3`) |
| Hardware | Apple M4 Pro (arm64), two machines tested |
| Default shell | zsh with Oh My Zsh |
| `ulimit -n` (soft) | `unlimited` |
| `ulimit -n` (hard) | `unlimited` |
| reproc from Homebrew | 14.2.5 formula, dylib soname 14.2.4 |
| reproc built from `main` | `git describe --tags` → `v14.2.5` (same as the current release; HEAD == v14.2.5) — same failure |

## Minimal reproducer

About 30 lines of C++ against reproc14. No libmamba, no conda, no codesign. Full source at the bottom of this report if useful.

```bash
# Assuming reproc is installed via Homebrew (brew install reproc)
clang++ -std=c++17 repro.cpp \
  -I/opt/homebrew/include -L/opt/homebrew/lib \
  -lreproc++ -lreproc -o repro
./repro
```

All the program does is call `reproc::run({"/bin/echo", "hello"})` a few times with different `env::behavior` settings. On my machine it prints:

```
[reproc::run]  echo / env::extend → status=-1, ec=22 (Invalid argument)
[reproc::run]  echo / env::empty  → status=-1, ec=22 (Invalid argument)
[reproc::run]  true / env::extend → status=-1, ec=22 (Invalid argument)
[reproc::run]  true / env::empty  → status=-1, ec=22 (Invalid argument)
```

Eight variations in total (I also tested the lower-level `reproc::process::start()` API directly). **All eight fail the same way**, with `EINVAL`, regardless of command, envp behavior, or API level.

But:

```bash
ulimit -n 1024 && ./repro
```

…every call succeeds. `status=0, ec=0`. The shell-level `ulimit` setting completely determines whether reproc can spawn anything.

## What I expected vs. what actually happens

| Item | Expected | Actual |
|---|---|---|
| `reproc::run({"/bin/echo", "hello"})` | `status=0`, `ec=0`, `hello` printed on stdout | `status=-1`, `ec=22 ("Invalid argument")`, no output |
| `/bin/echo` itself | Works | Works (direct `posix_spawn`-based C test works fine — see below) |
| macOS `fork()` / `execvp()` | Works | Works (verified by writing a plain C program using fork+execvp that runs `/bin/echo` successfully) |
| Changing `ulimit -n` from `unlimited` to `1024` | No effect on reproc's behavior | Every reproc call starts working |

The third row is what narrowed it down for me — I first assumed reproc was just wrapping `posix_spawn`, and when I wrote a standalone C program using `posix_spawn` directly it worked perfectly on macOS 26 with every envp variant. That made me go look at what reproc actually does, which is `fork() + execvp()` + a child-side cleanup loop, not `posix_spawn`. That's where I found `get_max_fd()`.

## What I think is happening

Walking through `reproc/src/process.posix.c` on the `v14.2.5` tag:

```c
static const int MAX_FD_LIMIT = 1024 * 1024;

static int get_max_fd(void)
{
    struct rlimit limit = { 0 };
    int r = getrlimit(RLIMIT_NOFILE, &limit);
    if (r < 0) {
        return -errno;
    }
    rlim_t soft = limit.rlim_cur;
    if (soft == RLIM_INFINITY || soft > INT_MAX) {
        return INT_MAX;
    }
    return (int) (soft - 1);
}
```

And in `process_fork()` (child side, before `execvp`):

```c
r = get_max_fd();
if (r < 0) {
    goto finish;
}
int max_fd = r;
if (max_fd > MAX_FD_LIMIT) {
    // Refuse to try to close too many file descriptors.
    r = -EMFILE;
    goto finish;
}
for (int i = 0; i < max_fd; i++) {
    // close every fd that's not in the except list
    ...
}
```

On macOS 26, the shell starts with `ulimit -n` unlimited, so `getrlimit(RLIMIT_NOFILE)` returns `RLIM_INFINITY`, `get_max_fd()` returns `INT_MAX = 2,147,483,647`, that's much greater than `MAX_FD_LIMIT = 1,048,576`, and the child sets `r = -EMFILE` and jumps to `finish:`. Which is a reasonable safeguard against a 2-billion-iteration fd-close loop — I'm not complaining about the check existing. But it means reproc is completely unusable on macOS 26 out of the box, because the default user shell has that unlimited value.

### The cosmetic second issue

At `finish:` the child writes its error back to the parent over the error pipe:

```c
finish:
    if (r < 0) {
        (void) !write(pipe.write, &errno, sizeof(errno));
        _exit(EXIT_FAILURE);
    }
```

Notice it's writing `errno`, not `-r` / `abs(r)`. If I'm reading it right, the value that ends up being read by the parent is whatever the most recently failing syscall left in `errno` — which might or might not be the thing that actually caused the child to jump to `finish`.

In this specific code path, `errno` at the point of the `-EMFILE` set is stale from the signal-reset loop a few hundred lines up:

```c
for (int signal = 0; signal < 32; signal++) {
    r = sigaction(signal, &action, NULL);
    if (r < 0 && errno != EINVAL) {   // ← intentionally ignoring EINVAL
        r = -errno;
        goto finish;
    }
}
```

`sigaction(signal=0, ...)` deliberately returns `-1` with `errno = EINVAL` because signal 0 isn't valid, and that loop specifically ignores `EINVAL`. But it doesn't clear `errno`, so `errno` stays `EINVAL` through the rest of the function. When the EMFILE branch fires and the child writes `errno` to the pipe, what gets reported to the parent is `22 (EINVAL)` — *not* `24 (EMFILE)`.

That's why every downstream reproc user on macOS 26 gets a mysterious "Invalid argument" error instead of a more-informative "Too many open files" / EMFILE. If this had been reported as EMFILE from the start, I suspect the connection to `ulimit -n` would have been obvious to one of the people in [miniforge#324](https://github.com/conda-forge/miniforge/issues/324) years ago.

Caveat on this second piece: I haven't patched reproc locally to verify that changing the `finish:` write from `&errno` to something like `&(int){-r}` would produce the expected value at the parent side. So the stale-errno explanation is my reading of the code rather than a patched-build confirmation, and I'd appreciate a sanity check on that specific step.

## What I tried on the way

In case any of this is useful for ruling things out:

- Updated macOS from 26.3.1 to 26.4 — no change.
- Updated Xcode Command Line Tools from 26.3 to 26.4 — no change.
- Tried reproc 14.2.5 from Homebrew, and also built reproc from source at the `main` branch (which is the same `v14.2.5` commit) — both fail identically.
- Reproduced on two separate M4 Pro machines with fresh macOS 26 installs — same failure on both.
- Wrote a plain C `posix_spawn`-based test program — works fine on macOS 26, so the underlying OS spawn syscalls are healthy.
- Tested both `reproc::run()` (high-level) and `reproc::process::start()` (low-level) — both fail at the same point.
- Tested with `env::extend` and `env::empty` — no difference.
- Tested with `/bin/echo` and `/usr/bin/true` — no difference (so it's not specific to writing output and hitting a drain/read path).
- Discovered that `ulimit -n 1024` before running the reproducer fixes every case.
- Traced the mechanism in `process.posix.c` as described above.

## Suggested fix directions

I don't know the reproc codebase well enough to send a PR with confidence, but these are the directions that come to mind:

**Primary fix — avoid iterating 2 billion fds.** Rather than trying to close every possible fd, there are a few OS-specific ways to enumerate only the fds that are actually open in the calling process:

- Linux: iterate `/proc/self/fd/`
- macOS/BSD: `proc_pidinfo(getpid(), PROC_PIDLISTFDS, ...)`
- Or rely on `FD_CLOEXEC` being set on everything reproc creates and trust that (reproc already does some of this, I think)
- Or use `closefrom()` (BSD) / `close_range()` (Linux 5.9+) where available

If none of that is appealing, a simpler change is to **cap `get_max_fd()`'s return value at something like `min(soft, 16384)`** when `RLIM_INFINITY` is reported, rather than `INT_MAX`. The loop would then be bounded and reproc would not refuse the spawn. This is a small change but means reproc silently closes up to 16K fds even on machines where far fewer are actually open.

A third option is to **raise `MAX_FD_LIMIT`** from 1 MiB to something bigger — but that just kicks the can down the road for any future macOS that bumps the default even higher, and doesn't address the "we're iterating a huge range for no reason" performance problem.

**Secondary fix — report the right errno.** Whatever the primary fix ends up being, I think the `finish:` path should report something that reflects `-r` (the reason the child decided to give up) rather than the stale `errno` from the signal-reset loop. Even just a local variable like `int child_err = -r; write(pipe.write, &child_err, sizeof(child_err));` would have saved multiple people multiple debugging sessions. This is a small, low-risk change that's worth doing regardless of how the primary bug gets fixed.

I'd be happy to test any of these directions on my machines if someone points me at a patch.

## What I'm hoping for from this issue

1. A sanity check on whether my reading of `process.posix.c` is right and whether the EINVAL-from-stale-errno story holds up.
2. If so, a fix in reproc (even just raising or clamping `get_max_fd()`) so macOS 26 users can use reproc-dependent tools without the `ulimit -n` dance.
3. Optionally, the cosmetic errno-reporting fix in the `finish:` path, because the misleading error message cost me a lot of time on the wrong hypothesis and I suspect it's cost others the same.

Thanks for reproc — I know this is an unexpected angle of attack from a random user.

---

## Appendix: the full minimal reproducer

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

Without `ulimit -n 1024`: every line prints `status=-1, ec=22 (Invalid argument)`. With `ulimit -n 1024`: every line prints `status=0, ec=0 (Success)`.
