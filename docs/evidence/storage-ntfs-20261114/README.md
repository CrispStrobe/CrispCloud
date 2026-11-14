# NTFS image browsing — qualification and recovery

The bounded read-only NTFS increment is implemented on
`integration/storage-ntfs-20261114` in
[draft PR #103](https://github.com/CrispStrobe/CrispCloud/pull/103), stacked on
the preserved ext continuation in PR #102. The
[supported profile](../../archive-ntfs-profile.md) describes admission,
application behavior, resource limits and explicit exclusions.

## Exact source attribution

| Revision | Meaning |
| --- | --- |
| `ffdd6a86820b0d58cf8b93b4e626d0439beefab9` | Preserved ext baseline; earlier ext receipts retain their original qualification pins. |
| `dec983b2fcb71dea7f90e1020c5d73e3f926a3f6` | Completed NTFS runtime; actual portable VM/JavaScript execution and original-manifest production web build. |
| `c2c17f7a273c45760fd54b9e5a8fe3cd57b0d51b` | Corrected native-test expectation; actual successful full native gate and strict changed-file analysis. |

The only non-documentation change between the last two revisions is
`test/archive_ntfs_reader_test.dart`. It separates the duplicate root-dot
case from the generic unsupported-name table and asserts its earlier corrupt
index-key rejection. No runtime, fixture, dependency, asset or workflow changed.
The [equivalence receipt](final-portable/runtime-equivalence-dec983b2-to-c2c17f7.json)
checks the full non-documentation Git-tree delta, all 606 actual portable
compiler inputs, production manifests, package configuration and Dart/Node
executables. The corrected test is absent from those compiler inputs. Earlier
executions are not relabeled as having run at the later revision.

## Results

| Gate | Actual revision | Result | Evidence |
| --- | --- | --- | --- |
| Native storage regression | `c2c17f7a` | **1,187 passed, 0 failed, 1 expected skip**, across 46 suites | [Summary](final-native/ntfs-corrected-final-native-summary.json), [receipt](final-native/ntfs-corrected-final-native-receipt.json), [artifact index](final-native/INDEX.json) |
| Strict Dart analysis | `c2c17f7a` | **25 changed Dart files**, `--fatal-infos`, no issues | [Receipt](final-analysis/ntfs-corrected-final-analysis-receipt.json), [artifact index](final-analysis/INDEX.json) |
| Dart VM acceptance | `dec983b2` | **18 groups / 2,037 checks** | [Portable receipt](final-portable/ntfs-final-portable-receipt.json) |
| Actual dart2js `-O2` / Node acceptance | `dec983b2` | **18 groups / 2,037 checks**; complete JSON and raw stdout equal to VM | [Portable index](final-portable/INDEX.json) |
| Production JavaScript web build | `dec983b2` | Successful **1.3.0+23** build, exact revision/version stamps and required license asset present | [Build receipt](final-web/ntfs-final-web-receipt.json), [artifact index](final-web/INDEX.json) |
| External fixture reproduction | Recorded producer inputs | Four complete NTFS 3.1 images reproduce exactly; three supported, one deliberately unsupported attribute-list layout | [External index](external-fixtures/INDEX.json), [reproduction receipt](external-fixtures/reproduction-receipt.json) |

The native suites cover the existing FAT/ext/disk/DMG/HFS/ISO/UDF/archive flows,
the new NTFS reader and partition composition, extraction, workspaces,
recognition, integrity, and native viewer behavior. The single skipped case is
the existing opt-in test that publishes/reopens a TGZ member larger than 2 GiB;
no NTFS case is skipped. Portable checks also run through one native reference
test, so these different counting units must not be added together.

Native validation uses the existing isolated test-host profile with only the
optional ebook-conversion hook disabled; the catalogue Rust hook remains enabled.
The lockfile stays unchanged and the original manifests are restored afterward.
The production web build uses a separate immutable Git archive and the unchanged
production dependency graph, with no native-test hook override. Native, analysis
and production-build receipts each bind 8,092 non-documentation source paths
before/after. Portable validation separately binds 5,048 selected tracked paths
(4,988 Dart files) and all 606 actual compiler inputs. Tool versions are Flutter
3.47.8, Dart 3.13.7 and Node 24.22.1.

## Independent inputs and practical coverage

The supported complete-image corpus uses 512-byte and 4096-byte logical sectors,
512-byte and 4096-byte clusters, and 1024-byte and 4096-byte FILE records. It
contains **143 supported unnamed file-path instances**, including sparse and
fragmented content, Unicode and supplementary-plane names, hard links, nested
and empty directories, nonresident indexes and named streams. All supported
regular payloads are compared in buffered and streamed reads.

The fourth image was independently mastered with a real directory attribute
list. It is a refusal control, not a successful application extraction.
Across all four images, independent external tools extracted and hashed
**204 unnamed path instances and eight named streams**. Supported-image ADS
content is externally verified but remains metadata-only in the application.
The producer/reproducer preserves 54 input bindings, 1,054 command records,
2,108 stdout/stderr channels and 643 text archive entries. Recovered deterministic
text is accepted only when its original recorded byte length and SHA-256 match.

External `ntfsinfo` inspection of `$Secure` emits a `$SDS` diagnostic despite a
zero exit status. A fresh untouched `mkntfs` control reproduces it before helper
population; direct `$SDS` extraction returns equal bytes. Security-descriptor
content inspection remains **incomplete**, with exact outputs retained in the
[external evidence](external-fixtures/README.md). Separate `ntfsfix -n`,
`ntfsresize --info --no-action`, namespace and user-payload results retain their
own evidence. They do not establish Windows chkdsk acceptance or filesystem-wide
consistency.

NTFS 3.0 coverage is synthetic and uses the older FILE header layout. The largest
complete external image is 32 MiB; native F3 tests use padded 80 MiB inputs and
verify positional access and source preservation. Derived MBR/GPT wrappers,
4096-byte GPT sector units, offsets above 2 TiB, malformed metadata, source
failures, cancellation, borrowed buffers, exact limits and shared allocation
budgets remain explicitly identified as derived/synthetic controls.

This qualification does not cover filesystem writing, mounting, device access,
recovery, journal replay, NTFS compression/encryption/reparse points, attribute
lists, Windows collation order, `$UpCase` semantics, ACL/security-descriptor
interpretation, or unreferenced-record/unused-space consistency. Alternate
streams retain exact names/sizes in notices and are not previewed, integrity
payload-tested or extracted as ordinary files.

## Preserved attempts and hosted status

The first native candidate at `dec983b2` had 1,186 passes, one failed expectation
and the same opt-in skip. Its complete log, event stream, source binding and
analysis result remain in [the candidate index](intermediate/candidate-dec983b2/INDEX.json).
The test-only correction is described above, and the complete native gate was
rerun successfully at `c2c17f7a`. The earlier six-viewer-test and 50-app-test runs
have working-tree source bindings in [the preliminary native index](intermediate/preliminary-validation-index.json).
[Preliminary portable evidence](preliminary-portable/README.md) is explicitly
marked as smoke-only, with no later qualification pin assigned.

[Hosted status](hosted-source-status.json) is separate from these local results.
At its recorded observation, the corrected source had eight queued checks;
earlier runtime checks were queued or cancelled. No hosted pass is claimed.
Later evidence-only commits preserve the qualified source and can trigger a
new hosted run.

During qualification, `main` advanced separately to
`70524c8141c7880c854ca7e58489f207ecf2085d` with CSV spreadsheet imports and BASIC/XML
highlighting. [The follow-up reconciliation](main-followup-reconciliation.json)
preserves that observation. A virtual Git merge is clean, including the shared
viewer file, but that merged tree was not built or tested. The NTFS branch
remains stacked on ext; neither main nor the ext base was rewritten.

## Recovery and artifact integrity

[Progress](PROGRESS.md) records incremental remote checkpoints.
[The consolidated result](final-validation.json) retains actual execution pins
and links to every gate. [The artifact index](artifact-index.json) hashes the
stored evidence; [the integrity report](evidence-validation.json) records
verification of stored and decompressed representations. Large logs and source
bindings use deterministic gzip. Full reproducible images, extracted binary
payloads and compiled artifacts are represented by their complete source/data
inputs and hashes rather than duplicate binary copies.
