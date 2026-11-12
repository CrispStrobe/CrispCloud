# Review-data attribution for sealed checkpoint 8060ac1

This audit separates two native DOCX → DOC bridge losses from parser behavior.
It reads the unchanged [sealed native report](evidence/8060ac1/native-report.json.xz)
and the exact saved DOC/DOCX artifacts. It does not rerun LibreOffice or replace
the historical report. The [machine-readable receipt](evidence/review-loss-audit-8060ac1.json)
pins the archive, uncompressed report, input/output files, and the separate
source used by the revision-ID probe.

## Observed losses and attribution

| Fixture | Authored DOCX | Native DOC bridge and native DOCX projection | Parser result | Attribution |
| --- | --- | --- | --- | --- |
| `word-compatibility` | One section-property revision, by `Independent Fixture`, containing previous page size 20000 × 25000 twips and page-number start 99 | No section-property revision; neither of the two binary SEPX groups contains `SWall` or `SPropRMark` | No corresponding section revision | History disappeared before the parser received the DOC |
| `comment-threads` | Three comments: a reply before its parent, a resolved root, and an independent unresolved comment | Two comments; the reply text is absent from the binary, both extended records have depth/parent/flags zero, and the root is unresolved in the native DOCX | The same two comments, authors, initials, text and parent relationships | Reply and resolved state disappeared before parser conversion |
| `comment-threads` date | Root date ends in `09:00:00Z` | Native DOCX also writes `Z`; the binary stores DTTM `2816545344` | Root date ends in `09:00:00`, preserving the wall-clock fields | Zone representation differs; binary DTTM does not store a timezone |

Both DOCs have zero CLX property records and one piece with PRM zero, so the
inspected section-history absence is not explained by a hidden piece-level
property group. The section-review author and missing reply text are absent in
both ASCII and UTF-16LE scans of their respective complete binary files. These
are fixture-specific observations, not general string-search proofs of absence.

All three recorded cycles retain the same already-imported comment/revision
state. Each comment cycle repeats the native `Z` / parser zone-free
representation difference; none adds a comment/revision difference relative to
the preceding parser import. This does not repair the earlier bridge losses or
make the fixture a positive test of binary thread reconstruction.

The original and native DOCX hashes in the receipt are those in the sealed
report. The audit independently verifies the saved native and parser DOCX files,
the two DOCs, and every saved semantic snapshot for these cases. The original
authored DOCX hash is reported from the sealed receipt, not rechecked against a
possibly regenerated source file.

## Independent positive checks and limits

`test/legacy_word_section_revisions_test.dart` independently constructs binary
section history. `tool/fidelity/section_review_probe.py` asserts both previous
and current properties against authored expectations even when the native
renderer drops its own review data. The native-loss case above does not weaken
those expectations.

`test/legacy_word_comment_threads_test.dart` independently constructs the
extended binary records and checks parent/reply relationships, last-paragraph
joins, multiple paragraphs and invalid trees. The record has no resolved/done
state; the writer does not fabricate one. Ink flags and retained ISF bytes do
not establish editable ink. See [revision and comment boundaries](revisions-comments.md).

The separate public-model probe emits inserted text in the main, header,
footnote and comment stories, plus row-format changes in the latter three.
Nine native revisions receive distinct IDs `0` through `8`. The main run is
split into three inserted fragments at its note and comment anchors. The probe
checks the expected part/kind counts as well as uniqueness, so dropping a story
cannot pass merely by leaving fewer distinct IDs. This verifies identifier
allocation; it does not establish full cross-story review semantics, native UI
accept/reject behavior, moves, or row insertion/deletion. Its source is identified
separately from the historical `8060ac1` parser.

## Reproduce

The [sealed input archive](evidence/review-loss-inputs-8060ac1.tar.xz) contains
the 24 exact DOC, native/parser DOCX and semantic-snapshot files inspected by
this audit. Its SHA-256 is
`e29d406dde763f9dd17ba48e71f51171ef276ee58ea09dc1ad03e83c4b949d4e`.
Every member was verified against the sealed report before and after archiving.
The archive uses sorted relative paths and zero USTAR timestamps/owner IDs;
it does not depend on the original temporary directory surviving.

From the repository root, with Dart dependencies already installed, extract
into a new directory and run:

```sh
mkdir build/review-loss-inputs-8060ac1
python3 -m tarfile -e doc/evidence/review-loss-inputs-8060ac1.tar.xz \
  build/review-loss-inputs-8060ac1
python3 tool/fidelity/review_loss_audit.py \
  --report doc/evidence/8060ac1/native-report.json.xz \
  --native-run build/review-loss-inputs-8060ac1 \
  --dart /path/to/dart \
  --output build/review-loss-audit-reproduced.json
```

The runner requires the exact archived report and verifies all inspected file
hashes before executing the companion Dart probe. Mismatched report/DOC bytes,
missing snapshots, unexpected observations, lost native revision elements and
duplicate IDs fail the audit. It refuses to overwrite an existing receipt. The
recorded source commit is a base identity accompanied by a dirty-worktree flag
and exact source hashes; it is not a claim that uncommitted audit code belonged
to that commit. Reproduction on a later source tree intentionally records new
source provenance while keeping the sealed inputs fixed.
