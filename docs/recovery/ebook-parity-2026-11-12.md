# Ebook platform and reader parity expansion — 12 November 2026

## Resumed from the interrupted session

The next recovery started from remote checkpoint
`67ee2afbe06ab857e6ea654ab8aa2b5c9f1fc2d0`, after the pasted conversation's
last visible `7a0f3a0` checkpoint. The shared reader, library and reading-data
integration therefore did not need reconstruction. The existing feature
branch was at `1d081588f4d2a86c7422c967e3d4b6134ffbf0c9`.

The main ebook workflow at `1d08158` completed all five jobs successfully.
The later Linux diagnostic run `43227210073` still failed the enhanced host:
WebKit's D-Bus proxy could not launch, and the independent Bubblewrap check
reported that the runner denied network-namespace loopback setup. Portable
compilation and launch passed. A successful dynamic-library lookup is not a
successful browser startup.

Continuation work isolates the browser readiness check in a bounded child
process so a failed runtime prerequisite cannot terminate the main app,
retains the required real rendering/input gate, reviews the shared workflows,
and reconciles the feature branch with current `main`. No browser sandbox or
runner security policy is relaxed. Every coherent increment is committed and
pushed to `feature/ebook-reader-editor`; final qualification is recorded below
only after its checks complete.

## Goal and starting point

Continue from `88936891af019001bc8da1c3ed3273749ad7238b` on
`feature/ebook-reader-editor`, draft PR #53. The user requests an explanation
of the Linux difference, a path to the same experience across platforms, and
a much broader extension toward FBReader feature parity. Continue saving
coherent remote checkpoints. Do not replace the package-preserving EPUB editor
or remove the portable/legacy recovery readers.

The existing stable `flutter_inappwebview` 6.1.5 host covers Android, iOS,
macOS, Windows and web. Its absence on Linux caused the separate chapter
renderer. Foliate itself is not the Linux limitation. Shared features require
the same engine, bridge, location semantics and application UI, plus a native
Linux host that actually renders and passes lifecycle/input tests.

## Current work streams

1. **Linux host:** investigate and prove inline composition of the existing
   Foliate assets, without a separate browser window. Audit runtime detection,
   navigation policy, content isolation, input, focus, resizing and disposal.
   Compare distro-supported WebKitGTK with a narrowly pinned WPE texture host;
   account explicitly for dependency availability and packaging. A constant
   reporting Linux support is not proof of an installed, working renderer.
2. **Shared reading controls:** percentage seeking, real back/forward navigation
   history, responsive column/margin/page-width settings and publisher-style
   controls. Fixed-layout books expose only meaningful controls. Preserve
   publication DOM and CFI nodes while applying reader styles.
3. **Portable reading data:** bounded, versioned JSON transfer of bookmarks,
   highlights, notes, appearance and current progress. Require exact content
   hash/length and compatible renderer; preview conflicts and apply atomically.
   Do not export source paths or account references in a portable sidecar.
4. **Library:** persistent book metadata, favorites, shelves/tags, reading state,
   recent/progress information and source-aware reopening. Resolve the recorded
   original storage reference; an account label is not permission to reopen a
   different source. Attachment-only entries must remain visibly non-reopenable.
5. **Application integration:** accessible shared controls, library entry points,
   reading-data import/export, localized labels and regression tests. Retain
   existing saves, invalid drafts, original input and fallback behavior.

## Comparison baseline

FBReader's product pages differ by platform and release. Its desktop news
identifies 2.1.5 as stable and 2.5 RC 1 as a release candidate on 29 October
2026. The latter adds shelves/batch actions, OPDS 2.0, system speech, EPUB media,
CBR/CB7 and experimental bookmark transfer. Android Premium includes speech
and network translation; the iOS page lists a different format/catalogue set.
Do not describe all of those as one identical, released FBReader feature set.

Primary references checked for this work:

