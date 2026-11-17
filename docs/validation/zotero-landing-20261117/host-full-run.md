# CrispCloud Zotero landing: fresh local qualification

The final host implementation passed all **12 required commands**, comprising
**41 host tests, 39 document-service tests and 28 Python tests**. Two separately
recorded ODT writer-to-actual-host-reader probes also passed, with zero skips.
The post-qualification preservation audit passed for all **2,554 managed files**.

These are fresh results from the exact sources below. They do not reuse the
unpublished final-run claims in the continuation notes. The earlier baseline
28-test run overlaps this final Python cohort and is not added to its total.

## Immutable source and runtime

| Input | Identity |
| --- | --- |
| CrispCloud implementation commit | `96c514eb98f7ba596a385c8f60496bc6c5994307` |
| CrispCloud implementation tree | `571031d5ac03bc32e00051d422020d7e26984e8e` |
| Canonical Quds commit | `837d06edbde08a2465e99cbbb15927ee4c87d8ac` |
| Canonical Quds tree | `c2173f93159150b078c1bae466c30d95a030f35b` |
| Standalone parser commit | `4895712158127b2fc930d796e17035c3ca0dac62` |
| Flutter framework | `3.47.8`, `737ba8f885dc774b53b442759999a312c9461e4e` |
| Flutter engine | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Dart SDK | `3.13.7` |

The host graph contains 107 resolved packages. Every one of its 97 hosted
package versions and archive hashes matches the production `pubspec.lock`.
The remaining nodes are genuine SDK or local-source wrappers. Setup preserved
the recorded lock, succeeded with `--enforce-lockfile`, and repeated successfully
offline. SDK binary hashes remained unchanged. See `setup/receipt.json`, its
raw logs, `harness-preparation.json` and the captured wrapper manifests, locks
and package graphs. The wrappers link actual host source; no production library
or test is replaced with a stub.

## Accepted commands and counts

`qualification/receipt.json` records the complete arguments, working directories,
times, exit codes and SHA-256 hashes of all raw logs. All twelve commands exited
zero in the following required order.

| # | Gate | Result |
| --- | --- | --- |
| 1 | `vendor-source` | All 2,554 managed hashes and 697 Quds source copies match |
| 2 | `vendor-tracked` | Managed source and declarations match the Git index |
| 3 | `host-tests` | 41 passed: Zotero integration, citing transport, ribbon and notices |
| 4 | `service-tests` | 39 passed; zero skips |
| 5 | `host-analysis` | Strict `dart analyze --fatal-infos` passed |
| 6 | `vendor-analysis` | Strict analysis passed across 48 selected changed/relevant Dart files |
| 7 | `host-format` | Formatter reports no changes |
| 8 | `viewer-format` | Delivered viewer source formatting passed |
| 9 | `vendor-format` | Formatter reports no changes |
| 10 | `python-sync-verifier-tests` | 28 passed |
| 11 | `whitespace` | `git diff --check` passed |
| 12 | `vendor-tracked-final` | Final managed source/index guard passed |

The four actual host suites are `office_zotero_test.dart`,
`office_zotero_citing_transport_test.dart`, `office_zotero_ribbon_test.dart`
and `office_proofing_licenses_test.dart`. The service cohort is the complete
`office_document_service_test.dart`. Python executes the existing
`test_sync_office_fidelity` and `test_sync_legacy_doc_parser` modules.

The runner fingerprints **3,779 source files** and **6,002 dependency files**
before and after execution. Both maps remained identical. It also verifies
the harness lock, manifests, package configuration/graph and runtime inputs,
restores the previous analyzer configuration, and rechecks all tracked
qualification inputs, including modes, against the exact implementation commit
at completion. Every integrity condition passed. The exact maps are included. The independent
review in `independent-review/` recomputed terminal counts and log hashes,
checked source Git blobs and modes, dependency inputs, analyzer restoration,
and the twelve inherited mode exceptions; it found no discrepancy.

## Supplemental writer-to-host checks

`supplemental/receipt.json` records a separate two-test run, its immutable
source and fixture identities, the probe's hash, the raw log hash and complete
before/after source and dependency maps. **Two tests passed, zero skipped**:

1. An authored DOCX Zotero fixture is read by the engine, exported through the
   actual ODT writer and read by CrispCloud's actual document service. All six
   expected visible paragraphs survive, hidden citation/bibliography instructions
   remain absent from preview text, and the source fields remain unchanged.
2. Exported ODT retains body spaces, tabs and normalized line breaks through the
   actual host reader, and header/footer preview text is present. The existing
   header/footer preview intentionally normalizes whitespace to one line.

