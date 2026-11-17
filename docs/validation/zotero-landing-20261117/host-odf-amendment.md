# Final host ODF amendment evidence — 17 November 2026

The **10 bounded gates passed** at CrispCloud `a8cc440260369214fce5cbae8b0230f425a46829` (tree
`51abd03067cec69735a9413e1bb9323f6eadd93b`), paired with canonical Quds `f510060e35d580cbc361985a123927705c92ddc4` (tree
`15f19ae4c6b97760755fa25061af29312f98f348`). The executed service cohort passed **40 tests**
(39 inherited tests and one new nested covered-cell regression, which checks
both ODT and ODS). Two existing writer-to-host-reader probes passed separately;
two new list-group/Zotero-list probes also passed separately. All three cohorts
completed with zero skips.

These are new, source-bound results. The earlier 41 host + 39 service + 28
Python passes and its separate two probes remain bound to host `96c514eb98f7ba596a385c8f60496bc6c5994307` /
Quds `837d06edbde08a2465e99cbbb15927ee4c87d8ac` in the original landing evidence. Repeated tests
must not be added to those counts as unique coverage. The unchanged host 41 and
Python 28 cohorts were not rerun in this bounded amendment.

Source: [CrispCloud commit](https://github.com/CrispStrobe/CrispCloud/commit/a8cc440260369214fce5cbae8b0230f425a46829)
and [Quds commit](https://github.com/CrispStrobe/quds_office_suite/commit/f510060e35d580cbc361985a123927705c92ddc4).

## Confirmed reader defect and regression

The final canonical work retains covered table-cell stories in ODF packages
while suppressing them from visible extraction. The inherited host reader
already skipped direct covered cells, but recursively collected every paragraph
inside an ordinary cell. A nested table therefore exposed retained covered-cell
payload in the visible preview.

The isolated negative control ran against the immutable original host
`96c514eb98f7ba596a385c8f60496bc6c5994307` and reader Git blob `455fbeb817d3f2843bfa24c1568c2a7c2acb0237`. It failed the
intended assertion with Flutter exit `1`: the actual
preview included both `HIDDEN COVERED STORY` and `HIDDEN DEEP STORY`.
`negative/receipt.json`, its raw log, source maps, dependency maps and exact
scratch probe preserve that failure. This expected failure is **not an accepted
test pass**. Source and dependency inputs were unchanged; the failure was an
assertion, with no disk or compilation failure.

The 14-line production change filters paragraph ancestors only when their name
and namespace identify an ODF `table:covered-table-cell`. It preserves visible
nested paragraphs and similarly named foreign elements. The new committed
regression checks these positive controls, suppresses both hidden stories in
ODT and ODS previews, and verifies retained hidden XML remains available in
the raw package view. `reader-patch/` preserves the exact prepared patch and
its inherited/changed blob identities; the accepted runtime result is in the
final 40-test service log.

## Executed commands and integrity

| Gate | Outcome | Raw log under `qualification/` |
| --- | --- | --- |
| `vendor-source` | passed | `vendor-source.log` |
| `vendor-tracked` | passed | `vendor-tracked.log` |
| `service-tests` | 40 passed, 0 skipped | `service-tests.log` |
| `existing-odt-host-probes` | 2 passed, 0 skipped | `existing-odt-host-probes.log` |
| `list-host-probes` | 2 passed, 0 skipped | `list-host-probes.log` |
| `reader-analysis` | passed | `reader-analysis.log` |
| `reader-format` | passed | `reader-format.log` |
| `source-preservation` | passed | `source-preservation.log` |
| `whitespace` | passed | `whitespace.log` |
| `vendor-tracked-final` | passed | `vendor-tracked-final.log` |

The exact argv and working directory for each command are in
`qualification/receipt.json`. Strict reader analysis uses `dart analyze
--fatal-infos` on the actual reader and service test, followed by a no-output,
exit-on-change format check. A temporary analyzer graph resolves genuine local
and hosted packages; its full input is archived and the prior config was
restored. Neither production manifests nor the service lock were rewritten.

The final run fingerprints **3,792 source files**
and **6,002 dependency entries**, plus runtime,
graph, wrapper declarations and probe hashes. Before/after maps are identical,
tracked inputs still match the source commit, and analyzer restoration passed.
The harness contains 107 packages; all
97 hosted package versions and
archive hashes match the production lock. Production dependency declarations
and lock are unchanged. Application metadata retains version
`1.3.4+29` from incoming host main. The setup rebased
paths and source links in an independently reconstructed wrapper without
running `pub get` again during this amendment.

`scope-review.json` records exact source differences and demonstrates that the
only changed host library/test are the reader and its regression. It also binds
the incoming application version, production lock, macOS workflow and Apple
release metadata byte-for-byte. Those release files were inspected and
fingerprinted; no workflow or signing operation was executed.

## Probe scope

`probes/odt_writer_host_test.dart` contains the two original supplemental checks:
the authored Zotero fixture through actual ODT writer and host reader, and
authored whitespace/header/footer preview behavior. They check visible text,
hidden instruction suppression and preservation of original field data.

`probes/odt_list_host_test.dart` adds two focused checks. One verifies contiguous
ordered and bullet groups, boundaries after ordinary/suppressed paragraphs,
XML group lengths, visible order, spaces, tabs and newlines. The other places
the Zotero fixture in an ordered list and checks six visible numbered results,
suppression of instructions and unchanged source field data. The exact scratch
sources are included. Canonical writer, extractor, table, header/footer and
presentation suites are qualified separately; their counts are not claimed by
this host receipt.

## Preservation and inherited modes

All **2,559** managed paths pass exact content and
tracked-source guards: **702** canonical paths
plus **1,857** standalone parser paths. The parser
subtree/pin, all 20 host customization blobs/modes and six original notices are
unchanged. `qualification/preservation.json` records their exact identities.

There are **12 inherited executable-mode differences and zero newly introduced
mode differences**. The earlier limited inventory recorded eight. Four others
were already present at the baseline host/Quds pair but became newly included
in the expanded managed inventory. The original eight-only failed audit is
retained in the companion original landing evidence; it is not an exhaustive
mode proof. The current audit derives the complete set from immutable trees at
host `fae07f9e84036328aee271b5c14cda6b082cfab4` and Quds
`732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2` and verifies every current difference.

| Managed path | Preserved host mode | Canonical mode |
| --- | --- | --- |
| `packages/quds_office_editor/lib/src/core/input_bridge.dart` | `100755` | `100644` |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_font_faces.dart` | `100755` | `100644` |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_page_thumb.dart` | `100755` | `100644` |
| `packages/quds_office_editor/lib/src/editor_pdf/render_pdf_canvas.dart` | `100755` | `100644` |
| `packages/quds_office_editor/lib/src/embed/office_direction_keys.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/extract/office_text_extractor.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/fonts/font_subsetter.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/fonts/sfnt_parser.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/pdf/file/cos/pdf_cos.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/pdf/file/interp/pdf_interpreter.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/pdf/pdf_document.dart` | `100755` | `100644` |
| `packages/quds_office_engine/lib/src/pdf/pdf_font.dart` | `100755` | `100644` |

## Reproduction

Use a Linux workspace containing clean source checkouts at the exact commits
above, plus the original `host-audit` and `validation-runtime` companion
evidence. Follow `validation-runtime/README.md` and its `bootstrap-current.py`
to restore official Flutter 3.47.8 / Dart 3.13.7, then run the documented Linux
engine precache. Restore the original focused dependency cache with the original
host evidence's `prepare-host-harness.py` and `resolve-host-harness.py`, using
its supplied historical lock inputs and the same `runtime/pub-cache`. These
setup steps resolve dependencies only; no earlier test suite needs to run.
The runtime and original host setup scripts, locks and archive hashes are
required companions; SDK/cache binaries are intentionally excluded here.

With `FLUTTER_ROOT`, `PUB_CACHE`, `TMPDIR`, `XDG_CONFIG_HOME`, analytics
suppression and `CI=true` exported as documented in the runtime instructions,
reconstruct a fresh final wrapper and keep the delivered evidence untouched:

```bash
export PYTHONDONTWRITEBYTECODE=1
mkdir -p host-late-replay
python3 host-late-audit/prepare-harness.py \
  --source "$PWD/host-latest" --commit a8cc440260369214fce5cbae8b0230f425a46829 \
  --runtime "$PWD/runtime" \
  --harness "$PWD/host-late-replay/service-harness" \
  --receipt "$PWD/host-late-replay/setup-receipt.json"
python3 host-late-audit/run-bounded.py \
  --repo "$PWD/host-latest" --source a8cc440260369214fce5cbae8b0230f425a46829 \
  --canonical "$PWD/quds-latest" --canonical-commit f510060e35d580cbc361985a123927705c92ddc4 \
  --harness "$PWD/host-late-replay/service-harness" \
  --setup-receipt "$PWD/host-late-replay/setup-receipt.json" \
  --output "$PWD/host-late-replay/qualification"
```

`prepare-harness.py` verifies all saved template hashes, unchanged production
dependency declarations (version alone may differ), identical production lock,
all hosted lock identities and the 107-node graph before linking actual source.
The final runner refuses a changed source/pin or existing output receipt. Keep
both checkouts frozen until it completes. Historical absolute paths in the
saved executed maps describe this run; preparation rebases paths for replay.

The optional historical negative-control replay requires a separate clean
workspace with original host `96c514eb98f7ba596a385c8f60496bc6c5994307` at `crispcloud`, a copy of this
evidence's scripts/probes/template at `host-late-audit`, and the same runtime
cache. Reconstruct `host-late-audit/negative-harness` with
`--receipt host-late-audit/negative/setup-receipt.json`, then invoke
`run-negative-control.py` in that clean evidence copy. Do not overwrite the
delivered negative receipt. Its expected failure remains outside acceptance.

## Limits

This is bounded local qualification. It does not establish a complete viewer
or export-dialog workflow, a full application/native build, native/Wasm Harper,
live Zotero/desktop integration, or Word/LibreOffice interoperability. The
service graph deliberately excludes the full viewer dependency closure.
Flat contiguous list grouping is covered; nested list levels, custom numbering
formats and explicit restart values are outside this feature's checked scope.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or
awaited. Canonical and host source checkpoints are independently identified;
publication and branch integration are recorded by the parent landing record.
The small evidence inventory in `delivery-files.json` excludes generated
build caches, SDK binaries, dependency packages and live source symlink trees.
