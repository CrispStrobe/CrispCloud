# File encoding and decoding

The file context menu offers **Encode / decode file…** for a single regular file on a local or remote source. The review captures the original account, file and folder. Choose **Encode to text** or **Decode to file**, the format, and an explicit new output filename. The file is created in the captured folder after verification; the original is retained.

The default encoded name appends `.uue`, `.xxe` or `.mime`. The default decoded name ends in `.decoded`, even when a header contains a different name. Changing a format or direction updates a generated default but preserves a name the user entered. Existing output names require a different name; there is no overwrite option. A successful review displays the output path, byte count and SHA-256 digest and records the original selection for restoration.

## Format scope

| Format | Encoder | Decoder and limits |
| --- | --- | --- |
| UUE | Historical six-bit encoding, `begin 600 name`, at most 45 input bytes per data line, backtick for zero, zero-length line and `end` footer. | One complete block. Accepts historical space-for-zero as well as backticks, LF or CRLF, and a bounded preamble. Requires exact line lengths and both end markers. Rejects extra blocks, checksum-suffixed variants, private line prefixes and `begin-base64` wrappers. |
| XXE | Conventional six-bit alphabet `+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`, `begin 600 name`, at most 45 input bytes per line, `+` zero-length line and `end` footer. | The same single-block framing checks as UUE. Does not implement extended checksummed or prefixed variants. |
| MIME (Base64) | One MIME entity with `MIME-Version: 1.0`, `application/octet-stream`, Base64 transfer encoding and attachment disposition. Encoded body lines contain at most 76 characters and use CRLF. UTF-8 names use an RFC 2231 `filename*` parameter. | One non-composite MIME entity using Base64. Supports plain ASCII filenames or one UTF-8/US-ASCII `filename*` parameter. Rejects multipart messages, `message/*`, quoted-printable and other transfer encodings, duplicate headers/parameters, malformed percent escapes, filename continuation parameters, and incomplete or noncanonical Base64 padding. Spaces/tabs and line breaks in the encoded body are accepted. |

These are file conversions, not a general email import feature. A complete multipart `.eml` message must first be reduced to the intended supported single-part entity. A `.mime` or `.eml` extension selects MIME decoding as a default; the actual bytes still determine validity. Raw Base64 without MIME headers is not accepted by this command.

UUE and XXE encoding require an ASCII embedded filename. Choose MIME for Unicode filenames. Embedded names are limited to 255 UTF-8 bytes and exclude control characters on encoding. The MIME writer's fully percent-encoded filename fits within a 998-character header line. Output filenames are separately limited to 240 UTF-8 bytes and must be a single portable filename without path separators, control characters, reserved device names or trailing dots/spaces.

Embedded names must be safe single-component filenames. All three decoders reject `.` and `..`, absolute paths, slash or backslash separators, Windows drive prefixes, surrounding whitespace and control characters. These checks run unconditionally, even when the caller ignores filename metadata, and fail before any output is staged or published. The encoder applies the same name boundary so it does not produce a file that this decoder would reject.

Accepted embedded names and mode values remain metadata: they never select output paths, set permissions, invoke applications, or cause overwrites. The user's explicit output name always wins over a safe embedded filename. The MIME parser validates filename parameters even when the caller discards the name.

## Verification and storage requirements

Conversion is streamed in bounded chunks using existing storage backends and the shared SHA-256 integrity helpers. There is no whole-file byte buffer or file-size-based allocation. The codec uses fixed 45/57-byte line buffers for encoding and approximately 32 KiB output batches. Decoding limits each input line to 4096 bytes and preamble/MIME headers to 64 KiB; MIME also limits the number of headers. An upstream storage chunk remains subject to that backend's bounded-download contract.

The service performs these steps:

1. Validate the explicit output name, captured storage identities, selected file metadata, destination folder, and absence of an output file. Reject selected or freshly reported symbolic links and non-regular inputs.
2. Convert the entire input once, hashing input and output while discarding the converted bytes. Malformed or unsupported encoded input fails before any temporary output is written.
3. Convert again into the backend's private staged file. Compare both passes' byte counts and SHA-256 digests, including the original input digest.
4. Read back and hash the complete staged output. Read and hash the original again to catch content changes that retain size and modification time. Recheck captured source/version fields, destination folder and absence of an output.
5. Publish the verified staged file with an exclusive operation. A competing file appearing at the destination must cause failure instead of replacement.

