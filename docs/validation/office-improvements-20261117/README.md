# Office preview and export improvements — final host qualification

The accepted source passes **107 core Dart/Flutter cases and 28 separate Python
controls**, plus **10 actual menu/export widget cases** in a second, separately
captured run. Both receipts are terminal `passed`, with no failures or skips:
[core qualification](qualification.json) and
[workflow qualification](workflow-qualification.json). This report supersedes the
earlier checkpoint summary in this directory; the preceding
[continuation evidence](../office-resume-20261117/README.md) remains intact.

| Source identity | Qualified value |
| --- | --- |
| Host implementation | [`f08035db691d5a1fe7299ad3608b626ab6202d27`](https://github.com/CrispStrobe/CrispCloud/commit/f08035db691d5a1fe7299ad3608b626ab6202d27) |
| Host tree | `f9b1822ceaacad6547533660af11ead3e13e1f68` |
| Canonical manifest pin | [`7fd2030fd39a2b0bbdb1b1e778840c332ae6bbc3`](https://github.com/CrispStrobe/quds_office_suite/commit/7fd2030fd39a2b0bbdb1b1e778840c332ae6bbc3) |
| Host comparison baseline | `83617b79f8a56600e9ca17e73f835d944c79dfa8` |

## Review branch and retained concurrent work

Review this continuation on
`codex/office-fidelity-improvements-20261117-e1978379`. The shared continuation
behind [PR #238](https://github.com/CrispStrobe/CrispCloud/pull/238) advanced from
captured `0b0557a9` to `78a4ccbb` while the improvements were being qualified.
Those arrivals were reconciled and preserved on the dedicated branch; the shared
branch was not overwritten. The branch name records its creation point, while
the table above identifies its final qualified implementation.

The [canonical companion report](https://github.com/CrispStrobe/quds_office_suite/blob/codex/office-fidelity-improvements-20261117-e1978379/docs/validation/office-improvements-20261117/README.md)
uses the same branch name and records canonical qualification independently.
Publication adds documentation and evidence after qualification. The
[source-equivalence receipt](source-equivalence.json) and
[delivery verifier](verify_delivery.py) bind every delivered non-documentation
Git blob and mode to the qualified source.

## What changed for readers and authors

ODF previews now select the visible document story by namespace identity. Stored
deletions, revision tables and change comments stay out of current previews,
including history-only documents. Live inserted text remains visible. Different
XML prefixes no longer hide supported paragraphs, styles, lists, links, notes or
header/footer text. Foreign extension elements retain the established fallback
behavior, and the existing narrow producer `style:list-style` tolerance remains.
Original XML is still available for inspection.

Cell extraction keeps each paragraph's own text and emits its anchored text-box
stories once, including nested frames. It no longer injects a frame's text into
the parent cell and repeats it afterward. Notes, annotations and ruby
pronunciation remain separate from ordinary cell text; ruby base text remains
readable. Namespace-qualified spaces, tabs, line breaks and CDATA are decoded.
CSV keeps decoded line breaks, while Markdown represents each table row on one
physical line.

The existing preview budget is enforced cumulatively across cells, including
explicit whitespace later trimmed from display and repeated-cell text reserved
before row retention. Decimal count checks reject malformed or excessive
expansions. Six host resource cases cover nondecimal, oversized and cumulative
whitespace. Note paragraphs and projected note-table cells retain boundaries
before readable-note whitespace normalization, preventing adjacent words from
being joined. These behaviors are included in the
[core independent review](independent-review.json).

The canonical integration also retains standalone default header/footer visuals,
shares their package media correctly, and normalizes emitted run colors before
style-cache comparison. Equivalent color spellings therefore do not manufacture
different continuous-section headers. Imported DOCX bookmark ends are paired by
ID with their starts within the same logical story; source boundary objects stay
unchanged, and independent header, note, comment and frame stories cannot consume
body endpoints.

Paragraph tab styles retain their own positions, alignment and leaders. Section
column counts and gaps are placed on the required `style:columns` child. The
incoming table repairs remain: row heights are minima so content can expand,
invalid dimensions and colors are omitted without dropping table content, and
hyphen and underscore leaders preserve distinct `style:leader-text` values.
These arrivals were reconciled with the earlier bookmark, color, media and column
fixes rather than discarded during the writer conflict.

## Accepted host coverage

| Accepted run | Dart/Flutter scope | Separate Python controls | Required gates |
| --- | --- | ---: | ---: |
| Core host | **107 passes across 10 suites** | **28 passes** | **9 passed** |
| Production menu/export workflow | **10 passes in one widget suite** | Not repeated | **6 passed** |

The core selection contains 41 document-service cases, eight annotation-preview
cases, two notice cases, 39 Zotero service/transport/ribbon cases, three
namespace/revision cases, six cell-story cases, six resource cases, and two
DOCX export/note-boundary acceptance cases. An independently authored DOCX goes
through the real importer, ODT writer and host preview service. Its assertions
cover colors, borders, bookmarks, links, lists, tables, notes, annotation privacy,
raw XML and preservation of source ownership. The bookmark failure control's
acceptance test remains byte-identical to the accepted test.

The workflow suite operates the actual dialog, menu, ribbon, controllers,
importers and export code. A deterministic cloud client and injected copy
destination supply the external boundaries. Its first two cases inspect ODT
content/privacy and ODP pending-title/notes preservation. Eight further cases
exercise both formats with saved, downloaded, cancelled and failed copy outcomes.
They introduce newer edits while the copy is pending, require those edits and the
original save target to survive, then exercise the original **Save** operation.
See the [workflow independent review](workflow-independent-review.json).

The core gates are vendor guards before and after, selected tests, strict host
analysis, strict changed-vendor analysis, host formatting, changed-vendor
formatting, Python controls and whitespace. Workflow gates are the two guards,
tests, strict analysis of the test, three support files and seven production
files, test-only formatting, and whitespace. Python and full vendor formatting
are not counted again in the workflow run.

Earlier 96-case host continuation evidence, earlier 107-case host checkpoints,
and the 1,533-case canonical cohort retain their original source attribution.
They are not added to these fresh results. Canonical, core-host and workflow
runs have separate receipts; repeated execution is not additional unique coverage.

## Frozen inputs and dependency provenance

Independent reviews recount raw events, check unique start/completion IDs and
exact selected suites, resolve test origins to source files, and verify saved
hashes against Git and live inputs. The core stream has 117 matched start/end
pairs, comprising 107 substantive cases and ten loading cases. Its Python log
contains 28 unique completed controls.

| Before/after input inventory | Core host | Workflow |
| --- | ---: | ---: |
| Materialized source entries | 7,490 | 7,494 |
| Dependency entries | 4,511 | 7,188 |
| SDK/runtime entries | 517 | 517 |
| Workspace entries | 14 | 28 |
| Package routes | 107 | 180 |

Both runs retain equal before/after maps. Library and resource symlink
destinations are recorded alongside bytes, including local assets, fonts, hooks
and native/Rust source directories. The temporary analyzer graph is checked while
installed and restored afterward. The runtime is Flutter **3.47.8** with Dart
**3.13.7**; exact runtime identities accompany the receipts.

The core graph verifies all **97 hosted** package versions and archive hashes
against the production lock. Workflow uses **179 locked dependencies plus the
root application**, giving 180 graph packages: **162 hosted pins**, 11 wrappers
routing to real host package libraries, and the exact external Git dependency
`libdbm` at `1d2b0a9e25e0890fc113dd6f533309275dc66830`, with SDK packages completing
the graph. Setup recovered **55 newly downloaded archives**, checking each
against its pinned digest. No dependency versions were relaxed and no library
or hook implementations were stubbed for provisioning.

Four sparse-omitted Roboto/RobotoMono font assets were restored from exact
`f08035db` Git blobs only after the core run and its source readback finished.
That explains the four additional workflow source entries; the implementation
commit did not change. The unchanged `crisp_storage` hook remains present with
optional `rust_smb` unset, and SQLite keeps its real default hook.

SQLite's Linux x64 release asset was separately authenticated before workflow
execution: **1,793,240 bytes**, SHA-256
`e184f6ba2b7a3440e272df64c6d038de5c7b1a997b7c2f9341164602f9bdf024`, matching the
production-pinned `sqlite3` 3.3.3 hook table. The completed
[workflow independent audit](workflow-independent-review.json) confirms that
both the actual hook output and the runtime manifest-selected bundle at
`build/native_assets/linux/libsqlite3.so` have that same size and digest. This
authenticates hook and manifest selection; dynamic loading was not instrumented,
and the evidence does not establish that these widget cases invoked SQLite
functions. The default `crisp_storage` and `objective_c` hooks completed without
emitting optional Rust or Apple native assets.

## Preservation and corrected test expectations

The [preservation report](preservation.json) authenticates **2,612 managed files:
755 canonical files and 1,857 unchanged standalone-parser files**. It preserves
all 50 canonical and 46 host Zotero paths, 20 audited host customizations, six
original notices with Unicode registration retained, and the same 12 inherited
executable-mode differences. There are no new mode differences.

Two precise test-contract corrections remain visible in the evidence. The
cell-story probe originally expected a literal newline inside a Markdown table
row. The corrected assertion requires one physical data row and separately
preserves exact decoded CSV newlines; authored fixtures, logical text,
hidden-payload checks and raw-XML assertions remain. Its uniqueness check targets
the data row so the generated ODS heading `Cells` is not mistaken for cell text.

The older tab probe treated hyphen and underscore as equivalent because the
then-current writer emitted only their shared solid leader style. Incoming
leader-text preservation makes those outputs distinct. The reconciled test keeps
same-hyphen `72`/`72.004` equivalence, adds an underscore change requiring a new
master, and retains the right/dotted change. Old/new test bytes, patches, reasons
and historical controls remain separately attributed. Earlier setup failures and
failed attempts are preserved rather than relabeled as accepted runs.

## Reproduction and delivery

The [runner](run_validation.py), [member index](evidence-index.json) and
[evidence archive](evidence.tar.xz) retain commands, raw logs, graphs, locks,
source maps, setup records, controls and review artifacts. The delivery verifier
checks archive members against recorded sizes and hashes and checks source
identity. Reproduction requires a host checkout at `f08035db`, canonical source
at `7fd2030f`, the recorded SDK/cache and both archived harnesses. Restore their
recorded package pins and source routing, relocate local paths deliberately, and
resolve the locked graphs offline. Record any relocated graph under its new hash.

Run the two modes sequentially because each temporarily installs a host analyzer
graph. Finish the core input audit before restoring the four workflow fonts when
reproducing the original sparse materialization. Use fresh output directories:

```sh
python3 run_validation.py --kind host \
  --repo /path/to/CrispCloud --harness /path/to/host-harness \
  --canonical-source /path/to/quds_office_suite \
  --sdk /path/to/flutter-sdk --cache /path/to/pub-cache \
  --expected-head f08035db691d5a1fe7299ad3608b626ab6202d27 \
  --baseline 83617b79f8a56600e9ca17e73f835d944c79dfa8 \
  --output /path/to/new-core-evidence

python3 run_validation.py --kind workflow \
  --repo /path/to/CrispCloud --harness /path/to/host-workflow-harness \
  --canonical-source /path/to/quds_office_suite \
  --sdk /path/to/flutter-sdk --cache /path/to/pub-cache \
  --expected-head f08035db691d5a1fe7299ad3608b626ab6202d27 \
  --baseline 83617b79f8a56600e9ca17e73f835d944c79dfa8 \
  --output /path/to/new-workflow-evidence
```

These results cover focused local preview/service behavior and actual menu/export
widgets with the stated doubles. They do not establish live operating-system
export-dialog or cloud-transport acceptance, current Word/LibreOffice/Zotero
interoperability, native proofing/model behavior, native storage behavior, or Wasm
acceptance. Imported consumer evidence remains tied to its own source. No GitHub
Actions, workflow, check-run or CI-status endpoint was queried or awaited.