- <https://inappwebview.dev/docs/webview/in-app-webview/>
- <https://inappwebview.dev/docs/intro/>
- <https://fbreader.org/en/linux>
- <https://fbreader.org/news>
- <https://fbreader.org/android>
- <https://fbreader.org/faq/paid-versions>
- <https://fbreader.org/en/ios>
- <https://books.fbreader.org/faq.html>
- <https://wpewebkit.org/developers/>
- <https://wpewebkit.org/about/get-wpe.html>

Remaining product areas to assess explicitly include automatic cross-device
sync/conflict recovery, OPDS acquisition/authentication, text-to-speech,
dictionaries/translation, licensed Readium LCP support, EPUB media overlays,
comics/legacy formats, custom fonts, accessibility, mobile gestures and device
validation. Source editing and native Kindle conversion already go beyond a
reading-only comparison; they do not substitute for these reading features.

## Starting verification (historical; updated results below)

Hosted run `43212170145` has now passed the application integration/web build
and macOS native job. Windows is running, and the Linux/core jobs are queued
at the initial check in this turn. Preserve those actual results and update
them when further evidence arrives. Local Chromium was previously prevented
from starting by the environment's Unix-socket restriction; an unavailable
runtime must not be recorded as a browser pass.

The new Linux path needs its own compile and actual runtime gate. Existing
EPUBCheck, package preservation, conversion, actual-worker and application
workflow checks remain active. A beta dependency must be pinned and reviewed;
do not upgrade unrelated platform implementations silently.

## Implemented extension and remote checkpoints

| Remote revision | Saved work |
| --- | --- |
| `61582b7706f358166ae6b4e4908cae4bec426874` | Scope and recovery plan on `checkpoint/ebook-parity-2026-11-12`. |
| `7a0f3a01165b6c1ce8957a8616d4163fe5c88068` | Bounded reading-data schema/import plans, local library model, appearance model and focused tests. |
| `2b31742f7f63ef23c9cee0cb56783f36e202e59a` | Shared navigation/layout controls, lifecycle guard, integrated library/import/export UI, recovery flows, localization and parity analysis. |
| `506167333440c34290e8f9acee6da4275b5f6bb7` | Optional native Linux host, bounded surface pool and real hosted rendering/input/runtime-absence gates. |
| `1d081588f4d2a86c7422c967e3d4b6134ffbf0c9` | Browser compatibility fallback, Linux packaging/registration, reviewed technical source bindings and native diagnostic gates; saved on the existing feature branch and draft PR. |

The implemented product scope is described in [the user guide](../ebooks.md)
and [the detailed FBReader comparison](../ebook-feature-parity.md). The Linux
host uses WebKitGTK 4.1, not the evaluated WPE beta. Its stable runtime probe
does not change the conservative static capability constant. Missing build or
runtime support keeps the portable EPUB reader usable.

The shared reader adds percentage seeking, session Back/Forward history,
publisher typography, responsive columns/margins/width, capability-aware
fixed-layout controls and selection copying. The local library adds recent
books, progress, favorites, shelves/tags/status, filtering/sorting and exact
source reopening. JSON transfer previews conflicts, binds the exact book and
renderer, persists atomically, rejects stale in-process state, and offers a
rescue export even when local preference writes fail. Closing after a failed
sidecar save requires an explicit recovery/discard choice.

Review also found and fixed two concrete portability defects: a paginator
render call before its iframe body exists, and the EPUB parser's unconditional
use of Object/Map grouping APIs. Both corrections live outside the pinned
vendor tree. The grouping layer preserves native implementations and is tested
with both APIs deliberately absent. This is not support for arbitrary old
WebViews; the remaining runtime feature requirements still apply.

## Verification of the expansion

- **154 application/service/widget tests passed**, including existing save and
  source-account guards, library queries/draft retry, sidecar validation and
  stale instances, import preview/application, rescue export after failed save,
  replacement without progress, Linux host selection and portable recovery.
- **8 reader controller/model tests passed**. Node checks exercise actual pinned
  Foliate history, deferred navigation completion, ordered commands, bounds,
  fixed-layout capabilities and the forced missing-body lifecycle case.
