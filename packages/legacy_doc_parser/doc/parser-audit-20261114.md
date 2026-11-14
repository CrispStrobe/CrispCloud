# Parser audit continuation — 14 November 2026

## Result and source identity

This pass fixes confirmed section geometry and coverage defects, incomplete
public comment-reference validation, and stale state in a reusable compound
byte sink. It also makes CI validate the public-model export corpora that
previously required separate manual SDK runs.

The starting main commit was
`731e37032e11a3bc1ae6bdb0475fdcb48067bda4`.
All executable changes were validated on clean commit
`2f8a307f6066401445109b41466e367dcc94cb99`.
Later commits retain evidence and update documentation only. Work was saved
incrementally on `fix/parser-audit-20261114`, using expected-head, non-force
updates and remote-ref readback after each checkpoint.

The [final receipt](evidence/parser-audit-20261114/final-receipt.json) and
[evidence index](evidence/parser-audit-20261114/README.md) identify the actual
commands, sources, outputs and retained artifacts. This is portable and
package-schema acceptance; no new native Office rendering or review acceptance
is claimed.

## Confirmed gaps and repairs

### 1. Section geometry used storage widths instead of all source domains

Current and previous section-property states could retain values outside the
MS-DOC semantic domains. Public models could also send these values directly
to DOCX emission. A shared source validator now checks both parsed states and
public section models.

| Property | Accepted source domain in twips |
| --- | --- |
| Page width and height | 144 through 31,680 |
| Top and bottom margins | -31,665 through 31,665 |
| Left/right margins, header/footer distances, equal-column spacing | 0 through 31,680 |
| Gutter | 0 through 65,535 |

These domains follow [MS-DOC section properties](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/46c3ec54-53ff-4c0a-b0d6-07ad15d2546e)
and the referenced [XAS_nonNeg](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/e7503912-c08e-4661-a920-76e9c6c8a28b)
and [YAS_nonNeg](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/dd308448-1497-447e-a77f-0c06b9ff5712)
types. Optional values remain absent instead of becoming invented geometry.

