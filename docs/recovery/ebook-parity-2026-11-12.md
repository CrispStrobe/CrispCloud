# Ebook platform and reader parity expansion — 12 November 2026

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
| `67ee2afbe06ab857e6ea654ab8aa2b5c9f1fc2d0` | Bounded native launch diagnostics, unchanged-policy sandbox probe and precise anchor/history/library limits on the checkpoint branch. |

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
Its direct run/job endpoints confirmed that it registered, even though generic
branch-run listings omitted it. **All five jobs passed**: EPUBCheck,
application tests/web release build, and the Ubuntu/macOS/Windows native
conversion jobs. The Ubuntu job also passed actual Chromium rendering and
interaction for EPUB/FB2/CBZ and all five Kindle fixtures. This exercised the
new progress/history, publisher styles, CFI-preserving appearance, fixed-layout
capabilities, highlights and script isolation, with no terminal page error.
The earlier iframe-body lifecycle failure is therefore verified fixed on that
browser. The production metadata adapter passed 24 assertions in actual
Chromium, as well as 24 assertions across 11 real Node workers with none leaked.
These browser results do not establish native WebKitGTK rendering.

The next Linux diagnostic run,
[43227210073](https://github.com/CrispStrobe/CrispCloud/actions/runs/43227210073)
at `67ee2af`, identified WebKit's fatal startup classification as
`Failed to fully launch dbus-proxy`. The unchanged-policy bubblewrap probe also
failed with `loopback: Failed RTM_NEWADDR: Operation not permitted`. These
establish unmet sandbox startup prerequisites on this runner; the network
probe alone does not establish the proxy's exact failure. The portable-only
application launch passed again. No runner policy or browser isolation was
changed. A safe product availability check must contain this kind of native
startup failure in a bounded child process before selecting the enhanced host;
library/version presence alone is insufficient.

### Startup guard implementation

The follow-up implementation uses a source-built helper beside the plugin.
Its worker creates the same ephemeral, sandboxed WebKit context and offscreen
view, serves only a fixed loopback readiness page, and requires the exact
JavaScript proof. A supervisor contains fatal worker exits and cleans up the
process tree. The asynchronous parent bounds output and time, requires a clean
helper exit and exact proof, and coalesces concurrent requests. Both public
probe and direct create paths use that result before creating an in-process
WebView. The result is cached for the running app; later per-view failures
remain possible. No book or account data is passed to the helper.

The helper is installed after Flutter's bundle cleanup with executable
permissions. It uses the complete system WebKit runtime without a hard WebKit
library dependency. Its own core dumps are disabled. Native and Dart timeouts
leave room for orderly cleanup before an unavailable result is returned.

The next native workflow distinguishes three acceptance targets: actual
enhanced rendering/input on an unchanged Ubuntu 22.04 runner; safe reporting of
the observed installed-but-unusable runtime on Ubuntu 24.04; and a portable-only
Ubuntu 24.04 build. The enhanced target still requires real pixels and input and
does not accept fallback as success. Results must be recorded after the run;
implementation and compile checks alone do not establish a rendering pass.

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
