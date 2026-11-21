# CrispCloud

**A cross-platform, dual-panel cloud file manager built with Flutter.**

Open-source and privacy-first. Runs on macOS, Windows, Linux, Android, iOS and
the web/PWA, with local, cloud, network and archive sources in one workspace.

## Highlights

- **Two independent panes** with tabs, history, favourites, filtering,
  commander-style selection and synchronised browsing.
- **15 storage integrations**, including SMB, SFTP, WebDAV, S3, Google Drive,
  OneDrive/SharePoint, Dropbox, Nextcloud, pCloud, Azure Blob, B2 and Hetzner.
- **Office and ODF** viewing/editing through the CrispStrobe Quds fork.
- **Encryption** with AES-256-GCM, Filen/Internxt E2EE, Cryptomator helpers and
  read-only VeraCrypt/TrueCrypt browsing.
- **Files, archives and disk images**: ZIP, 7z, TAR, RAR, ISO, DMG, FAT, ext,
  NTFS and more, with reviewed publication and recovery paths.
- **Built-in tools**: PDF editor, e-book reader/editor, image gallery, terminal,
  storage analyser, archive manager and catalogue/CLI companion.
- **Customisable shortcuts** with conflict checks in **Settings → Customize
  shortcuts** and the command palette.
- **9 UI languages** and platform-native menus, dialogs and drag-out.

## Office and OpenDocument support

| Format | Open | Edit / save |
| --- | --- | --- |
| DOCX, DOCM, DOTX, DOTM | Word editor | Edit; macros/templates preserved, never executed |
| DOC, DOT | Structured preview | Reviewed DOCX/DOCM copy; original unchanged |
| XLSX, XLSM, XLTX | Sheet editor | Edit; macros/templates preserved |
| XLS, XLT | BIFF8 import | Edit and save a new XLSX copy |
| XLSB | Grid preview | Read-only |
| ODS | Typed grid, formats, pictures, validation | Save new XLSX or export modelled ODS |
| PPTX | Slide editor | Edit |
| PPT, PPS, POT, ODP | Positioned preview | Read-only; modelled ODP export |
| ODT | Formatted read-only view | Modelled ODT export; ordinary save stays DOCX |

Macros and ActiveX are never executed. Signed OOXML packages are refused by the
existing guard. See [format coverage](docs/file-format-viewers.md) and
[remaining Office/ODF gaps](docs/office-remaining-gaps-20261115.md).

## Providers

| Provider | Notes |
| --- | --- |
| Filen.io | E2E encrypted; WebCrypto on web |
| Internxt | Encrypted storage |
| SMB / NAS | Native SMB2/3, signed connections, encryption required by default |
| SFTP | Native streaming and key authentication |
| WebDAV | Standard operations |
| S3 | Presigned URLs, SSE variants, storage classes |
| FTP / FTPS | Standard and TLS |
| Google Drive | OAuth2, shared drives, versions, Google Docs export |
| OneDrive / SharePoint | Graph API, delta, sites and drives |
| Dropbox | Shared folders, content hash, Paper export |
| Nextcloud | Chunked upload v2, ETag tracking |
| pCloud | Standard transfers and random-access helpers |
| Azure Blob | SAS tokens and blob operations |
| Backblaze B2 | S3-compatible and native API |
| Hetzner Storage Box | SFTP/WebDAV/FTP |

Additional accounts are currently session-only. Provider-specific setup and
limits are in [provider setup](docs/PROVIDER_SETUP.md).

## More tools

- **Archives:** browse, create, edit, extract; queue with pause/resume and
  recovery; supported disk images and filesystem readers.
- **PDF:** annotate, fill forms, organise pages and save copies.
- **E-books:** EPUB editing and Kindle/FictionBook/comic reading.
- **Images:** gallery, ratings, tags, comparison, contact sheets and editor hand-off.
- **Terminal:** local PTY/ConPTY, sandboxed macOS shell and SSH sessions.
- **Storage analyser:** treemap/sunburst and saved scans.
- **Catalogues and CLI:** `crispcloud` (`crisp` alias) for headless operations,
  scans and CAF/Cathy/Catfish interchange.

## Build and run

Prerequisites: Flutter **3.47.8** (see `.fvmrc`) and the platform toolchain.

```bash
git clone https://github.com/CrispStrobe/CrispCloud.git
cd CrispCloud
flutter pub get
flutter run -d chrome                         # Web
flutter run -d windows                        # Windows
flutter run -d linux                          # Linux
bash tool/build_macos_local.sh --debug --launch
```

For a macOS release build with version and git revision embedded:

```bash
bash tool/build_macos_release.sh
```

## Tests

```bash
flutter test                                  # unit and widget tests
flutter test --tags live --run-skipped        # credentialed provider tests
flutter test --tags benchmark --run-skipped   # load-sensitive benchmarks
flutter analyze
bash tool/check_office_fidelity.sh            # after shared Office changes
```

## Architecture

```text
Flutter UI (panes, dialogs, settings)
        │
providers / transfer queue / sync / backup / archives
        │
native Rust & Dart storage engines
        │
local filesystem, cloud APIs, SMB/SFTP/WebDAV/S3
```

Key boundaries:

- `CloudStorageClient` — provider interface
- `TransferQueue` — resumable, journaled copy/move jobs
- `SyncEngine` — background synchronisation and conflicts
- `PanelProvider` — dual-pane state
- Quds Office packages — shared Word/sheet/slide/PDF surfaces

See [architecture](docs/ARCHITECTURE.md),
[security architecture](docs/SECURITY_ARCHITECTURE.md) and
[storage engines](docs/STORAGE_ENGINE_ARCHITECTURE.md).

## Shortcuts

The defaults follow a Commander layout: `F3` view, `F4` edit, `F5` copy,
`F6` move, `F7` new folder, `F8`/`Delete` delete, `F9` terminal, `Tab` switch
panes, `Ctrl/Cmd+F` filter and `Ctrl/Cmd+Shift+P` command palette.

Every binding is configurable in **Settings → Customize shortcuts**. Changes are
saved with the app settings and used by menus, the command palette and help.

## Documentation

- [Workspace controls](docs/workspace-ux.md)
- [Transfer queue](docs/transfer-queue.md)
- [Delta sync](docs/storage-delta-profile.md)
- [Archive formats](docs/archive-format-coverage.md)
- [Credential storage](docs/credential-storage.md)
- [PDF editor](docs/pdf-editor.md)
- [E-books](docs/ebooks.md)
- [Command-line interface](cli/README.md)

## Licence

**AGPL-3.0.** See [LICENSE.txt](LICENSE.txt).

CrispCloud is not affiliated with any cloud provider. All trademarks belong to
their respective owners.
