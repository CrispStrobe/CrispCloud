# File manager capability audit and implementation

Audit date: 12 November 2026. Baseline: `4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c`.
Initial implementation branch: `feature/file-manager-capabilities-20261112`.
Follow-up branches and current evidence: [gap closure register](file-manager-gaps/README.md).

This audit compares the requested workflow ideas with application code and
focused tests. The initial increment table retains the historical baseline;
the feature matrices describe the current stacked implementation. **Implemented**
means that an application workflow exists in source, not that every provider,
platform or file size has passed live acceptance. Historical checklists are not
used as proof. Repeated requests are consolidated below. Observed validation
results and remaining acceptance limits are recorded at the end of this file.

## Initial implementation increments

| Increment | Baseline | Branch review status | Delivered behavior and evidence |
| --- | --- | --- | --- |
| DOS CP437 and Windows-1252 | Missing | Implemented; focused tests passed | Explicit decoding, editing, strict save conversion and content search share `lib/services/legacy_text_encoding.dart`. Viewer, editor and search controls expose both encodings. |
| Configurable archive creation | Local ZIP without options | Implemented; focused tests passed | Captured native local selections; ZIP, 7z, TAR and TAR.GZ; actual compression choices; ZIP/7z encryption; verified, exclusive publication. See [archive creation](archive-creation.md). |
| Explicit FTP over TLS and certificate enforcement | Implicit TLS existed; explicit mode was unavailable | Implemented; focused tests passed | Explicit, implicit and plain modes; legacy mode/port preservation; verified control and data TLS; rejected TLS negotiation cannot fall back to plaintext. See [FTP transport](ftp-transport.md). |
| Automatic selection memory | Manual save/restore only | Implemented; focused tests passed | Delayed capture after an accepted copy/move queue entry or successful mutation; original tab/source checks; configurable Numpad `/` restoration. See [selection memory](selection-memory.md). |
| Synchronized browsing | Missing | Implemented; focused tests passed | Relative navigation below two captured roots, with session/tab/root guards and a visible stop reason. See [synchronized browsing](synchronized-browsing.md). |
| SOCKS5 for native HTTP/HTTPS clients | Setting incorrectly emitted an HTTP proxy directive | Implemented; focused tests passed | Real CONNECT handshake, optional username/password authentication, remote destination DNS, verified HTTPS and bounded cancellation. See [proxy routing](proxy-routing.md). Direct FTP/SFTP/SMB and browser traffic remain outside this setting. |

These changes reuse existing permissive libraries and first-party application
code. No new external dependency was added. The existing MIT-licensed FTP
metadata runtime is retained locally under `packages/ftpconnect`; its upstream
version and the certificate/data-protection changes are documented in
[`UPSTREAM.md`](../packages/ftpconnect/UPSTREAM.md). Archive writers use the
existing `archive` and `koni_archive` dependencies.

### Boundaries of the new workflows

Legacy encodings are chosen explicitly; ambiguous bytes do not trigger a
code-page guess. ASCII controls retain their text meaning. Undefined
Windows-1252 slots retain their byte identity, and saving a character that the
selected code page cannot represent fails instead of substituting a byte.
Existing viewer/editor size limits still apply. Plain-file literal content
search streams the file; regex, document and archive content searches retain
their extraction budget, 64 MiB by default and configurable up to 256 MiB in
`FileSearchQuery`.

New archive creation is native local and bounded: 64 MiB per source file,
256 MiB total source content and packed output, 200,000 entries, 200 folder
levels and 8 MiB of member-path text. TAR.GZ additionally limits its decoded
TAR container, including headers, to 64 MiB so the normal viewer can read the
result. ZIP and TAR.GZ offer levels 0, 1, 6 and 9. The 7z writer exposes Store,
Deflate and LZMA2 methods, not numeric levels. ZIP/7z use AES-256; only 7z offers
encrypted filenames. Unsupported security options are rejected. Cancellation
is observed at checkpoints; packing is buffered and not a large-file
background worker.

