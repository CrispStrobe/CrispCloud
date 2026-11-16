# Reproducible local setup for the Zotero recovery

This package records the genuine runtime, resolved test graphs and isolated
source wrappers used for the fresh recovery qualification. It contains setup
evidence, not application-test results. Accepted test results and their complete
before/after source inventories are published separately.

## Immutable source and runtime

| Input | Identity |
| --- | --- |
| Canonical Quds source | `b87f9d6c3a2532c9695024adf48ca9fbd3c0927a` |
| CrispCloud source | `07083d1983db87a9868c3e8ba0cda1efd283b445` |
| Flutter framework | `3.47.8`, `737ba8f885dc774b53b442759999a312c9461e4e` |
| Flutter engine | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Dart SDK | `3.13.7` |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Linux Flutter tester SHA-256 | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |

The framework was cloned from the official Flutter repository at its exact
release tag. The Dart SDK came from the official engine-specific URL used by
that framework's `bin/internal/update_dart_sdk.sh`. Its complete archive and
executable hashes are in `runtime-download.json`. Flutter itself downloaded
the required test-engine artifacts. The Dart executable and `flutter_tester`
both match the genuine binary hashes recorded in the earlier committed setup.
No tracked SDK files were modified and no SDK version was substituted.

`runtime-verification.json` rechecks the setup receipt's runtime hashes while
packaging this evidence. Additional Flutter-tool manifests and resolved graphs
are preserved in `sdk-tool-inputs.json.gz`. The generated Flutter-tool snapshot
hash identifies the actual runtime used here; this package does not claim that
recompiling a JIT snapshot elsewhere produces identical bytes.

## Locked graphs and source links

The existing committed reconstruction recipes supplied the engine, editor,
Studio and actual-host manifests and locks. Only local paths were rebased.
All four final `pub get --enforce-lockfile` invocations succeeded, and every
dependency lockfile stayed unchanged during initial setup:

| Wrapper | Resolved packages |
| --- | ---: |
| Canonical engine | 55 |
| Canonical editor | 79 |
| Studio | 64 |
| Actual CrispCloud host | 96 |

The host wrapper adds the four actual bundled notice assets, including
FontTools. The corresponding fixture links point to real canonical/host
files. This changes asset declarations only; no dependency versions were
changed. `harness-assets.json` contains the exact entries, their hashes and
the unchanged host lock hash.

The unchanged pinned reconstructor links only `lib`, `test` and `tool` into
the canonical engine wrapper. It does not link the engine's complete example
project. Its broader support-package linking applies to `quds_reports` and
`legacy_doc_parser`. The unchanged bootstrap also contains no custom SDK zip
path guard: it delegates installation to Flutter's official downloader and
unzip routine. The example-project and top-level archive-license corrections
below arose in temporary setup steps, not in those committed scripts.

`harness-inputs.json.gz` contains the exact UTF-8 manifests, locks and package
graphs from both the warmed original wrappers and the new isolated wrappers.
Each record carries a path, byte count and SHA-256. Original inputs are checked
against the isolation receipt before being included. Package versions,
language versions and nonpath graph metadata are preserved. Host absolute
wrapper paths are rebased; relative paths remain relative.

The retry setup uses detached worktrees at the immutable commits above:

- `quds-validation`, with wrappers in `zotero-toolchain/retry-harness`;
- `crisp-validation`, with its wrapper in `zotero-toolchain/crisp-host-retry`.

The initial isolation check covered **1,565** canonical source/asset/manifest
inputs, including both `apps/quds_report_studio` dependency and analysis
manifests. The final complete-run source selection additionally includes the
three imported PDF examples below, for **1,568** inputs. All selected files
match their Git blobs. All **2,509** host managed-file hashes were checked.
The complete selected canonical SHA-256 map and host managed SHA-256 map are
in `source-maps.json.gz`. These setup checks establish file content; the
separate delivery verifier records Git modes and the precise managed-copy
boundary.

Only wrapper manifests, locks, package graphs and source symlinks were copied
for the retry. Old compiled-test and build caches were excluded. The genuine
SDK and dependency cache are shared without setup writes. The retry setup
did not execute `pub get` or launch any test. `retry-harness-setup.json.gz`
records every copied input, path rebase, source link and exclusion.

`pdf_widgets_test.dart` imports three real engine example libraries. The
post-isolation correction links only `pdf_widgets_invoice.dart`,
`pdf_widgets_proposal.dart` and `pdf_widgets_report.dart` into the wrapper's
`example` directory. They have no further relative imports, exports or parts;
their SDK/package imports resolve through the existing genuine graph. Their
exact committed bytes, directives and link targets are recorded in
`pdf-widget-example-links.json`. The wrapper does **not** expose the example
workspace pubspec. Its manifests, locks and graphs remain unchanged.

Those examples and the existing test also probe DejaVu/Liberation regular and
bold fonts under `/usr/share/fonts`. The same receipt records the presence
and SHA-256 of all four optional paths. These are actual external fixture
inputs; their availability is kept explicit rather than replacing them with
an unrecorded font.

## Setup corrections and interrupted attempts

The following corrections are retained explicitly; none is an application
test-pass claim:

1. The first framework clone failed with an HTTP/2 stream/early-EOF error.
   Repeating the exact pin with HTTP/1.1 succeeded. The original clone error
   was observed in the tool transcript; a separate raw clone-error log was
   not saved. The successful clean framework identity is independently checked.
2. A conservative archive check initially rejected the genuine top-level
   `LICENSE.dart_sdk_archive.md` alongside `dart-sdk/`. The check was corrected
   before extraction. A premature duplicate SDK download was cancelled, and
   a premature engine resolver invocation ended before Dart was available.
   Their captured setup logs are retained. The final official archive and
   Dart executable hashes were verified before qualification.
