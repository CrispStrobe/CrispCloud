# Office and first-party proofing integration follow-up

17 November 2026. Tested host runtime: `fbad6b4c01e2950e7d7612e88269ce4a7c3b04f9`.
Quds source pin: `2de01b5774b75ddad858fc61bda3b356570cbf38`.

Our UI, manual-review, worker lifecycle, cancellation, source-safety and undo
work remains reusable. The additional first-party adapter/UI code remains
retrievable on the historical feature branch. AOT/RML/nlp_base libraries,
dictionaries, transports and runtime registration remain excluded. Native spaCy
implementation is separate work. See the canonical
[reuse map](https://github.com/CrispStrobe/quds_office_suite/blob/e3a38789/docs/roadmaps/proofing-adapter-reuse.md).

This update fixes ODT section selection for leading tables of contents and
restores bounded PAGE/NUMPAGES conversion without losing cached text, links,
styles, locked-field behavior or authored column breaks. Ambiguous active
bookmark starts no longer acquire an invented end. It preserves incoming
first/even header/footer export, chart-table fallback and the production host
ODF visibility/cell-story/cell-limit workflows from main `73ebbfe6`.

The final native host test run passes **147 tests**, including actual ODT/ODP
menu exports, successful/cancelled/failed export outcomes, source preservation,
ODF hidden stories and cell limits, previews, annotations, license attribution,
manual grammar review, correction and undo/redo. Nine sync-guard tests pass.
The tracked source-fidelity gate verifies **2,624 files**, and crypto/export-policy
input checks pass after refreshing the reviewed source fingerprint. The SQLite
test helper restores the root pubspec after its temporary test dependency choice.

Canonical checks also pass 1,558 engine tests and 97 editor tests; a separate
24-test chart/column/tab delta overlaps the broad suite. In an actual external
LibreOffice render, contents starts on page two at the requested 600x400-point
size, PAGE/NUMPAGES renders as `Page 1 of 2`, and a locked field keeps `23`.
See the canonical [report and synthetic artifacts](https://github.com/CrispStrobe/quds_office_suite/blob/e3a38789/docs/validation/proofing-office-followup-20261117/README.md).
These are local native tests and external-reader rendering, not a TestFlight
upload or mobile-platform qualification. No GitHub Actions/status endpoints
were queried or awaited.

The guarded sync first rejected three recorded files whose bytes differed from
the claimed Quds revision. Their recorded hashes were verified and their changes
reviewed. The chart fallback was retained in canonical Quds, the stronger tab
regression kept, and existing unmanaged test files admitted only when matching
the canonical candidate byte for byte. No files were deleted. The standalone
parser source boundary and unrelated host changes remain intact.
