# Parser lineage reconciliation — 13 November 2026

CrispCloud's document/font continuation consumed parser `402b66d`, while the
Office oracle branch carried independently qualified fields, symbols and font
charsets at `1b8cc9e`. Canonical parser
[`840f8af1f645cd6ed85277ba6e619dc120d99277`](https://github.com/CrispStrobe/legacy-doc-parser/commit/840f8af1f645cd6ed85277ba6e619dc120d99277)
contains both histories and the later compound-file, public-field, Unicode and
metafile bounds corrections. Both ancestor relationships were checked before
applying the existing guarded sync tool.

The complete tracked parser source, licenses, fixtures, tools and historical
evidence are mirrored without local patches. The shared Quds source stays at
`e82c997b6df8746fe86fb83b9f416a89bb3e3b80`; this reconciliation preserves the
font and preview integration. The app dependency lockfile is byte-identical to
the document/font PR's `02160e56` base. Only the parser's declared Git pin,
upstream identity and corresponding source inventory change.

## Executed checks

| Check | Result |
| --- | --- |
| Parser suite using the app's locked `archive` 4.6.0 | **1,361 passed** |
| Existing production parser JavaScript acceptance using `archive` 4.6.0 | **Passed**, including fields, source charsets, symbol glyphs, compound allocation/ownership, Unicode stories, metafile and ink cases |
| Full-package fatal-info analysis | **No issues** with the normal standalone resolution |
| Python semantic/oracle controls | **184 passed** |
| Retained corpus integrity and OOXML package graph checks | **24 inputs verified** |
| Guarded parser and Office synchronization controls | **19 + 8 passed** |
| Source inventory and staged Git-index verification | **1,883 Office files verified**, including exact upstream parser bytes and modes |

The runtime is Linux x64 with the repository-pinned Flutter 3.47.8 / Dart 3.13.7.
The initial standalone resolution selected `archive` 4.7.1 and all 1,361 tests
also passed there. To check the actual app runtime dependency, a generated
package configuration changed only that package's root to the verified 4.6.0
cache. The direct `package:test` entrypoint used that configuration for the
complete repeat. The existing JavaScript verifier used the same configuration,
which was restored after execution. No tracked dependency manifest or lockfile
was edited for these checks. The two 1,361-test runs overlap and must not be added
together. Full-package analysis used the normally resolved 4.7.1 configuration.

[receipt.json](receipt.json) binds the source pins, tested source tree, lockfile,
inventory, command scopes and original output hashes.
[validation-logs.tar.xz](validation-logs.tar.xz) retains complete Dart, analyzer,
JavaScript, Python-control and corpus-check output. Deliberate compile/schema
failures inside the Python-control log are passing negative-control assertions.

## Scope and reproduction

This receipt qualifies the exact parser mirror from an isolated consumer
checkout based on the document/font PR. The combined application, native
renderer, Open XML SDK and release-build gates are separate. The earlier
canonical and app evidence retains its original source attribution; it is not
relabeled as a new native rendering result.

Resolve the package dependencies, select the app's locked `archive` version in
a disposable generated package configuration, and run the maintained package
test entrypoint, `tool/verify_web.py`, full-package analysis and
`python3 -m unittest discover -s tool/fidelity -p 'test_*.py'`. From the app root,
run both guarded-sync test modules and:

```sh
python3 tool/verify_office_fidelity.py --legacy-source /path/to/legacy-doc-parser --require-tracked
```

The new source-inventory entries cover `compound/cfbf_names.dart` and
`word_font_writer.dart`. Final application technical fingerprints must be
computed after the complete branch reconciliation; this receipt does not change
export-policy decisions or claim a release qualification.
