# Reconciled parser baseline — 13 November 2026

The resumed office-fidelity branch incorporates current main at
`cd9ab85aa43fb2955105d5fa34d802f1017307cf`, tree
`0398f0101b9dbf4ea2c94b810f092d2170580e6c`. This is a fresh qualification of
that exact clean checkpoint before further changes. The older feature-branch
head `91baa8f` had a stale header-alias frame assertion; current main had already
corrected it while preserving both distinct literal source anchors. No duplicate
runtime or test correction was introduced during this reconciliation.

All eight portable stages passed on direct Dart 3.13.7: formatting, fatal-info
analysis, **931 Dart tests**, corpus integrity, **162 Python controls**, actual
binary-DOC JavaScript acceptance, **51 media JavaScript checks**, and the package
dry run with zero warnings (plus the recorded compiler-version stage). All
**800 captured input hashes** were unchanged and the worktree was clean before
and after. The archive retains complete command arguments, logs and source
receipts; Python negative-control diagnostics are intentional passing tests.

The environment uses the verified official direct Dart executable and a genuine
resolved package configuration. The Flutter launcher was not used. This portable
checkpoint does not claim new native-rendering, schema, app-build or release
acceptance. Those gates must be bound to the runtime they actually validate.

Verify the retained bytes without extracting them:

```sh
python3 doc/evidence/continuation-baseline-20261113/verify.py
```

Reproduce from a clean checkout using the unchanged retained runner at
`doc/evidence/continuation-0c3e596/run_parser_gate.py`, passing `--repo`, a fresh
`--out` directory, and the direct `--dart` path. Supply a resolved package
configuration and an accessible `PUB_CACHE` first.
