# Host note amendment evidence — 17 November 2026

All **9 bounded gates passed** on CrispCloud `58a7e60b7a8b44d7809b6cf7c27541f41a3168dc` (tree
`a6fd4865300febb0bc44cb294c84aa61bdd86750`), pinned to canonical Quds `b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc` (tree
`642436fb32d73cb73706a4dd1c1fce32d0f2fb8b`). The run passed **12 focused service tests** and
**2 writer-to-actual-host-reader probes**, each with zero skipped tests.
The scopes and source identities are separate from all earlier receipts.

The immediately preceding host ODF amendment remains accepted at
`a8cc440260369214fce5cbae8b0230f425a46829` / Quds `f510060e35d580cbc361985a123927705c92ddc4` with
40 service + 2 existing writer-reader + 2 list probes. The original broad
41 host + 39 service + 28 Python receipt remains bound to host
`96c514eb98f7ba596a385c8f60496bc6c5994307` / Quds
`837d06edbde08a2465e99cbbb15927ee4c87d8ac`, with its separate 2 probes.
Repeated tests are not additional unique coverage.

Source: [host commit](https://github.com/CrispStrobe/CrispCloud/commit/58a7e60b7a8b44d7809b6cf7c27541f41a3168dc)
and [canonical commit](https://github.com/CrispStrobe/quds_office_suite/commit/b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc).

## Observed defect and minimal correction

The incoming writer adds ODT footnotes and endnotes by writing note bodies
through its existing block writer. This correctly retains covered table-cell
stories in the package. The host's ODT note preview previously traversed every
descendant of a note body, including retained covered cells. Its separate
ordinary-table ancestor filter did not cover this inline traversal.

Before changing the reader, the exact focused writer-to-reader probe ran on
published host `c66a84fcf5ce9016d8cc5b31b6d44f775d5a1149` (tree
`a10b5e183294e19324026abcb30df4e4299f8bbd`), already synchronized to the same canonical note
writer. It failed the intended assertion with Flutter exit 1: the preview
contained `HIDDEN COVERED NOTE` and `HIDDEN DEEP NOTE` between visible note
text. The original log, source/dependency maps and source identities are in
`negative/`. The result is an **expected failing negative control, with zero
accepted passes**. Source and dependency inputs were stable; it was an assertion
failure rather than a disk or compilation failure.

The correction adds four lines to the ODT-only inline switch. It stops at an
element only when both its local name and namespace identify an ODF covered
table cell. The new committed service regression checks a nondefault ODF table
prefix, covered and deeply nested hidden stories, ordinary visible text and a
foreign namespace element with the same local name. Hidden content remains in
the raw XML. `reader-patch/` preserves the prepared patch and exact before/after
blobs, and `scope-review.json` verifies those blobs are the accepted commits.

The negative probe source is byte-identical to the final accepted probe source.
Its baseline working checkout was advanced only after the negative run ended;
the archived before/after maps and immutable baseline Git identity describe
that run, rather than the later contents of the same checkout path.

## Executed gates

| Gate | Outcome | Raw log under `qualification/` |
| --- | --- | --- |
| `vendor-source` | passed | `vendor-source.log` |
| `vendor-tracked` | passed | `vendor-tracked.log` |
| `odt-service-tests` | 12 passed; 0 skipped | `odt-service-tests.log` |
| `note-host-probes` | 2 passed; 0 skipped | `note-host-probes.log` |
| `reader-analysis` | passed | `reader-analysis.log` |
| `reader-format` | passed | `reader-format.log` |
| `source-preservation` | passed | `source-preservation.log` |
| `whitespace` | passed | `whitespace.log` |
| `vendor-tracked-final` | passed | `vendor-tracked-final.log` |

The 12 selected service tests comprise all ten preexisting ODT service tests,
the already accepted ODF nested-cell regression, and the new covered-note
regression. Selection uses `--name '^(ODT |ODF nested covered stories)'` on the
actual committed service test file. This covers headings, ordinary tables and
lists, inline styles/links/notes, named styles, headers/footers, text boxes,
pictures and image geometry. The other document formats and unchanged broad
host/Python cohorts were not rerun for this ODT-only change.

The two scratch probes use the actual production writer and host service.
The first uses footnote and endnote definitions with the same native ID to
check correct note-class lookup, visible cached Zotero results, suppressed
instruction payload and unchanged source field data. It verifies exact authored
spaces/tabs/newlines in the emitted note-body XML, retained body whitespace and
the host's existing one-line normalization for each displayed note. The second
exports a note table containing merged covered-cell and deeper descendant
stories, then confirms the actual host hides those stories while keeping
visible note text and preserving the raw package payload.

The strict reader gates run `dart analyze --fatal-infos` and a no-output,
exit-on-change formatter against the changed reader and service test. The
temporary analyzer config is archived and restored after execution. Exact
command argv, working directories, timing, terminal counts and raw-log hashes
are recorded in `qualification/receipt.json`.

## Source, graph and preservation

The final run binds **3,792 source files** and
**6,002 dependency entries**, plus runtime binary,
manifest, graph and probe hashes. Source/dependency maps match before and after;
tracked inputs still match the published source; analyzer restoration passed.
The isolated wrapper contains 107 packages, including
97 hosted packages whose exact
versions/archive hashes match production. Dependency declarations and the
production lock are unchanged; no `pub get` ran during this amendment.

All **2,559** managed paths pass content/tracked
guards: **702** canonical paths and
**1,857** standalone parser paths. The parser
subtree/pin, 20 host customization blobs/modes and six notices remain unchanged.
All **12 inherited executable-mode differences** remain preserved, with no new
mode difference. Full baseline/current identities and paths are in
`qualification/preservation.json`; the correction from the old limited eight
mode inventory is documented in the earlier sealed host evidence.

`scope-review.json` also confirms unchanged incoming application version,
production lock, macOS workflow and Apple policy/inventory files. The field
boundary suppression branch and authored whitespace encoder remain
byte-identical to the preceding accepted canonical source. The full inline
writer changes only as recorded by the separate canonical note amendment;
canonical runtime counts are not claimed by this host receipt.

## Reproduction

Restore the official Flutter 3.47.8 / Dart 3.13.7 runtime using the companion
`validation-runtime` evidence and its bootstrap, and populate the original
focused dependency cache using the original `host-audit` prepare/resolve helpers
and saved historical lock inputs. These are setup prerequisites; earlier test
suites need not run again. Use clean host/canonical checkouts at the exact
commits above, and the exported environment described by the runtime kit.

Run from a workspace containing this `host-note-audit` directory, source
checkouts `host-latest` / `quds-landing`, and `runtime`:

```bash
export PYTHONDONTWRITEBYTECODE=1
mkdir -p host-note-replay
python3 host-note-audit/prepare-harness.py \
  --source "$PWD/host-latest" --commit 58a7e60b7a8b44d7809b6cf7c27541f41a3168dc \
  --runtime "$PWD/runtime" \
  --harness "$PWD/host-note-replay/service-harness" \
  --receipt "$PWD/host-note-replay/setup-receipt.json"
python3 host-note-audit/run-bounded.py \
  --repo "$PWD/host-latest" --source 58a7e60b7a8b44d7809b6cf7c27541f41a3168dc \
  --canonical "$PWD/quds-landing" --canonical-commit b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc \
  --harness "$PWD/host-note-replay/service-harness" \
  --setup-receipt "$PWD/host-note-replay/setup-receipt.json" \
  --output "$PWD/host-note-replay/qualification"
```

Preparation verifies the saved template hashes, unchanged dependency
declarations/production lock, all hosted lock identities and the 107-package
graph, then rebases paths and links actual source. The runner refuses changed
source identities, mismatched canonical pin, untracked execution inputs or an
existing output receipt. Keep source checkouts frozen until it finishes.

For an optional negative-control replay, use a separate clean host checkout at
`c66a84fcf5ce9016d8cc5b31b6d44f775d5a1149` and the same canonical source. Prepare a distinct
harness with `--receipt` pointing into a new output directory, then run
`run-negative-control.py` with its `--repo`, `--source`, `--canonical`,
`--canonical-commit`, `--harness` and `--output` options. Do not overwrite the
delivered evidence. A successfully reproduced expected failure remains outside
accepted pass counts.

## Limits and evidence contents

The host note preview intentionally normalizes each note to one line. Raw
authored note whitespace is checked separately. Incoming note numbering follows
encounter order; full native numbering formats, restarts, custom marks, repeated
references and malformed recursive note models are outside these assertions.
The host probes establish note preview behavior, not canonical note-body search
coverage. The shared canonical decoder's treatment of inline notes is covered
only to the extent stated in its separate evidence.

This does not claim complete viewer/export-dialog workflows, a full application
or native build, native/Wasm Harper, live Zotero/desktop integration, or
Word/LibreOffice interoperability. Release workflow and policy files are bound
as source inputs; no workflow, signing or release execution was performed.
No GitHub Actions, workflow, check-run or CI-status endpoint was queried or
awaited.

`delivery-files.json` lists the exact small evidence set, including scripts,
template/lock/graph inputs, probes, raw logs, negative control, patch and source
maps. It excludes generated build caches, SDK/cache binaries and live source
symlink trees. The independent review is published separately beside the
archive by the parent landing record. Earlier sealed evidence is unchanged.