FTP remains a native passive-mode transport. Both secure modes verify the
control and data certificates against the platform/Dart trust configuration.
The HTTP custom-CA setting does not change FTP trust. Browser FTP, FTP-specific
proxies and FXP remain gaps. **G25 adds verified native byte-offset download
resume**, durable retained stages and verified cleanup; selected real-server
interoperability remains pending. See [FTP resume](ftp-resume.md). Existing secure connections
retain implicit TLS and their saved port; new connections default to explicit
TLS. Details and migration rules are in [FTP transport](ftp-transport.md).

Selection memory is per-session and bound to the original tab, account,
connection and grant. Automatic snapshots are limited to 100,000 entries and
4 MiB of metadata. Restoring marks does not undo a move, rename or deletion.
Synchronized browsing only navigates: it does not create directories or copy
contents. It stops for a missing/inaccessible counterpart, a link explicitly
reported by a remote provider, a changed source/tab/session, a locked tab, or
navigation outside a chosen root. Root containment uses displayed paths;
local directory links follow normal filesystem rules within existing access
grants. The link is transient and is not restored after restarting the app.

## Workspace, display and navigation

| Requested workflow | Current status | Evidence and boundary |
| --- | --- | --- |
| Dual panes, tabs, brief/details/grid/thumbnail views | Implemented | `lib/widgets/file_panel.dart`, `lib/models/file_view_configuration.dart`; independent local or remote pane sources. |
| History, favorites and saved workspaces | Implemented | `lib/providers/bookmarks_provider.dart`, `lib/providers/workspace_provider.dart`; source-bound tabs, groups and paired bookmarks. |
| Synchronized browsing | Implemented | `lib/services/synchronized_browsing_service.dart`, provider and pane controls map relative navigation between captured roots. Missing counterparts stop the link without creating folders. See [synchronized browsing](synchronized-browsing.md). |
| Configurable buttons and external commands with arguments | Implemented | `lib/widgets/file_command_toolbar.dart`, `lib/services/custom_toolbar_command_service.dart`; saved command/argument templates and review. |
| Configurable main menu | Implemented / target-runtime acceptance pending | **Added in G04.** Saved command-based menu trees, user-command references, preview/reset/import/export and mandatory recovery controls; native presentation remains a target-runtime check. See [main menus](main-menus.md). |
| Command line and terminal | Implemented with platform limits / command-entry native acceptance pending | **G09 adds reviewed command entry:** typed or saved programs, bounded PATH lookup, immutable literal arguments and scoped filename/path insertion from the captured ordinary local pane. See [command entry](command-entry.md). The separate terminal retains desktop PTY/ConPTY, SSH and sandbox-specific shells. |
| Preferred external terminal application | Implemented / native acceptance pending | **Added in G12.** Per-OS configuration and reviewed launch at the captured local folder, with literal arguments and stale-request checks. See [external terminal](external-terminal.md). Actual terminal-window acceptance remains per OS. |
| Quick Open across commands, favorites, devices and rename presets | Implemented | **Added in G02.** Saved paths, sources, existing devices, workspaces and rename presets are direct searchable actions with captured identity and unavailable-target handling. See [Quick Open](quick-open.md). |
| Custom columns | Implemented | `lib/models/file_view_configuration.dart`, file-view editor; metadata columns and saved profiles. |
| Font/color/theme customization | Implemented | Settings, theme service, file-list font controls and configurable shortcuts. |
| Keyboard control and configurable shortcuts | Implemented | `lib/services/keyboard_shortcut_service.dart`, `lib/screens/keyboard_shortcuts.dart`; text inputs/editors retain input ownership. |
| Show hidden files | Implemented | Pane option, menu and shortcut. |
| Drag/drop between panes and onto folders | Implemented | Captured in-app source/destination review in `lib/services/folder_drop_service.dart`. |
| OS desktop/file-manager drag/drop | Partial | **Incoming routing completed in G01:** captured source/destination copy review supports native files/trees and browser handles/manifests in either pane. Real OS/browser acceptance is pending; native drag-out remains G06. See [incoming drops](external-drops.md). |
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

