# Native qualification of the combined storage continuation

**790 tests passed across 43 suites, with zero failures, skips or error events.**
The exact qualified source is `331981649872e363253aef13f57a638e5747b8e5`, tree
`6ec8e483ff2c597c145dfcff4e3f75331ad9faae`. Execution ran on Linux x86-64 with
Flutter 3.47.8 / Dart 3.13.7, using real native hooks and the committed dependency
lock. No dependency override or native-hook disabling was used.

The run started at 2026-11-14 20:47:40 UTC and completed at 20:51:53 UTC.
All **8,382 recorded inputs** matched before and after; HEAD, tree and clean
Git status also remained unchanged. The inventory includes every tracked file
outside `docs/evidence/`, plus the generated root package configuration and
package graph. Matching endpoint hashes do not prove absence of transient
writes between those observations.

## Runtime coverage

| Cohort | Suites | Passed |
| --- | ---: | ---: |
| Delta core, safety, S3 profile and provider admission | 4 | 159 |
| Existing pCloud/Nextcloud/S3 adapters and localized settings | 4 | 159 |
| Bandwidth, queues, scheduling, recovery and ordinary provider transfers | 27 | 304 |
| Office host lifecycle, ribbon, worksheet and native save workflows | 4 | 61 |
| Portable mesh parser and preview widgets | 2 | 40 |
| File-operation backends and publication phase guards | 2 | 67 |
| **Total** | **43** | **790** |

Counts exclude hidden framework setup/loading completions. The cohort includes
the existing bandwidth manifest, with its settings suite counted once. The
file named `transfer_bandwidth_browser_test.dart` ran on the native VM in this
invocation; its filename does not establish browser execution.

The S3 profile uses mock fault injection and one real loopback HTTP server with
signed HEAD/GET requests, exact conditional ranges, complete output comparison
and native staging. It does not establish interoperability with a live S3
deployment. The profile's size ceilings are enforced bounds, not a claim that
an 8 GiB fixture was executed.

## Evidence

- [Exact native command](native/command.json), [metadata](native/metadata.json),
  [per-suite summary](native/summary.json), and [raw events](native/stdout.jsonl).
- [Before](native/inputs-before.json.gz) and
  [after](native/inputs-after.json.gz) SHA-256 input inventories.
- [Independent review](independent-review.json): a second parse agrees with all
  counts, suite coverage, source hashes and original receipt artifact hashes.
- [Strict analysis](analysis/receipt.json): all 18 selected source/test files
  passed with no issues and unchanged inputs.
- [Python gates](python/receipt.json): 8 Office-sync, 19 legacy-parser-sync and
  23 host-evidence tests passed, plus verification of all 2,185 managed Office
  files. [The overlap record](python/source-overlap.json) explains the unrelated
  live-fixture lint commit during the last Python gate. All nine Python inputs
  stayed unchanged; the wrapper's nonzero aggregate status records that Git
  transition rather than a failed gate. Every gate subprocess exited zero.
- [Environment](environment/qualification-environment.json), exact Flutter
  version, launcher, committed manifests and historical toolchain setup.
- [The runner](run_delta_qualification.py) and the
  [suite manifest](../native-suites.txt) preserve the execution method. The
  runner expects the recorded `../toolchain/run` launcher; a developer with an
  equivalent installed toolchain can run the listed Flutter command directly.

The native stderr retains a Windows compiler-probe message emitted on Linux;
the actual native build/test invocation completed with exit code zero.

## Office output preservation

The run produced **54 Office artifacts**: 27 host fidelity outputs/references,
4 fill, 6 style-history and 17 worksheet-state artifacts. All were modified
inside the recorded run window. The independent review records each original
path, size, timestamp and SHA-256; the exact bytes are retained under
[`host-outputs/build/`](host-outputs/build/).

ZIP CRC, XML well-formedness and primary-part checks passed. The Flutter suites
assert saved package semantics through real host/editor paths and intercepted
provider writes. These results are separate from external OpenXML schema
validation, external Office rendering and live-cloud acceptance.

The canonical Office branch separately passed 115 native cases at
`cb42ef232e5794ac4c147ef1992133cf8710ab01`; its evidence and additional sorting
regression are preserved in
[quds_office_suite PR #12](https://github.com/CrispStrobe/quds_office_suite/pull/12).
Those 115 are not added to the 790 combined-tree total.

## Prior attempts and limits

The [pilot](pilot/) retains its raw failures from old upload/unbound-plan test
expectations. Its worktree changed during execution, so it is not qualified.
The [first strict analysis](prior-analysis/) retains eight pre-existing style
infos in the two historical live-test fixtures; the final source fixes them.

Ten Nextcloud/ownCloud live mutation scenarios are explicitly skipped in their
separate opt-in suites, which were not executed here. They are not part of the
790 passes. Automatic delta queue integration, durable delta restart/recovery,
remote delta writes, browser/mobile packaging, external-writer CAS and prompt
abort of a stalled provider remain outside this increment. See the
[delta profile](../../../storage-delta-profile.md) for the exact contract.
