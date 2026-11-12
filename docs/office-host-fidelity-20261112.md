# Host paragraph, style, reference and page-layout fidelity

This report retains the earlier host expansion and its original measurements.
The [follow-up report](office-fidelity-followup-20261112.md) records the current
shared source pin, custom-tab controls and continuation acceptance. It
supersedes the earlier tab-creation limitation without changing these historical
counts. The [consolidation report](office-fidelity-consolidation-20261112.md)
records the intervening save/upload milestone.

The app imports the vendored Quds packages through `pubspec.yaml` path
overrides. The authoritative source revision is
[`tool/office_fidelity_manifest.json`](../tool/office_fidelity_manifest.json).
Updating the fork alone does not update these app dependencies.

## Gaps addressed

| Host operation | Previous failure | Regression |
| --- | --- | --- |
| Open Paragraph and press Apply | Integer formatting of indents, spacing and tab positions rounded imported values; line spacing was rounded to two decimals | No-op import/export preserves authored twips and clean state |
| Change spacing on a selection | Applying every dialog field flattened unrelated per-paragraph values; tab reconstruction removed alignment and leaders | Only changed fields are applied; both selected paragraphs retain their distinct indents and tabs |
| Add a tab stop | Existing stops were rebuilt as left-aligned stops without leaders | Existing positions retain their metadata; new positions use default metadata |
| Edit header/footer paragraphs | Ribbon read body properties using the document caret while controller edited the active story | Header dialog displays header values and changes only that story |
| Remove before/after spacing | The ribbon marked an explicit zero as unspecified | Both preset commands and numeric edits retain explicit zero spacing |
| Enter invalid numeric properties | NaN/infinity could enter layout; malformed tab tokens silently deleted stops | Invalid values retain existing finite values, and invalid tab lists retain existing stops |
| Choose an imported custom style | Gallery displayed Normal and omitted the imported style | Gallery uses stable style IDs, authored custom names and Heading 1–9 |
| Insert hyperlinks | Link formatting was outside command history, so dirty state and undo/redo could miss it | Actual host menu/dialog actions assert dirty state, unchanged selected text and hyperlink relationships after undo/redo; requires the synchronized controller fix |
| Open Page Setup and press Apply | Rounding inches to two decimals changed imported margins | Unchanged point values remain exact and do not dirty the document |
| Change one page margin | Nonfinite input could replace valid geometry; other margins were rounded | Only the changed margin changes; header/footer distances and gutter survive |
| Report host coverage | A smaller instrumented subset could still produce a successful coverage command | The gate fails if any scoped Office source is absent from instrumentation |
| Preserve imported note markers | Two older tests expected a new marker even though their authored note had none | Native marker absence is checked against source XML; a separately positioned superscript marker remains at UTF-16 offset 7 through three real saves |

At this earlier checkpoint, the paragraph dialog preserved imported tab
alignment/leaders without offering their creation. The follow-up adds those
shared controls. Character-style editing, custom style creation and table-style
selection remain separate UI gaps.

## Executable scenarios and independent expectations

[`test/widget/office_paragraph_fidelity_test.dart`](../test/widget/office_paragraph_fidelity_test.dart)
authors the input DOCX as ZIP/XML. It invokes the actual host ribbon action
bridge and dialogs. Expectations inspect exported XML using `archive` and
`xml`; they do not re-use Quds deserialization as the oracle.

The tests check fractional values, distinct paragraph properties, decimal/right
tabs and leaders, a custom style, a header story, explicit zeros, page margins,
hyperlink relationship targets, and command history. The repeated-export
scenarios are:

| Scenario prefix | Cycle count | Main assertion |
| --- | --- | --- |
| `paragraph-noop` | 3 | Unchanged imported paragraph properties remain exact |
| `paragraph-edit` | 3 | Spacing changes without flattening other selected properties |
| `header-paragraph-edit` | 3 | Header changes while body and tabs survive |
| `hyperlink-selection` | 3 | Selected text remains and each hyperlink has a valid relationship |
| `margins-noop` | 3 | Unchanged margin geometry remains exact |
| `margins-edit` | 3 | One margin changes while other geometry survives |
| `comment-action` | 3 | Actual comment dialog retains author, text and matching range/reference IDs |
| `toc-action` | 3 | Heading gallery and contents action emit one TOC whose links resolve to bookmarks |
| `table-action` | 3 | Actual table dialog emits the requested two-by-three cell grid |

