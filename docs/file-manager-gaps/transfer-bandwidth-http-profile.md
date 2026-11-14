# Queued HTTP payload limits

G29 foreground HTTP increment, 14 November 2026. Native qualification is
recorded in [the source-bound evidence](../evidence/storage-bandwidth-20261114/).
The dedicated actual-Chrome helper run remains pending hosted CI.
The broader global-bandwidth gap remains open for the paths listed below.

## User controls and durable policy

**Settings → Network → Queued HTTP payload limits** and **Transfer queue panel →
Payload limits** open the same dialog. Upload and download are independent, entered in
KiB/s, and shared across participating queued jobs in the current foreground
application runtime. Empty or zero means unlimited. Fractional KiB/s values
are accepted down to one byte/s, with a maximum of one TiB/s per direction.
Decimal comma and Arabic digits are accepted. Labels cover the application's
nine languages; narrow enlarged German and Arabic layouts are part of the
qualification cohort.

The controller stores a versioned JSON object containing both integer byte/s
values under one preferences key. A save must succeed before it changes active
allocation; a failed save preserves the previous policy. Restoring invalid or
unreadable settings fails new queue execution visibly rather than substituting
unlimited traffic. Retry loading or explicitly save valid replacement limits
to recover. Queue work waiting for the policy remains cancellable. Existing
journal restoration is independent of policy loading.

**Covered HTTP traffic** in Activity reports separate upload/download rates
and session totals from the allocator. These are admitted payload handoffs at
the covered helper boundaries, including covered request metadata, retry
bodies and verification reads. They are distinct from logical file-copy
progress. They exclude TLS/protocol overhead, client/OS/network buffering,
rejected raw chunks and uncovered paths. A browser or operating system may
already have received bytes before response consumption is paced. Bytes handed
off before an eventual failure remain counted; they are never refunded.

Rates use a trailing approximately one-second window in bounded 100 ms buckets.
Activity refreshes at most every 250 ms while receiving events, followed by a
quiet second for rate decay. Session counters reset with the runtime owner;
they are not durable billing or wire-traffic measurements.

## Allocation and lifecycle contract

The [shared allocator](../../packages/crisp_storage/lib/src/transfer_bandwidth.dart)
has one independent pool per direction. The fair identity is
`OperationProgress.id`, not scheduler task ID. A batch split into several
simultaneous tasks receives one job's share. Each attempt has its own captured
context, so finishing one sibling task does not close another sibling's body.
Retries open fresh attempt contexts under the same stable operation identity
and count every submitted byte again.

Only ready payload competes. A source read, paused consumer or remote
acknowledgement does not reserve a job's share. Ready jobs receive equal-weight
byte service. Under a finite rate, each scheduling quantum is bounded by:

`max(1, min(65,536, floor(bytesPerSecond / 10)))` bytes.

Unlimited traffic still uses slices of at most 64 KiB. For a finite rate,
every quantum waits at least its byte count divided by the
current rate, rounded upward to a microsecond. No initial or idle credit is
accumulated. While the rate is fixed, a sliding handoff interval has at most
one-quantum boundary tolerance; real event-loop delays may make it slower.
Changing one direction resets its pending wait without restarting the other
direction. A changed limit starts a fresh wait for any remaining ready data;
already submitted bytes are not revoked.

**Pause an operation** withdraws its pending requests. Resume starts fresh
allocation without an idle burst. **Pause queue** retains its existing
admission-only meaning: active operations continue. Stop, context close and
allocator disposal wake blocked quota/source waits and propagate cancellation.
Upstream cleanup is requested without allowing a stuck cleanup future to hide
cancellation or a source-read error. A stream owns an immutable slice at each
handoff; producers may reuse their source buffer after the paused read is
released. Empty/readily available streams yield cooperatively to the event loop.

The existing [logical per-operation limiter](../../lib/services/stream_rate_limiter.dart)
is unchanged. It can pace preparation before a provider spools or encrypts data;
the new pool paces its own covered HTTP boundary afterward. Their combined
timing is not described simply as the smaller of the two configured limits.

## Actual hooked boundaries

Participation starts in [TransferQueue](../../lib/services/transfer_queue.dart)
for legacy and journaled tasks owned by
[TransferNotifier](../../lib/providers/transfer_provider.dart). The operation
zone carries the context into asynchronous work. The HTTP helpers capture it
at invocation; later finalization or subscription cannot adopt a different
operation. A closed captured request is rejected even when an injected client
does not implement abort semantics.

