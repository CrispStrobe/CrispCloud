# Selected document-engine validation receipts

Source tested by the passing browser job:
`540483491f4a02aad3672abe438ad4aad3696e21`.
Upstream File Viewer source:
`d264009ca6efb3daed79a39d1ae63133e0f25558` (3.3.3).

## Browser and native engines

[Workflow 43383695021](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383695021),
runtime job `131747097222`, passed with Node 24.22.2 and Chrome Headless Shell
149.0.7827.55 (Playwright Chromium build 1228). The preserved
[browser-ci.log](browser-ci.log) is a relevant-step excerpt from the successful
job, not a substitute for the linked full job log.

It records 61 Node/native-WASM contracts, 6 PS/EPS browser cases, 9 XML browser
cases, XLS/PPT and WPD/CHM browser suites, and packaged-host checks for all six
engines. All numbered suites have zero failures and zero skips.

The first run, 43383440269, failed before browser execution because the test
helper imported Playwright's CommonJS wrapper as named exports. The fix and its
non-launch regression were committed before the passing run. No production
renderer repair was needed for that failure.

The passing artifact is
[14017368714](https://github.com/CrispStrobe/CrispCloud/actions/runs/43383695021/artifacts/14017368714),
19,135,400 bytes. ZIP SHA-256:
`8271f5fc4a34627ad063ff7f933a8a729a29d646491d1f0877faeb068d221313`.
Generated files carry their own content hashes in the package runtime manifest.
The same artifact includes exact WordPerfect MPL source archives and original
shim/build materials for the source distribution.

## Genuine application checks

All local Flutter commands use the actual CrispCloud graph, Flutter 3.47.8 /
Dart 3.13.7 and normal native hooks. No test-only replacement graph or disabled
native build hook was used.

| Receipt | Result and scope |
| --- | --- |
| [app-tests.log](app-tests.log) | All 69 tests passed in one final invocation: document source/routing, F3 integration/review, existing internal-viewer widgets and MBOX widgets. |
| [analyze.log](analyze.log) | Focused final analyzer over 12 paths: no issues. |
| [host-tests.log](host-tests.log) | All 15 package host tests passed: real HTTP server/policy plus controlled Linux channel/widget lifecycle and input. |
| [host-analyze.log](host-analyze.log) | Host/package analysis: no issues. |
| [web-release-build.log](web-release-build.log) | `flutter build web --no-pub --release` succeeded. The optional Flutter-WASM dry run emitted exit 247; the successful build is the JavaScript web target. |
| [mbox-email-tests.log](mbox-email-tests.log) | Earlier dedicated MBOX plus existing EML/MSG parser/widget suite: 69 passed, zero skips. Some cases overlap the final app run; totals are not summed. |
| [mbox-analyze.log](mbox-analyze.log) | Earlier focused MBOX analysis: no issues. |

The final combined app test paths are:

```sh
flutter test --no-pub --reporter expanded --concurrency=2 \
  test/document_preview_source_test.dart \
  test/document_preview_routing_test.dart \
  test/widget/document_preview_integration_test.dart \
  test/widget/document_preview_review_test.dart \
  test/widget/internal_viewer_widget_test.dart \
  test/widget/mbox_message_view_test.dart
```

The host command runs the three files under
`packages/file_viewer_documents/test/` through the resolved application graph.
The browser workflow contains the exact npm/build/test commands and fixed source
pin; `RUNTIME_MANIFEST.json` records the realized dependency and artifact inputs.

## Platform limits

Local Chromium launch was unavailable because the workspace denied its socket
operation. Real browser execution therefore ran in GitHub CI, without substituting
a DOM shim. The local environment also lacks GTK/WebKit/epoxy development headers
and CMake. A dedicated CI job compiles a genuine minimal Linux consumer and rejects
the unavailable-host stub; it does not launch or claim desktop rendering.

Native WebKit/WebView rendering on all supported OS/device combinations and full
release qualification are not implied by these focused checks. The existing
Office evidence and Apple export-review gates remain intact.
