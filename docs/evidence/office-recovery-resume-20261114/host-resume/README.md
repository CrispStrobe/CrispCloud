# Resumed actual-host acceptance

The initial input checkpoint is retained in `inputs/`, captured before execution
on app source `31838929276690e2804231c7928ddd8f1e46811c`, with canonical Office
source `c37789b596a6f6516d9e2cee78ce57ab33872b07`. All 2,174 managed Office files
were verified before starting the bounded five-file native host cohort.

The source snapshot records 4,739 inputs. The committed pubspec and the expected
temporary system-SQLite test hook view are retained separately. The existing CI
helper restores the committed view after execution. Native compiler setup uses
a task-owned toolchain and records the exact package metadata and hashes.

This pre-execution checkpoint does not claim a successful test or coverage
result. The complete execution receipt, raw logs, LCOV and exact saved packages
will be recorded separately when the run finishes.
