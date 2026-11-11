# crisp_storage

Shared Dart storage primitives for CrispCloud and CrisperPlayer. The package
has no Flutter or platform-channel dependency. CrispCloud consumes it by path;
CrisperPlayer pins an exact CrispCloud Git commit and this package path, so CI
and fresh checkouts do not need sibling repositories.

- `RemoteClient`: read-only WebDAV/Plex and SFTP browsing/downloads. HTTP
  credentials stay in headers; redirects and paths outside the configured root
  are rejected. HTTP resume requires a strong ETag and validates Content-Range;
  an incompatible revision restarts. SFTP resumes using size/mtime validators.
- `SmbSession`: native SMB2/3 browsing, streaming, validated resumable downloads
  and file operations through the default `dart_smb2` / LGPL-2.1 libsmb2
  backend or optional shared Rust engine. Signing is enabled;
  SMB3 encryption is required unless the user explicitly opts out. Downloads
  await each bounded disk write. Failed initial connections can be retried by
  a later operation. See `NOTICE-LIBSMB2.txt` and the app's distribution review.
- `openVerifiedSsh` / `SshKnownHosts`: SHA256 host-key verification before
  authentication. Unknown keys require an explicit acceptance callback;
  changed keys fail closed. Inject secure read/write callbacks. Accepted keys
  survive password removal, and concurrent trust updates are serialized.
- `StoredList` / `ConnectionProfileStore`: serialized profile edits with injected
  persistence. No platform secrets or credential files are selected here.
- `TransferScheduler`: bounded concurrency, provider limits/delays, priorities,
  reordering, bounded exponential retry and cancellation during retry waits.
  Authentication and host-key failures are not transient errors. Callers own
  the actual stream cancellation and durable job manifests.

Run `dart pub get`, `dart analyze`, and `dart test` here. Both apps additionally
exercise the transports against local HTTP and real SSH servers. No external
account or user library is used by these tests.

CrispCloud keeps its write-capable provider adapters and browser SSH bridge.
Native WebDAV downloads stream through this package; browsers retain their
existing download path. CrisperPlayer owns audiobook imports and persistent
paused/queued transfer manifests. App credentials remain in platform secure
storage. CrispCloud's standalone CLI currently stores credentials in its YAML
configuration (owner-only permissions on Unix); it does **not** use Keychain.

Cross-app account sharing, cross-device progress sync, and persistent CrispCloud
transfer queues are not supplied by this package. Direct SMB is native-only.

Run the local SMB regression fixture (no user credentials or shares) with:

```sh
CRISPER_SMB_PYTHON=/path/to/python-with-impacket dart test test/smb_transfer_test.dart
```

The fixture validates SMB2 behavior; it does not qualify SMB3 encryption or
device-specific performance. Never disable production encryption for this test.

## Experimental Rust SMB

The default remains libsmb2. See [rollout and qualification](../../docs/SMB_RUST_ROLLOUT.md) for strict Rust/auto selection, native host builds and test gates.

## Filen/Internxt and the Dart/Rust boundary

Filen and Internxt are not currently part of this shared package. The Flutter
apps use Dart clients in their app adapters; CrispSorter already has native Rust
provider libraries. Reusing those libraries through a common contract and Dart
bridge is planned. The host keeps UI, secure-storage integration and job
scheduling; provider sessions, crypto and bounded transfers can run in Rust.

Retain current Dart behavior during qualification, pin shared sources, and never
switch engines after login/security failures or replay a started mutation.
Browser compatibility, session/checkpoint conversion and MPL license evidence
need their own checks. See
[the cross-app storage-engine design](../../docs/STORAGE_ENGINE_ARCHITECTURE.md).
