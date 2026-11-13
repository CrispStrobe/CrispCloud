# Word layout integration: first follow-up batch

This receipt records completed acceptance of clean, published CrispCloud
[`e3eaaa32bafa869548b30c0938aec776e99ea44e`](https://github.com/CrispStrobe/CrispCloud/commit/e3eaaa32bafa869548b30c0938aec776e99ea44e),
tree `f7a9943e1790de253930fec3e12375277132fa3a`. The subsequent evidence checkpoint
does not change that measured runtime identity.

## Exact source integration

| Component | Recorded identity |
| --- | --- |
| Parser | `74420eb2e0ec14401a0db5bcbb30ab6d202a2340` |
| Parser tree | `ac78b144d90bca0f44993d94ae0fd1c8115ce072` |
| Previous app checkpoint | `ec354cc3e6c11243bb66cbe9eb0763f15b72f7c1` |
| Managed Office inventory | 1,369 files: 948 exact parser files and 421 unchanged other files |
| Quds pin, retained | `6d6e77d14ead33de90c57ec5feb2ab3cc44f6501` |
| App version, retained | `1.2.9+22` |
| Root lockfile SHA-256, retained | `135a9ccb44a38b2b9c7dcb541540b52bf151e8f5af14bf6e13b95d9240ae18a5` |

The parser roll carries four independently investigated corrections: explicit
built-in Line Number character styles; integer-twip PICMID picture scaling
with exact pre-quantization bounds; supported textbox fill/line/shadow paint
properties; and an inert generated OLE placeholder image that remains visible
when native readers discard the former placeholder textbox. The OLE image is
explicitly marked as generated artwork for an unavailable preview; it is not
claimed to be recovered source content. Macro/object execution remains absent.

The complete parser mirror includes its tests, fixtures and original evidence.
The guarded dry-run and apply plans are retained. Before publication, all
working bytes, Git modes, pin declarations and the exact parser-prefix index
inventory passed `--require-tracked`. Each uploaded blob and final Git tree
were compared to local Git before creating the remote checkpoint branch. A
separate checkout of the fetched remote commit passed the same complete
source/index gate.

Only the parser mirror, its Git pin, the Office inventory and the existing
`reviewed_source_sha256` fingerprint changed in the measured app commit. The
fingerprint was refreshed after reviewing the 11 changed parser runtime files.
The crypto inventory, lockfile, Quds sources, app version, other dependency
pins, policy decisions, dates/references and source plists remain unchanged.
No release was built, submitted or deployed.

## Acceptance on that exact published runtime

| Check | Observed result |
| --- | --- |
| Production dependency resolution | `dart pub get --offline --enforce-lockfile` passed; manifest, lockfile and `.fvmrc` unchanged |
| Data-only Word cohort | 107 tests across eight suites passed, no failures or skips |
| Cohort source and dependency identity | All 1,180 captured hashes unchanged |
| Complete tracked app identity | All 7,257 tracked file hashes and production package configuration unchanged |
| Production JavaScript | DOC, RTF, PPT and MSG smoke checks passed |
| Actual installed-Office acceptance | All 13 LibreOffice/Poppler assertions passed |
| Source synchronization controls | 27 passed |
| Exact source retention | 1,369 Office files passed source, mode and Git-index verification, including the fetched remote checkout |
| Apple preflight controls | 38 passed |
| Crypto release-evidence controls | 40 passed; two expected macOS-only skips (42 discovered) |
| Ebook source controls | 22 passed |
| Actual ebook source verification | 279 files at `32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52` verified |
| Existing release-input checker | Passed using the actual production package configuration |

The cohort uses the retained import-only adapter and unchanged app assertions.
Its installed-converter suite uses fake local processes; those tests are
separate from the 13 actual native assertions. The native report retains
`partialFormatting`. It checks the existing authored DOC control's formatting,
table, image, page settings, auxiliary stories, independent PDF structure/text/
image presence, and unchanged source/prepared bytes. The existing tool deletes
its temporary PDF. This app receipt does not claim retained page rasters,
exact pagination, Microsoft Word execution, Flutter widgets or a full app build.

Per-feature source and rendering evidence remains in the exact upstream mirror,
including [Line Number style](../../../packages/legacy_doc_parser/doc/evidence/line-number-style-20261113/README.md),
[picture sizing](../../../packages/legacy_doc_parser/doc/evidence/picture-scaling-20261113/README.md),
[textbox paint](../../../packages/legacy_doc_parser/doc/evidence/textbox-next-20261113/README.md)
and [OLE placeholder](../../../packages/legacy_doc_parser/doc/evidence/ole-visible-placeholder-20261113/README.md).
Their measured source identities and renderer limits are preserved. The
remaining compatibility/list/note/native-bridge differences are not relabeled
as fixed by this integration. Later textbox fill and ink work belongs to a
separate source roll.

## Records and reproduction

`receipt.json` binds this README, verifier, exact file manifest and compressed
archive. `manifest.json` enumerates every retained record's size and SHA-256.
The archive retains all actual command JSON/stdout/stderr, production manifest/
lock/configuration, full tracked before/after inventories, cohort source and
event logs, guarded sync plans, reviewed policy/source comparison, remote
checkout verification and the existing exact Dart/Flutter recovery receipts.
No downloaded SDK binaries or dependency caches are duplicated.

```sh
python3 docs/evidence/word-layout-74420eb2-20261113/verify.py
python3 docs/evidence/word-layout-74420eb2-20261113/test_verifier.py
```

The verifier binds the ten exact command groups and offline resolution to their
execution records, validates all 107 visible successful test events and cohort
artifact hashes, checks native assertion names, and verifies unchanged source,
inventory, policy and dependency relationships. It fails explicitly if Python
optimization disables assertions. Its successful result establishes the
documented captured checks; it does not add a hosted CI result or a release claim.
The verifier controls reseal the outer archive/manifest receipts before checking
16 deliberate corruptions: each actual command replaced by an unrelated
executable, stale cohort-event hashes, changed post-run source, a failed native
assertion, a changed policy decision, an added policy key and a stale retained
policy copy. Both policy copies and the retained inventories are bound to their
corresponding complete source snapshots. Every corruption is rejected; an
optimized-Python invocation also fails explicitly.

To repeat acceptance, use a checkout of the measured app commit and the exact
genuine Dart/Flutter recovery described in the preceding
[48bf3a receipt](../word-gaps-48bf3a-20261113/README.md). The captured recorder is
`final/run_app_final_acceptance.py` inside the archive; its paths identify the
actual execution. New runs must use new output/cohort directories and retain
their own source identities.
