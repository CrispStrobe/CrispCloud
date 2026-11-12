# Native round-trip failure at clean checkpoint 8367ce0

The clean source snapshot `8367ce004f2a40d99fbae1eabc00d0053ceb1dab` and pushed commit
`d28be0a173415ebb392a8309aacdbe2bb1a50da7` have the identical Git tree
`9cf883d7829627051a2f1068235dfe20d2e37383`. Later documentation and evidence additions do not change these
measured source bytes.

## Measured result

24 of 24 original inputs imported, and
24 retained their initial page counts.
6 initial outputs matched page text, word geometry,
and RGB pixels exactly on the recorded renderer. 2
reviewed source goldens reproduced. 23 inputs
completed all 3 requested DOCX → native DOC → parser cycles
(69 completed cycle imports). The run records
1 cases with execution/import errors and
0 strict structural matches with the
native DOCX projection.

This run exited with status 1. The first native DOC re-export of
`header-textbox-first-enabled` fails import with `Ambiguous Word shape anchor`.
The initial controlled DOC succeeds, and the default-header case completes all
three cycles. The exact regenerated DOC and stack trace are retained below;
this is a new measured regression case, not a complete native pass.

The contemporaneous structural audit also found that the measured text oracle
counts paragraph tab-stop definitions as textual tabs. Such story/offset
differences require corrected replay of the exact retained DOCX files before
being classified as data loss. The original report remains byte-exact.

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
| `header-textbox-alias` | 1 → 1 | No | Yes |
| `header-textbox-first-enabled` | 1 → 1 | No | No |

## Independent validity and portable checks

The freshly built Open XML SDK 3.3.0 gate accepted all
193 required converted DOCX outputs with
0 schema errors. Exact file coverage and hashes,
deterministic generation, unchanged inputs and positive/negative validator
controls passed. This result does not certify rendering or complete semantics.

The portable gate passed 761 Dart tests, 129 Python tests,
whole-package analysis and formatting, JavaScript/Node DOC acceptance, and
51 media acceptance checks. The package publish dry
run reported zero warnings; no package was published.

## Retained files and reproduction

- `native-report.json.xz` contains the complete native report, compressed without
  changing any JSON bytes, including every comparison, cycle, stage, and
  source/output/code/tool/font receipt.
- `schema-report.json.gz` contains the full independent schema-gate report.
- `package-checks.log.gz` contains complete portable-gate stdout/stderr.
- `summary.json` indexes per-input results and verifies the compressed and
  original report bytes with SHA-256 hashes.
- `native-files.tar.xz` retains all 281 emitted DOC/DOCX files,
  with exact path/size/hash records in `native-files.manifest.json`. Run
  `python3 verify-native-files.py` to verify the sealed report bindings and
  deterministic archive, or pass `--extract NEW_DIRECTORY` for verified copies.

Source fixtures and cycle inputs are unchanged. No reviewed golden was updated.
Original OOXML → native binary changes remain separate from parser changes.
The earlier [8060ac1 failure](../8060ac1/README.md) remains retained unchanged.

Run the commands in [the oracle guide](../../fidelity-oracles.md) from the
pushed commit named above, with the recorded Office, PDF tools and fonts. To read
the complete native report, Python's standard `lzma` module is sufficient:

```python
import json, lzma
from pathlib import Path
report = json.loads(lzma.decompress(Path("native-report.json.xz").read_bytes()))
```
