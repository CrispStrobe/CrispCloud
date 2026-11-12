# Native checkpoint f24e5b2

This is a retained measurement of parser commit
`f24e5b25208368cb6c9bdf41c0c13851f862e79b`, with a clean worktree and the
11 pinned corpus inputs. It is not an approved whole-document golden.

The isolated Dart suite passed 325 tests, the Python structural/probe suite
passed 29 tests, static analysis and formatting were clean, and the actual
DOC/CFB JavaScript acceptance passed under Node. Native conversion completed
for all 11 cases without changing a source file. All page counts matched;
only `comment-threads` matched source pixels, text and word coordinates
exactly. Every case still had reported structural differences from the native
DOCX route. These are separate measurements, not a combined fidelity pass.

`summary.json` records per-case source/output hashes, rendering metrics,
converter warnings and limitations. `native-report.json.gz` contains the
complete original JSON report, including the actual semantic differences,
native bridge differences and second-import differences. Both compressed and
uncompressed hashes are recorded in the summary. Decompression uses ordinary
gzip; no document content is executed.

The independent Open XML SDK 3.3.0 check passed its positive/negative controls
and then found 15 errors in nine outputs. All were `w:noWrap` numeric boolean
values where the schema requires `on`/`off`. `schema-report.json` retains the
red result, exact document hashes and validator source/binary provenance.
Later commits correct the writer and add a regression; this earlier receipt
is deliberately not rewritten into a passing result.

The native comparisons also isolated a 108-twip table indentation loss,
list-marker font inheritance, and a note-numbering/indentation disagreement
between the binary specification and LibreOffice. Supported table borders
restored the authored vertical cell position. Linked textbox reflow, absolute
textbox placement, OfficeArt path geometry and section revision history have
separate probes because a page render alone cannot establish those contracts.

Reproduce the corpus measurement with `tool/fidelity/run.py` using an already
installed LibreOffice, Dart SDK, Poppler and the recorded fonts. The summary
identifies the exact renderer and font inventory. A different renderer or font
inventory is a new experiment, not an automatic replacement for this result.