3. A temporary engine `example` link caused Dart pub to attempt resolving an
   unrelated workspace-only example. That unnecessary link was removed;
   the same enforced-lockfile resolution then passed. The rejected resolver
   log and the successful replacement are both retained.
4. The first sparse source view omitted two application manifests selected
   by the source fingerprint. Their exact committed bytes were materialized;
   no production content changed. `sparse-manifest-correction.json` records
   both Git blobs and hashes. The isolated worktree includes them from creation.
5. The first engine test startup added only `flutterRoot` and `flutterVersion`
   to its package configuration. Removing exactly those two lines recovers
   the original configuration hash. `harness-metadata-adjustment.json` records
   this proof. The dependency graph and lock did not change. A run whose
   original byte fingerprint changed is not treated as accepted evidence.
6. Ownership/liveness of the earlier child-owned qualification processes
   could not be established after their handles disappeared. Fresh source
   worktrees and wrappers were therefore prepared. They preserve the genuine
   warmed Flutter metadata and exclude the old build/test caches. The root
   process owns the fresh runners and their polling. Earlier partial results
   are not added to fresh accepted totals.
7. The first isolated full canonical attempt stopped when the PDF widget
   suite could not import those three example files through the wrapper.
   Its preceding complete cohorts are preserved as historical results and
   excluded from the new final total. The narrow source links above correct
   the harness; the production files and test assertions are unchanged. The
   new complete-run fingerprint includes all three exact source files.

`setup-logs.json.gz` contains the captured setup logs and observed exit codes.
It does not contain the missing original clone stderr, fabricate the lost
historical qualification receipts, or turn partial runs into passes.

## Reproduction

Use checkouts named `quds` and `crispcloud` beside `zotero-toolchain`, with the
historical commits needed by the reconstruction receipts available locally.
The commands below assume the workspace is the current directory. Replace
`/path/to/setup-publication` with this package's location.

```bash
ln -s quds quds_office_suite
ln -s crispcloud CrispCloud
git -C quds checkout --detach b87f9d6c3a2532c9695024adf48ca9fbd3c0927a
git -C crispcloud checkout --detach 07083d1983db87a9868c3e8ba0cda1efd283b445

# A normal complete checkout is also sufficient. For sparse checkouts,
# include the application manifests selected by the canonical fingerprint.
git -C quds sparse-checkout set --cone packages tool apps/quds_report_studio \
  docs/validation/zotero-citing-20261115 \
  docs/validation/zotero-continuation-20261116
git -C crispcloud sparse-checkout set --cone lib packages test tool \
  docs/validation/zotero-citing-20261115

# Optional transport workaround before running the unchanged bootstrap.
git -c http.version=HTTP/1.1 clone --depth 1 --branch 3.47.8 \
  https://github.com/flutter/flutter.git zotero-toolchain/flutter-sdk

bash /path/to/setup-publication/scripts/bootstrap-local-tests.sh "$PWD"
python3 /path/to/setup-publication/scripts/prepare-harness-assets.py \
  --workspace "$PWD" --output harness-assets-reproduced.json
source zotero-toolchain/env.sh

# Use the genuine Flutter-managed pub command explicitly for the engine too,
# after SDK initialization and before establishing any qualification baseline.
# Do not hand-edit package-config metadata or relax the recorded locks.
(cd zotero-toolchain/harness/quds_office_engine && \
  dart "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" pub get --enforce-lockfile)
(cd zotero-toolchain/crisp-host-harness && \
  dart "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" pub get --enforce-lockfile)
python3 /path/to/setup-publication/scripts/check-reproduction-inputs.py \
  --workspace "$PWD"

git -C quds worktree add --detach --no-checkout "$PWD/quds-validation" \
  b87f9d6c3a2532c9695024adf48ca9fbd3c0927a
git -C quds-validation sparse-checkout set --cone packages tool apps/quds_report_studio
git -C quds-validation checkout --detach b87f9d6c3a2532c9695024adf48ca9fbd3c0927a

git -C crispcloud worktree add --detach --no-checkout "$PWD/crisp-validation" \
  07083d1983db87a9868c3e8ba0cda1efd283b445
git -C crisp-validation sparse-checkout set --cone lib packages test tool
git -C crisp-validation checkout --detach 07083d1983db87a9868c3e8ba0cda1efd283b445

python3 /path/to/setup-publication/scripts/create-isolated-harnesses.py \
  --workspace "$PWD" --output retry-harness-setup-reproduced.json
python3 /path/to/setup-publication/scripts/link-pdf-widget-examples.py \
  --workspace "$PWD" --output pdf-widget-example-links-reproduced.json
```

The unchanged bootstrap completes SDK initialization before resolving the
graphs. The explicit Flutter-managed engine command and read-only preflight
make the metadata requirement concrete: `flutterRoot` and `flutterVersion`
must already identify the verified SDK in all four graphs, every recorded
lock must remain unchanged, the full engine example project must be absent,
and the four host assets must resolve to actual source files. The preflight
fails before isolation if any condition is missing; it does not inject
metadata or silently repair a graph. The isolation helper repeats the
metadata checks, verifies all source inputs and refuses to replace existing
retry wrapper directories. Run qualification only after setup is complete;
do not reconstruct wrappers while a qualification is active. Exact test
commands and active-run journals belong to the separately published runners.

Gzip files are lossless UTF-8 JSON. For example,
`gzip -dc harness-inputs.json.gz` reads the full input archive. All package
artifacts except the inventory itself are indexed by SHA-256 in
`artifact-index.json`; the inventory explicitly excludes itself.

No GitHub Actions, workflow runs, CI status checks or workflow artifacts were
queried, awaited or rerun for this setup.
