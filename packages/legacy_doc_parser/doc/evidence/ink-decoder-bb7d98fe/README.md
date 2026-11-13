# Independent ink decoder acceptance at bb7d98fe

The bounded ISF decoder and its nonempty schema fixtures passed the complete
portable and fresh Open XML SDK gates at clean parser commit
`bb7d98fe25cc6e3e69fdad3a2483a6fe08e83dfc`, tree
`cd8a4dae3208c45f3465be9f71d7cd3c789d1db0`. Source inputs remained unchanged.
The independently authored inputs come from the retained
[Windows WPF oracle](../wpf-isf-oracle-20261113/README.md).

| Gate | Recorded result |
| --- | --- |
| Dart 3.13.7 format | 202 files, zero changes |
| Static analysis | No issues, fatal infos enabled |
| Dart tests | 992 passed |
| Fidelity corpus integrity | 24 original source hashes and package graphs verified |
| Python fidelity controls | 162 passed |
| JavaScript | Legacy DOC controls, 51 media checks, and 24 ink cases passed |
| JavaScript ink output | 32 strokes and 96 points decoded |
| Package publish dry run | Zero warnings; no package published |
| Open XML SDK 3.3.0, Office2019 validation | 242 generated DOCX packages, zero errors |
| Deterministic generation | Two complete 513-file corpora, identical bytes |
| SDK controls | Self-tests passed; valid control accepted; both malformed controls rejected |

The 12 new nonempty schema cases cover all six independent WPF case families
in compressed and uncompressed form. Every case has nonzero strokes and points.
The verifier binds each raw ISF payload and decoded count to WPF's reloaded
JSON, then checks the actual DOCX evidence part and its metadata. The source
payload remains exact. All 12 cases explicitly retain
`nativeInkEmitted: false`; no native Word ink element is produced.

This acceptance establishes bounded stroke decoding, rejection behavior,
source preservation and schema validity. It does not establish OfficeArt ink
placement, native Word editing, recognition, complete ISF support or Word
rendering. Unsupported streams expose an explicit inert result rather than a
partial stroke collection. The [decoder scope](../../ink-decoding.md) describes
the supported records and limits.

## Independent decoder probes

The archive retains the two original review scripts, exact stdout, copied
decoder source, source/Dart/fixture hashes and the receipt from clean review
commit `e5afd69c30b2d94995aa367b783ba3d0771e80c2`. The reviewed decoder bytes are
identical to the accepted decoder at `bb7d98fe`; both source identities remain
explicit, with raw Git objects and an optional repository check.

The boundary probe distinguishes empty drawing-attribute blocks from absent
blocks, and rejects empty paint/packet-descriptor tables. The separate bounded
probe made **23,998 calls**:

- All **1,550 truncations** were rejected.
- All **24 appended unknown body tags** returned an unsupported result without
  partial strokes. All 24 trailing-byte additions were rejected.
- **12,400 one-bit mutations** and **10,000 seeded short inputs** completed
  without an uncaught exception or an input-byte mutation.

The resulting status counts were 4,045 invalid, 15,829 unsupported, 4,060
decoded and 64 limit-exceeded. A mutated input can remain a valid stream; the
probe checks bounded behavior and preservation, not universal rejection.
These finite controls are not a proof about all possible ISF inputs. Original
workspace paths remain in the retained scripts and command receipts.

## Original schema setup failure

`diagnostic/` retains the original 12-package prepared corpus and two distinct
SDK reports. The first report has 12 `DirectoryNotFoundException` results
because the default `/tmp/` directory was unavailable. Package validation did
not complete in that attempt. The later corrected report validates the same
12 DOCX byte streams with zero errors. Both reports' input hashes are checked
against the retained prepared packages.

Those preliminary reports do not contain a clean whole-repository acceptance
receipt. They remain diagnostic records and are not attributed to the later
full run. The separate complete 242-output acceptance at `bb7d98fe` retains
its own exact commands, source identity, logs, complete corpora and SDK reports.

## Retained evidence and verification

`validation-artifacts.tar.xz` contains **1,360 files**, compressed to
**1,379,788 bytes**, SHA-256
`239c1714f720e9653cc6f490ecb65ca883cdad42910b8192c03339732d04b6b1`.
The portable receipt captures all **1,067 tracked files** plus the dependency
lock and package configuration, for 1,069 inputs. All **262 schema inputs**,
including the 92 original Windows fixture/oracle files, are retained. The
validator was rebuilt with .NET SDK 8.0.428 and runtime 8.0.34. Four reproducible
validator DLLs are omitted with exact sizes and hashes; compiler response,
build, package and SDK recovery records remain included.

From the repository root:

```sh
python3 doc/evidence/ink-decoder-bb7d98fe/verify_bundle.py --repository . --self-test
```

The verifier checks every retained archive member and bundle file, exact
command inventories, all 21 full-gate command arrays and both independent
probe commands, all three actual JavaScript result objects, source and Git
identity, both complete corpora, every SDK input/result, and nonempty ink
evidence against WPF. **38 targeted semantic corruption controls** reject
contradictions after outer archive loading, including altered JavaScript
counts, false probe results, erased setup failures, empty ink and an invented
native-ink claim. Explicit checks remain active under optimized Python.
`verification.json` retains the observed acceptance result.

The separate hosted [Dart package run 43384351772](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43384351772)
also succeeded at exact `bb7d98fe`: both `test` and `openxml-schema` jobs passed.
`hosted-ci.json` retains the run identity and job response. The local archive
above is a separate measurement and is not labeled as downloaded CI output.

`bundle-files.json` inventories all files in this directory except itself and
Python bytecode caches. Verification does not rerun Office, Dart or the SDK.