Source, dependencies and the probe stayed unchanged throughout this run.
These fresh probes are in `probes/odt_writer_host_test.dart`; they are not
represented as recovered historical tests or as full viewer/UI acceptance.

## Preservation and the executable-mode correction

`post-qualification-preservation.json` independently checks immutable Git trees,
Git blobs, worktree bytes, executable bits and manifest SHA-256 hashes. It proves:

- 2,554 managed files: 697 canonical files and the unchanged 1,857-file standalone
  parser.
- All 20 previously inventoried host customizations retain their exact baseline
  blobs and modes.
- The standalone parser subtree and source pin remain unchanged.
- All six original Office notices retain their exact blobs and modes.
- Every canonical-managed file matches the selected Quds blob. All 12 current
  canonical/host mode differences are inherited; none was introduced here.

The older report listed eight mode differences within its smaller managed
inventory. Four additional pre-existing differences became covered when files
were added to the managed inventory. All twelve are host `100755` versus canonical
`100644`:

| Path | Earlier inventory |
| --- | --- |
| `packages/quds_office_editor/lib/src/core/input_bridge.dart` | Previously inventoried |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_font_faces.dart` | Previously inventoried |
| `packages/quds_office_editor/lib/src/editor_pdf/pdf_page_thumb.dart` | Previously inventoried |
| `packages/quds_office_editor/lib/src/editor_pdf/render_pdf_canvas.dart` | Previously inventoried |
| `packages/quds_office_editor/lib/src/embed/office_direction_keys.dart` | Previously inventoried |
| `packages/quds_office_engine/lib/src/fonts/font_subsetter.dart` | Previously inventoried |
| `packages/quds_office_engine/lib/src/pdf/pdf_document.dart` | Previously inventoried |
| `packages/quds_office_engine/lib/src/pdf/pdf_font.dart` | Previously inventoried |
| `packages/quds_office_engine/lib/src/extract/office_text_extractor.dart` | Newly covered, pre-existing difference |
| `packages/quds_office_engine/lib/src/fonts/sfnt_parser.dart` | Newly covered, pre-existing difference |
| `packages/quds_office_engine/lib/src/pdf/file/cos/pdf_cos.dart` | Newly covered, pre-existing difference |
| `packages/quds_office_engine/lib/src/pdf/file/interp/pdf_interpreter.dart` | Newly covered, pre-existing difference |

The proof compares baseline host `fae07f9e84036328aee271b5c14cda6b082cfab4` and
its Quds pin `732fc3d0bc7a1118f3eb86e6c762fe70182c4fd2` with the final sources.
For an inherited exception, the baseline host and canonical blobs must be
identical and the host mode must remain unchanged. The complete before/after
records are included. The initial eight-only assumption is retained under
`audit-attempts/` as an **incomplete inventory assumption**, not exhaustive
preservation proof. `audit-provenance.json` records the correction. No source
or file mode was changed to make the audit pass.

## Reproduction

Use Linux with Git, curl, Python 3 and PyYAML. Extract this delivery so that
`host-audit/` is beside the source checkouts. The companion Quds landing evidence
includes the runtime setup package `validation-runtime/`, whose README and
`bootstrap-current.py` supply the genuine official SDK and unchanged Flutter-tool
lock. Obtain that package from the companion
[Quds landing report](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-recovery-20261116/docs/validation/zotero-landing-20261117).
SDK/cache binaries are intentionally omitted from this evidence archive.

From a fresh workspace containing those two extracted evidence directories:

```bash
git clone https://github.com/CrispStrobe/CrispCloud.git crispcloud
git -C crispcloud checkout --detach 96c514eb98f7ba596a385c8f60496bc6c5994307
git clone https://github.com/CrispStrobe/quds_office_suite.git quds
git -C quds checkout --detach 837d06edbde08a2465e99cbbb15927ee4c87d8ac

mkdir -p runtime
git -c http.version=HTTP/1.1 clone --depth 1 --branch 3.47.8 \
  https://github.com/flutter/flutter.git runtime/flutter-sdk
curl --fail --location --http1.1 --retry 3 \
  --output runtime/dart-sdk-linux-x64.zip \
  https://storage.googleapis.com/flutter_infra_release/flutter/cf636b1dfb818dd6a3ff16e390e93b1a036969c8/dart-sdk-linux-x64.zip
python3 validation-runtime/bootstrap-current.py --runtime runtime