| Requested workflow | Current status | Evidence and boundary |
| --- | --- | --- |
| Text, hex and binary viewing | Implemented with limits | `lib/services/internal_viewer_service.dart`, `lib/widgets/internal_viewer_dialog.dart`; bounded pages and full-stream search. Remote staging has a 2 GiB cap; rich renderers have smaller limits. |
| UTF-8 and Unicode | Implemented | UTF-8/16/32 plus Latin-1; encoding controls and streaming boundary handling. |
| DOS/Windows legacy text encodings | Implemented | `lib/services/legacy_text_encoding.dart`, `editor_document.dart`, `viewer_text_decoder.dart`, `viewer_search_service.dart` and `search_content_matcher.dart` share explicit CP437/Windows-1252 behavior. Strict editing rejects unrepresentable characters; there is no code-page auto-detection. Existing [editor](code-editor.md) and [file-operation/search](commander-file-operations.md) limits remain. |
| Adjustable viewer font/line display | Implemented | Viewer controls include text scale and line/byte display options. |
| Images, HTML, PDF, documents, audio and video | Implemented with format/platform limits | Preview pane and internal viewer; additional embedded editors are independent features. |
| View archive members | Implemented with limits | `lib/services/archive_viewer_service.dart`; bounded extraction and original member identity. |
| Syntax-highlighted internal editor | Implemented | F4 code editor, newline/encoding controls, guarded original-account saves and recovery. |
| Remote editing in built-in editors | Implemented | Captured target and external-change checks. |
| External editor with automatic remote upload on save | Missing | External application launch is currently limited to verified native local files. |
| Image comparison | Partial | Gallery offers linked image comparison; arbitrary external comparison-tool configuration is separate. |

## File operations and search

| Requested workflow | Current status | Evidence and boundary |
| --- | --- | --- |
| Recursive copy/move/delete/rename | Implemented | `lib/services/file_operation_service.dart`; reviewed plans, staging, capability checks, cancellation and recovery. |
| Text comparison, merge and binary comparison | Implemented with limits | `lib/services/file_comparison_service.dart`, diff viewer; text merge capped at 8 MiB, binary comparison streams full contents. |
| Local/remote recursive folder comparison and one/two-way sync | Implemented | Directory comparison, sync engine, captured sources and reviewed plans. |
| Folder-to-ZIP sync | Missing | Comparison cannot use an archive as a writable endpoint. |
| UUE/XXE/MIME file encode/decode | Implemented for documented formats and capable destinations | **Added in G13.** Streaming UUE/XXE and single-part Base64 MIME, strict input validation, verified exclusive output and explicit new filenames. Multipart/quoted-printable MIME and unsafe destination backends are unavailable. See [file conversion](file-conversion.md). |
| Split/combine large files | Implemented | `lib/services/file_split_service.dart`; manifests, hashes and reviewed restart recovery. |
| Duplicate file search | Implemented | Size prefilter followed by full SHA-256 verification in `duplicate_finder_service.dart`. |
| Name/extension/size/date/content selection and search | Implemented | Shared criteria, wildcard/regex modes, saved searches and selections. |
| Restore selection before the last operation | Implemented | Automatic delayed capture for accepted copy/move jobs and successful delete/trash/rename/archive creation; Restore Selection in the menu/palette and configurable Numpad `/`. Missing or replaced original rows are skipped. See [selection memory](selection-memory.md). |
| Full text search across roots and archives | Implemented with limits | Literal streaming search; bounded regex/document/archive extraction. Traversal limits are reported; arbitrary nested/encrypted archive search is incomplete. |
| Multi-rename with rules, editable names and presets | Implemented | Masks, regex, counters, pipelines, collisions/cycles, journals and whole-batch undo. |
| Overwrite previews and custom details | Implemented for bounded previews | **Added in G03.** Paired bounded image thumbnails and safe metadata retain original source identities and reject stale versions. Existing decisions and text/hash comparisons remain. See [conflict review](conflict-review.md). |
| OS access rights | Partial | Ordinary permissions, grants and native metadata are respected; no root/UAC elevation broker. |

## Connections, sharing and transfers

