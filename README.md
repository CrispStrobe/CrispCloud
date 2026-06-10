# CrispCloud

**Cross-platform dual-panel cloud file manager** built with Flutter. Open-source, privacy-first, running on macOS, Windows, Linux, Android, iOS, and Web/PWA.

14 cloud providers. 4468 tests. Block-level delta sync. End-to-end encryption. 9 languages.

## Providers

| Provider | Features |
|----------|----------|
| **Filen.io** | E2E encrypted, WebCrypto on web |
| **Internxt** | Decentralized encrypted storage |
| **SFTP** | Native streaming, key auth |
| **WebDAV** | Standard operations |
| **S3** | Presigned URLs, SSE-S3/KMS/C, 8 storage classes, delta sync (Range GET) |
| **FTP/FTPS** | Standard + TLS |
| **Google Drive** | OAuth2, shared drives, starred files, file versions, Google Docs export (6 formats) |
| **OneDrive / SharePoint** | Graph API, delta sync, shared libraries (SharePoint sites + drives) |
| **Dropbox** | Shared folders, content hash, Paper docs (list + export) |
| **Nextcloud** | Block-level delta sync (server app), chunked upload v2, ETag tracking |
| **pCloud** | Random-access I/O (pread/pwrite), delta sync |
| **Azure Blob** | SAS tokens, blob operations |
| **Backblaze B2** | S3-compatible + native API |
| **Hetzner Storage Box** | SFTP/WebDAV/FTP access |

## Block-Level Delta Sync

For large files (VeraCrypt containers, disk images, databases), CrispCloud uploads only the 4 MB blocks that changed instead of the entire file.

- **Algorithm:** Adler-32 weak hash + SHA-256 strong hash per block
- **Providers:** Nextcloud (via [server app](https://github.com/CrispStrobe/crispcloud-delta-sync)), pCloud (native pread/pwrite), S3 (Range GET download)
- **Savings:** A 500 MB file with 8 MB changed = 98.4% bandwidth saved

### Desktop Client Forks

We also maintain patched Nextcloud and ownCloud desktop clients with delta sync support, settings UI, activity display, and notifications:

- **[Nextcloud Desktop (delta sync)](https://github.com/CrispStrobe/nextcloud-desktop)** — [download binaries](https://github.com/CrispStrobe/nextcloud-desktop/releases/tag/delta-sync-latest) (Linux, Windows, macOS)
- **[ownCloud Desktop (delta sync)](https://github.com/CrispStrobe/owncloud-client)** — [download binaries](https://github.com/CrispStrobe/owncloud-client/releases/tag/delta-sync-latest) (Linux, Windows, macOS)
- **[Server App](https://github.com/CrispStrobe/crispcloud-delta-sync)** — PHP app for Nextcloud 25+ / ownCloud 10.11+, plus Dart CLI demo

## Key Features

- **Flexible layout:** dual/single panel toggle, tree sidebar toggle, grid/list toggle, density toggle — all independent and composable
- **Encryption:** AES-256-GCM + Cryptomator vault support + VeraCrypt container detection
- **Sync engine:** background sync, conflict resolution, selective sync
- **Backup engine:** scheduled backups with versioning
- **Preview pane:** images (zoom/pan), SVG, PDF (page navigation), syntax-highlighted code (30+ languages), markdown, CSV/TSV tables, DOCX/XLSX/PPTX/ODT text, fonts (TTF/OTF/WOFF2), audio/video
- **Archive browsing:** browse ZIP/TAR/TGZ files like folders (including on web)
- **Built-in editor:** edit remote and local files in-place with syntax highlighting (Ctrl+S auto-save)
- **Web support:** full file operations (open folder, copy, move, delete, download) via File System Access API with Safari/Firefox fallback
- **CLI companion** (`crisp`): headless S3/SFTP/WebDAV operations, 9 commands, shell completions
- **Plugin system** with local REST API and automation rules
- **FUSE mounts** for mounting remote storage as local drives
- **9 languages:** EN, DE, FR, ES, PT, ZH, JA, KO, AR
- **Accessibility:** 48dp touch targets on mobile, Semantics on file list items

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.44+)

### Build and Run

```bash
git clone https://github.com/CrispStrobe/CrispCloud.git
cd CrispCloud
flutter pub get
flutter run -d chrome    # Web
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux
```

### Tests

```bash
flutter test              # 4468 tests, 19 skipped
flutter analyze           # 0 warnings, 0 errors
```

## Architecture

Modular adapter pattern with provider-agnostic interfaces:

- **`CloudStorageClient`** — abstract interface for all 14 providers
- **`DeltaSyncService`** — block-level diff engine (Adler-32 + SHA-256)
- **`TransferQueue`** — concurrent transfers with exponential backoff retry
- **`SyncEngine`** — background sync with conflict resolution
- **`PanelProvider`** — dual-panel state management (Riverpod)

See [PLAN.md](PLAN.md) for the full roadmap (365/393 items done).

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Tab` | Switch panels |
| `Enter` | Open folder / execute file |
| `Backspace` | Parent folder |
| `Ctrl+A` | Select all |
| `Ctrl+C` / `F5` | Copy |
| `Ctrl+X` / `F6` | Move |
| `F2` | Rename |
| `F7` | New folder |
| `F8` / `Delete` | Delete |
| `Ctrl+F` / `Alt+F7` | Search |
| `Space` | Select + advance cursor |
| `Ctrl+Q` | Swap panels |

## License

AGPL-3.0. See [LICENSE](LICENSE).

Not affiliated with any cloud provider. All trademarks belong to their respective owners.