export FLUTTER_ROOT="$PWD/runtime/flutter-sdk"
export PUB_CACHE="$PWD/runtime/pub-cache"
export TMPDIR="$PWD/runtime/tmp"
export XDG_CONFIG_HOME="$PWD/runtime/config"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true
export PYTHONDONTWRITEBYTECODE=1
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
  "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" precache \
  --linux --no-android --no-ios --no-web --no-windows --no-macos

# Preserve the delivered evidence and put replay outputs in a separate copy.
cp -a host-audit host-repro
python3 host-repro/prepare-host-harness.py \
  --repo "$PWD/crispcloud" --harness "$PWD/host-repro/reproduced-harness"
ln -s "$PWD/host-repro/probes" host-repro/reproduced-harness/probes
python3 host-repro/resolve-host-harness.py \
  --repo "$PWD/crispcloud" --harness "$PWD/host-repro/reproduced-harness" \
  --flutter "$FLUTTER_ROOT" --pub-cache "$PUB_CACHE" \
  --output "$PWD/host-repro/reproduced-setup"
export TMPDIR="$PWD/host-repro/reproduced-setup/tmp"
export XDG_CONFIG_HOME="$PWD/host-repro/reproduced-setup/config"

python3 host-repro/run-host-qualification.py \
  --repo "$PWD/crispcloud" --harness "$PWD/host-repro/reproduced-harness" \
  --quds-source "$PWD/quds" \
  --quds-commit 837d06edbde08a2465e99cbbb15927ee4c87d8ac \
  --source-commit 96c514eb98f7ba596a385c8f60496bc6c5994307 \
  --output "$PWD/host-repro/reproduced-qualification" \
  --setup-receipt "$PWD/host-repro/reproduced-setup/receipt.json"
python3 host-repro/run-supplemental.py \
  --repo "$PWD/crispcloud" --source 96c514eb98f7ba596a385c8f60496bc6c5994307 \
  --harness "$PWD/host-repro/reproduced-harness" \
  --output "$PWD/host-repro/reproduced-supplemental"
python3 host-repro/audit-preservation.py \
  --host "$PWD/crispcloud" --canonical "$PWD/quds" \
  --host-ref 96c514eb98f7ba596a385c8f60496bc6c5994307 \
  --output "$PWD/host-repro/reproduced-preservation.json"
```

The preparation helper reads the included, hash-checked
`prior-setup/continuation-setup/harness-inputs-current.json.gz`, rebases only the
wrapper paths, and links real source files. Its lock-enforced resolver refuses
silent dependency updates. Run the main qualification and supplemental probes
sequentially, using fresh output directories; keep both source checkouts frozen.
Historical paths in recorded graphs identify the executed run. Newly resolved
graphs must use the new workspace and must not be copied blindly into a replay.

## Scope

This is focused local qualification of the actual engine/editor dependencies,
host Zotero widgets and transport, document service, licenses and sync guards.
It does not claim a full application build, complete viewer compilation, the
actual export-dialog workflow, native/Wasm Harper acceptance, live Zotero
accounts/desktop acceptance, or Word/LibreOffice interoperability. Viewer source
identity and formatting are checked; the minimal service graph deliberately
does not compile its larger dependency closure. Network/protocol/credential
interactions in the host tests use the existing test doubles.

No GitHub Actions, workflow, check-run or CI-status endpoints were queried or
awaited. Source checkpoints were saved remotely before qualification. Subsequent
documentation commits and merges retain the implementation identities above;
merge status belongs to the separate landing record, not this test receipt.

## Published evidence and incoming inventory

The complete execution package is [host-evidence.tar.xz](host-evidence.tar.xz).
[artifact-index.json](artifact-index.json) binds every member and verifies a
complete read-back after compression. Extract with `tar -xJf host-evidence.tar.xz`
to recover the `host-audit/` paths named above.

The [required-run receipt](qualification-receipt.json),
[supplemental receipt](supplemental-receipt.json),
[preservation proof](preservation.json) and
[independent terminal review](independent-review.json) are also available directly.

The [frozen incoming audit](incoming-audit.json) accounts for all 290 captured
host branch/PR refs: 214 ancestors and 76 exact whole-tree aliases to integrated
ancestors, with zero outstanding. The captured main
`71a2aafd1cf0383fa505d0e8c1307244433e7ffe` is included by ancestry, together with
the existing ODT and ODP export features. The guarded final sync brings in the
six-production-file German grammar/spreadsheet amendment and four test files,
while retaining the recovered Zotero implementation and protected ODT output.

Review and landing are tracked in [CrispCloud PR #201](https://github.com/CrispStrobe/CrispCloud/pull/201)
and [Quds PR #85](https://github.com/CrispStrobe/quds_office_suite/pull/85).
