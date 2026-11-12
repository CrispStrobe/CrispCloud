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

## Starting verification

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
