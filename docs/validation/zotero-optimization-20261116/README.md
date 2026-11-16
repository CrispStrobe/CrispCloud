# Zotero optimization: CrispCloud host qualification

## Exact sources

The qualified application source is
`1c5aa295cdc1cedf0e5496e4673731f35ad5d18c` on
`codex/zotero-optimization-20261116`. Its Office manifest pins Quds
`0dd09811b1c02514c32c33bd13744dadb202e7af`. Later delivery commits add
documentation/evidence and keep these production/test bytes unchanged.

The shared implementation now retrieves basic citation metadata in one verified
batch per durable library scope, for up to 50 distinct sources. It stages all
libraries before applying one undoable update. Missing, duplicate, substituted
or wrong-profile results and missing CSL refuse the whole operation. A changed
document or insertion point stops further batches.

Native Zotero processing now resolves field IDs directly, indexes separate
footnote/endnote identities, and calculates note order once per field-list
response. It recomputes that order after staged changes. Existing protected-field,
identity, document-state and conversion guards remain in place. Saved searches,
native preferences, mixed rich text, small capitals, bibliography paragraphs and
DOCX preservation from the earlier continuation remain included.

## Local results

| Executed check | Result |
| --- | ---: |
| Actual host service, transport, credential, target and ribbon tests | 39 passed |
| Strict analysis of eight host targets | Clean |
| Formatter | Eight files, zero changes |
| Whitespace | Clean |
| Working-tree and tracked/index Office guards | 2,411 entries verified each |
| Compiled-source/dependency input hashes | 1,617 unchanged |
| Application HEAD and Office manifest during checks | Unchanged |
| Standalone parser actual bytes and existing pin | 1,857 files unchanged |

The [host receipt](host/host-validation-receipt.json) records every command and
exit code. Its SHA-256 is
`59ead7b64dfb37221f2e5f084d7f65ad49d971ffb72003ccd2f068f1a771b470`.
Large source-map JSON files are preserved losslessly as gzip. Temporary
analysis configuration was restored; production dependency constraints were not
changed. The runtime was official Flutter 3.47.8 / Dart 3.13.7 with genuine
dependencies resolved using the original enforced locks.

The canonical Quds source independently passed **364 unique tests**: 119 native
Word/citing, 81 catalog/identity/batch, and 164 shared-editor tests. Together
these disjoint cohorts provide **403 focused tests**, without adding overlapping
development reruns. All six changed canonical Dart files passed strict analysis
and formatting. See the [canonical report](https://github.com/CrispStrobe/quds_office_suite/blob/codex/zotero-optimization-20261116/docs/validation/zotero-optimization-20261116/README.md)
for exact lists, source hashes and reproduction.

## Performance scope

Fifty distinct sources from one library now require one metadata request
instead of fifty. A canonical synthetic JIT benchmark with 2,400 fields and
1,600 notes measured field enumeration at 228.704 ms before and 1.773 ms after,
with identical protocol snapshot hashes. This isolates engine work; full
validation and construction were approximately unchanged, and no overall
application or live Zotero latency claim is made. The canonical report retains
all measurements, the baseline-file substitution and both source identities.

## Incoming work and preservation

The [incoming ref inventory](incoming-refs.json) accounts for all 44 incoming
branch heads and 156 advertised PR heads, plus this new branch. Main
`5d3a020d` through PR #166 and Zotero PR #161 were already included in the
terminal/recovery baseline `0c43c476`.

The second refresh incorporated terminal optimization `50107514` and recovery
evidence `3fb3eed4`, retaining both parents in `bf5a731c`. All recorded incoming
heads are ancestors of the integrated source. No original branch was rewritten.
The new terminal code is retained with its existing evidence; the terminal and
tmux suites were not rerun in this focused Zotero host graph.

Office synchronization used `tool/sync_office_fidelity.py` against the immutable
Quds commit, preserving the independently maintained legacy parser at
`4895712158127b2fc930d796e17035c3ca0dac62`. Both normal and tracked guards
validated the actual files and source mapping.

All consolidation, implementation and final evidence checkpoints were saved
remotely with `[skip ci]`. No GitHub Actions jobs were queried, awaited or rerun.

## Reproduce

Restore the original locked host harness documented in the canonical setup
receipt. With the official toolchain on PATH, run the existing host validator:

```sh
python3 docs/validation/zotero-fidelity-20261116/run-host-checks.py \
  --repo /absolute/path/to/CrispCloud \
  --harness /absolute/path/to/crisp-host-harness \
  --quds-source /absolute/path/to/quds_office_suite \
  --expected-quds 0dd09811b1c02514c32c33bd13744dadb202e7af \
  --output /absolute/path/to/new-host-evidence
```

This pass does not claim a new full application build, new live Zotero/Word
acceptance, private-account/keychain acceptance or deployment. Earlier live
desktop results retain their own source identities. The basic-refresh 50-source
limit, protected-story boundaries and active-ODT limitation remain unchanged.
