# Qualified ink and textbox integration

This receipt records completed acceptance of clean, published CrispCloud
[`86d5a218853d8441afe8bc28f19cfe0adf4cd71e`](https://github.com/CrispStrobe/CrispCloud/commit/86d5a218853d8441afe8bc28f19cfe0adf4cd71e),
tree `765bf752b0095233192d38e678941e7ca92a76b8`. Later documentation and evidence
commits do not change the identity of this measured runtime.

## Exact source integration

| Component | Recorded identity |
| --- | --- |
| Parser | `c5ff75e76163d9abbdd44a9f2a7c5ad210929289` |
| Parser tree | `25bd05c12fa2272a32ec2aaba2cc0117be5bed96` |
| Previous app checkpoint | `6f2e3245b7971d620410a65e75bf54b04132319a` |
| Previous parser | `74420eb2e0ec14401a0db5bcbb30ab6d202a2340` |
| Managed Office inventory | 1,679 files: 1,258 exact parser files and 421 unchanged other files |
| Quds pin, retained | `6d6e77d14ead33de90c57ec5feb2ab3cc44f6501` |
| App version, retained | `1.2.9+22` |
| Root lockfile SHA-256, retained | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` |

The parser adds complete bounded inspection of supported nonempty ISF strokes,
including original packet coordinates and pressure, paint, selected transforms
and pressure metrics. It retains the original ink bytes and explicit decode
status. Unsupported, malformed or oversized streams do not expose partial
strokes. This is inspection and preservation: conversion still emits no active
native Word ink and does not invent placement, editing behavior or a rendered
pressure outline. Independent Windows WPF observations qualify the supported
records; WPF execution is not Microsoft Word execution.

Textbox conversion adds qualified scaled gradients and embedded picture,
texture and monochrome pattern fills. A documented absent line width is emitted
only for a resolved, explicitly enabled textbox line together with its matching
source-to-target frame conversion. Original source coordinates, absent operands,
explicit false/zero values and unsupported-property guards remain distinct.
The earlier Line Number style, PICMID scaling, textbox paint and inert OLE
placeholder fixes remain included.

The guarded plan contains 338 writes and no deletions. Together with the Office
inventory and reviewed fingerprint, the measured app changes 340 paths. All
tracked upstream files and modes are retained, including original diagnostic
logs and evidence archives. The working bytes, pin declarations and exact
Git-index inventory passed `--require-tracked`. Uploaded blob IDs and the final
remote Git tree were compared with local Git, then a separate checkout of the
fetched remote commit passed the same source/index gate. The independent
projection review measured local commit `907d3be3` with the identical published
tree and independently checked all 1,258 parser files and their modes.

Only the parser mirror, its Git pin, Office inventory and existing
`reviewed_source_sha256` fingerprint changed in the runtime commit. The nine
changed library files were reviewed before that fingerprint refresh. The
crypto inventory, root lockfile, Quds and other dependency pins, app version,
policy decisions, dates/references and source plists remain unchanged. No
release was built, submitted or deployed.

## Acceptance on the exact published runtime

| Check | Observed result |
| --- | --- |
| Production dependency resolution | `dart pub get --offline --enforce-lockfile` passed; manifest, lockfile and `.fvmrc` unchanged |
| Data-only Word cohort | 107 tests across the eight required suites passed, no failures or skips |
| Cohort source and dependency identity | All 1,182 captured hashes unchanged |
| Complete tracked app identity | All 7,573 tracked file hashes and production package configuration unchanged |
| Production JavaScript | DOC, RTF, PPT and MSG smoke checks passed |
| Actual installed-Office acceptance | All 13 LibreOffice/Poppler assertions passed |
| Source synchronization controls | 27 passed |
| Exact source retention | 1,679 Office files passed source, mode and Git-index verification, including the fetched remote checkout |
| Apple preflight controls | 38 passed |
| Crypto release-evidence controls | 40 passed; two expected macOS-only skips, 42 discovered |
| Ebook source controls | 22 passed |
| Actual ebook source verification | 279 files at `32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52` verified |
| Existing release-input checker | Passed using the actual production package configuration |

The cohort uses the retained import-only adapter and unchanged assertions. Its
installed-converter tests use fake local processes; the 13 actual native
assertions are separate. The native report retains `partialFormatting`. It
checks the existing authored DOC control's formatting, table, image, page
settings, auxiliary stories, independent PDF structure/text/image presence and
unchanged source/prepared bytes. The existing tool deletes its temporary PDF.
This app receipt does not claim retained page rasters, exact pagination,
Microsoft Word execution, Flutter widgets or a full app build.

The exact parser mirror retains the [ink contract](../../../packages/legacy_doc_parser/doc/ink-decoding.md),
[initial WPF oracle](../../../packages/legacy_doc_parser/doc/evidence/wpf-isf-oracle-20261113/README.md),
[transform/metric oracle](../../../packages/legacy_doc_parser/doc/evidence/wpf-isf-metrics-20261113/README.md),
[scaled-gradient controls](../../../packages/legacy_doc_parser/doc/evidence/textbox-fill-controls-20261113/README.md)
and [bitmap-fill controls](../../../packages/legacy_doc_parser/doc/evidence/textbox-bitmap-controls-20261113/README.md).
The later [paired absent-width evidence at parser evidence commit 8d28f041](https://github.com/CrispStrobe/legacy-doc-parser/blob/8d28f04110de5d7cd5f110f8700c1a9cca7baffc/doc/evidence/textbox-default-width-20261113/README.md)
is an external proof checkpoint; that folder is not present in the measured
`c5ff75e7` vendor projection. The vendor bytes have not been supplemented or
silently relabeled as a later parser revision.

Each feature keeps its measured source identity and renderer limits. Native
texture/pattern tiling and secondary gradient opacity can differ from the
source-correct emitted properties. Unqualified Word14 textbox paint/layout,
compatibility/list/note differences and native bridge loss remain limitations;
this app cohort does not settle every repeated-save paint comparison. It does
not convert those differences into an exactness claim.

## Hosted checks with separate source identities

The [provider run for this exact runtime](https://github.com/CrispStrobe/CrispCloud/actions/runs/43388810612)
passed on `86d5a218`, attempt 1. Its conformance job and all 15 steps succeeded,
including golden vectors, HTTP mocks and cross-decryption. The complete run/job
responses are retained and bound to the measured runtime commit and tree.
This records provider compatibility; it does not establish hosted Office
acceptance for this runtime.

The retained GitHub run/job responses record successful hosted checks for the
previous app checkpoint **`6f2e3245`**, with its previous parser pin. The
[provider run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383828311)
passed its conformance job. The
[Office run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383828350)
passed host-roundtrip and external-schema jobs, including source verification
before temporary hooks, actual-host save/export, SDK validation and native
repeated-save checks. Their run IDs, attempt, exact head/tree, job names and
successful steps are verified separately. They are not hosted acceptance of
`86d5a218` or `c5ff75e7`.

## Records and reproduction

`receipt.json` binds this README, verifier, self-test, exact manifest and
compressed archive. `manifest.json` lists every retained record's size and
SHA-256. The archive retains all actual command JSON/stdout/stderr, production
manifest/lock/configuration, full tracked before/after inventories, cohort
source/event logs, guarded sync plans, reviewed policy/source comparisons,
independent projection review, remote checkout verification and exact existing
Dart/Flutter recovery receipts. Downloaded binaries and dependency caches are
not duplicated.

```sh
python3 docs/evidence/word-final-c5ff75e7-20261113/verify.py
python3 docs/evidence/word-final-c5ff75e7-20261113/test_verifier.py
```

The verifier binds all ten command groups and offline production resolution
to the executed arguments, working directory and source identity. It also
binds the inner Dart-test command, all eight suite paths, test-start/completion
associations and exact per-suite totals to the 107 visible successful events.
Native assertions, cohort artifact hashes, unchanged source/inventory/policy
relationships and earlier hosted identities are independently cross-checked.
Python optimization is explicitly rejected because the helper uses assertions.

The 22 deliberate corruption controls reseal the outer archive, manifest and
receipt before verification. They cover substituted top-level and cohort
commands, stale event hashes, unrelated suite paths, incorrect suite attribution
or totals, changed post-run source, a failed native assertion, altered/new
policy decisions, stale policy copies, earlier hosted success misattributed
to the new runtime and a failed current provider step. Every corruption is rejected; an optimized-Python
invocation also fails explicitly.

To repeat acceptance, use the measured app commit and the genuine toolchain
recovery described in the earlier [48bf3a receipt](../word-gaps-48bf3a-20261113/README.md).
The captured recorder is `final/run_app_final_acceptance.py` in the archive.
Its paths identify this actual execution; a new execution must use fresh
output/cohort directories and retain its own exact source identity.
