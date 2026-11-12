# Remote viewer preparation lifecycle

Gap: **G14**. Initial status: **Scoped; implementation and validation pending**.
This increment follows the native archive endpoint work recorded in the
[gap register](README.md). Its feature branch is
`feature/viewer-spool-lifecycle-20261112`.

## Problem and deliverable

Large native remote previews already stream into a bounded temporary file.
The existing loop checks cancellation and source availability only when the
next chunk arrives. An idle input stream or a stalled metadata request can
therefore keep preparation alive after the user cancels or the original
account becomes unavailable.

Deliver a bounded preparation lifetime around the existing spool. The same
helper serves the internal viewer, previews, archive browsing and native file
actions. Preserve its 2 GiB default byte limit, one-chunk filesystem
backpressure and caller ownership of a completed spool.

## Implementation contract

- Start an overall deadline before initial metadata inspection and keep it
  active until the completed spool is handed to its caller. The default is
  six hours, allowing a 2 GiB transfer at approximately 100 KiB/s.
- Apply a separate two-minute inactivity deadline. Only nonempty data that
  reaches the temporary file counts as progress; empty events and slow drips
  cannot extend the overall deadline.
- Check requested cancellation and captured-source availability at awaited
  boundaries and on a 50 ms timer while an operation is pending. The first
  stop reason is permanent for that preparation attempt.
- Race metadata and stream waits against the stop condition. Once stopped,
  revoke authority to write or return a spool, initiate input cancellation,
  and observe late completions without adopting their data.
- A backend may fail to acknowledge cancellation. Bound the caller's wait,
  close owned local resources independently, and state this transport boundary
  explicitly instead of claiming the remote socket has stopped.
- Freeze the metadata evidence used for final comparison, including the
  recognized revision aliases. In-place mutation of a provider's metadata
  map must not alter the captured evidence.
- Coalesce simultaneous completed-spool close requests and allow a failed
  cleanup to be retried. Preserve the original preparation failure while
  reporting secondary cleanup problems without credentials or raw responses.
- Provide narrowly scoped clock/timer and temporary-root seams for
  deterministic deadline tests and isolated filesystem fixtures. Keep existing
  callers source-compatible and keep browser disk-spool support unavailable.

## Required evidence

Test stalled initial/final metadata, a stream that never emits, midstream
stalling, repeated empty chunks, whole-deadline exhaustion during a slow
stream, and cancellation or account loss while each wait is pending. Late
metadata, late chunks, rejected or never-completing cancellation acknowledgments
must not return a usable spool or leave an active local writer.

Retain byte-limit, truncation and source-change checks, and add revision-alias
and mutable-map regressions. Exercise real temporary files, successful handoff,
simultaneous close, failed cleanup and cleanup retry. Rerun the existing viewer
streaming and archive browser-session suites because both call this helper.
The final application analysis and JavaScript release build remain separate
integration gates.

## Remaining G14 boundaries

Before/after metadata consistency does not establish an immutable provider
snapshot. Provider-enforced versioned ranges, an asynchronous bounded page
cache, stronger snapshot reporting and large text-comparison design remain
implementation work. The current editable comparison and rich-renderer size
limits continue to apply. This lifecycle increment will not close G14 as a
whole.

No dependency is proposed. Publish this scope before its implementation, then
save the verified code and its observed validation/status on the feature branch.

## Delivered increment and observed gates

The native helper and browser signature are implemented as described in the
[feature specification](../viewer-spool-lifecycle.md). A captured stream bridge
also delivers source errors promptly when the provider's cancellation
acknowledgement hangs. Local file writes preserve backpressure without a
filesystem durability flush for every chunk. Secondary cleanup diagnostics
omit raw provider responses and credentials.

**29 lifecycle checks passed**, using actual native temporary files and an
injected clock. **81 existing checks passed** across six streaming, archive,
viewer-interface and offline-help suites. Total: **110 distinct checks across
seven suites**. Three initial failures were confined to a directory-override
fixture: native temporary-directory creation re-entered that override with its
new child path. The fixture now validates the exact owned child and creates it
in its captured outer zone. The final lifecycle suite passed with unchanged
production code and unchanged cleanup assertions.

Focused analysis of the helper, browser stub and lifecycle test is clean. The
English, German and French guides describe the limits and validate with 23
aligned topics. No dependency was added. G14 remains partially implemented;
the provider/paging/comparison boundaries above remain open.

Remote scope: `57d9cfd46d760bf56d20d8d88cc5abf15fb3e394`.
Remote code: `dfb7978afd5f0ce80f4af7ac924cfa709c01a0aa`.
Branch: `feature/viewer-spool-lifecycle-20261112`.
Review: [draft PR 83](https://github.com/CrispStrobe/CrispCloud/pull/83).

## Integrated validation

The final gates cover the complete continuation through code checkpoint
`dfb7978afd5f0ce80f4af7ac924cfa709c01a0aa`, including external tools,
native archive endpoints and viewer preparation.

| Gate | Observed result |
| --- | --- |
| Full application analysis | Passed in 96.3 seconds with **0 errors, 96 warnings and 1,040 informational findings**, using the repository's nonfatal warning/info gate. This is not a lint-clean report. |
| JavaScript release build | Passed in **209.7 seconds** with `APP_VERSION=1.1.0+12` and `GIT_HASH=dfb7978a`; both values are present in the compiled JavaScript. |
| Packaged offline help | English, German, French and the help manifest match their reviewed source bytes exactly in `build/web/assets`. All three guides have 23 aligned topics and current digests. |
| Scope integrity | All 51 stable gap identifiers are present exactly once across the six lane files; relative links resolve in the 15 audit/scope documents checked. |
| Outgoing naming and whitespace | The continuation's 90 changed files contain no competing product names; `git diff --check` passed. |

Analysis command:

```sh
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
```

Release command:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=APP_VERSION=1.1.0+12 \
  --dart-define=GIT_HASH=dfb7978a
```

This run compiled JavaScript only. WebAssembly and browser-runtime acceptance
remain G51; the optional WebAssembly probe from the preceding continuation
exited 247 and was not repeated here. Installed native tools, signed release
behavior and live-provider interoperability remain G50. Hosted CI completion
is not established by these local gates. The final status/documentation commit
changes no application code or packaged help bytes after this build.
