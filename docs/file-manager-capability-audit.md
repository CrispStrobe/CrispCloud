# File manager capability audit and implementation

Audit date: 12 November 2026. Baseline: `4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c`.
Working branch: `feature/file-manager-capabilities-20261112`.

This audit compares the requested workflow ideas with application code and
focused tests. Existing implementations are not a claim that every provider,
platform or file size has passed live acceptance. Historical checklists are not
used as proof. Repeated requests are consolidated below.

## Implementation increments

The following gaps fit the current architecture without adding a dependency:

1. Explicit DOS CP437 and Windows-1252 text decoding, editing and search.
2. Reviewed archive creation with supported format, compression and password
   options, using the existing archive libraries and captured file targets.
3. Explicit FTP over TLS, preserving the existing implicit TLS connection mode
   and validating certificates on control and data connections.
4. Source-bound synchronized browsing between matching directory structures.

Each coherent increment is committed to the remote feature branch. Validation
and exact remaining limits will be recorded here as implementation completes.
These are first-party implementations. No new third-party dependency or license
is needed for the initial scope.

## Workspace, display and navigation

| Requested workflow | Baseline status | Evidence and boundary |
| --- | --- | --- |
| Dual panes, tabs, brief/details/grid/thumbnail views | Implemented | `lib/widgets/file_panel.dart`, `lib/models/file_view_configuration.dart`; independent local or remote pane sources. |
| History, favorites and saved workspaces | Implemented | `lib/providers/bookmarks_provider.dart`, `lib/providers/workspace_provider.dart`; source-bound tabs, groups and paired bookmarks. |
| Synchronized browsing | Missing | Paired bookmarks open both roots, but later navigation is independent. Included in this branch's scope. |
| Configurable buttons and external commands with arguments | Implemented | `lib/widgets/file_command_toolbar.dart`, `lib/services/custom_toolbar_command_service.dart`; saved command/argument templates and review. |
| Configurable main menu | Partial | Shortcuts are customizable and reflected in menus; menu structure is fixed. |
| Command line and terminal | Implemented with platform limits | `lib/widgets/terminal_panel.dart`, `docs/terminal.md`; desktop PTY/ConPTY, SSH and sandbox-specific shells. Exact legacy key conventions differ. |
| Quick Open across commands, favorites, devices and rename presets | Partial | `lib/widgets/command_palette.dart` searches commands and opens managers; saved objects are not all direct searchable actions. |
| Custom columns | Implemented | `lib/models/file_view_configuration.dart`, file-view editor; metadata columns and saved profiles. |
| Font/color/theme customization | Implemented | Settings, theme service, file-list font controls and configurable shortcuts. |
| Keyboard control and configurable shortcuts | Implemented | `lib/services/keyboard_shortcut_service.dart`, `lib/screens/keyboard_shortcuts.dart`; text inputs/editors retain input ownership. |
| Show hidden files | Implemented | Pane option, menu and shortcut. |
| Drag/drop between panes and onto folders | Implemented | Captured in-app source/destination review in `lib/services/folder_drop_service.dart`. |
| OS desktop/file-manager drag/drop | Partial | Drop-in exists, but some routes still infer source from pane side; no native drag-out bridge found. |
| Temporary gathering stack | Partial | Source-bound collections gather references from different folders, without a dedicated drop-stack surface. |
| Tags | Partial | Device-local image gallery tags, ratings and labels; not general native file tags. |
| Storage size visualization | Implemented | `lib/services/storage_scan_service.dart`, `docs/storage-analyzer.md`; treemap, sunburst, saved scans and partial-result reporting. |
| Activity and logs | Implemented | Operations panel, transfer history, audit and diagnostic logs. |
| Favorite synchronization across computers | Missing | Favorites can be imported/exported, but no automatic cloud synchronization. |
| Git status and actions | Missing | No integrated status/add/commit/push/pull workflow. |
| Native indexed search | Missing | Recursive application search exists; no OS search-index integration. |
| Process viewer, application removal, default file-manager registration | Missing | These require separate native platform work. |
| Languages and help | Partial | Nine UI locales: English, German, French, Spanish, Portuguese, Chinese, Japanese, Korean and Arabic, with English fallback. User guide is English; the larger requested language set is incomplete. |

