# Clean native and schema checkpoint 8060ac1

The clean source snapshot `8060ac13317754819ebec82ec7232ba6304cb038` and pushed
commit `504679d841d0ec6a20749cee392c6a4bb9718d8d` have the identical Git tree
`8eb4883f0de944c9a1ac119a9141685521e2cac0`. Later corrections do not change these
historical results.

## Measured result

All 22 original inputs imported and retained their initial page counts. Six
initial parser outputs matched page text, word geometry, and RGB pixels on the
recorded renderer. Both reviewed source goldens reproduced. Twenty-one inputs
completed all three requested DOCX → native DOC → parser imports. The Word 16
fixture failed at its first regenerated DOC because its OfficeArt BStore count
was inconsistent with the complete FBSE records. This is a retained red result.

Every input has strict structural differences from the native DOCX projection.
Those differences include explicit defaults, inactive stories, ID/representation
rewrites, native bridge losses, and unimplemented semantics. They are retained
in full and are not all classified as parser data loss. Six exact initial
renders are not six full-fidelity passes.

| Input | Initial pages | Exact initial RGB/text/geometry | Three cycles completed |
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
| `word16-page-origin` | 1 → 1 | No | No: first regenerated DOC rejected |
| `poi-simple-table2` | 1 → 1 | No | Yes |

## Independent validity and portable checks

The freshly built Open XML SDK 3.3.0 validator accepts all 92 required DOCX
outputs with zero schema errors. Exact file coverage, input/output hashes,
positive/negative validator controls, deterministic generation, and unchanged
source inputs were checked independently. The full report identifies the
validator source and its pinned dependencies. This validity result does not
certify pagination or complete semantics.

The portable package gate passed 534 Dart tests, 92 Python tests, whole-package
analysis and formatting, JavaScript/Node DOC acceptance, and 40 media checks.
The package publish dry run reported zero warnings; no package was published.

## Retained files

- `native-report.json.xz`: the entire original native report, compressed without
  changing its JSON bytes. It includes every difference, cycle, source/output
  hash, stage, and code/tool/font receipt. XZ's larger dictionary keeps repeated
  structural snapshots compact; Python's standard `lzma` module can read it.
- `schema-report.json.gz`: the entire independent SDK gate receipt.
- `package-checks.log.gz`: complete stdout/stderr from the portable gate.
- `summary.json`: compact per-input findings and hashes of these archives and
  their original uncompressed reports.

The source DOCs and DOCX fixtures are unchanged. No goldens were automatically
updated. Original DOCX → native DOC losses are measured before parser conversion.
Microsoft Word was not executed; these native measurements use the exact
LibreOffice, Poppler, and installed font identities in the report.

To inspect the complete native report:

```python
import json, lzma
from pathlib import Path
report = json.loads(lzma.decompress(Path("native-report.json.xz").read_bytes()))
```
