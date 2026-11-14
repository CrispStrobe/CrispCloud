# Browser launch blocked by the execution environment

**Status: `browser_not_executed_environment_blocked`.** Chromium never reached
a usable browser test session. **No binary-comparison test cases executed.**
The expected gate contains 29 cases: 19 portable capture/navigation tests and
10 stream-limit tests, counted from source including parameterized loops.

The attempted gate used saved source
`e52ea1f9399c2547978bb497073adcee5022cc81`. The retained pre-run inventory is
byte-identical to [the final native inventory](../../final-native-source.json.gz)
for that revision, covering 8,111 source paths. [files.json](files.json) maps
the original browser inventory filename to that shared file and records all
stored/original byte hashes.

Chromium failed during startup when `process_singleton_posix` attempted a
socket operation and received `EPERM` (`Operation not permitted`). The native
launcher logged repeated startup failures. The parent then interrupted the
stalled test process with Ctrl-C; the observed process exit code was **130**.
The raw log and partial JSON event stream are preserved with deterministic gzip
compression. Their suite-loading error is not an executed comparison-test
failure; the event stream contains no completed run `done` event.

`run_gate.py` writes its after-inventory and receipt only after
`subprocess.run` returns normally. It has no interrupt finalization handler,
so this interrupted attempt has **no completed after-inventory or gate
receipt**. The pre-run source binding must not be treated as a successful
browser qualification.

A subsequent explicit elevated-execution attempt was rejected by the
environment before any command started. No alternative route, browser flag
change, or permission change was attempted. Browser runtime qualification
remains pending. [status.json](status.json) records this outcome separately
from passing native tests and analysis.
