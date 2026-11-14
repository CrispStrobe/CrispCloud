# Final independent OpenXML SDK acceptance

**All 27 fresh files passed: three authored inputs and 24 captured uploads,
zero schema errors.** All three host executions used app source
`ccba883b3a042582d3fd80f75772c20bff9e2c4b`; their separate source, command,
artifact-manifest, and successful collection receipts are retained.
The existing validator's positive and negative self-tests passed immediately
before each cohort's SDK invocation.

| Cohort | Files | Inputs | Uploads | Errors | Source workbook SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- |
| worksheet-positive-1 | 17 | 1 | 16 | 0 | `ea001af95d00b2a64d657bbc430ee75b0ba5fc10ce84456b9b39863b643dcabd` |
| style-positive-1 | 6 | 1 | 5 | 0 | `a7169355e89a1e5f232a407652adf4a5bed20bd0ddfbf8390f152f9ebb230107` |
| native-fill-positive-1 | 4 | 1 | 3 | 0 | `46e2283f807e8776e8d6a6413f43ab06d87c61ce52ec0aa4a171e4aae4eceacb` |

`summary.json` is the index. Each cohort directory contains the SDK's direct
`schema-report.json`, raw self-test/schema logs, exact commands and exit codes,
a hash inventory, copied frozen host receipts, and the exact validated XLSX
bytes under `artifacts/`. Large JSON host receipts are losslessly compressed;
their original hashes, compressed hashes, and compression flags are recorded.

Validation used immutable captured copies so later Flutter setup could not
rewrite a previous cohort's `source.xlsx`. Every file matched the host's
finalized SHA-256 manifest before validation, the SDK's own hash during
validation, and the preserved bytes afterward. Each required filename matched
the explicit manifest at the executed commit. The collector also checked that
validator/project and test-source bytes matched that commit. The unrelated
live Flutter `pubspec.yaml` override was not checked or changed.

## Runtime and scope

The unchanged repository validator used the already prepared official .NET
SDK **8.0.428**, runtime/reference pack **8.0.34**, and **OpenXML SDK 3.3.0**,
with its existing `Office2019` validation target. `Program.cs` SHA-256:
`4d41f286855ed11a12ecdf0641773c33285847180a3e5cdbf43ce2385a099880`.
`validator-provenance.json` retains download URLs/checksums, source/project,
compiler and assembly identities, and exact dependency versions. The existing
setup instructions remain at
`../../office-recovery-resume-20261114/host-resume/external/VALIDATOR_SETUP.md`.
No runtime binaries or duplicate toolchain are included here.

These receipts establish schema validation of the captured package bytes.
The UI behavior and exact data/formatting expectations are established by the
separately receipted host regressions. The three new acceptance roots have
explicit schema-only artifact scope; no new renderer, visual-pass, or
qualified native-import exception result is claimed.

Historical fill acceptance and baseline source records remain unchanged in
their original directories. This final record uses only the fresh three
cohorts from the same integrated source.

## Reproduction

`validate_acceptance_run.py` is the exact collector used. Each `run-config.json`
records the executed commit, manifest root, immutable host capture directory,
exact expected hashes, test sources, and receipt paths. The collector checks
those identities, runs the unchanged validator self-test, validates the
captured directory, and preserves identical copies. To recheck archived bytes
with the recorded validator/runtime, run the SDK validator on each cohort's
`artifacts/` directory and retain new receipts separately. The original raw
receipts and package hashes should remain unchanged.
