# Parser audit follow-up acceptance receipts

Recorded 13 November 2026 from a clean checkout of
`8bf4db2585288e293d10d8fcf6a2d17697c621c1`, following the first audit's
`de4566aa69f6e6c6b5347b8463f4ecb7995d35f1` report checkpoint.

See the [findings and compatibility decisions](../../parser-audit-20261113-followup.md),
[results](results.json), [exact source identities](runtime-source-sha256.json),
[resolved dependencies](resolved-pubspec.lock), and [archive hash](archive-sha256.json).
Later documentation/evidence edits do not change the tested runtime or tools.

## Results

| Check | Recorded result |
| --- | --- |
| Dart regression suite | 1,175 pass; 62 added in this pass, 120 across both audit passes |
| Analysis and formatting | No fatal-info issues; all 224 maintained Dart files pass |
| Python control suite | 162 pass; deliberate negative-control error messages remain in the original log |
| Source corpus | All 24 source hashes and package graphs verify |
| Actual compiled JavaScript | Existing DOC/media/ink checks, eight field cases, four story cases, 30 malformed allocation rejections, seven valid allocation fixtures, shared-tail and portable-integer controls pass |
| Open XML SDK | All 263 DOCX outputs have zero validation errors; independent validator self-tests and positive/negative controls pass |
| Determinism | Two complete 556-file generations match byte-for-byte |
| Previous corpus | All 260 prior DOCX outputs remain byte-identical; three outputs added, none removed |
| Package dry run | Zero warnings; no package published |

The gate used Dart 3.14.0, .NET SDK 8.0.428 and a fresh source-built validator
from the repository's pinned Open XML SDK 3.3.0 packages. The compiler, runtime,
NuGet, source and generated-output identities are retained in the schema report.
The prior dependency lockfile was resolved offline and retained here.

## Bundle contents

[validation-evidence.zip](validation-evidence.zip) retains **88 files plus an
internal manifest**:

- Complete clean-checkout acceptance logs and structured command receipts,
  including source hashes before and after execution, clean Git status, exact
  commands and the runner script.
- The full 263-output Open XML SDK report, all deterministic file hashes,
  compiler/build records, self-test logs and positive/negative control files.
- The three new binary DOC/DOCX pairs from the final schema generation.
  The remaining generated corpus is reproducible from committed generators.
- Original failing regressions and focused passing runs for Unicode stories,
  field text, allocation metadata and portable unsigned integers, including
  actual compiled-JavaScript observations and their small source probes.
- Independent review probes and separate original/revised results for shared
  allocation tails and partial mini-containers. These original observations
  concern an intermediate uncommitted candidate without a retained exact source
  snapshot; they are not presented as release-source measurements.
- Comparisons against the previous 260-output corpus and the five earlier
  native-rendering input files.

No new native renderer run is claimed. All five previously rendered field DOCX
inputs are byte-identical to this runtime's outputs. The first audit's
[two retained LibreOffice differences](../parser-audit-20261113/README.md)
therefore remain relevant and are not turned into passing measurements.

Generated JavaScript bundles and SDK binaries are omitted; committed helpers,
resolved dependencies and the recorded commands reproduce them. Original logs
retain their actual temporary paths. No historical receipt or reviewed golden
was rewritten.

## Verify the archive

```python
import hashlib, json, zipfile
from pathlib import Path

root = Path('doc/evidence/parser-audit-20261113-followup')
receipt = json.loads((root / 'archive-sha256.json').read_text())
payload = root / receipt['file']
assert hashlib.sha256(payload.read_bytes()).hexdigest() == receipt['sha256']
with zipfile.ZipFile(payload) as archive:
    expected = json.loads(archive.read('manifest.json'))['files']
    assert set(archive.namelist()) == set(expected) | {'manifest.json'}
    for name, item in expected.items():
        content = archive.read(name)
        assert len(content) == item['bytes']
        assert hashlib.sha256(content).hexdigest() == item['sha256']
```

These are local clean-checkout measurements. GitHub-hosted Actions status is
separate and must be read from its run; it is not inferred from this receipt.
