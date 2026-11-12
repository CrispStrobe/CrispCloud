# Shared transfer bandwidth implementation design

Gap: **G29**. Status: **Scoped; implementation has not started**.
Source review: 12 November 2026, after the G05/G09/G25/G49 continuation.

The native-runtime feature is feasible with existing Dart, HTTP and preferences
dependencies. It needs transport integration as well as a shared allocator.
The existing [client-copy limiter](../../lib/services/stream_rate_limiter.dart)
paces one logical operation before adapters may spool or encrypt it. The
[scheduler](../../packages/crisp_storage/lib/src/transfer_scheduler.dart)
controls task admission and concurrency, not byte allocation. Neither alone
provides aggregate upload/download enforcement.

## Accounting contract

Use two independent pools for **client transport payload bytes**: upload and
download. This includes encrypted envelopes when those are transported payload,
but excludes TLS, protocol framing and operating-system transport buffering.
The UI must not present it as exact wire traffic.

Fairness is by `OperationProgress.id`, so a batch split into many scheduler tasks
does not obtain extra shares. A client-mediated remote-to-remote copy uses both
pools under the same job identity. Retried requests and verification reads
consume their actual direction's budget again. Local spooling, local hashing,
renames and server-side payload copies do not consume a network budget.

Define one owner per application runtime, bounded credit and cancellable byte
quanta. A proposed initial quantum is at most 64 KiB and about 100 ms of the
configured rate, with a minimum of one byte; validation must establish the final
burst tolerance. Only jobs with ready data compete. No share remains held while
a source read, remote acknowledgement or paused job is waiting.

Normalize a zero setting to unlimited; pause remains a separate state. Changing
limits, cancelling, pausing/resuming and disposing a job must wake pending
requests. Never refund bytes already submitted to transport after a failure.
Existing per-operation pacing can coexist, but the combined behavior is not
described simply as the smaller of two limits.

## Captured context and transport hooks

A captured context carries the allocator, stable operation ID, control signals
and direction-specific coverage. It must follow the original asynchronous
operation into the final transport stream without changing source/client
identity. A scoped Dart zone or explicit context is feasible; stream creation
and subscription must not inherit a later caller's job accidentally.

| Surface | Required hook and boundary |
| --- | --- |
| [Transfer provider](../../lib/providers/transfer_provider.dart) | Start/finish participation for journaled and legacy jobs; batch tasks share their operation ID. |
| [Bounded HTTP transfers](../../packages/crisp_storage/lib/src/cloud/bounded_http_transfer.dart) | Meter downloaded payload responses, including verification and ranges. Audit adapters with separate readers. |
| [Stream requests](../../packages/crisp_storage/lib/src/cloud/transfer_stream_request.dart) | Pace native request bodies after spooling/encryption. Buffered parts also need their final HTTP body paced. |
| Multipart and spool providers | Cover prepared parts, retries, blocks and encrypted requests; pacing only preparation leaves later uploads unrestricted. |
| [FTP session](../../lib/services/ftp_transfer_session.dart) | Meter data-socket reads and uploaded data streams while preserving control sequencing and TLS ownership. |
| SFTP and SMB | Cover final bounded read/write calls and compatibility methods taking alternate paths. |
| Sync, migration, editors and foreground verification | Define a participant for payload traffic outside the main queue, or disclose that narrower coverage explicitly. |
| [Activity view](../../lib/widgets/operations_panel.dart) | Use allocator direction counters rather than logical file progress for measured upload/download rates. |

FTP range reads can drain the remaining server transfer after the requested
range has been returned. Charge received data before that range truncation;
counting yielded bytes alone would understate consumed payload. Shared HTTP
upload hooks must similarly cover actual multipart bodies after their source
has already been consumed into a spool.

## Coverage that cannot be claimed yet

**Browser uploads:** the pinned `http` 1.6.0 browser client collects the request
body before calling `fetch`. Pacing that collection delays preparation, not the
later upload. The app's [browser spool uploader](../../lib/services/spooled_http_upload_web.dart)
also submits a complete File/Blob. Browser upload pacing therefore needs a new
transport and separate acceptance; the current path must report unsupported.
Streamed browser response consumption can participate in download pacing, with
transport-buffering limits disclosed.

**Separate background runtimes:** [mobile background sync](../../lib/services/background_sync_mobile.dart)
dispatches through the background task runtime. Loading the same setting there
does not share the GUI allocator's budget. Strict aggregate enforcement across
runtimes needs a broker or coordinated ownership. Until then, background work
must be explicitly outside that shared budget or deferred when enforcement is
required; a Dart singleton is insufficient.

**Alternate methods and server-side work:** provider-wide capability flags are
too coarse. The same provider can have a covered native stream and an uncovered
browser or compatibility path. Track each direction/leg as limited, unlimited,
not applicable, unsupported or mixed. A server-side copy followed by a limited
client verification read must expose those different boundaries.

## Incremental implementation and evidence

1. Add the pure shared allocator, captured job lifecycle and persistent settings.
   Verify aggregate rates, fairness, bounded bursts, dynamic changes, zero,
   cancellation, pause/resume, failed consumers and disposal deterministically.
2. Integrate native HTTP upload/download boundaries, including buffered parts,
   prepared spools, encryption envelopes and retry charging. Observe loopback
   payload timing and test both directions concurrently.
3. Cover direct protocols and alternate call sites: FTP drained ranges,
   SFTP/SMB compatibility methods, sync, migration, recovery and verification.
   Prove remote-to-remote accounting and local/server-side exemptions.
4. Add settings and Activity state with nine-language labels and narrow enlarged
   German/Arabic layouts. Describe browser/background coverage per path.
5. Record actual transport coverage and target-runtime evidence before updating
   G29's status. Preserve each coherent increment on a remote feature branch.

No dependency or support claim is introduced by this design. Browser upload
transport and cross-runtime aggregation remain explicit implementation
boundaries, not hidden bypasses.
