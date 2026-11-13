# Final combined portable and schema acceptance at c5ff75e7

All eight portable gates and the fresh Open XML SDK gate passed on clean
runtime `c5ff75e76163d9abbdd44a9f2a7c5ad210929289`, tree
`25bd05c12fa2272a32ec2aaba2cc0117be5bed96`. The complete source inventories
remained unchanged throughout both gates. This checkpoint combines the
qualified textbox fill/frame changes with the bounded ink transform and
pressure decoder, preserving the previous layout and media corrections.

| Gate | Recorded result |
| --- | --- |
| Dart 3.13.7 format | 208 files, zero changes |
| Static analysis | No issues, fatal infos enabled |
| Dart tests | **1,028 passed** |
| Corpus integrity | 24 original source hashes and package graphs verified |
| Python fidelity controls | **162 passed** |
| JavaScript document controls | Actual compiled legacy DOC controls passed |
| JavaScript media controls | 51 checks passed |
| JavaScript original WPF ink | 24 ISFs, 32 strokes, 96 points |
| JavaScript WPF header controls | 32 ISFs, 32 strokes, 160 points; one explicit source/native metric distinction |
| Publish dry run | Zero warnings; no package published |
| Open XML SDK 3.3.0, Office2019 | **254 DOCX outputs, zero errors** |
| Deterministic generation | Two complete **538-file** corpora, identical bytes |
| SDK controls | Self-tests passed; valid control accepted; both malformed controls rejected |

The 16 nonempty ink schema cases contain the 12 original WPF cases and four
transform/pressure cases. Each actual DOCX retains the exact ISF payload, the
expected positive stroke/point counts and an explicit `nativeInkEmitted: false`
claim. Every raw payload and count is bound to the separately generated WPF
fixture and decoded JSON. The compact maximum-2047 metric remains encoded as
2047 despite WPF's later maximum-1023 reload; that observed distinction is
explicitly required by the header JavaScript result and retained oracle tests.

This is portable/schema acceptance, not a Word rendering or editing
certificate. The separate [complete native corpus](../native-corpus-c5ff75e7/README.md)
retains the measured layout and appearance differences. The
[ink decoder scope](../../ink-decoding.md) describes supported records and
inert fallbacks; no guessed native ink placement or active ink object is added.

## Two independent decoder review checkpoints

Both review directories retain exact scripts, stdout, source copies, runtime
and fixture hashes, and explicit source identities:

- The original review at `e5afd69c30b2d94995aa367b783ba3d0771e80c2` made 23,998
  bounded calls, rejecting all 1,550 truncations and keeping all 24 unknown-tail
  streams inert. It also exercised 12,400 bit mutations and 10,000 seeded short
  inputs, without an exception or input mutation. This remains evidence for
  that earlier decoder, with its own unchanged source snapshot.
- The transform/metric review at `61d7e43c28dbaa2cde73d272ab62d009a34a8c66`
  used decoder bytes identical to this final runtime. It made 26,543 calls,
  rejecting all 1,831 truncations and keeping 32 unknown-tail streams inert,
  alongside 14,648 bit mutations and 10,000 seeded short inputs. No uncaught
  exception or input mutation occurred.

These finite probes establish the recorded boundary behavior; they do not
prove correctness for every possible ISF stream. Original path spellings and
all decoded/invalid/unsupported/limit status counts remain in the receipts.

## Earlier failures remain separate

`diagnostic/pre-format/` preserves the original failed format check at
`f255c9da9baed1fdd6034818b1c97069d44589d4`. It detected one formatting change
in the retained textbox inspection script, exited 1 and stopped. Its raw Git
objects, complete 948-file tracked inventory, both logs and unchanged-source
receipt remain explicit; it is not relabeled as the final successful run.

The other diagnostic subtree retains the preliminary 12-package schema run
that encountered a missing `/tmp/` directory, followed by the corrected SDK
report for the exact same DOCX bytes. The initial exceptions occurred before
package validation completed. These preliminary reports are distinct from
the complete clean 254-output gate above.

## Source identity and retained bytes

The portable receipt covers **1,258 tracked files** plus the dependency lock
and package configuration, for **1,260 inputs**. All **382 schema inputs**,
both complete generated corpora, source and SDK controls, build configuration,
recovery receipts and logs are retained. The validator was rebuilt with .NET
SDK 8.0.428 and runtime 8.0.34. Four reproducible validator DLLs are omitted
with exact sizes and hashes.

The launch records independently bind the complete before/after input maps,
exact harness arguments, driver and launcher hashes, explicit environment
overrides, successful exit codes and console logs to the same frozen commit.
The portable console records exactly equal its eight individual stage records.

`validation-artifacts.tar.xz` contains **1,546 files**, compressed to
**1,474,284 bytes**, SHA-256
`3c7180634c9d8c283b4feae748b522b3ae4fa000264dd4d5df6347c6b38ea9c5`.
The manifest inventories each member, omitted DLLs and the verifier source.

From the repository root:

```sh
python3 doc/evidence/continuation-c5ff75e7/seal_validation_evidence.py --repository . --self-test
```

The helper verifies exact full-gate, probe and launch command arrays; all four
actual JavaScript results; complete source/Git coverage; both corpora; every
SDK input/result; original failure attribution; and the nonempty ink evidence.
**44 semantic corruption controls** reject contradictions after outer archive
loading. Checks use explicit exceptions and remain active under optimized
Python. `verification.json` retains the observed verification result.

## Separate hosted CI observation

The exact runtime also completed [GitHub Actions run 43387392944](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43387392944)
successfully. The retained API observation identifies the successful `test`
job 131758985202 and `openxml-schema` job 131758984962, including all required
step outcomes. The returned decoded logs contain the 1,028-test and 162-control
results, all four actual JavaScript result objects, and the 254-output SDK gate.

**Hosted Dart was 3.14.0; local Dart was 3.13.7.** Hosted status and decoded logs
are retained separately and do not relabel the local source, generated corpora
or native render artifacts as CI downloads. `hosted-logs.tar.xz` stores the
exact returned log strings encoded as UTF-8, preserving line endings and BOM;
it is not the original GitHub ZIP. Its two members total 315,332 bytes and
compress to 42,956 bytes, SHA-256
`633642d04bc392ae7bce237b5e6ac01b890260a517b42712a460b03fc6a30146`.

The complete bundle, including these API/log receipts, is verified with:

```sh
python3 doc/evidence/continuation-c5ff75e7/verify_bundle.py --repository . --self-test
```

The additional hosted verifier binds exact run/job identities, required step
successes, all member hashes, the checked-out source, hosted toolchain, and
actual result markers. Seven targeted corruptions reject altered run identity,
failed jobs/steps, stale hashes and resealed contradictory SDK/JavaScript/head
logs, also under optimized Python. The original 1,546-member local archive and
its verifier remain unchanged. `bundle-files.json` inventories every file in
this directory except itself and Python bytecode caches.
