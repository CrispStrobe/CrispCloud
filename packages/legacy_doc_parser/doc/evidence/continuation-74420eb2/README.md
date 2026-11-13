# Portable and schema acceptance at 74420eb2

All eight portable gates and the fresh Open XML SDK validation completed on
clean parser commit `74420eb2e0ec14401a0db5bcbb30ab6d202a2340`, tree
`ac78b144d90bca0f44993d94ae0fd1c8115ce072`. The recorded source inputs remained
unchanged throughout each run. This evidence covers the combined Line Number
style, PICMID extent, textbox paint and OLE placeholder changes.

| Gate | Recorded result |
| --- | --- |
| Dart 3.13.7 format | 198 files, zero changes |
| Static analysis | No issues, fatal infos enabled |
| Dart tests | 954 passed |
| Fidelity corpus integrity | 24 source hashes and package graphs verified |
| Python fidelity controls | 162 passed |
| JavaScript compilation and execution | Legacy DOC controls and 51 media checks passed |
| Package publish dry run | Zero warnings; no package published |
| Open XML SDK 3.3.0, Office2019 validation | 230 generated DOCX packages, zero errors |
| Deterministic generation | Two complete 488-file corpora, identical bytes |
| SDK controls | Self-tests passed; valid control accepted; both malformed controls rejected |

The schema validator was rebuilt from the captured source using .NET SDK
8.0.428, runtime 8.0.34, and the pinned SDK packages. Direct compiler arguments,
response file, package recovery receipts, source identities and DLL hashes are
retained. Four reproducible validator DLLs are omitted with their measured size
and hash. The archive retains all 168 schema inputs, both generated corpora,
control packages, logs and original command records.

## Original formatting rejection

The `diagnostic/pre-format/` archive subtree preserves the earlier failed run
at `f255c9da9baed1fdd6034818b1c97069d44589d4`, tree
`ed79243acead0cc5bc2de9aa1b203aef8fa22089`. Its format check found one change in
`doc/evidence/textbox-next-20261113/source_inspect.dart` and exited 1. The run
stopped there. Its source bytes did not change, and it is not reported as a
successful acceptance run. The later clean run is a separate source identity.

## Retained bytes and verification

`validation-artifacts.tar.xz` contains **1,186 files**, compressed to
**1,326,444 bytes**, SHA-256
`904af808f1fca38a373d6f9bd0bab7c34e4cf359c711f72c9c0835480dc4b95f`.
The manifest inventories every member, the omitted DLLs and the verifier itself.
Original source, report and log bytes are retained without rewriting paths or
timestamps. Both portable receipts cover all **948 tracked inputs** plus the
dependency lock and resolved package configuration, for 950 inputs per receipt.

From the repository root:

```sh
python3 doc/evidence/continuation-74420eb2/seal_validation_evidence.py --repository . --self-test
```

The helper checks archive/member identity, exact command inventories and all
23 recorded command arrays (including the original rejected run), full source
coverage, raw Git objects, complete corpus determinism and every SDK result's
input hash. It rejects **33 targeted semantic counterexamples** after outer
archive loading, so those controls exercise evidence bindings rather than
merely compressed-file checksums. All checks use explicit exceptions and remain
active under optimized Python. `verification.json` retains the observed result.

The separate hosted [Dart package run 43383581993](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43383581993)
also succeeded at exact commit `74420eb2`. Both its `test` and `openxml-schema`
jobs completed successfully. `hosted-ci.json` retains the run identity and job
status response. This status observation does not relabel the local artifact
archive as downloaded CI output.

Schema validity and portable tests do not establish visual fidelity. The
separate [complete native corpus](../native-corpus-74420eb2/README.md) retains
the measured rendering and repeated-save differences. Microsoft Word was not
executed for this acceptance.
