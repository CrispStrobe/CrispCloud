# Clean native and schema checkpoint 6b2b611

The clean source snapshot `6b2b6116eeaf2d416f702081470b1d802952b535` and pushed commit
`34e14841ef679c6b480673ef5be354286dbd67dc` have the identical Git tree
`1853ed03beb9ca2afb8158f6c46fb0cb1da064d5`. Later documentation and evidence additions do not change these
measured source bytes.

## Measured result

22 of 22 original inputs imported, and
22 retained their initial page counts.
6 initial outputs matched page text, word geometry,
and RGB pixels exactly on the recorded renderer. 2
reviewed source goldens reproduced. 22 inputs
completed all 3 requested DOCX → native DOC → parser cycles
(66 completed cycle imports). The run records
0 cases with execution/import errors and
0 strict structural matches with the
native DOCX projection.

These are separate measurements. Equal page counts do not establish exact
pagination; exact pixels do not establish retained review or editing semantics.
Structural differences include explicit defaults, representation changes,
native bridge losses, inactive stories and unimplemented semantics. The complete
report retains each difference without automatically classifying it as parser
data loss. Microsoft Word was not executed: native measurements use the recorded
LibreOffice, Poppler and font identities.

| Input | Initial pages | Exact initial RGB/text/geometry | All 3 cycles completed |
| --- | --- | --- | --- |
| `formatting` | 1 → 1 | No | Yes |
| `word` | 1 → 1 | No | Yes |
| `word-compatibility` | 2 → 2 | No | Yes |
| `table-borders` | 1 → 1 | No | Yes |
| `story-media` | 1 → 1 | No | Yes |
| `comment-threads` | 1 → 1 | Yes | Yes |
| `note-markers` | 1 → 1 | No | Yes |
| `bookmarks` | 1 → 1 | No | Yes |
| `content-controls` | 1 → 1 | Yes | Yes |
| `content-controls-legacy` | 1 → 1 | Yes | Yes |
| `word-altchunk` | 1 → 1 | Yes | Yes |
| `linked-textboxes` | 1 → 1 | Yes | Yes |
| `officeart-shapes` | 1 → 1 | No | Yes |
| `linked-textboxes-native` | 1 → 1 | Yes | Yes |
| `emf-vectors` | 1 → 1 | No | Yes |
| `wmf-vectors` | 1 → 1 | No | Yes |
| `linked-textboxes-compact` | 1 → 1 | No | Yes |
| `list-continue` | 1 → 1 | No | Yes |
| `list-restart` | 1 → 1 | No | Yes |
| `word14-margin-origin` | 1 → 1 | No | Yes |
| `word16-page-origin` | 1 → 1 | No | Yes |
| `poi-simple-table2` | 1 → 1 | No | Yes |

## Independent validity and portable checks

The freshly built Open XML SDK 3.3.0 gate accepted all
129 required converted DOCX outputs with
0 schema errors. Exact file coverage and hashes,
deterministic generation, unchanged inputs and positive/negative validator
controls passed. This result does not certify rendering or complete semantics.

The portable gate passed 616 Dart tests, 104 Python tests,
whole-package analysis and formatting, JavaScript/Node DOC acceptance, and
44 media acceptance checks. The package publish dry
run reported zero warnings; no package was published.

## Retained files and reproduction

- `native-report.json.xz` contains the complete native report, compressed without
  changing any JSON bytes, including every comparison, cycle, stage, and
  source/output/code/tool/font receipt.
- `schema-report.json.gz` contains the full independent schema-gate report.
- `package-checks.log.gz` contains complete portable-gate stdout/stderr.
- `summary.json` indexes per-input results and verifies the compressed and
  original report bytes with SHA-256 hashes.

Source fixtures and cycle inputs are unchanged. No reviewed golden was updated.
Original OOXML → native binary changes remain separate from parser changes.
The earlier [8060ac1 failure](../8060ac1/README.md) remains retained unchanged.

Run the commands in [the oracle guide](../../fidelity-oracles.md) from the
recorded source commit, with the recorded Office, PDF tools and fonts. To read
the complete native report, Python's standard `lzma` module is sufficient:

```python
import json, lzma
from pathlib import Path
report = json.loads(lzma.decompress(Path("native-report.json.xz").read_bytes()))
```
