# Parser audit acceptance receipts

Recorded 13 November 2026 against clean implementation commit
`92486f82dd746ab14b5ccf1310f629b74f7bfa5a`. The baseline suite ran at
`c1b3ec5b685bfebb9199684ceb35b4c9f231ef7a`. Later workflow/documentation/evidence
commits leave the measured parser, tests, fixtures and tools unchanged.

See the [audit findings](../../parser-audit-20261113.md),
[machine-readable summary](results.json), [source identities](runtime-source-sha256.json),
[resolved dependencies](resolved-pubspec.lock), and
[archive hash](archive-sha256.json).

## Results

| Check | Result |
| --- | --- |
| Baseline / final Dart tests | 1,055 / 1,113 pass; 58 added tests. |
| Full fatal-info analysis | No issues. |
| Maintained-source formatting | All 216 Dart files pass. |
| Python controls | 162 pass. |
| Source corpus | 24 input hashes/package graphs verify. |
| Actual compiled JavaScript | DOC/CFB, text bounds, 51 media checks, five field cases, aggregate ink, 24 base and 32 header ISFs pass. |
| Independent Open XML SDK matrix | 260 DOCX outputs; zero errors; self-tests and positive/negative controls pass. |
| Determinism | Two complete 550-file generations match byte for byte. |
| Package dry run | Zero warnings; no publication. |
| New native field smoke | Five successful imports, three matching visible-text results, **two retained divergences**. |
| Native attribution controls | Ten independently authored DOCX files validate with zero errors and reproduce the two importer behaviors. |

The native smoke explicitly records `passed: false`; it is not folded into a
general passing-fidelity claim. Independent field-tree comparisons match the
parser's output exactly. They attribute the extra nested-field value and
missing-REF error to this LibreOfficeDev importer. Neither stripping supported
field syntax nor altering the expected text was used to create a pass.

The initial full-tree formatter failure is also retained. That command selected
a historical probe whose exact SHA-256 is pinned by an existing evidence
receipt. The separately recorded active-source formatter pass corresponds to
the CI correction in `1b4d23afd8afe9b652daf0cc51196303c3df539f`; all six archived
probes remain byte-exact, and the full analyzer remains enabled.

## Retained bundle

[validation-evidence.zip](validation-evidence.zip) contains 176 retained files
plus an internal SHA-256 manifest:

- Complete baseline/final Dart output, analysis/format logs, dependency
  resolution, Python controls, actual compiled-JavaScript output, corpus check
  and package dry-run output.
- The complete Open XML gate report, all 260 output validation receipts,
  deterministic file hashes, compiler commands, SDK/dependency/source identities,
  self-test output and original positive/negative controls.
- All six new binary DOC sources and converted DOCX outputs in the schema
  matrix. Other deterministic corpus outputs are reproducible from committed
  generators; they are not duplicated in this compact archive.
- All original native field fixtures, five PDFs, raw extracted text, commands,
  versions and the failed visible-text comparison report.
- All ten independent attribution controls, their PDFs/raw text, zero-error
  schema report, exact field-tree comparisons and authoring scripts.

Logs retain their original absolute temporary paths. Reports fingerprint the
actual executable and package bytes; the recorded path is not an installation
requirement. Native import used only explicitly named generated DOCX files,
not the original binary fixtures containing unsupported field instructions.

The native version-query setup failure that lacked a writable `TMPDIR` is
separately recorded; actual conversion and extraction used the documented
writable environment. Failed setup observations and negative controls are
not relabeled as successful runs.

The archive can be checked without executing any contained code:

```python
import hashlib, json, zipfile
from pathlib import Path

root = Path('doc/evidence/parser-audit-20261113')
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

These are local measurements at the exact clean runtime. Hosted GitHub Actions
status is separate and should be read from the corresponding run, rather than
inferred from this receipt.