| Boundary | What is covered | What the boundary does not establish |
| --- | --- | --- |
| [`sendTransferRequest`](../../packages/crisp_storage/lib/src/cloud/bounded_http_transfer.dart) | Complete finalized native request body, followed by its bounded metadata response | Other `client.get`, `post`, `send` or SDK methods bypassing this helper |
| [`bindHttpTransferBandwidth`](../../packages/crisp_storage/lib/src/cloud/transfer_bandwidth_http.dart) | Buffered, streamed and multipart request bodies after preparation, including any encrypted envelope and multipart framing | TLS/HTTP framing, socket buffering or proof that the remote server accepted the handed-off body |
| [`streamHttpDownload`](../../packages/crisp_storage/lib/src/cloud/bounded_http_transfer.dart) | Validated response chunks and admitted range/verification reads through this helper | An entire provider's download API, transport-level receive windows or bytes rejected before admission |
| [Browser Blob upload](../../lib/services/spooled_http_upload_web.dart) | Explicit unsupported coverage for both its upload and separate response path | Upload enforcement or metering of its preparation as a network transfer |

The wrapper preserves request method, URI, final multipart boundary/headers,
content length, redirect policy, connection policy and any original abort
trigger. Native HTTP abort also follows the context lifetime, including while
waiting for response headers. Download source/account checks remain before
requests, around admitted chunks and at completion. Client ownership and exact
length checks retain their existing contract.

Oversized response metadata is rejected before waiting for quota, at the
existing 256 KiB bound. Download length overruns are similarly rejected before
admission. This prevents a one-byte/s setting from turning malformed responses
into many hours of waiting. Rejected raw bytes, or bytes already buffered during
cancellation, are not included in the admitted handoff counters. This is a
bounded consumption policy, not an all-network receive cap.

### Call-site coverage

The following adapters currently call one or both helpers. Coverage is by the
specific leg that calls the helper while a queued operation context is active;
these are **not provider-wide capability claims**.

| Existing caller | Covered helper paths |
| --- | --- |
| [Nextcloud](../../lib/services/nextcloud_client_adapter.dart) | Prepared stream upload and common streamed download |
| [Google Drive](../../lib/services/gdrive_client_adapter.dart) | Upload-session initiation/chunks and common streamed download |
| [OneDrive](../../lib/services/onedrive_client_adapter.dart) | Upload-session requests/chunks/covered cleanup and common streamed download |
| [Dropbox adapter](../../lib/services/dropbox_client_adapter.dart) and [publication](../../lib/services/dropbox_file_publication.dart) | Covered upload/publication requests and common streamed download/verification |
| [pCloud](../../lib/services/pcloud_client_adapter.dart) | Covered buffered/prepared upload requests and common streamed download |
| [Backblaze B2](../../lib/services/b2_client_adapter.dart) | Covered single/part upload requests and common streamed download |
| [S3](../../lib/services/s3_client_adapter.dart) | Covered upload-part/body requests; other S3 client reads remain outside this profile |
| [Internxt streaming transfer](../../packages/crisp_storage/lib/src/cloud/internxt_streaming_transfer.dart) | Covered encrypted transfer requests and common streamed downloads |
| [Filen stream transfer](../../packages/crisp_storage/lib/src/cloud/filen_stream_transfer.dart) | Covered transfer requests through `sendTransferRequest`; other read paths are not inferred as covered |

Local spooling, hashing, local copies and server-side payload movement do not
acquire a body budget. A client-mediated remote-to-remote copy uses both pools
only when both legs use covered helpers; an uncovered leg stays uncovered.
Small covered control requests associated with server-side work still count
their own HTTP payload, not the remotely copied file size.

## Runtime and remaining scope

| Runtime or path | This increment |
| --- | --- |
| Foreground native queued common HTTP helpers | Shared native request-body pacing and response-consumption pacing |
| Foreground browser common HTTP requests | Upload unsupported: the pinned HTTP browser client collects the complete body before `fetch`; the upload control is disabled |
| Foreground browser common streamed responses | Shared consumption pacing, subject to browser buffering; dedicated Chrome acceptance is required for the helper contract |
| Direct browser File/Blob uploader | Both directions explicitly unsupported by this hook |
| FTP, SFTP and SMB | Not integrated; data sockets, drained ranges and bounded native write/read methods need separate hooks and evidence |
| Other HTTP methods and SDK paths | Not integrated merely because the provider also has a covered helper path |
| Sync, editors, migration or verification outside the foreground queue | No automatic participant; dedicated operation ownership remains necessary |
| Separate background runtimes | No shared broker; loading the same settings elsewhere would not combine their traffic with this runtime |

The pure allocator's VM and compiled-JavaScript tests establish scheduling and
lifecycle behavior. HTTP request fixtures and native loopback tests establish
the exercised handoff and cancellation contracts. The dedicated Chrome cohort checks the browser helper's explicit unsupported
upload behavior and paced response consumption using a mock HTTP client inside
the actual browser runtime; its observed status is recorded separately. None proves live-service throughput, every adapter alternative,
transport-buffer size or cross-process enforcement. Recorded source revisions,
commands, successes and failures belong in the linked evidence; G29 closes only
when its remaining implementation and acceptance requirements are satisfied.