- Normal parser and forced **missing grouping + raw-DEFLATE fallback** variants
  passed with actual EPUB/FB2/CBZ parsing, normalized export and existing
  Unicode/resource/TOC/security assertions. Vendor integrity is unchanged.
- **Full web release build passed in 182.5 seconds.** The bundled `reader.js`,
  `reader_controls.js` and `reader_compat.js` match their source bytes. Local
  Chromium still cannot start in this environment because socket creation is
  denied; actual-browser confirmation is a hosted gate.
- Native surface arithmetic passed **600 boundary combinations**, including
  high-DPI inputs that previously could round above the 16-megapixel cap.
- The engineering inventory retains all 177 prior paths and adds 30, for
  **207 reviewed paths**. Existing release-evidence tests completed 41 cases
  with two existing platform skips; all 37 Apple preflight tests passed. The
  source evidence check passed. All non-digest distribution/policy fields and
  validator rules remain unchanged.

Earlier hosted run [43212170145](https://github.com/CrispStrobe/CrispCloud/actions/runs/43212170145)
at `8893689` completed app/web, macOS, Windows and EPUBCheck successfully. Its
Ubuntu native conversion, Wasm and import-chain checks also passed, but the
actual reader-browser step exposed the iframe-body lifecycle error addressed
above. It must be rerun on the updated reader source.

### First native-host run: real compile succeeded, runtime unresolved

Run [43222486521](https://github.com/CrispStrobe/CrispCloud/actions/runs/43222486521)
at `5061673` produced these results:

| Job | Observed result |
| --- | --- |
| Portable-only Linux host | Passed real compilation, application launch, package analysis/tests and the no-hard-browser-dependency check. |
| Enhanced WebKitGTK host | Passed package analysis/tests and compiled the real enabled plugin. The application process then exited before completing the rendering/input test (Flutter exit 79), without an assertion or useful native stack. This is a failed runtime gate. |

The diagnostic run
[43225371822](https://github.com/CrispStrobe/CrispCloud/actions/runs/43225371822)
at `1d08158` again passed the portable-only job. Its enhanced job compiled and
completed native view creation, offscreen display setup and the first Flutter
GL upload. It then terminated with a GLib fatal log inside WebKit while
`webkit_web_view_load_uri` was starting the page process. This narrows the
failure; it does not demonstrate publication rendering or an enhanced-reader
pass. The installed system runtime was WebKitGTK 2.52.6.

Opt-in diagnostics record fixed lifecycle labels and, in the follow-up
revision, fixed classifications of upstream process-launch failures. They do
not record the native message's path/argument suffixes. CI extracts function-only
backtraces without arguments, locals or environment values; raw core dumps are
deleted and never uploaded. A bubblewrap namespace probe reports runner
availability without changing host policy or skipping the reader test. No
browser sandbox setting or test acceptance rule is relaxed. Actual texture
pixels, Flutter overlay composition, selection/copy, navigation, multiple
instances, hostile-resource isolation and runtime-removal launch must still pass.

The main ebook workflow at `1d08158` is
[43225371743](https://github.com/CrispStrobe/CrispCloud/actions/runs/43225371743).
Its direct run/job endpoints confirm that it registered, even though generic
branch-run listings omitted it. At the diagnostic checkpoint, EPUBCheck and
macOS had passed; application/web, Windows and the Ubuntu browser gate were
still running or queued. Keep the Linux diagnostic work on the checkpoint
branch while these jobs finish, so another feature-branch push does not cancel
the actual-browser gate.

Shipping Linux build jobs now install the optional development headers, the
application's generated registrants include the new plugin, and the Debian
package recommends the complete system runtime. AppImage/tar builds use the
system runtime as documented in [Linux packaging](../../linux/README.md).
Linux publication accessibility semantics, in-book Tab traversal, Wayland,
hardware touch, graphics-driver coverage and performance remain explicit gaps.

## Remaining product parity

Automatic cloud reading-state synchronization, OPDS catalogues/authentication,
speech, dictionaries/translation, licensed LCP, EPUB media overlays/playback,
CBR/CB7 and broader legacy formats, richer library metadata/covers/bulk actions,
custom fonts, persistent navigation stacks and robust annotation re-anchoring
remain distinct increments. The FBReader comparison differentiates stable
desktop 2.1.5 from 2.5 RC 1, Android editions and iOS rather than claiming that
one product feature list is universal across platforms.

## Continuation checkpoints after `67ee2af`

- `280f55167f43f227068d8a462a88aabc18e56afb`: recovered the newer remote checkpoint and saved the continuation plan on the feature branch.
- `5e0b6f94c542a41db232eb62ec19d21a9ddacffb`: merged current main (`977b5037`), preserving both source inventories and reviewing the combined startup changes.

The next shared-reader increment fixes explicit reading-data discard being retried on disposal, concurrent section-load resource leaks, and canceled searches leaving stale overlays. It also blocks late events from replaced reader views and reports search result chapter indices from their CFIs. Focused Dart analysis, both parser compatibility modes and vendor checks passed. The committed browser and one-shot storage-write regressions still require their runtime gates before final qualification. The Linux startup-helper work remains a separate increment.

### Linux readiness guard implementation checkpoint

Shared-reader corrections are saved at `ae0ef0bd32c786400bb28aa6f24794948e6ae1f7`. The native continuation now implements the previously unfinished startup guard. It runs a fixed script/painting probe in a separate bundled executable before creating a real view, returns portable availability on failure and cleans child processes on all outcomes. Seven real subprocess scenarios passed; actual-header helper compilation also passed. Full native packaging/rendering still requires the new hosted run.

The Linux workflow has three explicitly different jobs: required complete enhanced rendering on Ubuntu 22.04; safe recovery from the observed blocked sandbox startup on Ubuntu 24.04; and the portable-only build. The official Jammy WebKitGTK 4.1 package is 2.50.4, above the retained 2.48.4 minimum (https://packages.ubuntu.com/jammy-updates/libwebkit2gtk-4.1-dev). Neither runner security policy nor the browser sandbox is relaxed. A recovery pass is not an enhanced-rendering pass.

### Integrated main synchronization

The startup guard is saved at `e2231a963ae3e5bad6e5164a38bd8006f53b8619`; `04429947003f44d9066906b340195526df8efd36` corrects the new test to use its intended Linux platform. All 22 editor-dialog tests, all 8 reader-package tests, focused/package analysis, seven actual native startup scenarios and complete enhanced-plugin/helper real-header syntax compilation passed before the next integration. The complete earlier application selection passed its 154 existing cases; the new test initially used Flutter's Android default and then passed after the platform fixture correction.

Concurrent repository integration advanced main to `02be67fe`, including absent-platform-plugin recovery and macOS browser dependency fixes. The feature branch now retains those changes plus the full startup guard and shared-reader corrections. Three documentation conflicts were reconciled, retaining all inventoried paths and unchanged distribution decisions. The merged application and web build are being revalidated. Intermediate queued CI runs canceled by later checkpoints are not counted as passes.


## Integration of parallel readiness candidates

The integration retains the newer production isolated-startup path from `e2231a96` and its runtime/helper tests. The alternative readiness candidate in `0ba63f3f` and `13667db4` is superseded for the active build; its original code and evidence remain in Git history and its recent remote branches. The two helper protocols and their CMake targets must not be mixed. This resolution does not extend Linux renderer certification beyond the documented runtime and platform limits.

## Verified continuation outcome

The integrated source checkpoint is
`b89dbdad868cffa2cb93aa5d700270532e0136d7`. The following final documentation
update changes no production source, dependency lock, test or workflow. Local
and remote commit trees were checked for exact equality at every publication.
The existing draft PR #53 was conflict-free against `main` at `02be67fe` when
this record was written.

| Check | Observed result |
| --- | --- |
| Merged app/service/widget selection | **157 passed** in 55 seconds, including explicit discard, failed-save recovery, library/account binding, reading-data imports and existing file-save guards. Native converter build hooks stayed enabled. |
| Editor-dialog regression file | **22 passed**, including the corrected explicit Linux test variant. The earlier test-setup failure happened before its behavioral assertions and was repaired, not excluded. |
| Reader Flutter package | **8 passed**; package analysis clean. |
| Focused app analysis and formatting | No issues; all four changed Dart files passed formatting with no changes. |
| Shared reader parser/lifecycle checks | Default and forced missing-grouping/raw-DEFLATE variants passed; suspended-search and section-resource lifecycle regressions passed. |
| Vendor integrity | The 16 pinned JavaScript files and five notices match their recorded source; vendor code is unchanged. |
| Native startup guard | **7 actual subprocess scenarios passed**, including concurrent probes, expiry/invalidation, missing/crashed helpers, deadlines, disposal and residual-child cleanup after normal or abnormal exit. |
| Native compilation | Helper and complete enhanced plugin pass C++17 syntax compilation with warnings treated as errors against actual Flutter 3.47.8, GTK 3.24.49, WebKitGTK 2.52.6 and epoxy headers. This does not establish a linked or rendered Linux app. |
| Actual application web release | **Passed**, 218.5 seconds, with `flutter build web --release --no-pub --no-wasm-dry-run`. |
| Bundled assets | Five reader assets and the metadata Wasm/runtime/worker are byte-identical to source; all three metadata digests also match `WASM.json`. |
| Source evidence | All **292** inventoried paths and the combined lockfile pass the unchanged source-binding validator. |
| Existing evidence/preflight suites | **42 tests** with two existing skips, plus **38 preflight tests**, passed. These checks do not constitute distribution approval. |

The local Chromium attempt used the installed browser and a fresh temporary
profile. It failed before reader code ran because `socket()` was denied by the
execution environment. No browser or runner isolation setting was relaxed.

At the final source check, the main ebook PR workflow
[43234364793](https://github.com/CrispStrobe/CrispCloud/actions/runs/43234364793)
had all five jobs queued, and native workflow
[43234364973](https://github.com/CrispStrobe/CrispCloud/actions/runs/43234364973)
had all three matrix jobs queued. Later documentation pushes may supersede
those runs; use the exact current head's registered workflow for final hosted
acceptance. **No new hosted rendering, native-runtime or EPUBCheck pass is
claimed for this continuation.** The earlier `1d08158` main-workflow results
remain historical evidence for that revision.

Keep PR #53 in draft until the enhanced Linux publication test, blocked-startup
recovery, portable-only launch and main ebook workflow complete successfully.
The implemented guard makes failed startup a handled capability decision;
full Linux rendering, target-device behavior, accessibility, automatic reading
state synchronization, OPDS, speech, dictionaries/translation and licensed DRM
remain subject to their documented gates or further product work.

### Remote checkpoints from this continuation

| Revision | Saved work |
| --- | --- |
| `280f55167f43f227068d8a462a88aabc18e56afb` | Recovery of the latest interrupted-session checkpoint and continuation plan. |
| `5e0b6f94c542a41db232eb62ec19d21a9ddacffb` | Initial main synchronization and retained source inventories. |
| `ae0ef0bd32c786400bb28aa6f24794948e6ae1f7` | Explicit-discard protection, section-resource lifecycle and canceled-search fixes. |
| `e2231a963ae3e5bad6e5164a38bd8006f53b8619` | Isolated Linux readiness helper, owned-process cleanup and distinct hosted gates. |
| `04429947003f44d9066906b340195526df8efd36` | Corrected the portable-reader regression's Linux test platform. |
| `b89dbdad868cffa2cb93aa5d700270532e0136d7` | Integrated current main, including ebook platform recovery and macOS dependencies; all merged local checks above target this source. |
