# Independent recovery host review

Read-only review of the applied host overlay, the prepared patch, its rationale,
all production `WordConversionInspection.losses` consumers, and the downstream
copy/save/editor actions. Exact source SHA-256 identities are in the adjacent
JSON record. This is a source review, not a runtime acceptance receipt.

## Result

No concrete blocking classification, acknowledgment, copy-save, retry or
unknown-source regression was found in the reviewed overlay. No source files
were changed by this reviewer. Root owns the source checkpoint and targeted
runtime verification.

## Verified relationships

- Initialization attempts recovery only after source inspection returns
  `invalidInput`. Other inspection failures remain failures. Unknown inventory
  is admitted only when the canonical converter explicitly reports
  `recoveredTextOnly`; an ordinary structured success cannot replace an
  unavailable source inventory.
- Unknown inventory skips installed-converter discovery, offers only the
  built-in text method, and fixes that route to DOCX. No DOCM or installed
  converter choice is enabled by the new fallback.
- Every prepared recovered output is copied into immutable bytes and passes
  the full existing bounded OPC validator. Making source evidence nullable
  changes only the source-comparison checks after package validation.
- All production consumers of the inspection's `losses` list are in the
  conversion dialog. The recovery flag always forces acknowledgment, even
  when an unavailable source inventory produces an empty losses list. Counts
  are labeled as detected output content with the existing evidence limitation
  notice. The recovery explanation and complete text-only omission notice are
  displayed before saving; the UI does not claim source preservation.
- The installed-converter service still invokes inspection with a non-null
  source. It uses that operation to validate output and does not equate empty
  losses with fidelity.
- Save retry reconstructs only the validated filename while retaining the
  exact reviewed bytes, inspection object, extension, converter label and
  recovery flag. A failed save keeps the prepared copy available; changing the
  method or output clears the prepared copy and acknowledgment.
- `LegacyWordCopy.isTextOnly` now includes recovery identity, so the existing
  conversion action opens the saved recovery copy in the editor. Its target
  remains the captured source's create-only destination beside the original;
  filename collisions, path redirection and original replacement remain
  rejected by `LegacyWordCopyTarget`.
- The bulk conversion service adds an explicit recovery omission notice. The
  notice survives PDF conversion. The bulk dialog keeps its Save action
  disabled until the notices are reviewed, and it writes a new document.

## Prepared canonical parser fix cross-review

The separate parser owner's proposed fixes were also reviewed read-only.
No concrete new defect was found in the changed work-accounting, Word6 UTF-16
decoding or conservative charset/locale admission rules.

Each FAT-chain read consumes byte budget before materialization. Each eligible
CLX validation consumes candidate count, its full CLX size and the declared body
character count before any late validation failure. The limit exception reaches
the outer recovery refusal; failed candidates cannot reset the budget.
Contiguous candidates are views bounded by input, stream and CLX limits, and
the character budget bounds decoding and scalar validation.

For Word6/95, declared UTF-16 scales both simple and complex piece reads by two
bytes per code unit. The joined body passes the existing scalar validator, so
valid pairs may cross pieces while isolated or control-separated halves remain
invalid. Unsupported 8-bit charset/locale profiles are explicitly refused. The
comment rollback boundary is half-open, preserving annotations that begin in
the next story.

## Remaining validation

The source-bound targeted host tests and canonical parser regression tests
remain the appropriate runtime gates. This review did not run, duplicate or
reinterpret those gates and did not inspect GitHub Actions.