## Viewing and editing

| Requested workflow | Baseline status | Evidence and boundary |
| --- | --- | --- |
| Text, hex and binary viewing | Implemented with limits | `lib/services/internal_viewer_service.dart`, `lib/widgets/internal_viewer_dialog.dart`; bounded pages and full-stream search. Remote staging has a 2 GiB cap; rich renderers have smaller limits. |
| UTF-8 and Unicode | Implemented | UTF-8/16/32 plus Latin-1; encoding controls and streaming boundary handling. |
| DOS/Windows legacy text encodings | Missing | CP437 and Windows-1252 are in this branch's scope; selection remains explicit rather than ambiguous auto-detection. |
| Adjustable viewer font/line display | Implemented | Viewer controls include text scale and line/byte display options. |
| Images, HTML, PDF, documents, audio and video | Implemented with format/platform limits | Preview pane and internal viewer; additional embedded editors are independent features. |
| View archive members | Implemented with limits | `lib/services/archive_viewer_service.dart`; bounded extraction and original member identity. |
| Syntax-highlighted internal editor | Implemented | F4 code editor, newline/encoding controls, guarded original-account saves and recovery. |
| Remote editing in built-in editors | Implemented | Captured target and external-change checks. |
| External editor with automatic remote upload on save | Missing | External application launch is currently limited to verified native local files. |
| Image comparison | Partial | Gallery offers linked image comparison; arbitrary external comparison-tool configuration is separate. |

## File operations and search

| Requested workflow | Baseline status | Evidence and boundary |
| --- | --- | --- |
| Recursive copy/move/delete/rename | Implemented | `lib/services/file_operation_service.dart`; reviewed plans, staging, capability checks, cancellation and recovery. |
| Text comparison, merge and binary comparison | Implemented with limits | `lib/services/file_comparison_service.dart`, diff viewer; text merge capped at 8 MiB, binary comparison streams full contents. |
| Local/remote recursive folder comparison and one/two-way sync | Implemented | Directory comparison, sync engine, captured sources and reviewed plans. |
| Folder-to-ZIP sync | Missing | Comparison cannot use an archive as a writable endpoint. |
| UUE/XXE/MIME file encode/decode | Missing | Needs explicit streaming codecs and captured output publication; MIME scope must be defined. |
| Split/combine large files | Implemented | `lib/services/file_split_service.dart`; manifests, hashes and reviewed restart recovery. |
| Duplicate file search | Implemented | Size prefilter followed by full SHA-256 verification in `duplicate_finder_service.dart`. |
| Name/extension/size/date/content selection and search | Implemented | Shared criteria, wildcard/regex modes, saved searches and selections. |
| Restore selection before the last operation | Partial | Manual save/restore exists; automatic pre-operation capture and a numeric-keypad restore shortcut are absent. |
| Full text search across roots and archives | Implemented with limits | Literal streaming search; bounded regex/document/archive extraction. Traversal limits are reported; arbitrary nested/encrypted archive search is incomplete. |
| Multi-rename with rules, editable names and presets | Implemented | Masks, regex, counters, pipelines, collisions/cycles, journals and whole-batch undo. |
| Overwrite previews and custom details | Partial | Conflict choices, sizes/times, text/hash comparison exist; image thumbnails/custom metadata are absent from that dialog. |
| OS access rights | Partial | Ordinary permissions, grants and native metadata are respected; no root/UAC elevation broker. |

## Connections, sharing and transfers

