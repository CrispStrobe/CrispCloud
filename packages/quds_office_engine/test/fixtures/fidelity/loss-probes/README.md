# Unresolved Word structure probes

These XML documents are independently authored specimens for two confirmed
data-loss paths. `content-control.xml` contains one block content control with
an alias, tag, ID and end-run properties. `bookmark-ranges.xml` contains two
distinct ranges in one paragraph and a third range crossing paragraphs.

Run from the engine package:

```bash
python3 tool/fidelity/unsupported_word_audit.py
```

The script packages these XML documents without the engine serializer, uses the
real modification CLI to edit the preceding ordinary paragraph, and checks
three save/reopen cycles with Python's XML parser. Input files and expected
structures are never regenerated from engine output. Temporary Office files
are removed; observed source and output structures are recorded in
`build/fidelity-unsupported-probes/report.json`.

**The command exits with status 1 while data loss is observed.** It is a
diagnostic report, excluded from the passing fidelity gate. The report compares
bookmark names and paired range endpoints rather than treating a harmless
change of numeric bookmark IDs as data loss. It is expected to become a passing
regression only after the corresponding model and editing semantics are fixed.
