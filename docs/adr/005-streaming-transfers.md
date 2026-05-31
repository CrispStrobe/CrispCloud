# ADR 005: Streaming File Transfers

**Status**: Accepted

---

## Context

The naive approach to file transfer is:

1. **Upload**: read the entire file into a `Uint8List`, call an HTTP PUT/POST with the bytes body.
2. **Download**: receive the entire HTTP response body as `Uint8List`, write to disk.

This works for small files but fails for large ones. A 4 GB video fully buffered in memory on a mobile device with 2 GB of RAM will OOM-crash the process. Even on desktop, buffering a 1 GB file before beginning an upload adds unnecessary latency and blocks progress reporting until the buffer is complete.

The provider landscape creates additional complexity:

- **SFTP** (`dartssh2` package) natively exposes a channel-based streaming API with configurable window size.
- **S3** accepts chunked transfer-encoding with a streaming HTTP body.
- **Google Drive, OneDrive, Dropbox** require multipart form uploads or resumable upload sessions for files above certain thresholds. Their Dart HTTP clients do not expose lower-level stream control.
- **FTP** (`ftpconnect`) reads entire files via its internal implementation.
- **WebDAV, Filen, Internxt, Nextcloud, pCloud** vary in their HTTP client capabilities.

We needed a streaming abstraction that:
- Works natively for providers with true streaming support.
- Falls back gracefully for providers that buffer internally.
- Does not require changing the UI layer or transfer queue when a provider adds streaming support.

---

## Decision

### Interface Design

Two streaming methods are added to `CloudStorageClient` as optional overrides with buffer-based defaults:

```dart
// Upload: accepts a Stream<List<int>> instead of a complete byte buffer
Future<void> uploadStream(
  Stream<List<int>> dataStream,
  int length,
  String fileName,
  String targetPath, {
  Function(int, int)? onProgress,
}) async {
  // Default: buffer the stream, delegate to uploadFile
  final builder = BytesBuilder(copy: false);
  await for (final chunk in dataStream) { builder.add(chunk); }
  await uploadFile(builder.takeBytes(), fileName, targetPath, onProgress: onProgress);
}

// Download: returns a Stream<List<int>> instead of a complete byte buffer
Stream<List<int>> downloadStream(
  String remotePath, {
  Function(int, int)? onProgress,
}) async* {
  // Default: download all bytes, yield as one chunk
  final bytes = await downloadFileBytes(remotePath, onProgress: onProgress);
  yield bytes;
}
```

Providers that support true streaming override these methods. The `supportsStreaming` capability flag signals whether the provider's implementation is genuinely non-buffering.

### SFTP: True Streaming

The SFTP adapter overrides both methods. Upload reads the local file in 32 KB chunks via `File.openRead()`, writing each chunk to the SFTP channel. Download reads 32 KB chunks from the SFTP channel, yielding each chunk to the caller who writes it to disk. The maximum memory footprint for an SFTP transfer of any size is approximately 64 KB (one read chunk + one in-flight write chunk).

### S3: Streaming Upload with Multipart for Large Files

For files under 5 MB, S3 accepts a streaming PUT request. For files over 5 MB, the S3 adapter automatically uses the Multipart Upload API:
1. `CreateMultipartUpload` — returns an `uploadId`.
2. `UploadPart` — each 5–100 MB part is a separate PUT with a `partNumber`. Parts can be sent sequentially or in parallel.
3. `CompleteMultipartUpload` — assembles the final object from all parts.

The `uploadId` and completed part ETags are persisted between calls so that an interrupted multipart upload can be resumed.

### Back-Pressure

A `StreamController` transform limits how far ahead the read side can get from the write side: at most 2 chunks (64 KB for SFTP) are in flight at once. This prevents runaway buffering when the network is slower than disk read speed.

### Desktop and Mobile: File-to-Stream

On desktop and mobile, the transfer queue wires `File.openRead()` (a `Stream<List<int>>` over a disk file) directly into `uploadStream`. Downloads pipe `downloadStream` into `File.openWrite()` via `pipe()`. No intermediate `Uint8List` is created.

On the Web, the File System Access API's `FileSystemWritableFileStream` would be the correct sink for downloaded content, but this is not yet wired up. Web downloads currently buffer in memory.

---

## Consequences

**Positive:**

- SFTP transfers of any size (tested up to multi-GB) use constant memory — approximately 64 KB regardless of file size.
- S3 multipart uploads provide reliable progress reporting at chunk granularity and support resumption after interruption.
- The default buffer-fallback means all 11 providers work correctly even without streaming implementations; new providers are not required to implement streaming immediately.
- The `supportsStreaming` flag lets the UI warn users about memory usage for large transfers on non-streaming providers.

**Negative / Trade-offs:**

- Most providers (GDrive, OneDrive, Dropbox, FTP, WebDAV, Filen, Internxt, Nextcloud, pCloud) currently fall back to the buffer-based default. For large files on these providers, memory pressure remains. The streaming implementation is prioritized for SFTP and S3, which are the most common self-hosted and high-volume providers.
- The 2-chunk back-pressure limit assumes the consumer (disk write or network send) processes chunks faster than the producer (disk read). If not, the `await` on the StreamController pause signal adds latency. In practice this is unnoticeable.
- On Web, `Uint8List` downloads hit the browser's memory limit for very large files. The fix (File System Access API `showSaveFilePicker` + writable stream) is tracked but not yet implemented.
- Multipart S3 uploads leave behind in-progress uploads if the app crashes mid-transfer. The resume logic handles this, but orphaned multipart uploads on S3 accumulate storage charges until cleaned up. Users should configure an S3 bucket lifecycle rule to abort incomplete multipart uploads after 7 days.
