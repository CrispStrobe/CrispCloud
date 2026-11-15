# Native Zotero citing — CrispCloud host qualification

The final local host run passed on CrispCloud source checkpoint
`6a53294ad086e2a1c6475d888fbed7dcc2591449`, with exact canonical Quds pin
`55d46a0fb5f7392dab1a604bc3c15126bd3e380d`. This includes the later incoming
main branches and terminal continuation discovered during implementation.
The runtime qualification uses actual repository sources and a genuine
resolved Flutter dependency graph.

## Results

| Check | Result | Evidence |
| --- | ---: | --- |
| Actual host transport/service/credentials/target/ribbon tests | **37 passed** | [Test log](host-tests.log) |
| Strict analysis with `--fatal-infos` | **Eight targets clean** | [Analyzer log](host-analysis.log) |
| Dart formatting | **Eight targets unchanged** | [Formatter log](host-format.log) |
| Whitespace | **Clean** | [Whitespace log](host-whitespace.log) |
| Genuine dependency resolution with enforced lockfile | **Passed; 96 packages** | [Resolution log](host-pub-get.log), [dependency inputs](host-dependency-inputs.json) |
| Normal and tracked-source vendor gates | **2,391 entries verified** | [Normal guard](host-vendor-verify.log), [tracked guard](host-vendor-verify-tracked.log) |
| Standalone parser pin, full inventory and actual bytes | **1,857 files unchanged** | [Parser proof](standalone-parser-proof.json) |
| Sources and dependency declarations before/after qualification | **1,582 files unchanged** | [Before](host-source-before.json), [after](host-source-after.json) |

The [qualification receipt](host-validation-receipt.json) records every command,
exit code, runtime identity, log digest, and source fingerprint. All seven
qualification commands exited successfully. The before/after source aggregate
is identical, the vendor manifest remained unchanged, and no source paths
changed during execution. The runtime is official Flutter 3.47.8 / Dart 3.13.7.

The managed inventory comprises **534 Quds files and 1,857 standalone parser
files**. The [sync plan](crisp-vendor-plan.json), [applied plan](crisp-vendor-apply.json),
[main-merge resolution](main-merge-resolution.json), and
[terminal-merge resolution](terminal-merge-resolution.json) retain integration
accounting. The main merge preserved incoming conditional-affix changes before
the normal guarded sync; the terminal merge changed no managed Office source.
All integration merges retained their parents. The final Quds source includes canonical
main through PR #46.

A cutoff snapshot found one further terminal continuation, `a965bfd4`, after
the first successful host run. It was merged at `6a53294a`, and the complete
host qualification was repeated on that delivered tree. The
[earlier f0f38636 receipt and logs](intermediate-f0f38636/README.md) remain
preserved as an intermediate record. The [source delta](host-rerun-source-delta.json)
confirms that Office sources and all eight host Zotero targets remained
unchanged across this integration; the new receipt additionally fingerprints
the added terminal sources. The two executions are not added together as a
larger test count.

## Final documentation pin

The delivered vendor manifest now pins canonical Quds
`fc37658c907edf6687eccb9564d3046283b49a3a`, which adds the final guides and
qualification evidence to the tested `55d46a0` source. Within the canonical
packages, only the engine and editor changelogs changed. The normal guarded
[final sync plan](final-vendor-plan.json) and [apply receipt](final-vendor-apply.json)
record those two writes and no deletions.

[Final pin verification](final-pin-verification.json) confirms that all
**1,582 measured host/vendored source and dependency files still exactly match
the completed runtime qualification**, before and after this final sync.
The [normal final vendor gate](final-vendor-verify.log) again verified all
2,391 managed entries against an immutable archive of `fc37658c`, and the
[final parser proof](final-standalone-parser-proof.json) confirms the standalone
parser remains unchanged. The original runtime receipt retains its actual
tested pin; runtime tests were not repeated for these documentation changes.

## Qualification scope

The host cohort contains 37 tests across the actual repository's
`office_zotero_citing_transport_test.dart`, `office_zotero_test.dart`, and
`office_zotero_ribbon_test.dart`. Fourteen cases exercise the new native citing
transport. The other 23 cover catalog/cloud transport boundaries, target
validation, credentials, and the Word ribbon entry point.

The new cases check both exact local document POST routes, JSON and UTF-8 body
limits, header restrictions, redirects, bounded response streams, the separate
native-dialog timeout, shorter per-request deadlines, disposal while awaiting
headers or reading a body, rejection of late results, and sanitized failures.
They use controlled test clients to exercise the actual host implementation.

Strict analysis covers eight relevant host source/test targets with
`--fatal-infos`. The qualification script also checks formatting, whitespace,
the normal vendor gate, and the gate's `--require-tracked` variant. Canonical
engine, controller, and dialog tests are recorded in the Quds repository and
are not counted as additional host test executions.

## Source and dependency evidence

[run-host-validation.py](run-host-validation.py) records source hashes before
and after execution. Its source inventory covers the actual host library,
the three host test files, the four vendored libraries, and their dependency
and analysis declarations. It records the full vendor-manifest hash and exact
Quds commit separately. Git HEAD is informational: publishing the same source
while tests run does not invalidate qualification; changing measured source or
the vendor manifest does.

The script verifies that both test and analysis package graphs resolve
`crisp_cloud` and all four local dependencies to the actual repository library
directories. It then runs `dart pub get --enforce-lockfile` in the prepared
harness and retains its manifests, lockfiles, package count, and source-root
mapping. Production dependency constraints remain unchanged. The resolved
harness is focused on these host imports; it does not resolve or build the
complete native application.

The standalone-parser proof compares the current pin, complete managed parser
inventory, and actual file bytes with the continuation's initial host commit
`fe22a0458acfa90c0cce457d20fecbaa85a260e6`. The normal vendor gates additionally
check the managed sources and Git executable modes. Parser changes must be
reviewed explicitly instead of being reported as an unchanged dependency.

## Reproduction

Use the official Flutter/Dart versions and genuine dependency inputs recorded
by the completed receipt. Reconstruct the focused harness with links to the
actual checkout and rebase only its scratch path dependencies. The existing
[setup guide](../zotero-20261115/SETUP.md) describes the harness approach. Resolve
its declared dependencies normally; do not substitute implementations or
handwritten package stubs. Ensure the canonical checkout's analyzer package
configuration maps to the same real source libraries.

Create an immutable checkout or archive of the exact Quds source pinned by
`tool/office_fidelity_manifest.json`. Publish or stage the intended managed
files before qualification so the normal tracked-source gate can validate
them. Then run:

```sh
python3 docs/validation/zotero-citing-20261115/run-host-validation.py \
  --harness /path/to/resolved-host-harness \
  --flutter-root /path/to/flutter-sdk \
  --quds-source /path/to/exact-quds-source \
  --expected-quds FULL_PINNED_QUDS_COMMIT
```

The script writes commands, exit codes, logs, before/after source inventories,
runtime information, dependency inputs, and parser proof into this directory.
It fails if a gate fails, the executed test count differs from 37, or source
identity changes while it runs.

## Acceptance boundaries

These are focused local host tests. They do not establish a full native app
build, a connection to a user's live Zotero database or private account, real
OS-keychain behavior, or acceptance in native Word with Zotero refresh. The
canonical fixture tests exercise real pinned citeproc output; they are
separate from a live desktop integration test.

No GitHub Actions were queried, awaited, or rerun for this qualification.
