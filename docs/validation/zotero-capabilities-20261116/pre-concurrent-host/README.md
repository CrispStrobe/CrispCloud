# Final CrispCloud host qualification

Published implementation: `501c3a6667c7e295b3702a7d2857170eec6af416`.
Git tree: `aec8c6ea452d9ceebd1a6cec48b33ba29e4d4cb1`.
Canonical Office pin: `039c1e293052f548367f9ea3b0fa5ff56949ccaa`.
The earlier unpublished local commit `1db6ccdf8c718826e32d7ec1b8a26fcd3598e70e`
had the same tree; the accepted run started and ended at the published commit.

## Accepted results

| Check | Result |
| --- | ---: |
| Host transport, credentials, target and ribbon tests | 39 passed |
| Actual bundled German notice tests | 2 passed |
| Final host cohort | **41 passed** |
| Python Office sync and standalone parser sync/verifier regressions | **28 passed** |
| Strict analysis of actual host sources and all four test files | 8 targets, no issues |
| Strict analysis of vendored Zotero engine/editor sources | 4 targets, no issues |
| Declared-language formatting | 12 files, zero changes |
| Source and tracked-index Office guards | 2,459 managed files verified |
| Production source/asset/configuration inventory | 3,674 files unchanged |
| Resolved dependency library/configuration inventory | 5,822 files unchanged |
| Resolved dependency graph | 96 genuine packages |

The standalone parser remains pinned to
`4895712158127b2fc930d796e17035c3ca0dac62`. The normal vendor guard and tracked
guard both passed before testing, and the tracked guard passed again afterward.
Dependency declarations and locks were not resolved or rewritten during this run.
The temporary analyzer configuration on the actual host checkout was restored.
Canonical Quds package configuration was untouched.

The [receipt](receipt.json) records exact commands, target lists, UTC times,
counts, source identities, toolchain information, and log hashes. Its SHA-256 is
`9c44b1a6580b961dba808df80e29c4d2cdb30fcaa6fac3e2dade4fb1bd84cbdc`.
The before/after source and dependency JSON inventories preserve individual
hashes. Dependencies include their actual Dart libraries, declarations,
resolved package roots and relevant SDK/test-runner binaries. A native-only
Android plugin has no Dart `lib/`; this is recorded rather than replaced.
[setup-attempts.json](setup-attempts.json) describes the initial snapshot-helper
correction that stopped before any tests and is excluded from all counts.

## Harness and real assets

The harness uses symlinks to the actual CrispCloud application and vendored
Office libraries. No replacement Zotero implementation is involved.
[harness-assets.json](harness-assets.json) records the three additions to the
locked harness's Flutter asset section, matching production exactly:

- `packages/quds_office_engine/third_party/hyphenation/LICENSE`
- `packages/quds_office_engine/third_party/proofing/WORTLISTE_LICENSE`
- `packages/quds_office_engine/third_party/proofing/QUDS_WORDS_LICENSE`

The harness engine's `third_party` directory and the new license test are linked
to the actual host files. The test reads Flutter's real bundle, compares those
bytes with the source files, checks license-registry exposure, and compares the
standalone hyphenation notice with the complete upstream source header.

## Reproduce

Use immutable checkouts of the published CrispCloud implementation and the
canonical Quds pin above, named `CrispCloud` and `quds_office_suite` in the same
workspace. Restore the genuine pinned SDK and original enforced harness locks:

```sh
bash quds_office_suite/docs/validation/zotero-continuation-20261116/setup/bootstrap-local-tests.sh /absolute/workspace
source /absolute/workspace/zotero-toolchain/env.sh
```

Add exactly the three asset entries listed above under the host harness's
`flutter.assets`. Its dependencies and lockfile remain unchanged. Link
`zotero-toolchain/crisp-host-harness/packages/quds_office_engine/third_party` to
`CrispCloud/packages/quds_office_engine/third_party`, and link
`zotero-toolchain/crisp-host-harness/test/office_proofing_licenses_test.dart` to
the corresponding actual host test. The receipt preserves the before/after
harness declaration hashes; the dependency inventories include complete final
harness declarations and locks for comparison.

Run the included script with the restored paths and a fresh output directory:

```sh
python3 run-final-host.py \
  --repo /absolute/workspace/CrispCloud \
  --harness /absolute/workspace/zotero-toolchain/crisp-host-harness \
  --quds-source /absolute/workspace/quds_office_suite \
  --expected-quds 039c1e293052f548367f9ea3b0fa5ff56949ccaa \
  --published-source 501c3a6667c7e295b3702a7d2857170eec6af416 \
  --expected-tree aec8c6ea452d9ceebd1a6cec48b33ba29e4d4cb1 \
  --output /absolute/workspace/new-host-qualification
```

The script validates the implementation tree and canonical pin before running.
It uses the existing locked graph, executes only the recorded tests and gates,
captures source/dependency hashes, and restores the host analyzer configuration
even after a failed check.

## Scope

This is focused local host qualification, not a full application compile or a
new full production dependency resolution. Network, credentials and desktop
protocol responses use test doubles. No new live Zotero account/picker,
Word/LibreOffice interoperability, or operating-system keychain acceptance is
claimed. Canonical engine/editor tests are reported separately and are not
added again here. No GitHub Actions, workflow jobs, check statuses, waits or
reruns were used.