| Requested workflow | Current status | Evidence and boundary |
| --- | --- | --- |
| SFTP, WebDAV, S3, B2, Drive, OneDrive, Dropbox, SMB | Implemented | Provider adapters and conformance tests; support varies by platform and backend capability. |
| Multiple connections and cross-server copies | Implemented | Independent source identities and client-mediated streams. |
| FTP and implicit FTPS | Implemented | `ftp_client_adapter.dart`, `ftp_transfer_session.dart`; implicit TLS still begins before the greeting. Certificate/data-protection enforcement covers transfer and metadata paths. **G37 adds physical TCP/TLS cleanup on deadline or owner close/logout**, proven by peer-closure fixtures. See [FTP transport](ftp-transport.md). |
| Explicit FTP over TLS | Implemented | Saved security mode, localized selector and port migration; `AUTH TLS` before login, followed by verified TLS and protected passive data channels. Failed negotiation and invalid certificates stop the connection. |
| HTTP proxy for HTTP cloud traffic | Implemented | `lib/services/proxy_service.dart`; does not automatically cover direct FTP/SSH sockets. |
| SOCKS5 | Implemented for native HTTP/HTTPS | The shared `socks_connector.dart` transport retains the `socks5_connector.dart` entry point for native HTTP/HTTPS tunneling. Scope includes CONNECT, remote DNS, optional password authentication and configured host bypasses. UDP, direct FTP/SSH/SMB and browser transport remain outside this setting. |
| SOCKS4/4a HTTP routing | Implemented for native HTTP/HTTPS | **Added in G27.** Explicit local IPv4 versus remote DNS, bounded user IDs, strict HTTPS trust and no automatic fallback. All 197 focused proxy/security tests passed, including the native-parser host validation regression; see [proxy routing](proxy-routing.md). |
| FTP/SFTP-specific proxies | Missing | Separate protocol/socket adapters remain scoped in G28. |
| FXP | Missing | Cross-server copies currently pass through the application. |
| Resume downloads | Provider-specific; FTP implemented / live acceptance pending | **Added in G25.** Native FTP uses negotiated binary offsets, captured source/connection evidence, verified prefixes and a full assembled-content digest before publication. Durable partial references survive retries and are cleaned only after verified publication. Upload resume and selected live-server acceptance remain separate. See [FTP resume](ftp-resume.md). |
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

| Requested workflow | Current status | Evidence and boundary |
| --- | --- | --- |
| Browse local/remote archives like folders | Implemented with limits | ZIP, TAR/TGZ, 7z, RAR; bounded BZ2/XZ/ZSTD streams/containers. Native input up to 2 GiB, browser input up to 256 MiB, smaller member/edit budgets. |
| Edit/add/rename/delete/repack archive members | Implemented for selected formats | `lib/services/archive_workspace.dart`; ZIP, 7z, TAR and TGZ/TAR.GZ, verified original-container saves. |
| Create an archive | Implemented for bounded native local inputs | The native local context action opens a reviewed ZIP/7z/TAR/TAR.GZ dialog with a captured selection and destination. Source hashes, decoded contents and staged output are checked before exclusive publication. Remote/browser creation remains G23. See [archive creation](archive-creation.md). |
| Password-protected archive input | Implemented | ZIP/7z/RAR reading and encrypted ZIP/7z repack preserve original protection. |
| Password/compression settings for new archives | Implemented for supported formats | ZIP/TAR.GZ compression levels, 7z compression methods, ZIP/7z AES-256 and optional 7z filename encryption. TAR/TAR.GZ do not offer password protection. Passwords are not persisted. Exact limits are in [archive creation](archive-creation.md). |
| Large archive packing in a background worker | Missing | Current creation/repack is bounded and in-process, not a queued streaming worker. |
| Direct archive-to-archive transfer | Missing | Copy-out exists; writable archive endpoints are not connected to the general transfer planner. |
| Additional packer plugins and legacy binary plugins | Partial/missing | First-party extension/custom-command interfaces exist; no legacy binary plugin ABI or general external-packer bridge. |
| Remaining archive-format breadth | Missing | No complete native dispatch for ARJ/LZH/CAB/ACE/UC2, RPM/CPIO/DEB, ISO/XAR/XIP or all ZIP-derived aliases/raw LZMA. Requires format-by-format implementation and license/limit review. |

## Remaining implementation opportunities

The complete follow-up scope is maintained in the [gap closure register](file-manager-gaps/README.md): 51 stable items across six implementation lanes, each with dependencies, explicit boundaries and acceptance checks. Follow that register for ongoing implementation status and separately named acceptance requirements.

The selected lanes below record delivered increments alongside concrete work
still needed. A scoped item is a proposal with acceptance criteria; only an
explicitly implemented or closed entry claims delivered behavior.

