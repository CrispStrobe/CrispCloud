# Office fidelity continuation — 13 November 2026

This is the retained first-pass handoff. The [follow-up handoff](continuation-20261113-followup.md)
supersedes its integration guidance and next-work status. Exact identities,
measurements and rejected controls below remain historical.

The current implementation and reproducible evidence are saved incrementally on
`feature/office-fidelity-gaps-20261113` in both
[`CrispStrobe/legacy-doc-parser`](https://github.com/CrispStrobe/legacy-doc-parser/tree/feature/office-fidelity-gaps-20261113)
and [`CrispStrobe/CrispCloud`](https://github.com/CrispStrobe/CrispCloud/tree/feature/office-fidelity-gaps-20261113).
These branches incorporate the newer main-branch work that superseded the
[12 November handoff](continuation-20261112.md). Continue from these current
branches; the earlier handoff and sealed receipts retain their historical
identities. Runtime and evidence-only commits are separate checkpoints.

## Exact integration boundary

| Component | Validated source |
| --- | --- |
| Standalone parser runtime | `48bf3a84e822b960e369f0134d597e025c775a41` |
| Parser runtime tree | `a952a0b5930baf97728120e6f34062586df89d11` |
| CrispCloud runtime | `0233ed8e9501538a9e68051b58a048407b2e29d0` |
| App runtime tree | `bea1c6b8a9d4f6533462e715b82017a6a62f4b6c` |
| Quds pin, retained from current app main | `6d6e77d14ead33de90c57ec5feb2ab3cc44f6501` |
| Guarded Office inventory | 1,226 files: 805 exact upstream parser files and 421 unchanged other files |
| App version, retained | `1.2.9+22` |

CrispCloud pins this exact parser runtime and contains no app-local parser
patch. Subsequent evidence and handoff commits do not change either measured
runtime or require a parser roll. The app's current main already included the
newer archive and release-input work; that work, the root lockfile, Quds source
and policy decisions were preserved. These are development checkpoints, with
no merge into main, deployment or package publication.

The parser baseline at `cd9ab85a` passed 931 Dart tests before the new guard.
Its [sealed baseline](evidence/continuation-baseline-20261113/README.md) remains
distinct from the final 934-test acceptance. Baseline, note attribution, bounded
OfficeArt changes, diagnostic experiments and final acceptance were each saved
to remote commits as they completed.

## Changes and source attribution

**Disabled-line fallback dashes remain explicit unsupported evidence.**
OfficeArt's `fNoLineDrawDash` requests a dashed fallback when the normal line is
disabled. The parser now retains the active request as unresolved evidence and
reports partial formatting, instead of treating a shape with that appearance
omitted as fully supported. This does not implement fallback-dash rendering.
The guard is deliberately inactive when the ordinary line is enabled, including
its default-enabled state. Tests cover use bits, inherited settings, explicit
overrides and clearing the inherited request. The
[OfficeArt context contract](officeart-context.md) records that boundary.

**The note differences have independent source explanations.** The
[raw note audit](evidence/note-source-attribution-20261113/README.md) decodes the
CFB, FIB, CLX, note PLCs and section property streams without using the Dart
parser. In `note-markers`, the sixth/table footnote starts with one automatic
U+0002 marker, and the complete source text has no question mark; the native
bridge substitutes a literal `?` in its textbox.
The parser retains the source marker, table and real paragraph boundaries.
In `word-compatibility`, the source version makes the old DOP start-at-four
field inapplicable. The sections request Roman numbering restarted in each
section, so the source-defined first note is `i`; the native reference uses
`iv`. Neither observation warrants inventing source text or a producer override.

The prior [footnote-table audit](evidence/table-note-oracle-20261113/README.md)
also remains applicable. The 74.427-point initial `table-borders` disagreement
comes from the native DOC importer flattening a real source table. The parser
matches the authored DOCX render. Both table/note cases remain exactly stable
against their first parser import through three cycles in the final corpus.

**The complete corpus confirms the integrated header and Word16 corrections.**
Both header textbox fixtures are now exact initially and in every comparison
through three cycles. The bounded
[explicit-border frame mapping](textbox-frame-borders.md) closes their former
0.35-point repeated movement. Word16's initial word displacement falls from
1.446 points to zero with the source-equivalent
[disabled-width-balancing output](evidence/compatibility-width-balance-20261113/README.md).
Its RGB raster still differs. On the first native re-export, the bridge changes
the source compatibility bit, and a 1.446-point word difference returns; later
cycles add no further word-position drift. The final measurement does not
claim that Word16 is exact through native binary round trips.

The source-direction correction integrated from current main also preserves
section and gutter direction. The final corpus comparison retains the changed
`word-compatibility` rendering separately from its unchanged aggregate failure
counts; its remaining note and line-number differences are still open. This
is not a new all-document fidelity guarantee.

**Absent textbox stroke widths remain unresolved.** Word14 still measures
0.75-point initial displacement. Its parser output matches its own regenerated
binary exactly in all three cycles, while the native bridge introduces 0.05
points per cycle. The new
[bounded output probes](evidence/textbox-default-probe-20261113/README.md)
retain complete diagnostics: explicit default width reduces the initial
displacement to 0.40 points, and one additional frame adjustment reduces it to
0.20 points, but no candidate is RGB-exact or accepted as a runtime change.
Those counterfactuals have no repeat/schema acceptance claim. Six synthetic
boundary controls proved unsuitable as native layout controls and are retained
as failures. Source coordinates, absent widths and reviewed goldens are intact.

**CrispCloud now verifies what will actually be saved to Git.** Current main's
mirror manifest named six parser diagnostic logs missing from its Git tree
because of the blanket `*.log` ignore rule. The exact upstream blobs were
restored, and a narrowly scoped exception includes parser evidence logs. The
new `--require-tracked` mode checks staged blob bytes, modes, source-pin
declarations and the exact parser-prefix inventory. It rejects ignored or
stale files, unstaged deletions, unmerged entries and extra staged files. CI
runs this check immediately after checkout, before its temporary SQLite hook.
The [app acceptance](https://github.com/CrispStrobe/CrispCloud/blob/ec354cc3e6c11243bb66cbe9eb0763f15b72f7c1/docs/evidence/word-gaps-48bf3a-20261113/README.md)
includes a separate checkout of the published runtime and its exact index.

## Completed validation

| Gate | Result and scope |
| --- | --- |
| Parser portable suite | 934 Dart tests and 162 Python controls; formatting and analysis clean |
| Parser source identity | All 807 captured input hashes unchanged, including 805 tracked files |
| Fixture integrity | 24 source hashes and OOXML package graphs verified |
| Parser JavaScript | Actual DOC acceptance and 51 media checks passed |
| Package dry run | Zero warnings; no publication |
| Independent Open XML SDK 3.3.0 | 229 required DOCX outputs accepted with zero Office2019 validation errors |
| Schema generation | Both complete 486-file generations match byte for byte |
| Native corpus | 24 initial cases and 72 repeats, zero execution/import errors |
| Native source identity | Original/cycle bytes unchanged; all 138 runtime/configuration inputs consistent; one compiled-executable hash |
| Native artifact verification | All 24 archives, 2,646 artifact files and 240 lossless raster pages verified |
| App data-only Word cohort | 107 tests across eight suites, no failures/skips; all 1,179 captured inputs unchanged |
| App complete tracked identity | All 7,108 tracked source hashes and production package configuration unchanged during acceptance |
| App production JavaScript | DOC, RTF, PPT and MSG smoke passed |
| App actual installed-Office checks | 13 LibreOffice/Poppler assertions passed |
| App source controls | 27 sync, 38 Apple preflight, 40 crypto evidence and 22 ebook controls passed; two expected macOS-only skips |
| App actual source verification | All 1,226 Office files and 279 pinned CrisperBooks files verified; existing release-input checker passed |

Hosted checks also passed on the exact measured runtime commits: the parser's
[Dart package workflow](https://github.com/CrispStrobe/legacy-doc-parser/actions/runs/43376006611),
CrispCloud's [provider compatibility workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296067),
and both jobs of its [Office fidelity integration workflow](https://github.com/CrispStrobe/CrispCloud/actions/runs/43376296083).
The Office jobs include the committed-source check, shared corpus and actual
host-save workflow, required-host-export coverage, invalid-XML control,
independent schema validation and actual-host repeated-save rendering. These
hosted results are separate from the local receipts and execution limits below.

The complete [portable/schema bundle](evidence/continuation-48bf3a/README.md)
retains 1,174 files, all stage logs, source receipts, positive and negative
controls, both complete generated corpora and exact Git identities. Its verifier
checks the entire retained inventory and rejects nine corruption controls,
including under optimized Python. It can additionally compare all captured
tracked files with the pinned Git objects.

The [final native bundle](evidence/native-corpus-48bf3a/README.md) retains the
original reports, index, 312 DOC/DOCX files, 230 PDFs, all 240 compressed RGB
pages and 73 execution logs. Its comparison with the earlier `0c3e596` corpus
uses the same source and binary bytes, renderer, fonts and tool identities.
No reviewed source golden was changed.

| Native comparison | Historical `0c3e596` | Final `48bf3a` |
| --- | ---: | ---: |
| Initial page counts agree | 24/24 | 24/24 |
| Initial page dimensions agree | 22/24 | 22/24 |
| Initial per-page word sequences agree | 21/24 | 21/24 |
| Initial word geometry within 0.25 pt | 11/24 | 14/24 |
| Initial full render exactness | 6/24 | 8/24 |
| Repeat full render exactness versus preceding parser import | 52/72 | 58/72 |
| Repeat full render exactness versus first parser import | 42/72 | 48/72 |

Full render exactness combines page counts, dimensions, word geometry,
extracted layout text and exact RGB raster equality on the recorded renderer.
It is stricter than passing the 0.25-point word tolerance. Every repeat page
count and dimension agrees. Both authored source-render goldens reproduce;
the parser matches one of the two. Strict structural comparisons still report
differences in every case. These are separate contracts.

The renderer is LibreOfficeDev 26.8.0.0.alpha0, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, at 72 DPI. The evidence records
the distinct Poppler executable versions and hashes, fonts and Dart 3.13.7.
Microsoft Word was not executed. The app's fake-process converter tests are
separate from its 13 actual native assertions. Flutter widgets, native ebook
build hooks and a complete app/release build were not run locally in this
continuation. Acceptance uses a genuine production package configuration
resolved offline with the existing lockfile; no SDK version was synthesized.

## Next bounded work

1. Resolve Word14's absent-width/effect interaction with independently authored
   source fixtures, native renders and repeat cycles. Preserve the rejected
   default-width and frame counterexamples; a lower initial word-drift number
   alone is insufficient to accept a transform.
2. Keep Word16's native compatibility-bit rewrite distinct from its corrected
   initial import and stable table origin. Any further correction must preserve
   the binary source's explicit true/false instruction.
3. Investigate remaining compatibility/line-number geometry and unsupported
   drawing effects without undoing the independently decoded note semantics,
   source tables or section direction. The two list fixtures omit source page
   sizes, so their source-defined Letter versus native A4 difference remains an
   attributed default difference.
4. Extend GDI/metafile behavior, nonempty ink rendering/association and broader
   move/table/object revision semantics with independent source controls.
   Existing bounded support does not imply complete Word fidelity.

Start from the current remote branches, preserve the exact app parser pin and
guarded mirror, save implementation checkpoints remotely, and bind every new
measurement to its own clean runtime. Evidence-only additions do not require
rerunning unchanged runtime gates or rolling the app to a documentation commit.
