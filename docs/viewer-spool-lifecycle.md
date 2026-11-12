# Viewer temporary-copy lifecycle

The native viewer can prepare a remote file as a temporary local copy before
opening its text, hex, media or archive view. This increment makes that
preparation respond to cancellation and stalled sources while keeping the
existing byte limit and callers.

The implementation is in `lib/services/viewer_spool_io.dart`. The browser stub
accepts the same arguments and continues to report that temporary disk viewing
is unavailable. No dependency was added.

## Limits and progress

| Rule | Default behavior |
| --- | --- |
| Temporary-copy size | 2 GiB; a caller may choose its existing smaller limit |
| Overall preparation deadline | Six hours from the start of guarded preparation |
| Inactivity deadline | Two minutes without a successfully written nonempty chunk |
| Cancellation/source checks while waiting | Every 50 milliseconds, while the event loop can run |
| Input buffering | Backpressure follows each awaited local file write |
| Success | Complete input, matching reported length when available, final metadata checks, and a closed local writer |

The six-hour deadline allows a large copy over a slow connection without letting
an endless trickle keep preparation alive indefinitely. The separate inactivity
deadline covers the initial metadata request, waiting for input, and the final
metadata request. Empty chunks and metadata responses do not reset it.
Successfully written file bytes reset inactivity; they do not extend the
overall deadline.

Each input chunk is written before another is requested. The temporary copy
does not require a filesystem durability flush for every chunk; one final
flush precedes closing the writer and handing the path to its owner. Progress
means successfully written bytes, not a promise that a temporary copy will
survive power loss.

Existing callers keep their current limits. The helper does not increase the
viewer’s rich-document budget, the media-preview budget, archive member/edit
budgets or the text-merge limit.

## Cancellation and deadlines

Both metadata futures and pending source-stream reads are guarded. When the
existing cancellation predicate becomes true, the original source becomes
unavailable, or a deadline expires, the helper latches that stop condition.
Changing the predicate or reconnecting afterward does not revive the same
preparation.

A stopped preparation:

1. Revokes permission to accept another chunk or return a completed spool.
2. Requests cancellation of its owned input subscription.
3. Observes late completion/errors without waiting indefinitely for the
   provider’s cancellation acknowledgement.
4. Closes its owned local file handle and removes its incomplete child
   directory.

A late metadata response cannot create or return a spool after cancellation.
A late stream event cannot start another file write. An already-issued native
file write is allowed to finish before its handle is closed and the partial
file is removed.

The stream bridge preserves pause/resume backpressure and delivers a source
error without placing it behind the source’s cancellation acknowledgement.
Requesting cancellation is not proof that a provider’s socket has already
closed. Provider APIs that offer no physical-stop acknowledgement retain that
boundary.

Native filesystem calls cannot be interrupted by this helper. Their outstanding
operations and cleanup are awaited so a file handle is not abandoned while
still in use. Deadline detection also depends on the application event loop
being able to run. These limits bound stalled remote waits; they are not an
operating-system preemption guarantee.

## Source and version checks

The original backend and source-account guard remain captured by the caller.
Preparation never obtains another account from the current pane.

After the first successful metadata request, the helper creates a separate
`FileItem` with a copied, unmodifiable metadata map before constructing or
subscribing to the source read. Its revision fields must be immutable scalar
values. This prevents a provider-owned metadata map from changing the read’s
expected version or the comparison baseline in place.

The final check compares file identity, storage scope, type, reported length,
modification time, and each available revision alias:

- `etag`, `eTag`
- `version`, `versionId`
- `revision`, `rev`
- `cTag`

The helper also verifies that the number of received bytes matches a reported
length. An unknown length remains subject to the byte cap.

These checks establish consistency of the metadata the provider exposes.
They do **not** create an immutable remote snapshot. A provider without an
enforced revision can change content while retaining all reported metadata.
This increment adds no provider range API, conditional-read guarantee or
mixed-version paging claim.

## Cleanup and ownership

Every preparation creates a new `crisp-viewer-` child directory. It never
owns or deletes the parent directory. A successful `ViewerSpool` retains the
copy until its existing owner calls `close()`.

Concurrent `close()` calls share the same pending deletion. Successful close
is idempotent. If deletion fails, another call can retry cleanup of that same
owned directory.

A failure during preparation preserves its primary error. Secondary stream
cancellation or local cleanup failures are recorded separately. Those
diagnostics omit raw provider errors, response bodies and credentials. A failed
partial-directory removal records the owned local directory location so the
remaining temporary data can be identified for cleanup. The helper does not
report that removal succeeded when the filesystem refused it.

This remains an ephemeral viewing facility. It does not introduce retained
editing sessions or restart recovery.

## Caller boundary

The following existing routes use the helper:

| Caller | Covered step |
| --- | --- |
| Internal viewer | Preparing a large or unknown-size native remote file |
| Media preview | Preparing its bounded native remote media copy |
| Archive browser | Spooling the captured container to a native temporary file |
| Sharing action | Preparing the remote file passed to the sharing workflow |

The new deadline belongs to `createViewerSpool` only. Metadata requests,
renderer initialization, archive decoding and sharing operations performed by
a caller before or after that helper retain their own lifecycle. In particular,
`ArchiveBrowserSession.open` performs metadata checks outside the helper;
this increment does not claim a deadline for the complete archive-open flow.

No host action, renderer or source-capture code changes are needed.

## Validation

`test/viewer_spool_lifecycle_test.dart` uses actual native temporary files
with an injected monotonic clock and timer factory. It covers:

- cancellation and inactivity during the initial/final metadata request;
- late metadata successes/errors after cancellation;
- stalled streams before the first chunk and after a written prefix;
- continuing small writes that hit the overall deadline;
- empty chunks that do not count as progress;
- an unacknowledged or failing source cancellation;
- preservation of a source error while cleanup acknowledgement is pending;
- captured-account loss and a subsequent apparent reconnect;
- each revision alias, including in-place mutation of provider metadata;
- overflow, truncated input, unknown length and an empty file;
- partial-directory cleanup failure and sanitized secondary diagnostics;
- concurrent close calls and retry after failed deletion;
- backpressure and successful explicit cleanup.

The focused integration gate also includes the existing streaming-viewer,
archive-browser session and internal-viewer widget suites:

```sh
../run_flutter.sh test \
  test/viewer_spool_lifecycle_test.dart \
  test/viewer_streaming_service_test.dart \
  test/archive_browser_session_test.dart \
  test/widget/internal_viewer_widget_test.dart
```

The test clock advances deadlines directly; no wall-clock sleep determines
whether the timing contract passes. Native file operations use their actual
completion signals. The optional `temporaryRoot` isolates each test’s owned
children.

This is a G14 lifecycle increment. Verified remote range paging, bounded
large-text comparison and stronger provider snapshot contracts remain open.