| Requested workflow | Baseline status | Evidence and boundary |
| --- | --- | --- |
| SFTP, WebDAV, S3, B2, Drive, OneDrive, Dropbox, SMB | Implemented | Provider adapters and conformance tests; support varies by platform and backend capability. |
| Multiple connections and cross-server copies | Implemented | Independent source identities and client-mediated streams. |
| FTP and implicit FTPS | Implemented | `ftp_client_adapter.dart`, `ftp_transfer_session.dart`; TLS begins immediately for the saved secure mode. |
| Explicit FTP over TLS | Missing | Existing library supports it, but application configuration and bounded transfer transport do not. Included in this branch's scope. |
| HTTP proxy for HTTP cloud traffic | Implemented | `lib/services/proxy_service.dart`; does not automatically cover direct FTP/SSH sockets. |
| SOCKS5 | Incorrectly exposed | Current setting emits an HTTP `PROXY` directive instead of a SOCKS handshake. Must be corrected before claiming support. |
| SOCKS4 and FTP/SFTP-specific proxies | Missing | Separate socket/protocol adapters are required. |
| FXP | Missing | Cross-server copies currently pass through the application. |
| Resume downloads | Provider-specific | SFTP/SMB and selected cloud adapters have range/resume paths; FTP transfer has no byte-offset restart. Journal recovery is not equivalent to byte resume. |
| Queues, download later, background operations, priority/reorder | Implemented | Durable transfer jobs, scheduled start, waiting/conflict states and history. |
| Transfer bandwidth caps | Partial | Per-operation client-stream pacing exists; separate global upload/download wire limits do not. |
| Sharing and provider links | Implemented with limits | Provider-aware sharing including Dropbox; no local synced-directory-to-Dropbox link resolution. |
| Network neighborhood/discovery | Missing | SMB uses explicit host/share configuration. |
| SCP, AFP, native NFS, Cloud Files provider | Missing | SSH terminal or an optional mount helper is not a native transfer provider. |
| iCloud | Partial | OS-managed files may be reachable through a granted local folder; no dedicated iCloud adapter/favorites synchronization. |
| Encrypted online connections and file encryption | Implemented with provider limits | TLS/SSH, SMB policy and file encryption; see `docs/crypto-audit.md` for exact guarantees. |
| 32-bit and 64-bit desktop releases | Partial | Current Windows/Linux artifacts are x64. No 32-bit desktop build/release target. |
| Parallel-port file transfer | Missing; outside current platform design | Would require legacy native/hardware support. |

## Archive coverage

| Requested workflow | Baseline status | Evidence and boundary |
| --- | --- | --- |
| Browse local/remote archives like folders | Implemented with limits | ZIP, TAR/TGZ, 7z, RAR; bounded BZ2/XZ/ZSTD streams/containers. Native input up to 2 GiB, browser input up to 256 MiB, smaller member/edit budgets. |
| Edit/add/rename/delete/repack archive members | Implemented for selected formats | `lib/services/archive_workspace.dart`; ZIP, 7z, TAR and TGZ/TAR.GZ, verified original-container saves. |
| Create an archive | Partial | Existing new-archive context action is native local ZIP only, without options. Reviewed options are in this branch's scope. |
| Password-protected archive input | Implemented | ZIP/7z/RAR reading and encrypted ZIP/7z repack preserve original protection. |
| Password/compression settings for new archives | Missing | Included in this branch's scope where supported by the existing writer. |
| Large archive packing in a background worker | Missing | Current creation/repack is bounded and in-process, not a queued streaming worker. |
| Direct archive-to-archive transfer | Missing | Copy-out exists; writable archive endpoints are not connected to the general transfer planner. |
| Additional packer plugins and legacy binary plugins | Partial/missing | First-party extension/custom-command interfaces exist; no legacy binary plugin ABI or general external-packer bridge. |
| Remaining archive-format breadth | Missing | No complete native dispatch for ARJ/LZH/CAB/ACE/UC2, RPM/CPIO/DEB, ISO/XAR/XIP or all ZIP-derived aliases/raw LZMA. Requires format-by-format implementation and license/limit review. |

## Verification record

The baseline audit was source-based. Implementation test results and remaining
runtime checks will be added after each feature checkpoint. The repository
targets Flutter 3.47.8/Dart 3.13; using an older cached SDK is not equivalent to
testing the supported application toolchain.
