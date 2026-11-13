# Parser audit, third pass — 13 November 2026

This continues the [first audit](parser-audit-20261113.md) and
[second pass](parser-audit-20261113-followup.md), starting from
`7aee6425b74cfe9bf607c20e11e0a0dce8431322`. Ten further implementation and
acceptance checkpoints were saved to the existing GitHub branch. The complete
runtime and acceptance tools were tested from clean commit
[`b1dff952a11e7de058a924cf7da8752574d0fbc5`](https://github.com/CrispStrobe/legacy-doc-parser/commit/b1dff952a11e7de058a924cf7da8752574d0fbc5).
The subsequent report/evidence commit changes no tested source or fixture.
[PR #8](https://github.com/CrispStrobe/legacy-doc-parser/pull/8) contains all three
passes. Original evidence and reviewed goldens remain unchanged.

## Confirmed defects and corrections

### Compound directory names must retain their exact identity

Allocated directory names could silently truncate odd or oversized byte
lengths, omit a required terminator, stop at an embedded NUL, or accept
characters that conflict with storage paths. The initial regression run
recorded 23 failing checks across the raw and bounded reader APIs.

The decoder now checks the declared UTF-16 byte length, final terminator,
embedded NULs, and the four prohibited characters. It still ignores bytes
beyond the declared terminator and stale name fields in unused slots. Positive
controls retain 31-unit names, U+0005 metadata names, and supplementary Unicode.
These rules follow the allocated-name contract in
[MS-CFB §2.6.1](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/60fe8611-66c3-496b-b70d-a504c94c9ace).

Checkpoint: [`5c95f3a`](https://github.com/CrispStrobe/legacy-doc-parser/commit/5c95f3a29c5643d3b459de53c1fb685ee33c2dbf).

### A stream must not return another allocation owner's bytes

Fifteen authored corruption cases showed that individually bounded chains
could still overlap another regular stream, a mini stream, the root
mini-container, or FAT/DIFAT/directory/mini-FAT metadata. Reading the first
alias could return bytes before the second alias was examined.

The reader now records physical metadata sectors and performs one cached
ownership pass before a nonempty stream read. It keeps physical-sector and
mini-sector numbers in separate namespaces, rejects every affected stream
regardless of read order, and includes spare allocated capacity in ownership.
Each sector is visited at most once per namespace. Caller-built entries must
match the allocation-affecting fields in the immutable parsed directory.

This implements the single-directory-owner requirement in
[MS-CFB §2.7](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/b089deda-be20-4b4a-aad5-fbe68bb19672)
without making unrelated invalid chains eagerly fatal. Valid extra capacity,
partial final mini-containers, external DIFAT, and independent streams beside
an unrelated bad chain retain their previous behavior. This is not full CFB
conformance certification: padding, unused slots, timestamps, red-black
balancing, and all FAT-marker invariants are not newly enforced. The distinction
between requested-part validation and full validation remains explicit in
[MS-CFB §4.1](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/3c5249cc-1dc2-46f0-8faf-06c6a36f0085).

The second pass's deliberately shared-tail work control now requires rejection:
both readers reject all 65 aliases with **zero payload reads**. A separate valid
stream with 1 MiB allocated and 4,096 logical bytes retains the performance
control: four reads copy exactly **32 sectors**, with no spare-payload reads.
Historical receipts describing the earlier behavior have not been rewritten.

Checkpoint: [`93d5e4f`](https://github.com/CrispStrobe/legacy-doc-parser/commit/93d5e4f44a623b20279822f662f5c54e7b61cf19).

### Failed public-entry reads must not credit the read budget

Independent review found that a caller-built negative stream size reduced the
bounded reader's aggregate counter before the underlying reader rejected that
entry. Catching the error could therefore permit a later valid read beyond the
configured limit. On-disk stream sizes are unsigned; this was a public-model
boundary defect.

The wrapper rejects negative sizes before budget arithmetic. The regression
consumes 65 bytes, rejects a forged negative entry, consumes the remaining
65 bytes, and rejects a third read at an exact 130-byte limit. The same control
passes on the VM and actual compiled JavaScript.

Checkpoint: [`b1dff95`](https://github.com/CrispStrobe/legacy-doc-parser/commit/b1dff952a11e7de058a924cf7da8752574d0fbc5).

### Nested cached results are distinct from instruction text

The enclosing field's raw instruction includes nested fields and their cached
results. Valid cell, line, page, column, and hyphen controls in a nested cached
result could make an otherwise supported enclosing field inert. The separate
cached-result writer also dropped the column break and both hyphens. Six new
positive cases failed before correction.

The writer validates emitted literal instruction slices separately and checks
each typed child's instruction recursively. Nested cached results now retain
the same normalized controls as ordinary structured text. Nine positive cases
and six literal-instruction negatives establish that valid result controls are
preserved while the corresponding invalid instruction controls remain inert.
The shared binary fixture inventory grows to nine field cases, including one
mixed nested result with all supported controls. No field is evaluated.

Checkpoints: [`df6989f`](https://github.com/CrispStrobe/legacy-doc-parser/commit/df6989fc6fc51145c09ab716fa332806077b6fae)
and [`3d66705`](https://github.com/CrispStrobe/legacy-doc-parser/commit/3d6670589621ca295e892d6b75a84f70c5159c6e).

### Public field models must have unambiguous source ownership

Ten malformed caller-built models previously converted successfully: crossing
or duplicate ranges, missing or skipped parents, a child sharing its parent's
separator, and fields outside or without their named story. Inactive fields
could bypass some checks.

All fields now receive story-boundary validation before activation. A sorted
stack derives each field's immediate source-range parent and compares it with
the declared parent. The work is O(n log n) within the existing 20,000-field
limit. Valid adjacent fields, reverse input order, and exact instruction/result
boundaries remain supported.

Checkpoint: [`6e2c711`](https://github.com/CrispStrobe/legacy-doc-parser/commit/6e2c711521a5142d653ff876025b6609722c23ab).

### Native metafile output must inspect the actual image bytes

Caller-built image models could pair malformed or escape-bearing EMF/WMF bytes
with a forged `nativeEmbeddingAllowed: true` metadata flag. The native DOCX
writer trusted that flag, unlike the HTML path, which already inspected raw
records. Eighteen regressions reproduced the gap across inline images,
floating images, and textbox fills.

Every native image relationship now requires a fresh bounded structural check
of the immutable raw metafile bytes. The check uses the existing record and
escape policy, produces no SVG, caches each asset by identity, and applies a
64 MiB aggregate scan allowance. Rejected images retain their exact original
bytes as inert evidence and report the image limitation. A negative metadata
flag still vetoes embedding. Valid images retain their original bytes.

Twenty-four shared VM/JavaScript cases cover six valid and eighteen inert
outputs. Additional unit controls use a 1 MiB image referenced 100 times to
check that valid reuse stays within the inspection budget. An independent
review found no blocking issue in the final image-validation paths. This
extends the existing structural and escape-record policy; it is not a claim
to implement or validate every GDI operation.

Checkpoint: [`3950b87`](https://github.com/CrispStrobe/legacy-doc-parser/commit/3950b8757780a681b415b98e9555aada665dcd1e).

### List metadata must preserve labels without inventing number sequences

The list audit established three separate cases:

| Source case | Previous behavior | Corrected behavior |
| --- | --- | --- |
| Bullet/no-number restart bytes | Rejected valid ignored values or leaked them into model/native XML | Ignore start/restart fields when no sequence exists; retain strict checks for numbered levels |
| No-number level with literal text or ancestor placeholders | HTML dropped the whole label | Retain literals and numbered ancestors; replace only the empty self-number |
| Literal binary `%1`–`%9` text, outside explicit placeholder offsets | Reinterpreted literals as numbering placeholders | Reject explicitly before silently changing the label |

The restart behavior follows
[MS-DOC LVLF](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/500d1b05-cd15-46af-bc8f-03bc290d1bdd).
The label algorithm copies the stored label and substitutes only its explicit
placeholder positions; an empty level number does not erase the whole label.
See [MS-DOC §2.4.6.3](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/1a0bc623-211f-44f6-828b-51993f16e586)
and [level-number construction](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-doc/361e48e1-ae56-4b62-a950-01664b2cc006).

Literal `%1` through `%9` remains an **explicit unsupported source case**:
the current model and native
[`w:lvlText` contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.leveltext?view=openxml-3.0.1)
reserve those sequences. Parsing now raises a descriptive `FormatException`;
it does not produce an evidence package on that failure. Ordinary `%`, `%0`,
`%x`, a trailing percent, and a percent immediately before a true binary
placeholder still work. No invisible escape character is inserted into the
label. Twenty new tests cover the restart and label cases; the shared
JavaScript matrix contains nine supported and six rejected inputs.

Checkpoints: [`085cc99`](https://github.com/CrispStrobe/legacy-doc-parser/commit/085cc99c3db9ceb40590feb95536138db46e415d)
and [`21491c9`](https://github.com/CrispStrobe/legacy-doc-parser/commit/21491c99e96f89c171f8da734c9c2b05d8926c7b).
The integrated acceptance tools were saved in
[`9b2b685`](https://github.com/CrispStrobe/legacy-doc-parser/commit/9b2b6851ea7b4e2868f04c69a1f9afa8ee4e53f5).

## Clean-checkout acceptance

| Gate | Result at `b1dff95` |
| --- | --- |
| Dart suite | **1,300 passed**; 125 added in this pass, 245 across the three passes |
| Analysis / formatting | No issues with fatal-info analysis; **242** maintained Dart files unchanged by formatting |
| Python controls / retained corpus | **162** tests and all **24** source-hash/package-graph checks pass |
| Actual compiled JavaScript | DOC/media/ink/story gates plus nine field fixtures, public field ownership, directory names, allocation ownership, read-budget, list metadata and 24 public metafile cases pass |
| DOC-derived Open XML SDK corpus | **273 DOCX outputs**, zero errors; exact hash coverage, source-built validator self-tests and positive/negative controls pass |
| Separate public-model SDK corpus | **24 DOCX outputs**, zero errors, with raw EMF/WMF inputs and explicit model descriptions; these are not represented as binary DOC sources |
| Determinism | **586** DOC-derived corpus files and **49** public-model files match between independent generations |
| Previous output preservation | All **263 previous DOCX files** remain byte-for-byte identical; **10** new DOC-derived outputs, none removed |
| Source identity | Clean tested commit; **619** portable source hashes and the schema gate's **396** source hashes remain unchanged |

The final SDK coverage is therefore **297 outputs**, with the two input kinds
kept explicit. The environment is Dart 3.14.0, .NET SDK 8.0.428, Node 24.22.1,
Python 3.12.14, and the repository's pinned Open XML SDK 3.3.0 inputs.

An initial post-processing check for the separate public-model corpus resolved
relative validator paths from the acceptance launcher's directory instead of
the validator's actual working directory. The SDK itself completed with zero
errors. A separate final check resolved those recorded paths correctly and
verified exact file hashes and coverage. The original failed receipt and raw
validator report remain retained alongside the corrected final receipt; no
runtime or output bytes changed. Independent review recomputed the acceptance
counts, source identities, and previous-output comparison.

The optional `dart pub publish --dry-run` was blocked by automatic approval
review because it could contact pub.dev and disclose package contents or
metadata beyond the authorized audit/GitHub workflow. That optional step was
omitted rather than retried. Its partial log and the rejection explanation are
retained. The six completed portable gates all exited successfully; **this
pass makes no successful publication dry-run or publication claim**.

## Evidence and remaining boundaries

The [third-pass evidence bundle](evidence/parser-audit-20261113-third-pass/README.md)
contains original before/after development logs, exact final source identities,
resolved dependencies, command receipts, independent SDK controls, the ten new
DOC/DOCX pairs, and all 24 public-model image outputs and raw inputs.
Development logs are observations from the evolving working tree; the final
clean-checkout receipts provide the complete hash-bound implementation identity.

The first audit's two measured LibreOffice field-import differences remain
open. All five previously rendered field DOCX files are still byte-identical;
this pass adds no native-rendering claim. Microsoft Word rendering, arbitrary
pagination, full CFB conformance, the literal-percent label limitation, and the
broader documented fidelity gaps are not represented as solved. Downstream
application pins, package publication, and merging remain outside this pass.
Hosted GitHub Actions status is separate from the completed local acceptance;
the latest inspected runs were still queued.
