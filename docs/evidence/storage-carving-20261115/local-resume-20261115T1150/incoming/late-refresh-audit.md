# Finite late-source refresh

The final refresh identified new app and Office source plus new parser merge
ancestry. This record closes that observed batch. No rolling branch refresh or
GitHub Actions polling was performed. Exact commit/tree/blob identities and
comparisons are in `late-refresh-audit.json`; associated PR metadata is in
`late-pr-metadata.json`.

## Observed input heads

| Repository | Input | Finding |
| --- | --- | --- |
| CrispCloud | `fix/ods-date-styles` at `b0e0f1746e5042f9dfced8ab471222d33bcb63a0` | One commit on main `4933ffc2`: authored ODS date styles, full month/weekday rendering, fixture/test updates and vendor manifest. |
| CrispCloud | PR 120 metadata reported descendant `c8fd8d76a5367e2712600451de3a2811b085a6c5` | One further commit vendors ODS comments and updates the corresponding fixture, tests and manifest. Root explicitly included this already-observed descendant in the finite batch. |
| Quds | PR 24 / `fix/odf-legacy-spreadsheets` at `9cc8c6e91ff9acf0f52a68aea7c0da69934a2661` | Three commits after prior head `e033226b`: `5ab1afda` date-style order, `edaa328d` long month/weekday rendering, `9cc8c6e` comments. |
| Parser | main at `7df906d2643d1fec39c49fc795733316a49f3278` | Three merge commits combine already incorporated PR 14–18, followed by README capability documentation. No new parser production/test/dependency bytes. |

All five app vendor paths changed by the late feature batch have the same Git
blob IDs as the Quds `9cc8c6e` copies. Thus the app branch contributes ancestry
and its manifest, while the reconciled canonical source supersedes those
vendor copies without losing an independent app implementation.

The entire parser tree comparison between our original merged checkpoint
`9864ac623a95b82c305ea2923f4ac783bbd200fe` and new main `7df906d2` changes only
`README.md`. The subsequent recovery-work bounds, Word6 UTF-16/encoding fixes,
story-boundary correction and regression receipts must remain on top. The
parser owner handles the README/ancestry merge without changing those bytes.

## Canonical resolution

Root published the resolved Office source as
`b4950d60eb03365c1798d2dfc66a2c85a4e61be5`, tree
`f0687114070721dea2e655b6c0f2a882a1706492`, with parents:

- `cd56ae1550f37367ef5ec921d124211c7d7e224b`, the saved native geometry fix.
- `9cc8c6e91ff9acf0f52a68aea7c0da69934a2661`, the observed latest ODS feature head.

The native geometry model, serializer and native-metrics test are byte-identical
to `cd56ae15`. The merge changes six files: ODS reader, number/date formatter,
edge ODS fixture, ODS tests, new date-format tests and CHANGELOG. No dependency
declarations or locks were changed.

The original incoming annotation code could incorporate note paragraphs into
the cell value, match foreign namespace lookalikes, select only the first of
multiple annotations, and perform a linear duplicate search for every note.
The resolved import carries annotation text/author separately through the
existing sparse cell templates and appends a note once per admitted coordinate.
Comment-only cells obey the same grid and 200,000-cell bounds; repeated note
text and authors consume the shared 8 MiB expanded UTF-8 text budget before
materialization. Covered-cell annotations, multiple/nested/foreign annotations
and ambiguous or foreign author declarations explicitly decline.

Date components and their attributes are namespace-aware. Authored literals,
including multiple spaces, quotes, semicolons and letters resembling date
tokens, retain their literal meaning. The existing XML element reader preserves
whitespace after the unchanged complete bounded validation pass. Format section
splitting now respects quotes/escapes, and literal removal handles escapes
before quotes. Existing elapsed-time and minute/month context logic remains.

## App integration order

1. Save the combined current host recovery, parser and geometry checkpoint.
2. Merge app `c8fd8d76`, preserving `b0e0f17` through its ancestry.
3. Synchronize the published canonical Office resolution and parser owner's
   final stable source pin, then rebuild the complete vendor manifest.
4. Save the combined source before the source-bound runtime qualification.

The reviewer did not mutate the app or parser checkouts. Root owns app merge,
canonical publication/alignment, synchronized copies and test receipts.

## Qualification impact

Add `packages/quds_office_engine/test/sml_styles_date_test.dart` to both the
engine cohort and engine analysis list. Its three tests cover full date names,
clock minute context, escaped quotes, literal semicolons and numeric-section
controls. The existing engine cohort already includes the changed ODS reader,
authored-number, time-format and native-font/geometry suites. The ODS suite gains
seven reconciliation cases plus the incoming fixture assertions for dates and
comments. Those cases cover note/value separation, repeated notes, source
namespace ambiguity, text/grid/materialization bounds and XLSX copy saves.

Also include the existing `sheet_comments_schema_test.dart` engine suite: its
two cases check author-table indexes and comment relationships in saved OOXML,
which the newly imported notes now exercise. Existing app ODS editor/viewer and
PDF export cohorts remain applicable.

Formatter parsing and whitespace checks succeeded before the source checkpoint;
the formatter reported unavailable standalone canonical lint resolution, as
expected because canonical workspace dependency resolution was deliberately
not run. No runtime test ran against an unsaved late-source tree. Runtime
acceptance belongs to the subsequent source-bound gates, not to this audit.
