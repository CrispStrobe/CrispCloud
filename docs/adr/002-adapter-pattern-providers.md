# ADR 002: Adapter Pattern for Cloud Storage Providers

**Status**: Accepted

---

## Context

CrispCloud targets 11 cloud providers and servers (and more in the roadmap), each with a completely different API:

- **Filen and Internxt**: proprietary encrypted storage APIs with their own SDK-level abstractions.
- **SFTP**: binary SSH protocol via the `dartssh2` package.
- **WebDAV**: HTTP-based XML protocol.
- **S3**: AWS REST API with SigV4 request signing.
- **FTP/FTPS**: legacy binary protocol via the `ftpconnect` package.
- **Google Drive, OneDrive, Dropbox**: OAuth2 + REST/Graph APIs, each with different authentication flows, path models, and pagination strategies.
- **Nextcloud**: WebDAV + OCS API.
- **pCloud**: OAuth2 + proprietary REST API with EU/US endpoint selection.

The application needs to perform the same operations (list, upload, download, delete, move, rename, create folder) on all providers from a single UI. The UI must not contain provider-specific branching.

We evaluated two approaches:

**Option A: Direct provider calls in the UI layer.** Each UI action contains a switch/if-else tree that calls the correct provider-specific code. This is simple to start but catastrophically bad at scale: every new provider requires touching every UI action, and testing requires knowing about all provider combinations.

**Option B: Adapter pattern with a common interface.** Define a `CloudStorageClient` abstract class. Each provider is a concrete adapter that implements this interface. The UI and business logic only ever speak to `CloudStorageClient`. The factory creates the right adapter based on the selected `CloudProvider` enum value.

---

## Decision

All cloud provider access goes through the `CloudStorageClient` abstract interface in `lib/services/cloud_storage_interface.dart`.

The interface defines:
- **Core operations**: `login`, `logout`, `isAuthenticated`, `listPath`, `uploadFile`, `downloadFileByPath`, `downloadFileBytes`, `createFolderPath`, `deletePath`, `movePath`, `renamePath`
- **Optional capability operations** with default implementations: `uploadStream`, `downloadStream`, `copyPath`, `fullTextSearch`, `getThumbnail`, `getQuota`, `healthCheck`
- **Capability flags**: `supportsStreaming`, `supportsMultipart`, `supportsVersioning`, `supportsSharing`, `supportsSearch`, `supportsThumbnails`, `supportsTrash`, `supportsNativeShare`, `supportsServerSideCopy`, `supportsFullTextSearch`

Each provider implements a concrete adapter in `lib/services/*_client_adapter.dart` and a config service in `lib/services/*_config_service.dart`. The `CloudStorageFactory.create()` method maps `CloudProvider` enum values to adapter instances.

**Default implementations on the interface** mean a new provider only needs to override the capabilities it actually supports. For example, `copyPath` defaults to download+reupload; a provider that supports server-side copy overrides it. `fullTextSearch` defaults to downloading small text files and searching locally; GDrive/Dropbox/OneDrive override it with server-side queries.

The `EncryptedStorageWrapper` also implements `CloudStorageClient`, wrapping any adapter with transparent AES-256-GCM encryption. This composes cleanly with the adapter pattern — the rest of the application cannot tell whether it is talking to a plain or encrypted connection.

---

## Consequences

**Positive:**

- The UI has zero provider-specific branches. All file operations are one-liners against `CloudStorageClient`.
- Adding a new provider is a self-contained task: create the adapter file, the config service file, add one enum value, one factory case, one import, and one test file. No existing code changes required except those four lines.
- The `EncryptedStorageWrapper`, `MultiCloudService`, and the CLI adapter share code with the GUI because they all consume `CloudStorageClient`.
- Each adapter is independently testable by constructing it with a mock HTTP client or a test server.
- Capability flags let the UI gracefully degrade for providers that do not support certain features (e.g., no "Share Link" button when `supportsSharing` is false), rather than crashing or showing disabled UI based on provider identity.

**Negative / Trade-offs:**

- The interface is defined around the lowest common denominator of all providers. Provider-specific features (e.g., Filen's encryption key derivation, S3 storage classes, SFTP chmod) cannot be expressed through the interface and require separate service classes or out-of-band access.
- The default `fullTextSearch` implementation (download + local grep) is expensive for large directories. It is acceptable as a fallback but must not be presented as equivalent to a server-side search.
- The `login(email, password)` signature is a poor fit for OAuth2 providers. OAuth2 providers currently store an auth URL and open a browser; the `login` call completes the token exchange. This is functional but mismatches the semantic intent of the method.

**Future:**

If a richer plugin API is added (Phase 9), third-party providers can implement `CloudStorageClient` externally and be registered with the factory at runtime — the interface design already supports this.
