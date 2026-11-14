# Independent worksheet-state schema evidence

The existing unchanged OpenXML SDK validator independently accepted both exact
captures of the authored worksheet-state source: **1 file, 0 errors** in each
separate invocation. Its positive and negative self-tests ran immediately
before each check. These are input-fixture results from the baseline stage.

| Capture | Exact source SHA-256 |
| --- | --- |
| First emitted source | `1bf2bbb70f0dbea81a6398a934dd267d943335edf92b6f46028ede4248bf1d71` |
| Final stable baseline-5 source | `d34eea0d7347fe74c8cba77fbeddc6b9fad29dfb4f31a099d7ce953f7fbae2ad` |

The two ZIP archives have identical uncompressed parts. The final source
was captured from baseline-5, whose head and changed-source snapshots are
preserved in `baseline-5-source/host-inputs.json`; `source-binding.json` relates
the exact test bytes to their subsequent publication at app
`4518e7719e6d4a78c19386ea4f9dd30933bd6931`. The host execution's recorded identity
is retained separately from that publication identity.

Each capture directory retains its exact source bytes, SDK schema report,
self-test and schema logs, command/exit-code receipt, and relevant hashes.
Final host-output validation will be added separately after the positive gate
emits its exact workbooks.

## Validator identity

The runtime is the existing task-local official .NET SDK **8.0.428**, runtime
**8.0.34**, and OpenXML SDK **3.3.0**, using the repository validator's
`Office2019` target. Its `Program.cs` SHA-256 is
`4d41f286855ed11a12ecdf0641773c33285847180a3e5cdbf43ce2385a099880`.
`validator-provenance.json` preserves official package URLs/checksums, compiler
and source identities, exact dependency versions, and setup commands. The full
existing setup note remains in
`../../office-recovery-resume-20261114/host-resume/external/VALIDATOR_SETUP.md`.
No toolchain binaries are duplicated here.

This evidence establishes OOXML schema validation. The new acceptance roots
are explicitly scoped to schema checks; no new renderer result is claimed.
