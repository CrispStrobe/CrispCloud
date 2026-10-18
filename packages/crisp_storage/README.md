# crisp_storage

Shared Dart storage primitives for CrispCloud and CrisperPlayer. The package
has no Flutter or platform-channel dependency. CrispCloud consumes it by path;
CrisperPlayer pins an exact CrispCloud Git commit and this package path, so CI
and fresh checkouts do not need sibling repositories.

- `RemoteClient`: read-only WebDAV/Plex and SFTP browsing/downloads. HTTP
  credentials stay in headers; redirects and paths outside the configured root
  are rejected. HTTP resume requires a strong ETag and validates Content-Range;
  an incompatible revision restarts. SFTP resumes using size/mtime validators.
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

Direct SMB transport, cross-app account sharing, cross-device progress sync,
and persistent CrispCloud transfer queues are not supplied by this package.