A binary-valid gutter above 31,680 remains available in the parsed model.
Actual current or historical OOXML emission rejects that unsupported native
value explicitly, following [Word's pgMar contract](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/c13857a6-6aa5-4b53-a2a8-a8498e62085b).
It is never clamped. An inactive previous snapshot with a source-valid gutter
of 65,535 remains valid because that value is not emitted as active OOXML.

The independent fixture matrix checks malformed and boundary values in
current and historical binary records and public models. The compiled
JavaScript geometry group checks 70 rejected public conversions, 52 rejected
binary inputs, 48 exact parsed values and 44 emitted geometry cases.

### 2. Public section ranges could silently lose an entire section

A reproduced input contained one paragraph covering `[0, 2)` and sections
covering `[0, 3)` and `[3, 4)`. Conversion succeeded with only one preserved
section: the first boundary never matched a block ending, and the final
section was emitted anyway. Invalid geometry on the skipped section could
therefore avoid serialization-time validation.

Public sections now start at zero and cover the main body's end, matching the
normalized parser contract. The writer also rejects any intermediate section
boundary that was not emitted. This independently protects empty-body inputs,
where the main extent otherwise comes from the final section.

Every current section and its immediate stored previous snapshot receives
source-domain geometry validation before emission, including snapshots whose
revision mark is inactive. This does not apply native export restrictions to
un-emitted historical values.

The 21 regression tests include valid-valued malformed ranges, empty-body
multi-section negatives, all ten inactive historical geometry properties, and
positive controls for distinct two-section output, empty initial sections,
one-section empty bodies and the inactive large gutter. The two-section
positive checks values, XML placement, text and preservation counts.

### 3. Hidden comments could bypass anchor and range validation

Public comments were validated too late to cover every hidden member or
suppressed reply. An incomplete range could also be treated like an absent
range. The writer now validates each comment before visibility and parent
suppression:

- The anchor must belong to an existing story.
- Range endpoints must either both be absent or both be present.
- A present range must be ordered and stay within the anchor's owning story.

Valid point ranges at the beginning or end of a story remain accepted.
Header and auxiliary-story anchors, replies supplied before their parent,
and anchors outside their own selected range remain supported. The existing
empty-main-story policy is preserved.

There are 43 new VM regression cases covering visible, hidden and
hidden-parent cases, missing endpoints, reversed ranges, invalid/gap anchors,
cross-story ranges and positive boundary controls.

### 4. Draining a compound byte sink left a stale logical length

`ByteSink.takeBytes()` drained its underlying builder without resetting
`_length`. A later reuse could then insert incorrect alignment padding.
The method now clears the logical length after successfully taking the bytes.

The tests check reuse at alignments four and eight, empty drains, length,
padding, nondraining `toBytes()`, and independence of previously returned
arrays. The same reuse checks run in the compiled JavaScript compound
acceptance group, alongside its existing mutation matrix.

The current compound writer normally uses these local sinks once. This is a
confirmed helper-state defect; this audit does not claim that the current
one-shot writer was already producing corrupt files from this defect.

### 5. The automated SDK gate omitted existing public-model exports

The previous CI gate validated only the DOC-derived corpus. Six existing
public-model generators, totaling 325 outputs, were left to separate manual
runs. The gate now includes them and the 44 new section-geometry outputs.

| Corpus | Packages |
| --- | ---: |
| DOC-derived conversions | 1,057 |
| Public metafiles | 24 |
| Public compound/OLE/VBA | 17 |
| Public character/paragraph formatting | 106 |
| Public table formatting | 44 |
| Cached-field structure | 88 |
| Display-field revision evidence | 46 |
| Public section geometry | 44 |
| **Total** | **1,426** |

The seven public groups have independently pinned case names and input/output
paths. The gate rejects missing, duplicate or extra cases, malformed manifests,
unchecked baselines, substituted or escaping paths, missing files, output
aliases and unregistered files. Every corpus is generated twice; retained
source, output and metadata files must match byte for byte.

Each group has exact hashes, an individual SDK report and unchanged-input
checks. Source provenance now includes the executed
`tool/*_web_acceptance.dart` helpers. CI retains the generated public corpora
with its schema artifact. Seven new focused Python test methods exercise
inventory sizes and corruption/repetition controls.

The executed current DOC-derived count is 1,057. The earlier 1,046 count
belonged to an older inventory and was stale in the validator README; that
documentation is corrected. The new 369 public packages are not all newly
implemented formats: 325 were existing outputs newly covered by this gate.

## Measured validation

| Check | Result on the final executable commit |
| --- | --- |
| Full Dart suite | 3,688 passed |
| Dart analysis | No issues |
| Formatting | 338 maintained files; zero changes required |
| Compiled JavaScript acceptance | 34 groups passed |
| Python fidelity/control suite | 195 passed |
| Retained source/package oracle | 24 source hashes and OOXML package graphs verified |
| Open XML SDK 3.3.0, Office2019 rules | 1,426 packages; zero schema errors |
| SDK controls | Internal self-tests passed; one independent valid package accepted; both independent malformed packages rejected |
| Repeated SDK corpus generation | All eight groups byte-identical |
| Provenance | Clean source commit; parser/generator/validator inputs and validator build artifacts unchanged |
| Package publication dry run | Passed; zero warnings; nothing published |

The .NET validator was freshly built with .NET SDK 8.0.428 using the repository's
direct-compiler fallback and hash-pinned NuGet archives. The ordinary
`dotnet publish` attempt failed because the sandbox could not create its
named migration mutex; its failed-build receipt and log are retained.
The fallback runs the same validator, dependency hash checks and controls.

The tests reproduced the defects before the repairs:

| Regression group | Before repair | After repair |
| --- | --- | --- |
| Geometry and reusable byte sink | 109 passed, 108 failed | 217 passed |
| New comment cases | 23 passed, 20 failed | 51 passed including eight existing thread tests |
| Section coverage and inactive history | 5 passed, 16 failed | 248 passed including geometry, native-recovery fixture and revision tests |

The early portable checkpoint at `64901c6` has its own receipt. The final
3,688-test and 1,426-package results belong to `2f8a307`; they are not
retroactively assigned to that earlier checkpoint. Full commands, logs,
source hashes, dependency lockfile, SDK reports and the new 44 DOCX outputs
are retained in the compact final archive.

The new comment and public section-range test files execute on the Dart VM.
The 34 JavaScript groups are a separate, explicitly defined acceptance suite,
not a claim that every VM test also ran in JavaScript. The retained corpus
oracle checks source hashes and package graphs; it is not a new native render.

## Recovery and storage

The interrupted session's runtime fixes survived on GitHub. The previous
audit branch ended at `4de67fe946bd13304e5999759f1d9846e9a50864`;
merge `83acdf1c8b6b1b6346f0744988ef3d15f9fa08ff` integrated it into main,
followed by the macOS fixture-path fix at `731e370`.

The fifth-pass control archive names 17 data ZIPs. Only data parts 001–004 and
the control archive survived. Two recovery checks verified their ZIP CRCs and
all 3,124 retained manifest members against their SHA-256 values.
**10,979 of the declared 14,103 files remain absent**, in parts 005–017.
Historical portable/SDK receipts are usable within their recorded scope.
Missing native artifacts cannot be reconstructed from the transcript or
counted as independently reverified results. See the
[recovery index](evidence/parser-audit-20261113-fifth-pass/README.md).

The initial local filesystem filled while unpacking a Dart SDK, before
production edits. Its numeric quota could not be measured after command
startup failed; elevated cleanup was rejected by the environment policy.
A fresh temporary filesystem reported 4.9 GiB and supported the remaining
work, with about 3.1 GiB free after the final checks. Installation archives
were removed after extraction. The replacement is temporary; the code,
tests, reports and compact evidence are saved remotely.

## Remaining scope

- Scalar geometry validation does not prove that combined margins and page
  dimensions form a physically usable layout.
- Binary historical fixtures verify retained snapshots; public-model fixtures
  separately exercise emitted `sectPrChange`. These checks do not establish
  native editor accept/reject behavior.
- This pass did not rerun Word or LibreOffice rendering. Exact pagination,
  field recalculation differences, arbitrary drawing/metafile behavior and
  complete revision topology remain bounded by the existing
  [fidelity contracts](fidelity-status.md).
- Compound ownership/allocation paths were reviewed without finding another
  substantiated read-side defect in this pass. That is not a claim of complete
  CFB conformance.
- Hosted Actions runs were queued when the final local evidence was recorded.
  The recorded local acceptance does not represent a completed hosted run.
