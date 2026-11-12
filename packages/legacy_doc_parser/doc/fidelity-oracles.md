# Fidelity corpus and independent oracles

`tool/fidelity/corpus.json` pins ten authored Office XML fixtures from the MIT
Quds fork at `ca9853b5b08784beac50df5680176cb4e5b3cb25`, plus the package's
existing native DOC fixture. Source paths, feature tags, SHA-256 hashes, and
license provenance travel with the corpus. The Quds expectations are retained
under `test/fixtures/fidelity/quds-expectations`; they describe original OOXML,
not a promise that a native DOC bridge can carry every newer OOXML feature.

```
python3 tool/fidelity/oracle.py
python3 -m unittest discover -s tool/fidelity -p 'test_*.py'
python3 tool/fidelity/run.py --office /path/to/installed/soffice \
  --dart /path/to/dart --output build/fidelity-first-run
```

No Office application is installed or downloaded. Normal unit tests do not
require native Office. The opt-in runner uses an isolated profile and creates
a new output directory. Source fixtures are hashed again after every run.
Package XML and relationships are inspected without fetching external targets.

For each original DOCX the runner first creates a DOC using installed
LibreOffice, then records the differences between the authored OOXML and a
native DOC-to-DOCX conversion. Those **bridge changes** matter: comments,
controls, modern revisions, and unsupported graphics may be lost before our
parser sees any bytes. They cannot prove or disprove our DOC parser's support.
Independently assembled binary unit fixtures cover those ambiguous cases.

The generated DOC is then converted by this package. The runner compares all
reachable stories, table/cell counts, comment threads, revision structures,
image hashes, links and sections against the native DOCX. Relocated parts are
resolved by relationships, not hard-coded filenames. Exact source DOC and
converted DOCX are also independently rendered to PDF. Page dimensions, page
count, page-by-page words, bounding-box drift, layout text, and raster hashes
are recorded. A same-page-count result alone never passes exact pagination.

Finally our DOCX is saved back to DOC by Office and imported a second time.
Changes are reported separately from the first conversion. Renderer version,
font inventory hash, source hashes, package commit and dirty-worktree state
are included. The native DOCX render is measured too, so native conversion
loss cannot silently become the expected output.

`run.py` exits unsuccessfully for conversion/oracle failures. Ordinary measured
differences are findings, not an assertion of equality. `--require-exact`
additionally rejects every semantic, round-trip, or exact-render difference.
It never regenerates or blesses goldens. Reports and rasters stay in the
requested output directory for inspection. Exact results apply only to the
recorded fixture, Office build and fonts; they do not certify all documents.
