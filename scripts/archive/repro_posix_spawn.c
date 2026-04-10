// repro_posix_spawn.c
//
// Absolutely minimal test: can macOS 26 posix_spawn /bin/echo at all?
//
// Build:
//   clang repro_posix_spawn.c -o repro_posix_spawn
//
// If this FAILS, macOS itself has a regression.
// If this SUCCEEDS, the bug is strictly inside reproc.

#include <spawn.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

extern char **environ;

static int spawn_and_wait(const char *label, char *const argv[], char *const envp[])
{
    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], NULL, NULL, argv, envp);
    if (rc != 0) {
        printf("[%s] posix_spawn FAILED: rc=%d errno=%d (%s)\n",
               label, rc, errno, strerror(errno));
        return -1;
    }
    printf("[%s] posix_spawn OK: pid=%d\n", label, pid);

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        printf("[%s] waitpid FAILED: errno=%d (%s)\n", label, errno, strerror(errno));
        return -1;
    }
    if (WIFEXITED(status)) {
        printf("[%s] child exited cleanly: exit=%d\n\n", label, WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        printf("[%s] child killed by signal %d\n\n", label, WTERMSIG(status));
    } else {
        printf("[%s] child status opaque: raw=0x%x\n\n", label, status);
    }
    return 0;
}

int main(void)
{
    printf("posix_spawn direct test on macOS 26\n");
    printf("===================================\n\n");

    // Test 1: inherited environment (parent's environ)
    {
        char *argv[] = { "/bin/echo", "hello-inherited", NULL };
        spawn_and_wait("inherited env", argv, environ);
    }

    // Test 2: empty envp (libmamba's setting)
    {
        char *argv[] = { "/bin/echo", "hello-empty", NULL };
        char *envp[] = { NULL };
        spawn_and_wait("empty envp", argv, envp);
    }

    // Test 3: minimal explicit env
    {
        char *argv[] = { "/bin/echo", "hello-minimal", NULL };
        char *envp[] = { "PATH=/usr/bin:/bin", NULL };
        spawn_and_wait("minimal envp", argv, envp);
    }

    // Test 4: /usr/bin/true with empty envp
    {
        char *argv[] = { "/usr/bin/true", NULL };
        char *envp[] = { NULL };
        spawn_and_wait("true + empty envp", argv, envp);
    }

    return 0;
}
