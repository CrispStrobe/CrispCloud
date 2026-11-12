# File conflict review

When a copy or move needs a decision for an occupied destination, the review
shows the incoming and existing files together. Wide dialogs use two cards;
narrow dialogs stack them. Each card retains the original path, storage label,
file kind, exact byte size and modification time in UTC. **More details** shows
available content type, storage class, object ID, revision, reported checksum
and creation time. These fields come from an explicit allowlist; credentials,
download URLs, encryption keys and arbitrary provider metadata are excluded.
Reported checksums are provider metadata, not a new content verification.

Supported raster images receive a small first-frame preview. The preview reads
through the captured operation backend, so matching paths on different storage
accounts remain distinct. It checks source/session identity and file metadata
before and after reading and again after decoding. Available object IDs,
versions and checksums participate in those checks. The operation still runs
its own source/destination checks before performing the chosen action.

## Limits and unavailable previews

- Automatic image previews require a backend that advertises bounded
  downloads. Other backends show an unavailable state without opening the
  file; a small declared file size cannot constrain an adapter's own buffer.
- Each input is limited to 4 MiB, including unknown-size streams.
- Image dimensions are inspected before pixel decoding: at most 16 million
  pixels, with neither edge above 8192 pixels.
- Each thumbnail is at most 384 pixels on either edge and 1 MiB of PNG data.
  The two previews are decoded sequentially.
- Only the first frame of an animated image is displayed and labeled.
- A request has a 15-second deadline. Stalled source reads are cancelled.
- Platform decoder support determines which raster formats can be shown.
  Folders, symbolic links and unsupported formats are not opened for previews.
  SVG and other formats requiring a separate renderer are outside this surface.

Oversize, unsupported, damaged/unreadable images and timeouts have explicit
states. A transient read failure or timeout can be retried against the same
captured file. Previews remain in memory; they do not create a thumbnail disk
cache or write to either endpoint. Available metadata cannot detect every
external edit that preserves all reported version fields; previews remain
review aids, not authorization to bypass operation integrity checks.

## Decisions and lifetime

Previews never select Replace, Skip, Keep both, Rename, Resume, Append or Merge.
These remain explicit decisions, including the existing apply-to-all option.
A detected source-session or file-version change clears the previews and asks
for a new operation review. Choosing a decision, cancelling or closing the
dialog cancels outstanding preview/comparison reads. Late asynchronous results
cannot update the closed review or switch to another account.

Text comparison and SHA-256 comparison use the same captured targets and
revalidate them around reads. Text comparison retains its 1 MiB per-file UTF-8
limit; SHA-256 streams the full file when explicitly requested. Both are
read-only and are cancelled when the conflict review closes.

## Validation

`test/file_conflict_preview_service_test.dart` covers real PNG decoding and
downscaling, header dimension limits, byte limits, corrupt input, unsupported
entries, separate sources, changed versions, cancellation, timeout and metadata
redaction. `test/widget/file_operation_conflict_dialog_test.dart` covers paired
cards, explicit decisions, unavailable previews, source loss, late callbacks
and narrow enlarged German/Arabic layouts. These suites plus the existing
operation-dialog and operation-service suites passed all 140 tests on the pinned
Flutter toolchain. Focused static analysis was clean. Platform image-format
availability and live-provider certification remain separate acceptance work.
