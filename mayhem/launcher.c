/*
 * launcher.c — tiny ELF shim so the Mayhem target `cmd` is a native executable (Mayhem rejects
 * script/wrapper targets; fuzz-smoke checks the ELF magic). It exec's the CPython interpreter on
 * a Python script (the Atheris harness, or the oracle driver), forwarding every argument unchanged.
 *
 * Atheris is a libFuzzer engine: with libFuzzer flags (`-runs=...`, `-max_total_time=...`) the
 * harness iterates like any libFuzzer target; with a file argument it replays that single input
 * once — so the SAME binary is both the fuzz target and the standalone reproducer.
 *
 * pysimdjson's hot path is the csimdjson native extension, built with `-fsanitize=fuzzer-no-link`
 * (SanitizerCoverage). Its sancov symbols are satisfied at runtime by preloading Atheris'
 * `ubsan_with_fuzzer.so` (which bundles libFuzzer + the UBSan runtime). We setenv LD_PRELOAD
 * HERE — scoped to this process — rather than as an image-wide ENV, so the rest of the image
 * (build, fuzz-smoke of other targets, apt) is unaffected.
 *
 * The script path, interpreter, and preload are fixed at compile time by the image layout (the repo
 * is COPYed to /mayhem; build.sh resolves the atheris preload path).
 */
#include <unistd.h>
#include <stdlib.h>

#ifndef HARNESS_PATH
#define HARNESS_PATH "/mayhem/mayhem/fuzz_loads_dumps.py"
#endif
#ifndef PYTHON_BIN
#define PYTHON_BIN "/usr/bin/python3"
#endif

#include <string.h>
#include <stdio.h>

int main(int argc, char **argv) {
#ifdef PRELOAD_PATH
    /* APPEND to any existing LD_PRELOAD instead of clobbering it — Mayhem's coverage collection
     * preloads its own tracer into the target; overwriting it would zero out edge reporting. */
    const char *cur = getenv("LD_PRELOAD");
    if (cur && *cur) {
        size_t n = strlen(cur) + 1 + strlen(PRELOAD_PATH) + 1;
        char *joined = malloc(n);
        if (!joined) return 1;
        snprintf(joined, n, "%s:%s", cur, PRELOAD_PATH);
        setenv("LD_PRELOAD", joined, 1);
    } else {
        setenv("LD_PRELOAD", PRELOAD_PATH, 1);
    }
#endif
#ifdef USERBASE_PATH
    /* The packages (atheris, csimdjson) live under this $HOME-independent user base; the target may
     * run as another identity with another HOME. */
    setenv("PYTHONUSERBASE", USERBASE_PATH, 1);
#endif
    /* new argv: python3 HARNESS_PATH <forwarded args...> NULL */
    char **nargv = calloc((size_t)argc + 2, sizeof(char *));
    if (!nargv) return 1;
    nargv[0] = (char *)PYTHON_BIN;
    nargv[1] = (char *)HARNESS_PATH;
    for (int i = 1; i < argc; i++) nargv[i + 1] = argv[i];
    nargv[argc + 1] = NULL;
    execv(PYTHON_BIN, nargv);
    /* execv only returns on error */
    return 127;
}