| Opportunity | Concrete work still needed |
| --- | --- |
| Overwrite image previews and richer file details | **Completed in G03.** Paired bounded previews and safe metadata retain original source/destination identity, reject stale versions and cancel late work. See [conflict review](conflict-review.md) and the [closure evidence](file-manager-gaps/01-workspace-and-interaction.md#g03). |
| Quick Open for saved objects | **Completed in G02.** Direct actions retain source identity, validate original tab restoration and open rename review without mutations. See [Quick Open](quick-open.md). |
| Configurable main-menu structure | **Implemented in G04.** Validated command identifiers and layouts, inactive preview, reset/import/export and last-valid recovery are covered by the 96-test menu integration gate. Native presentation remains G50/G51. See [main menus](main-menus.md). |
| Temporary gathering stack | Build a dedicated drop/collect surface on existing source-bound collections; preserve original references until a reviewed transfer succeeds. |
| UUE/XXE/MIME file conversion | **Completed in G13 for the documented formats.** All 80 codec/service/dialog tests passed, including real native exclusive publication. Single-part Base64 MIME and backend capability limits remain explicit. See [file conversion](file-conversion.md). |
| Folder-to-archive sync and archive-to-archive transfer | Add writable archive endpoints to comparison/transfer planning, preserve passwords and container identity, and verify/repack the original container before reporting success. |
| Larger background archive jobs | Move bounded packing to a cancellable worker or streaming spool, add durable queue/recovery behavior, and validate output without whole-container buffering. |
| Additional archive formats | Review reader/writer capability, limits, licensing and malformed-input handling individually. Read-only support does not imply editable or creatable archives. |
| External editor with remote save/upload | Stage a source-bound file, track editor changes and require safe conflict handling before uploading to the original account/path. |
| FTP resume, FXP and additional proxy modes | **G25 download resume implemented:** negotiated offsets plus verified source/prefix/assembled contents and retained-stage cleanup. Record selected live-server acceptance; implement FXP and direct-protocol proxy modes independently. |
| Favorite synchronization | Define account, encryption and merge semantics for portable favorites without copying local access grants or credentials to another computer. |
| Git integration | Add repository discovery, per-file status and reviewed add/commit/push/pull actions with command cancellation and credential handling. |
| Broader localization and help | Translate remaining UI/help content and validate layout, shortcuts and terminology for each newly supported locale. |

### Larger platform-dependent projects

Native drag-out, general filesystem tags, OS indexed search, share-sheet/default
file-manager integration, process control, application removal and elevated
operations require separate platform bridges, permission behavior and device
tests. Network discovery and native SCP/AFP/NFS/Cloud Files providers require
their own transport/capability implementations; accessing a mounted directory
does not establish a native provider. Dedicated iCloud integration and favorite
sync require Apple-specific account/container work. Existing mount experiments
retain the boundaries documented in [the mount and license audit](fuse_and_license_audit.md).

32-bit desktop distribution requires compatible plugin/native-library builds
and release CI; an x64 build does not establish 32-bit support. Parallel-port
transfer requires a separate legacy hardware/runtime project. Legacy binary
plugin compatibility requires an ABI host and platform/bitness isolation; the
application's own extension interfaces do not supply that compatibility.

## Initial implementation validation record

The final integrated feature suite passed **538 tests across 30 test files** on
Flutter **3.47.8** and Dart **3.13.7**. A separate navigation/workspace regression
run passed **113 tests across 10 files**; some navigation tests are included in
both runs, so these counts must not be added as a unique-test total.

The integrated feature suite and release web build exercised code checkpoint
`4cb57c839034bf3a9d96513bb51c69933639a3bb`. A later cleanup localizes neutral
rename-mode labels and removes an inherited comment; saved preset keys and
file-operation/transport behavior are unchanged. The rename dialog was checked
again after that cleanup. Initial test failures exposed an FTP port-normalization
edge case, IPv6 bypass comparison, and two test-fixture setup assumptions. Those
were corrected before the passing integrated run.

| Scope | Observed validation | Result |
| --- | --- | --- |
| Legacy encodings | Codec byte roundtrips, strict save conversion, viewer/editor controls, comparison, streaming viewer and content search | Passed in the 538-test integrated suite |
| Archive creation | ZIP/7z/TAR/TAR.GZ roundtrips, compression/encryption, source changes, cancellation, size limits, duplicate names and corrupt staged output | Passed in the integrated suite |
| FTP TLS and migration | Real loopback control/data TLS, certificate and negotiation rejection, transfer bytes, legacy mode/port preservation, malformed identities and localized controls | Passed in the integrated suite |
| Selection memory and keyboard routing | Operation acceptance/failure behavior, rename journals, paged selections, queue/rename dialogs, menu and keyboard dispatch | Passed in the integrated suite |
| Synchronized browsing | Service, actual pane-controller and narrow/localized UI tests; source/session/tab/root changes, missing counterparts, newer navigation, noninteractive access and cancellation | Passed in the integrated suite |
| HTTP/HTTPS SOCKS5 | Real loopback HTTP/HTTPS, auth, remote DNS, IP address types, certificate rejection, fragmentation, coalesced bytes, paused transfer streams, timeout/cancellation, bypasses and restored settings | Passed in the integrated suite |
| Final neutral UI naming | Existing rename-dialog regression suite after localized label cleanup; saved preset variant order retained | 26 tests passed; label helper analysis reported no issues |
| Existing navigation/workspace behavior | Guarded navigation, history recovery, refresh lifecycle, source restoration, tabs, headers and recovery UI | 113 tests passed in the separate regression run |
| Full application static analysis | `flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos`, matching the repository's error gate | Passed with **0 errors**; 99 warnings and 1,101 informational findings remain reported across the repository |
| Release web compilation | Version/hash injected: `APP_VERSION=1.1.0+12`, `GIT_HASH=4cb57c8` | Passed: JavaScript release output produced. The optional WebAssembly dry run returned exit 247; WebAssembly is not validated. |
| Hosted CI | Feature-branch workflows are triggered by the pushed checkpoints | Queued at the last inspection; completion is not claimed |
| Signed/native and live-provider acceptance | Windows/macOS/mobile UI, platform access grants and external provider/server configurations | Not performed in this workspace |

The focused synchronized-browsing files and the archive, FTP and proxy
implementation lanes also passed targeted analysis without errors or warnings.
`git diff --check` passed. The full-repository analyzer is **not** a lint-clean
report: the warning/information counts above remain visible and are permitted
by the existing CI gate.

Loopback tests do not establish every server's interoperability, signed
application behavior or acceptance on all native platforms. The JavaScript
release web build succeeded. Its optional WebAssembly dry run
failed with exit 247, so this report does not establish WebAssembly support.
Compilation does not establish browser behavior for every workflow.
FTP-specific proxies and FXP remain absent. G25 now adds native verified download
resume, with live-server acceptance pending. G37 adds
observed physical FTP transport cleanup during stalled TLS negotiation,
including pending login and data channels. Owner close/logout and deadlines
are covered; generic pre-subscription queue-stop propagation retains the
separate [FTP API boundary](ftp-transport.md).

## Follow-up gap closure validation

All 51 remaining gap scopes are recorded in six lane documents. Eight further
implementation increments are preserved on remote feature branches: five closed
scopes (G02, G03, G13, G27, G37), and three implemented features with named
target-runtime acceptance pending (G01, G04, G12). The remaining 43 items are
31 scoped implementations, ten research prerequisites and two cross-cutting
acceptance items.

The [follow-up validation record](file-manager-gaps/validation-20261112.md)
contains the branch/PR checkpoints and individual test gates. Counts from
overlapping gates are not added together. The final conversion gate passed 80
tests; the final proxy/security gate passed 197. Full application analysis
completed with **0 errors, 96 warnings and 1,038 informational findings** under
the existing nonfatal warning/info gate.

The integrated **JavaScript release web build passed** for code checkpoint
`ebede8d596e8a5f83cf78ccd420573505a2e4531`, with `APP_VERSION=1.1.0+12` and
`GIT_HASH=ebede8d`. Its optional WebAssembly dry run again exited 247. Browser
runtime, WebAssembly, signed/native and live-provider acceptance remain open.
The current feature branch checks were queued at inspection; hosted CI success
is not claimed. No new dependency was introduced in these eight increments.