Both read paths must advertise bounded download, and the destination must also advertise bounded upload, staged verification and an exclusive publication mechanism. Accepted publication capabilities are either native atomic no-replace move, or native no-replace conditional copy together with conditional deletion. Supported native desktop folders can use the existing exclusive rename implementation. Providers that cannot make these guarantees are explicitly unavailable in this workflow. In particular, generic legacy rename fallbacks and the current browser-local destination contract are not advertised as safe conversion destinations.

Current UI scope is a single file and output in that file's captured folder. There is no cross-pane destination chooser, batch conversion, queued/restartable conversion job or automatic deletion of the original. Backend adapters remain responsible for provider-specific staging, exclusive publication and cleanup. The workflow uses the existing operating-system grants; it does not traverse outside granted roots to inspect ancestor directories.

## Cancellation and changing sources

The review and service independently bind the original storage identities. Replacing or disconnecting an account invalidates the review and cancels active reads. Closing the dialog's host cancels work; late progress/error callbacks do not update disposed widgets. The **Cancel** button interrupts streaming reads, including a source or verification stream stalled without producing more bytes. Pending metadata reads are also detached from the result. Provider writes or commit acknowledgements already in flight may need to return before their next cancellation checkpoint; cancellation does not undo a confirmed successful commit.

Cancellation or validation failure before publication leaves the original intact. Staged files use the backend's normal cleanup behavior. If an account disappears, the backend does not attempt cleanup against a replacement account. A lost remote commit acknowledgement can leave an output or recovery stage whose outcome requires inspection, consistent with the underlying transfer backend. The UI never displays raw provider exceptions or credentials.

## Implementation and verification

- Codec: [`file_conversion_codec.dart`](../lib/services/file_conversion_codec.dart).
- Verified conversion and storage gates: [`file_conversion_service.dart`](../lib/services/file_conversion_service.dart).
- Captured-source dialog: [`file_conversion_dialog.dart`](../lib/widgets/file_conversion_dialog.dart).
- English and eight translated locales: [`file_conversion_strings.dart`](../lib/l10n/file_conversion_strings.dart).
- Entry point: [`file_context_menu.dart`](../lib/widgets/file_context_menu.dart).
- Tests: [`file_conversion_codec_test.dart`](../test/file_conversion_codec_test.dart), [`file_conversion_service_test.dart`](../test/file_conversion_service_test.dart), [`file_conversion_dialog_test.dart`](../test/widget/file_conversion_dialog_test.dart).

Coverage includes known six-bit/Base64 vectors, all byte values and arbitrary input chunking, empty files, line/header bounds, malformed and unsupported MIME, Unicode header round trips, malicious embedded-name rejection before staging, safe embedded-name override, existing/racing destinations, same-size source mutation, staged corruption, source identity replacement, cancellation of a stalled stream, review-only behavior, late callbacks and narrow Arabic layout. A real native temporary-directory test uses `LocalOperationBackend` to encode, decode and refuse an occupied output, checking original bytes, output hashes and cleanup. That fixture runs on Linux/Windows; macOS grants remain a native acceptance check. The final focused run passed all 80 tests across the codec, service and dialog suites on Linux. No new conversion file has analyzer findings; existing context-menu lint findings remain reported separately.

No new dependency is added. Encoding implementations are independent code using Dart's core library and the existing integrity helpers; the latter already use the project's `crypto` dependency.

## Specification references

- [RFC 2045: MIME format and Base64 transfer encoding](https://www.rfc-editor.org/rfc/rfc2045.html).
- [RFC 2231: character sets and language information in MIME parameters](https://www.rfc-editor.org/rfc/rfc2231.html). This workflow implements single extended filename parameters and explicitly rejects continuations.
- [POSIX uuencode utility specification, authorized reproduction](https://man7.org/linux/man-pages/man1/uuencode.1p.html), and [uudecode specification](https://man7.org/linux/man-pages/man1/uudecode.1p.html). The decoder deliberately does not apply the output filename or permissions behavior of the command-line utility.
- [OpenBSD uuencode format manual](https://man.openbsd.org/uuencode.5), including conventional backtick zero and block framing.
- [A Survey of Printable Encodings](https://www.mdpi.com/1999-4893/18/8/504), documenting printable six-bit alphabets, including the conventional XXE alphabet. Extended XXE variants are outside this workflow.
