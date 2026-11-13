# Fourth parser-audit evidence — 13 November 2026

The [audit report](../../parser-audit-20261113-fourth-pass.md) records the
defects, fixes, compatibility decisions and remaining limits. The complete
runtime and acceptance tools were tested at clean commit
[`e84f4131ce1515675dc97dfa6442d0c4a8ac77cf`](https://github.com/CrispStrobe/legacy-doc-parser/commit/e84f4131ce1515675dc97dfa6442d0c4a8ac77cf).
This bundle was added afterward without changing tested code or fixtures.

## Download and integrity

- [Complete evidence ZIP](parser-audit-20261113-fourth-pass.zip): **422,509 bytes**;
  **128 files plus the internal SHA-256 manifest**.
- [SHA256SUMS](SHA256SUMS) verifies the ZIP.
- [Expanded manifest](manifest.json) records all 128 file lengths and digests.

ZIP SHA-256:

```text
f6ada331236255c606cb4234973856011ec26162a894d9976ce1e456dab9afc4
```

All 129 members, their CRCs and all manifest-listed byte lengths and hashes
were checked after archive creation. The manifest does not hash itself.

## Retained results

| Evidence | Verified scope |
| --- | --- |
| `acceptance/portable-receipt.json` and logs | Six passing gates: 1,361 Dart tests, 162 Python controls, 24 retained corpus checks, analysis, formatting and actual compiled JavaScript |
| `schema/report.json` and SDK reports | 279 DOC-derived DOCX files, zero errors, exact hash coverage, source-built validator controls, 604-file determinism |
| `acceptance/schema-receipt.json` and public-model reports | 24 public-image DOCX and 17 public-compound DOCM files, zero errors; 49- and 35-file determinism respectively |
| `acceptance/previous-output-comparison.json` | All 273 prior DOC-derived and 24 prior public-image DOCX files remain byte-identical; six new DOC-derived outputs, none changed or removed |
| `acceptance/independent-acceptance-review.json` | Separate review recomputed exact source identities, inventories, raw-byte retention, active/inert relationships and all validation/preservation counts |
| `acceptance/environment.json`, `dependencies/` | Runtime versions and hashes, resolved Dart dependencies, validator project and pinned provenance |
| `regressions/` | Original failing checks, intermediate and final passing logs; independent exact-TAB and prior-list comparison |
| `new-list-cases/` | Six new binary DOC, converted DOCX and HTML sets, including exact TAB labels and supported literal/ancestor/legal labels |
| `public-compound/` | All 17 DOCM outputs, exact original container bytes, and explicit caller-built model descriptions |
| `text-unicode-inputs/` | Ten malformed and three supported DOC inputs, observed extraction outcomes, and their export script |
| `acceptance/checkpoints.json` | Four runtime/acceptance checkpoints saved remotely before this report |

The complete schema-checked scope is **320 packages: 303 DOCX and 17 DOCM**.
Public-model image and compound cases are kept separate from DOC-derived cases.
The two structurally eligible OLE/VBA controls are synthetic bounded identity
fixtures; they do not claim valid VBA program contents or execution safety.

## Receipt history and boundaries

The before/after regression logs describe evolving development trees. Complete
tested-source identity comes from the final clean-checkout receipts: 628
portable sources and 400 schema inputs, of which 398 are committed files and
two are separately hashed generated dependency files.

The public-compound intermediate run exposed an uncaught `CfbfException`;
the corrected writer catches both reader exception types and the final focused
run passes. The original failure is preserved. The independent reviewer also
corrected two review-script assumptions: there are 15 compiled-JavaScript
groups, and compiler byte counts can contain thousands separators. The initial
review script/result and corrected reproduction remain together. Neither
review-script correction changed tests, outputs or acceptance receipts.

The previous output corpus was regenerated at `105901f` in a separate clean
checkout with the same resolved dependency lockfile. Its old/new hash mapping
is retained; unchanged historical output bytes and previously bundled public
images are not duplicated here. Compiler caches, installed SDKs and compiled
JavaScript are reproducible from the pinned sources and are also omitted.

The literal binary `%1`–`%9` label limitation and two prior LibreOffice
field-import differences remain open. This pass adds no native Word/Office
rendering claim, full CFB conformance claim, general VBA/OLE validity claim,
package-publication claim, or completed hosted-CI claim. The third-pass
172-file evidence manifest remains intact and was independently rechecked.
