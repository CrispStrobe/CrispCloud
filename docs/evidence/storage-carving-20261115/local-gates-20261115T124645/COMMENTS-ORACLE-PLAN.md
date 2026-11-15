# Final comments-oracle gate plan

Status: prepared and statically reviewed. The app source checkpoint and all final host gates remain pending. This plan claims no new passing runtime total.

The final plan incorporates immutable app `3e9560c9b4bd617b5346bacd8b5039493f0f2dc1` and corrected canonical Quds source `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`; parser remains `08296edbee08da013a8ff718798972552ccd03f7`. Canonical siblings are `QudsCanonical` and `ParserCanonical`. Root must sync the managed source, finish dependency resolution, and save the full app source before any accepted final gate.

## Gate scope

The selected host cohorts contain 65 app, 23 engine and 11 editor suites. Strict analysis covers 76 app, 19 engine, six editor and one CLI file. The namespace regression suite joins the engine cohort; both namespace/schema test files and the comment fixture generator join strict engine analysis. Runtime counts come only from the completed raw events. Navigation capture stays separate from primary host totals.

`gate-commands-final.json` contains 13 individual commands using fresh `-final` receipt labels. Each receipt, passing or failing, must be remotely saved and verified before the next command. Dependent scripted-oracle and navigation-review commands explicitly select their final generation labels. Existing plain labels and the retained `historical/source966-gate-plan.json` remain source966 predecessor evidence.

## Independent comments verification

The new gate calls the actual pinned Dart executable to run the canonical fixture. The three original repeated-save packages each contain six authored plain comments. Six additional packages cover valid and invalid-root unowned comments parts through empty, added-note and cleared-note save/reopen phases. Authored expectations are recorded before serialization. The eleven output files are freshly generated and hashed before independent readback.

The Python reader uses ZIP/CRC checks, relationship and SpreadsheetML XML structure, and openpyxl to check text and author values. It verifies both Original and Added sheets, preserves original notes, compares unrelated orphan XML and outgoing relationship bytes and content type, and requires a separate explicit valid comments authority even after clearing. Empty authors/commentList containers cannot hide unexpected same-namespace children or bare text. The external sentinel URL is package metadata; the reader never follows it. The deliberately invalid orphan comments root is preserved without treating it as an owned comments part.

The wrapper binds the immediate generator output inventory, actual Dart and generator identities, tested app head and source/resolution digest. The enclosing recorder independently proves input stability. The reader records its executable and module hashes and exact before/after input hashes. Any generation, reader, inventory, binding or postprocessing failure returns a nonzero status and retains raw logs and available reports.

This is bounded plain-comment verification. It does not certify broad Open XML schemas, rich comments, VML geometry or rendering in external Excel. Existing exact Linux golden comparisons retain their source and font checks and must run on the final source. No CI wait or private corpus scan is part of the plan.

## Static review and provenance

The wrapper and reader derive from the immutable incoming helpers, whose original identities are retained in the overlay provenance. The local runner preserves all recorder, prerequisite, fresh-output, postprocessing and portable/native tool safeguards. Python syntax parsing and a separate read-only generator-contract review completed; this preparation did not run any host runtime test.

The final read-only acceptance auditor will require all 13 selected receipts, five ancillary artifact directories, exact generator-to-reader bindings, actual raw totals, canonical source identities and parser reuse proof before acceptance. Its configuration must be filled only from root's final saved source/checkpoint and fixed review head.
