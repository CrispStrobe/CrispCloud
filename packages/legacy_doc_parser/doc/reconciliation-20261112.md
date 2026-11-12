# Recovered fidelity work reconciled

This continuation combines the tested preservation line at `8454efb` with the
independently saved `feature/office-fidelity-oracles-20261112` work at
`b03747396878518d0d623599baf9b376df776e3d`. The shared ancestor already contains
the structural oracle and section-revision work. Both lines remain in Git
history; neither branch's implementation is treated as an independent native
oracle for the other.

## Retained foundations and recovered additions

| Area | Reconciliation decision |
| --- | --- |
| Tables | Keep the current native conditional styles, contextual run/paragraph formatting, explicit row/cell resets, six-edge row borders, and measured nested origins. Retain the recovered native list fixtures. Further bounded table mutations are separate increments. |
| Lists | Add the recovered shared sequence resolver, source start overrides, story scopes, and native resume instances. Preserve the current marker-font inheritance and NumRM/LISTNUM revision output. Native labels and multilevel approximation warnings are separate evidence. |
| Media | Add bounded HTML image previews with cross-story budgets, distinct metafile device and physical bounds, and the exact terminal-CR formatting recovery. Keep compound EMF/WMF paths, strict WMF object indices, explicit source evidence and the current shape gates. |
| Kerning | Retain the source half-point threshold through parser, runs, paragraph marks, list markers, conditional table text and revision copies. A recovered native receipt remains historical until the combined source is rerun. |
| Positioning | Preserve the explicit OfficeArt fields and the older SPA fields separately. Word-produced QA inputs corroborate the DOC-specific zero-based origin convention; the generic MS-ODRAW table discrepancy is documented in the positioning evidence. Test multiple offsets, axes and invalid values. |
| Review data | Keep the current insertion/deletion, paragraph-mark, formatting, section, numbering and LISTNUM histories and bounded ink evidence. The recovered branch does not contain equivalent coverage for the latter cases. |
| Oracles | Retain the stronger namespace-aware AlternateContent selection, style/default and numbering resolution, story/section identities and semantic mutation checks. Keep the current staged failure receipts, exact build provenance, original-DOCX comparison and repeated binary round trips. |
| Goldens | Retain two reviewed independent source-DOC RGB page goldens with their source hashes and original font/renderer fingerprints. A different environment is unverified; converted output never becomes a source golden. |

The compact eight-marker textbox fixture remains
`test/fixtures/word_native/linked-textboxes.doc`. The different recovered
24-marker source is `linked-textboxes-extended.doc`. Their bytes and provenance
are kept separately. The expanded corpus contains 19 pinned cases, including
native list controls, authored OfficeArt and EMF/WMF documents.

## Changes that are not copied blindly

The recovered renderer's WMF high-bit stock-object interpretation is not
imported: that convention belongs to EMF, and the current malformed-WMF tests
remain active. The current zero-extent line handling and typed ink evidence
also remain intact.

The recovered table-style PAPX prefix change is not adopted. An independent
Apache POI DOC contains its explicit style identifier in that prefix; the
current framing handles that real input. The table continuation documents the
source and fixture separately.

The recovered note-settings heuristic activates obsolete DOP fields from four
FIB/layout values alone. That does not establish which application produced a
document. The current normative version/section rules remain the baseline
until an unambiguous interoperability rule is demonstrated. The existing
native note-label disagreement stays visible rather than being certified by
matching a guessed producer.

Complete OfficeArt, GDI, ink, pagination and review behavior is not established
by these reconciliations. The feature ledger and native reports retain the
remaining gaps and distinguish source retention, editable output, schema
validity and renderer agreement.

## Later saved continuation through 2d490e5

The separately saved oracle branch advanced to
`2d490e5490f7d549deb36573a5ac26fc5f875cfa` during reconciliation. Its additional
production change uses the lowercase VML dash keywords already present in this
writer. Both sets of progress are retained in merge ancestry. Its complete
native reports, source receipts, reviewed image and acceptance ledger are kept
byte-for-byte under [the historical evidence archive](evidence/recovered-2d490e5/README.md).
Those reports describe their original source tree and renderer; they are not
relabelled as validation of the reconciled tree. New native measurements and
schema checks use explicit new source identities.

The reconciled schema inventory now includes bounded packed OfficeArt POINT
encodings, table mutations and row exceptions, list counter transitions,
international note formats, and three unmodified Word/POI documents. Schema
validity is checked separately from pixels, editable semantics, and source
recovery warnings. The native fidelity corpus includes 22 source documents.