Each cycle saves, independently checks the package, and reopens it for the next
cycle. Assertions use fixed authored values; the normal gate does not generate
or accept replacement expectations. These semantic cases complement the
reviewed pixel goldens maintained in the source repository under its pinned
Flutter version.

At that checkpoint, all 27 new exports were listed in
[`tool/office_host_evidence.json`](../tool/office_host_evidence.json), alongside
the existing 14 host exports. The current manifest also includes the later
consolidation outputs. The inventory checks exact paths and package
integrity before the independent schema job runs. A control deletes each
declared export in turn and requires rejection, so a future added scenario
cannot silently disappear from schema evidence.

## Running and interpreting the gate

Use the app's pinned Flutter 3.47.8 toolchain:

```sh
flutter pub get
flutter test test/widget/office_paragraph_fidelity_test.dart
python3 -m unittest discover -s tool -p 'test_office_host_*.py'
bash tool/check_office_fidelity.sh
```

On Linux the existing system-SQLite wrapper remains available:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

The host gate also includes the existing footnote/endnote ribbon test that was
previously outside this selected cohort. Coverage is written to
`build/fidelity-host/coverage/gaps.json` with source hashes and uncovered lines.
`--require-all-sources` rejects an absent source and publishes explicit failed/unverified state.
It does not require every line to be hit or claim full branch coverage.

## Earlier coverage-branch checkpoint

The coverage branch's full host gate passed locally at app commit
[`9bf04566`](https://github.com/CrispStrobe/CrispCloud/commit/9bf04566434318ad199971d1071ca0ca02c81905),
using the app's pinned **Flutter 3.47.8 / Dart 3.13.7**. Its 278 shared file hashes
match suite
[`31add779`](https://github.com/CrispStrobe/quds_office_suite/commit/31add77938bb1242d510ab544dbe886d87ebdf75).
The following evidence-only commit on that branch did not change those tested
source bytes. These measurements are historical; the
[follow-up report](office-fidelity-followup-20261112.md) records the current
continuation acceptance evidence.

| Check | Result |
| --- | --- |
| Actual Flutter host tests | 115 passed |
| Required actual saved host exports | 41/41 verified |
| Shared engine acceptance tests | 530 passed |
| Required shared engine exports | 217/217 verified |
| Shared Python semantic/corruption controls | 264 passed |
| Host Office coverage | 2,282/3,661 instrumented lines (62.3%) |
| Scoped Office source files | All nine instrumented and source-hash matched |
| Shared vendor pins | 278/278 matched |
| Independent Open XML SDK validation | 258/258 packages; all 41 actual host saves and all 217 shared exports pass |

The [coverage inventory](office-host-coverage-gaps.json) records source commit,
all nine source hashes, uncovered lines and absent files (none in this scope).
Coverage measures executed instrumented lines, not branches or correctness.

The [SDK evidence](office-schema-evidence.json) contains every package hash
and zero validation errors; its input paths and bytes were independently matched
before and after validation. Native prerequisites were provided without altering
the tests or application sources, and the CI SQLite helper restored
`pubspec.yaml` exactly. That checkpoint's Actions run is
[43183465694](https://github.com/CrispStrobe/CrispCloud/actions/runs/43183465694);
its queue/execution status is separate from the completed local evidence.

That source checkpoint preserves native note-separator definitions and
their absence, prevents inserted notes from reusing special-definition IDs,
checks native paragraph-property order in retained parts, and carries the
reviewed story-page correction through three actual save/reopen cycles. Full
suite support boundaries and the independent native-render evidence are in the
[suite coverage guide](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-coverage-20261112/docs/office-fidelity-coverage-20261112.md).

## Historical evidence

[Actions run 43177469270](https://github.com/CrispStrobe/CrispCloud/actions/runs/43177469270)
tested app `86338bd` with suite `adcccb4`. Its 115 host tests, all 41 saved host
exports and all 41 host SDK validations passed, but the overall schema job
failed on 14 shared auxiliary fixtures because their authored paragraph
properties were ordered incorrectly. The `c19e90d` source checkpoint corrected
that fixture and strengthened the oracle. These prior results are retained as
counterexamples and do not certify later source changes.

The earlier **54.9%** coverage report measured an older source revision. It is a
separate historical observation. A passing semantic oracle or Open XML SDK
check does not establish pixel identity with Microsoft Word.
