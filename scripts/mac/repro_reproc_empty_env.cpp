// repro_reproc_empty_env.cpp
//
// Reproducer for suspected reproc-on-macOS-26 issue that manifests in
// libmamba as "Could not codesign executable: Invalid argument".
//
// This file tests multiple hypotheses side by side:
//
//   * high-level reproc::run vs low-level reproc::process lifecycle
//   * env::extend (inherit parent env) vs env::empty (libmamba's setting)
//   * /bin/echo (writes to stdout) vs /usr/bin/true (no output)
//
// Build (macOS, Apple Silicon, reproc installed via Homebrew):
//
//   clang++ -std=c++17 repro_reproc_empty_env.cpp \
//     -I/opt/homebrew/include -L/opt/homebrew/lib \
//     -lreproc++ -lreproc -o repro_reproc_empty_env
//
// Run:
//
//   ./repro_reproc_empty_env

#include <reproc++/run.hpp>
#include <reproc++/reproc.hpp>
#include <array>
#include <iostream>
#include <vector>
#include <string>

static void report(const char *label, int status, std::error_code ec)
{
    std::cout << "  " << label << "\n";
    std::cout << "    status = " << status << "\n";
    std::cout << "    ec     = " << ec.value()
              << " (" << (ec ? ec.message() : "Success") << ")\n";
}

// ---- Test A: high-level reproc::run ----

static void test_run(const char *cmd_label, std::vector<std::string> cmd,
                     const char *behavior_label, reproc::env::type behavior)
{
    reproc::options options;
    options.env.behavior = behavior;

    auto [status, ec] = reproc::run(cmd, options);

    std::cout << "[reproc::run]  " << cmd_label << " / " << behavior_label << "\n";
    report("result", status, ec);
    std::cout << "\n";
}

// ---- Test B: low-level reproc::process lifecycle ----

static void test_process(const char *cmd_label, std::vector<std::string> cmd,
                         const char *behavior_label, reproc::env::type behavior)
{
    std::cout << "[reproc::process]  " << cmd_label << " / " << behavior_label << "\n";

    reproc::options options;
    options.env.behavior = behavior;

    reproc::process proc;

    auto start_ec = proc.start(cmd, options);
    if (start_ec) {
        report("start() FAILED", -1, start_ec);
        std::cout << "\n";
        return;
    }
    std::cout << "    start()  OK\n";

    // Drain stdout so the child can exit (if it writes anything).
    std::array<uint8_t, 256> buf{};
    while (true) {
        auto [n, read_ec] = proc.read(reproc::stream::out, buf.data(), buf.size());
        if (read_ec == reproc::error::broken_pipe) {
            std::cout << "    read()   EOF (broken_pipe, normal)\n";
            break;
        }
        if (read_ec) {
            report("read() FAILED", -1, read_ec);
            break;
        }
        if (n == 0) {
            break;
        }
        // Show what the child wrote so we can confirm it ran.
        std::cout << "    read()   got " << n << " bytes: \"";
        std::cout.write(reinterpret_cast<char *>(buf.data()), static_cast<std::streamsize>(n));
        std::cout << "\"\n";
    }

    auto [status, wait_ec] = proc.wait(reproc::infinite);
    report("wait()", status, wait_ec);

    std::cout << "\n";
}

int main()
{
    std::cout << "reproc-on-macOS-26 repro matrix\n";
    std::cout << "===============================\n\n";

    std::vector<std::string> echo_cmd = {"/bin/echo", "hello"};
    std::vector<std::string> true_cmd = {"/usr/bin/true"};

    // --- reproc::run ---
    test_run("echo",  echo_cmd, "env::extend", reproc::env::extend);
    test_run("echo",  echo_cmd, "env::empty",  reproc::env::empty);
    test_run("true",  true_cmd, "env::extend", reproc::env::extend);
    test_run("true",  true_cmd, "env::empty",  reproc::env::empty);

    // --- reproc::process lifecycle ---
    test_process("echo", echo_cmd, "env::extend", reproc::env::extend);
    test_process("echo", echo_cmd, "env::empty",  reproc::env::empty);
    test_process("true", true_cmd, "env::extend", reproc::env::extend);
    test_process("true", true_cmd, "env::empty",  reproc::env::empty);

    std::cout << "Key things to look for in the output above:\n";
    std::cout << "  - Does high-level reproc::run fail where low-level reproc::process succeeds?\n";
    std::cout << "  - Does env::empty behave differently from env::extend?\n";
    std::cout << "  - Does /usr/bin/true behave differently from /bin/echo?\n";

    return 0;
}
