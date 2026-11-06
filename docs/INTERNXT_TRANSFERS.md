# Internxt bounded transfers

The adapter uses the installed `internxt_client` 0.2.3 protocol and crypto APIs,
with a separate transfer implementation in `internxt_streaming_transfer.dart`.
It does not call the SDK's whole-file byte upload, streamed-to-memory download,
or disk download helper. The latter can extend a truncated download to the
advertised length, which is unsuitable for transfer verification.

## Download

Each operation captures the account, token, mnemonic, bucket, root folder,
bridge authentication and adapter session generation. Path lookup, metadata,
download-link requests, each data chunk and completion check that snapshot.
Restoring identical credentials after an adapter logout does not revive an
operation from the previous session.

Fresh metadata identifies the drive UUID, network object, encryption index and
exact plaintext/ciphertext length. The current single-shard AES-CTR format has
equal plaintext and ciphertext lengths. The HTTP stream rejects early EOF and
extra bytes, and decryption emits pieces no larger than 64 KiB. If the provider
supplies the ciphertext SHA-256, it is checked at completion. This is not a new
authenticated encryption format or a proof of plaintext authenticity.

Native downloads write into a private directory next to the destination, flush,
and replace the selected destination only after the complete stream validates.
A save-dialog grant that cannot create files beside the destination uses a
private temporary directory and then copies the verified file to that grant.
The fallback's final copy cannot provide an atomic replacement guarantee.
Remote filename metadata never determines a staging path. Explicit buffered
preview downloads are limited to 32 MiB; larger consumers must use the stream.

## Upload

The adapter validates the declared source length while encrypting a single
continuous AES-CTR stream into private storage. It derives a secure random file
index through the SDK and computes SHA-256 over the ciphertext. Native storage
uses a private temporary file; browser storage uses OPFS. No upload session is
created until the complete input has matched its declared length.

Files below 100 MiB use one signed PUT. Larger files use Internxt's multipart
start/finish protocol. The preferred part size is 30 MiB, increased when needed
to keep the signed-URL response to at most 128 parts and within the 256 KiB
metadata-response limit. Each native part reads a file range in bounded pieces;
each browser part is a Blob slice of the OPFS-backed File. Parts are sent
sequentially and their ETags are placed in the finish manifest in part order.
A missing ETag blocks finalization, including when browser CORS hides it.

The transfer uses the SDK's 20 GiB per-file upload limit. It needs private disk
or browser quota for the ciphertext spool. The browser must support OPFS and
allow the signed upload/download endpoints through CORS. Authenticated requests
use only the captured API endpoint; signed storage requests receive no account
authorization headers and cannot downgrade to HTTP or follow redirects.

Start, finish and drive-file registration are not automatically retried. After
registration, fresh metadata must match the uploaded network object, bucket,
destination folder, name, extension and length before success is returned.
Local private storage is removed on every success or failure path. A network
failure after a provider mutation may leave a pending remote upload/session;
the protocol implementation does not guess an undocumented abort endpoint or
blindly retry an action with unknown completion.

## Freshness and capabilities

The SDK session's listing caches are private and can remain valid for one hour.
The adapter uses SDK path/listing parsers with request-local caches, bounded
metadata responses and account guards so a streamed upload becomes visible in
the next listing. Legacy path mutations resolve a fresh UUID before dispatch.

The adapter advertises bounded upload/download and multipart support. It does
not advertise conditional copy/delete, an exclusive move primitive, atomic
remote replacement, range resume or persistent multipart resume. Those require
separate provider contracts and verification.

Deterministic tests exercise the installed SDK's actual CTR implementation,
HTTP protocol fixtures, split and multipart boundaries, truncation, account
changes, acknowledgement failures, metadata limits, private-file cleanup and
native destination preservation. Live-provider credentials are not required by
these tests.
