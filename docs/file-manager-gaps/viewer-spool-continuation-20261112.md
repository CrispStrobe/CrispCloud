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
