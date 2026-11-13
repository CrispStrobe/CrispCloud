# Parser audit follow-up — 13 November 2026

This continues the [first audit](parser-audit-20261113.md) from
`de4566aa69f6e6c6b5347b8463f4ecb7995d35f1`. Seven further implementation and
acceptance checkpoints were saved to the existing GitHub branch before the
complete clean-checkout gate at
[`8bf4db2585288e293d10d8fcf6a2d17697c621c1`](https://github.com/CrispStrobe/legacy-doc-parser/commit/8bf4db2585288e293d10d8fcf6a2d17697c621c1).
The subsequent report/evidence commit changes no tested runtime, fixture or
acceptance-tool bytes. [PR #8](https://github.com/CrispStrobe/legacy-doc-parser/pull/8)
contains both audit passes.

## Reproduced defects and fixes

### Independent stories must own complete Unicode scalars

The structured reader validated the concatenated UTF-16 text buffer, but a
surrogate pair could cross two independent story ranges. Paragraph emission
could then borrow a code unit from the next story, leaving an isolated low
surrogate in that story. Three authored binary documents reproduced the gap:
main/footnote, main/endnote, and an unused spare-textbox range followed by an
emitted textbox. All three were accepted before the fix.

An emitted-story boundary guard now rejects those malformed inputs. Physical
piece and formatting-run boundaries may still divide the two code units of a
valid scalar; that supported behavior is unchanged. Positive controls retain
distinct supplementary characters in main and note stories, check run extents,
verify source immutability, and inspect both generated DOCX parts on VM and
actual compiled JavaScript.

Checkpoint: [`4ba81ab`](https://github.com/CrispStrobe/legacy-doc-parser/commit/4ba81ab73a9e4946030ec9fd7774496ebf8d290a).

### Field text must survive serialization exactly

The writer replaced TAB, CR and LF with spaces even inside quoted instruction
literals. Nested instruction slices suffered the same loss. The field metadata
reader also omitted Word's nonbreaking-hyphen, soft-hyphen and column-break
controls from cached results, despite the structured run path retaining them.
Six new regressions failed before correction.

Field instructions now use numeric XML character references for TAB, LF and
CR. This also preserves CRLF through XML end-of-line normalization. The option
is restricted to instruction text: invalid controls and unpaired surrogates
remain rejected, escaping remains active, and expansion counts against the
existing XML budget. Cached result metadata now maps the two hyphens to U+2011
and U+00AD and retains column breaks. No field is evaluated.

The shared binary/VM/JavaScript/schema matrix adds instruction-whitespace,
nested-instruction-whitespace and cached-controls cases, taking the field
inventory from five to eight. These checks compare parsed instruction strings
exactly, independently project visible text and break elements, and retain
private-result and unsupported-external-field controls.

Checkpoints: [`6e4f64b`](https://github.com/CrispStrobe/legacy-doc-parser/commit/6e4f64baec2f94de99d03c82f87dfd7c7bf15b59)
and [`cda8169`](https://github.com/CrispStrobe/legacy-doc-parser/commit/cda816963b06e0905afeb4b9bc4115e8b4b890c3).
Relevant contracts: [XML legal characters](https://www.w3.org/TR/REC-xml/#charsets),
[end-of-line normalization](https://www.w3.org/TR/REC-xml/#sec-line-ends), and
[WordprocessingML field-code text](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.fieldcode?view=openxml-3.0.1).

### Allocation validation must include tails without multiplying work

The raw compound reader could expand duplicate FAT references and ignored
declared FAT/DIFAT counts. Both reader paths accepted inconsistent mini-FAT or
version-4 directory counts. Directory and mini-FAT chains accepted a free-sector
marker as an end marker. Stream reads could stop at their logical size before
observing an invalid or cyclic final link. The initial 29-case regression set
recorded 22 failures; the completed allocation suite adds 39 tests.

The reader now validates every link of a requested stream chain, checks declared
table counts, and rejects duplicate FAT references before expansion. It copies
only logical stream bytes. Successful and failed chain suffixes are cached;
FAT, mini-FAT and directory metadata are immutable snapshots so cache decisions
cannot be invalidated by caller mutation. The mini-container cache is shared by
raw and bounded access. The raw API now explicitly documents that its source
must remain unchanged while the reader is in use.

Independent review caught two problems in an intermediate, uncommitted
candidate. Both were corrected before the production checkpoint:

| Control | Initial candidate observation | Saved implementation |
| --- | --- | --- |
| 65 short streams sharing a 1 MiB tail | 133,120 sector views, including 132,600 zero-length reads | 520 views, all for requested logical data; cached suffix validation avoids repeated tail work |
| Partial root mini-container lengths 1, 65 and 127 bytes | Rejected despite containing every requested byte | Accepted, matching the previous reader |

The original and revised probe logs are retained separately. The intermediate
candidate was not committed and has no retained exact source snapshot; these
logs are development observations, not a hash-bound release receipt.

Valid extra allocation capacity remains accepted and hidden from logical
output, consistent with [MS-CFB §2.7](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/b089deda-be20-4b4a-aad5-fbe68bb19672).
Positive controls also cover partial sectors, external DIFAT, multiple mini-FAT
sectors and version-4 directory counts. Shared-tail inputs are adversarial work
controls; their bounded reading does not certify global sector ownership or
complete CFB conformance. [MS-CFB §4.1](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/3c5249cc-1dc2-46f0-8faf-06c6a36f0085)
distinguishes requested-range validation from full-file validation.

Checkpoint: [`e104f2b`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e104f2be8a3d06957dae25c97692004f5d737514).

### Unsigned byte helpers must not truncate on JavaScript

A separate low-level reproduction showed `4294967297` round-tripping on the
VM while compiled JavaScript wrote and read `1`. The unsigned 64-bit helpers
used shifts that lost the high word in JavaScript.

Arithmetic encoding/decoding now preserves every integer from 0 through
2^53-1. Wider or negative integer values raise `RangeError`; failed writes
append no bytes. Twelve tests cover the 32-bit boundary, the maximum portable
integer, rejection cases and raw FILETIME preservation. Current bounded DOC
writing uses smaller stream sizes, so this is a low-level portability fix,
not evidence of previously observed DOC data loss. Full-width FILETIME bytes
continue through their separate raw-byte path, including an all-ones control.

Checkpoint: [`055dac7`](https://github.com/CrispStrobe/legacy-doc-parser/commit/055dac77a1638cd842c7af3b6f60b1635fc86a40).

## Clean-checkout acceptance

| Gate | Result at `8bf4db2` |
| --- | --- |
| Dart tests | **1,175 passed**; 62 added in this follow-up, 120 across both audit passes |
| Fatal-info analysis / formatting | No issues; all 224 maintained Dart files pass |
| Python controls | All 162 pass, including intentional negative controls |
| Retained corpus integrity | All 24 source hashes and OOXML package graphs verify |
| Actual compiled JavaScript | Existing DOC/51-media/ink gates plus eight field cases, four story cases, 30 malformed allocation rejections, seven valid allocation fixtures, shared-tail work and portable-integer controls pass |
| Independent Open XML SDK | All **263 DOCX outputs** have zero errors; source-built validator self-tests and positive/negative controls pass |
| Repeated generation | All **556 files** match byte-for-byte between complete runs |
| Previous corpus preservation | All **260 previous DOCX outputs** remain byte-for-byte identical; three new outputs added, none removed |
| Package publication dry run | Zero warnings; no publication |

The environment uses Dart 3.14.0, .NET SDK 8.0.428 and the repository's
hash-pinned Open XML SDK 3.3.0 inputs. Full receipts, source identities,
resolved dependencies, original regression logs, the three new binary/DOCX
pairs and independent review controls are retained in the
[follow-up evidence](evidence/parser-audit-20261113-followup/README.md).

No new native-rendering claim is made. The first audit's two measured
LibreOffice field differences remain documented; all five previously rendered
field DOCX files are among the 260 byte-identical outputs. Native Microsoft
Word behavior, arbitrary pagination, broader unsupported features and
downstream application pin updates are outside this follow-up.

Hosted GitHub Actions status is separate from these local clean-checkout
results. The branch remains available for review in PR #8.
