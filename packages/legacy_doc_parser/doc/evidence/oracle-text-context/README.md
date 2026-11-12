# Context-aware text and offset oracle

This correction changes the Python semantic oracle only. It does not change
the DOC parser, converter, native documents, rendered pages or reviewed goldens.
Historical reports, including the sealed `6b2b611` and `8367ce0` native runs,
remain unchanged. New snapshots use `oracleSchemaVersion: 4` so corrected
measurements cannot silently be treated as version-3 observations.

## Defect and bounded correction

WordprocessingML uses `w:tab` for two different elements. Microsoft's
[TabStop](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tabstop)
definition places a formatting stop under `w:tabs`, while
[TabChar](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.tabchar)
places an actual character in run content. The former does not add a Unicode
tab to the paragraph's text. The old oracle visited every `w:tab` descendant
without checking its parent or whether it belonged to a property subtree.

The same defect affected inline paragraph text, numbering text, revision text
markers and comment/revision offsets. A shared context walker now keeps
properties at zero text width while still visiting their revision nodes for
metadata and offsets. Tab-stop properties and their history remain present in
the formatting snapshots; changing or losing them is still reported.

Recognized text/control characters require a run parent. The documented
WordprocessingML and OMML math run parents remain supported. Real tabs, line,
page and column breaks survive ordinary and review text projections. Whole-story
summaries omit only trailing paragraph separators that the summary itself adds;
they no longer strip real run tabs, breaks or preserved spaces at text boundaries.
The existing separate paragraph/block snapshots still record empty paragraphs.

The context audit also corrected an unrelated namespace collision: a DrawingML
`a:p` no longer inserts a Word paragraph separator merely because its local name
is `p`. Nested textbox/table content remains excluded from outer inline offsets.
Malformed content placed inside a property subtree is retained as property data,
not promoted into story characters, run profiles or break counts. Independent
schema validation remains responsible for rejecting malformed packages.

## Exact before/after replay

The before source is pushed parser commit
`d28be0a173415ebb392a8309aacdbe2bb1a50da7`. The report retains SHA-256 hashes
of both measured versions of `tool/fidelity/oracle.py` and
`tool/fidelity/structure.py`. Each version executes in a separate Python
interpreter, preventing a shared imported helper from contaminating the result.
No native Office process is run.

| Input | Literal source facts | Before | After |
| --- | --- | --- | --- |
| Retained `list-continue` cycle 1 | Five property stops; zero run tabs | Story `P1\n\tP2\n\tP3\n\tP4\n\tP5`; every paragraph profile starts with a false tab | Story `P1\nP2\nP3\nP4\nP5`; paragraph profiles contain no tabs |
| Independently authored real tabs | Two property stops; three real run tabs | Story loses real leading/trailing tabs; paragraph profile includes two invented tabs | Exact `\tA\tB\t`, retaining all three real tabs |
| Independently authored revision/comment anchors | Text `AB`; four current/prior property stops; zero run tabs | Paragraph-change offset 2, run-change offset 5, paragraph-mark offset 6, comment offset 6 | Correct offsets 0, 1, 2 and 2 |

Paragraph property records are byte-for-byte equivalent as JSON values before
and after in all three replay cases. The current/prior tab-stop settings and
revision metadata are preserved. Removing a false text difference does **not**
make differing tab-stop formatting, list layout or native rendering equal.

The retained list input is copied exactly from
`list-continue/roundtrip-01/import.docx` in the sealed
[`6b2b611` archive](../6b2b611/README.md). Its hash was verified against that
archive's per-path manifest. The two small controls are independently authored
OOXML, retained as exact bytes with literal expected text and offsets.

## Validation and retained files

All **139 Python fidelity tests pass**, including ten new adversarial tests for
property stops, real boundary tabs, prior properties, revision/comment offsets,
foreign paragraph names, nested textboxes, OMML controls, markup-compatibility
alternatives, review views and malformed property content. The source-corpus
check verifies all **24 source hashes and package graphs**. The independent
Open XML SDK validator accepts all **three replay inputs with zero errors**;
exact inspected-file coverage and hashes were verified.

- `inputs.tar.xz` contains the three exact DOCX inputs as sorted regular files
  with fixed archive metadata. Its compressed size is 6,500 bytes.
- `inputs.json` records their hashes, provenance and literal expected results.
- `replay-report.json.xz` retains both complete measured text/offset projections,
  property snapshots, source hashes and per-case checks.
- `schema-report.json.xz` and `python-tests.log.xz` retain validation evidence.
- `receipt.json` records compressed and uncompressed report hashes and the
  measurement-tool hash.

Reproduce the replay from a checkout containing this correction and the recorded
before commit. The output directory must be new:

```sh
python3 doc/evidence/oracle-text-context/replay.py --output build/oracle-text-context-replay
```

The script verifies and materializes the exact inputs, reads the old oracle from
Git, copies both measured source versions, records their hashes, and checks each
projection against its literal expectation. It also verifies that neither the
inputs nor current measurement sources changed during the replay. The saved
native reports and their original findings are not rewritten by this command.
