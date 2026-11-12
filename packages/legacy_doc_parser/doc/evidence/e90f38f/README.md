# Clean native and schema checkpoint e90f38f

The clean source snapshot `e90f38f1f69932e8330cec051b9d43cf0c99fc0f` and pushed commit
`c3fa95e5ac9b27114f77333e28e604a70e89575d` have the identical Git tree
`05146b129aa6d25e64aa6b0519c7ead7dfa46844`. Later documentation and evidence additions do not change these
measured source bytes.

## Measured result

24 of 24 original inputs imported, and
24 retained their initial page counts.
6 initial outputs matched page text, word geometry,
and RGB pixels exactly on the recorded renderer. 2
reviewed source goldens reproduced. 24 inputs
completed all 3 requested DOCX → native DOC → parser cycles
(72 completed cycle imports). The run records
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
| `header-textbox-alias` | 1 → 1 | No | Yes |
| `header-textbox-first-enabled` | 1 → 1 | No | Yes |

## Independent validity and portable checks

The freshly built Open XML SDK 3.3.0 gate accepted all
194 required converted DOCX outputs with
0 schema errors. Exact file coverage and hashes,
deterministic generation, unchanged inputs and positive/negative validator
controls passed. This result does not certify rendering or complete semantics.

The portable gate passed 797 Dart tests, 147 Python tests,
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
- `native-files.tar.xz` retains all 288 emitted DOC/DOCX files,
  with exact path/size/hash records in `native-files.manifest.json`. Run
  `python3 verify-native-files.py` to verify the sealed report bindings and
  deterministic archive, or pass `--extract NEW_DIRECTORY` for verified copies.

Source fixtures and cycle inputs are unchanged. No reviewed golden was updated.
Original OOXML → native binary changes remain separate from parser changes.
The earlier [8367ce0 first-header failure](../8367ce0/README.md) and
[8060ac1 BLIP-store failure](../8060ac1/README.md) remain retained unchanged.
This run uses the corrected version-4 text oracle; historical tab-stop-as-text
differences are not rewritten. The runtime under `lib/` and the dependency
manifests are byte-identical in integrated `47b9c95`; its added test and harness
changes have separate acceptance receipts.

Run the commands in [the oracle guide](../../fidelity-oracles.md) from the
pushed commit named above, with the recorded Office, PDF tools and fonts. To read
the complete native report, Python's standard `lzma` module is sufficient:

```python
import json, lzma
from pathlib import Path
report = json.loads(lzma.decompress(Path("native-report.json.xz").read_bytes()))
```
