# File manager gap closure plan

Date: 12 November 2026. Scope baseline: `28b7b9ce388e08345aa995037256ab50ab0e17b9`.
Scope branch: `feature/file-manager-gap-closure-20261112`.
Implementation branches and evidence are recorded in the checkpoint ledger.

This plan covers every missing or partial capability from the requested file-manager
feature inventory and the preceding [source audit](../file-manager-capability-audit.md).
It scopes implementation and acceptance separately. Existing features and the six
completed increments in the preceding branch are preserved; repeated requests
are consolidated into the stable gap identifiers below.

## Status and closure rules

- **Scoped:** implementation boundaries and acceptance checks are defined; work is not complete.
- **Implementing:** a concrete increment is being prepared; closure still requires validation and a remote checkpoint.
- **Partially implemented:** a verified increment is pushed, while named parts of the feature still require implementation.
- **Implemented / acceptance pending:** the stated code scope is verified locally and pushed; named platform or live-server checks remain.
- **Closed:** all listed deliverables and required acceptance checks have observed evidence.
- **Research:** a specific architecture, licensed implementation, runtime or hardware prerequisite must be resolved before a support claim.

Each increment must capture source/account/tab identity before asynchronous work,
preserve explicit review for mutations, and fail without switching to another source.
New dependencies require a recorded permissive license and version/provenance.
No credentials or device-local access grants belong in portable settings.

Root-owned integration closes one gap at a time. Independent preparation and review
may run in parallel. Push the scope first, then each coherent implementation/fix
checkpoint, then its validation and status update. Use leased fast-forward updates;
preserve earlier feature branches and do not rewrite or merge the main branch.

## Current progress

Fourteen feature scopes have reached implementation on remote feature branches:
**seven closed scopes** (G02, G03, G05, G13, G27, G37, G49) and **seven implemented features
with target-runtime/live-server acceptance pending** (G01, G04, G09, G10, G11, G12, G25).
The remaining 37 items
comprise **25 implementation gaps, 10 research prerequisites and two
cross-cutting acceptance items**. The acceptance work also applies to delivered
features where their specific boundary names a target-runtime check.

G18 additionally has a delivered native local archive workflow, and G14 has a
delivered native viewer-preparation lifecycle increment. Both remain in the
25 implementation gaps: remote/browser archive publication and verified remote
paging/larger text comparison still require code, alongside native acceptance.
G29 also has a [qualified foreground native HTTP increment](transfer-bandwidth-http-profile.md)
with persisted shared limits and Activity counters. Its remaining provider paths,
direct protocols and background ownership keep it in the implementation gaps;
the separate browser helper acceptance is recorded with its evidence.

The [12 November validation record](validation-20261112.md) separates passing
unit/widget/native-loopback evidence, static analysis, JavaScript compilation,
the unsuccessful optional WebAssembly dry run and outstanding native/live checks.
The current stack contains the original scope and every incremental checkpoint.

Continuation work from `403e942d` is recorded in
[the active increment plan](continuation-20261112.md). G25 has verified native
loopback/recovery coverage, and G09 has verified command/keyboard coverage.
G05's reviewed reference workflow and G49's maintained three-language offline
help are closed with their separate regression evidence and remote checkpoints.

The [external tools and archive continuation](continuation-tools-archives-20261112.md)
starts from `d76fe9b`. G10's retained remote editor sessions and G11's reviewed
external comparison workflow are implemented with native/live acceptance pending.
G10 conditionally publishes Dropbox revisions; other bounded-download sources
support independent copies only. G18 now connects reviewed native archive
imports, member edits and explicit recovery to pane, clipboard and menu actions.
Shared retained staging and archive publication have separate verified
foundation checkpoints.

The [viewer preparation continuation](viewer-spool-continuation-20261112.md)
adds bounded cancellation, source/version checks and retryable temporary-copy
cleanup to the existing native viewer spool. Its partial G14 boundary retains
the existing size limits and does not claim immutable provider snapshots.

## Lane index

| Lane | Scope | Items |
| --- | --- | --- |
| [Workspace and interaction](01-workspace-and-interaction.md) | G01–G09 | 9 |
| [Viewing, search and tools](02-viewing-search-and-tools.md) | G10–G17 | 8 |
| [Archives and containers](03-archives-and-containers.md) | G18–G24 | 7 |
| [Connections and transfers](04-connections-and-transfers.md) | G25–G38 | 14 |
| [Native platforms and release](05-native-platforms-and-release.md) | G39–G47 | 9 |
| [Localization and acceptance](06-localization-and-acceptance.md) | G48–G51 | 4 |

## Ordered gap register

| ID | Feature | Status | Dependency / next boundary |
| --- | --- | --- | --- |
| [G01](01-workspace-and-interaction.md#g01) | Source-bound incoming drops | Implemented / target-runtime acceptance pending | Real OS/browser drag sessions under G50/G51 |
| [G02](01-workspace-and-interaction.md#g02) | Direct Quick Open actions | Closed: direct saved-item workflow | New network discovery remains G30 |
| [G03](01-workspace-and-interaction.md#g03) | Conflict previews and details | Closed: bounded preview scope | Platform decoder support remains explicit |
| [G04](01-workspace-and-interaction.md#g04) | Configurable main menus | Implemented / target-runtime acceptance pending | Native menu presentation and keyboard dispatch under G50/G51 |
| [G05](01-workspace-and-interaction.md#g05) | Gathering stack | Closed: reviewed reference workflow | Explicit collection commands; native drag-out remains G06 |
| [G06](01-workspace-and-interaction.md#g06) | Native outgoing drag | Scoped | G01; native bridge |
| [G07](01-workspace-and-interaction.md#g07) | General file tags | Scoped | Stable file identity; native metadata bridge |
| [G08](01-workspace-and-interaction.md#g08) | Favorite synchronization | Scoped | Versioned favorites; selected sync backend |
| [G09](01-workspace-and-interaction.md#g09) | Command entry and keyboard conventions | Implemented / native acceptance pending | Captured local commands and scoped insertion verified; actual OS behavior under G50 |
| [G10](02-viewing-search-and-tools.md#g10) | External remote editing | Implemented / native and live acceptance pending | Retained sessions and Dropbox revision-guarded publication; further provider contracts remain explicit |
| [G11](02-viewing-search-and-tools.md#g11) | External comparison tools | Implemented / native acceptance pending | Private-copy workflow verified; installed GUI tools under G50 |
| [G12](02-viewing-search-and-tools.md#g12) | Preferred external terminal | Implemented / native acceptance pending | Verify installed terminals on each claimed desktop OS |
| [G13](02-viewing-search-and-tools.md#g13) | UUE, XXE and MIME conversion | Closed: documented streaming formats | Single-part Base64 MIME; verified exclusive-output backends only |
| [G14](02-viewing-search-and-tools.md#g14) | Large-file viewer and comparison limits | Partially implemented: native preparation lifecycle | Provider-enforced snapshots/ranges; async paging; large text comparison |
| [G15](02-viewing-search-and-tools.md#g15) | Nested and encrypted archive search | Scoped | G18 archive identity; reader capabilities |
| [G16](02-viewing-search-and-tools.md#g16) | Native indexed search | Scoped | Native search bridge |
| [G17](02-viewing-search-and-tools.md#g17) | Additional viewer adapters | Scoped | Existing viewer dispatch; extension review |
| [G18](03-archives-and-containers.md#g18) | Writable archive endpoints | Partially implemented: native local workflow | Remote access-policy contracts; browser operation leases; native acceptance |
| [G19](03-archives-and-containers.md#g19) | Directory-to-archive synchronization | Partially implemented: reviewed native one-way synchronization | Two-way baselines; nested destinations; remote/browser publication; native acceptance |
| [G20](03-archives-and-containers.md#g20) | Archive-to-archive transfer | Partially implemented: reviewed copy and native top-level moves | Nested cross-container routes; remote/browser publication; native acceptance |
| [G21](03-archives-and-containers.md#g21) | Large background archive jobs | Partially implemented: bounded native foreground TAR/CBT and data-image creation | Durable packing queue/restart; larger existing edits; platform/provider acceptance |
| [G22](03-archives-and-containers.md#g22) | Archive format coverage | Partially implemented: readers, writers and integrity checks | Remaining profiles; format/license review; native acceptance |
| [G23](03-archives-and-containers.md#g23) | Remote and browser archive creation | Scoped | G18; G21 where streaming is required |
| [G24](03-archives-and-containers.md#g24) | External packer adapters | Scoped | G17 extension isolation |
| [G25](04-connections-and-transfers.md#g25) | FTP byte-offset resume | Implemented / live-server acceptance pending | Native loopback/recovery verified; selected server interoperability under G50 |
| [G26](04-connections-and-transfers.md#g26) | Server-to-server FTP transfer | Scoped | G25 transfer evidence; server support |
| [G27](04-connections-and-transfers.md#g27) | SOCKS4 HTTP routing | Closed: native HTTP/HTTPS scope | Direct-protocol proxy work remains G28 |
| [G28](04-connections-and-transfers.md#g28) | Direct-protocol proxy routing | Scoped | Per-protocol socket factories |
| [G29](04-connections-and-transfers.md#g29) | Global transfer bandwidth limits | Partially implemented: foreground HTTP | Shared transfer scheduler |
| [G30](04-connections-and-transfers.md#g30) | Network volume discovery | Scoped | Native discovery adapters |
| [G31](04-connections-and-transfers.md#g31) | SCP provider | Scoped | SSH host verification; streaming adapters |
| [G32](04-connections-and-transfers.md#g32) | AFP provider | Platform research | Permissive implementation; target server/OS |
| [G33](04-connections-and-transfers.md#g33) | Native NFS provider | Platform research | Permissive implementation; target server/OS |
| [G34](04-connections-and-transfers.md#g34) | Cloud Files provider | Scoped | Account/API compatibility fixtures |
| [G35](04-connections-and-transfers.md#g35) | Managed cloud filesystem integration | Platform research | Apple entitlements; target device |
| [G36](04-connections-and-transfers.md#g36) | Local synced-file sharing links | Scoped | Provider/account mapping; explicit share capability |
| [G37](04-connections-and-transfers.md#g37) | FTP stalled-handshake cleanup | Closed: owned transport scope | Generic pre-subscription queue-stop propagation remains explicit |
| [G38](04-connections-and-transfers.md#g38) | Browser protocol access | Architecture research | Gateway deployment/trust model |
| [G39](05-native-platforms-and-release.md#g39) | Native share targets | Scoped | Native share bridge |
| [G40](05-native-platforms-and-release.md#g40) | Default file-viewer registration | Platform research | Packaging/registration per OS |
| [G41](05-native-platforms-and-release.md#g41) | Process viewer | Scoped | Native process metadata/control |
| [G42](05-native-platforms-and-release.md#g42) | Application removal | Platform research | Platform ownership and protected-path rules |
| [G43](05-native-platforms-and-release.md#g43) | Privileged file operations | Platform research | Platform privilege service and signing |
| [G44](05-native-platforms-and-release.md#g44) | Git workspace integration | Scoped | Installed Git; credential and conflict handling |
| [G45](05-native-platforms-and-release.md#g45) | 32-bit desktop distribution | Toolchain research | Compatible Flutter/Dart and native dependencies |
| [G46](05-native-platforms-and-release.md#g46) | Direct cable transfer | Hardware research | Hardware/protocol fixtures; compatible runtime |
| [G47](05-native-platforms-and-release.md#g47) | Native binary extension compatibility | Architecture research | ABI specification; bitness/OS hosts; license review |
| [G48](06-localization-and-acceptance.md#g48) | UI language coverage | Scoped | Terminology review; localization inventory |
| [G49](06-localization-and-acceptance.md#g49) | Localized help | Closed: English/German/French offline guides | 23 aligned topics; nine-language controls; more guide languages remain future work |
| [G50](06-localization-and-acceptance.md#g50) | Native and live-provider acceptance | Acceptance pending | Target machines; explicit test accounts and fixtures |
| [G51](06-localization-and-acceptance.md#g51) | Web runtime and WebAssembly acceptance | Acceptance pending | Browser test harness; dependency compatibility |

## Execution order

1. Continue workspace interactions with G05 gathering stack, then G09 command entry using the delivered G01/G04 foundations.
2. Add G10 external remote editing before G11 external comparison/merge-back staging; implement G14–G17 within their stated resource and platform boundaries.
3. Add G18 writable archive endpoints before G19/G20 transfer and synchronization integration; preserve the separate G21–G24 format, worker and adapter boundaries.
4. Continue G25 FTP resume, G26 server-to-server transfer, G28 direct-protocol proxies and G29 global bandwidth allocation, then remaining provider work as its prerequisites become available.
5. Complete localization/help and native/release lanes with their required target-specific evidence. G50/G51 stay open until their actual acceptance checks pass.

Numbering is stable traceability, not a claim that later independent work must
wait for unavailable legacy hardware or a platform-specific entitlement.

## Checkpoint ledger

| Increment | Remote branch / commit | Evidence | Status |
| --- | --- | --- | --- |
| Scope all remaining gaps | `feature/file-manager-gap-closure-20261112` · `9887b53` · PR #58 | 51 scoped items across six lanes | Scope and acceptance criteria preserved remotely |
| G03 conflict previews | `feature/conflict-review-20261112` · `132f70e` · PR #59 | 140 tests passed across four service/widget suites; focused analysis clean | Closed for the documented bounded preview scope |
| G12 external terminal | `feature/external-terminal-20261112` · `f798f27` · PR #60 | 45 tests passed across five suites; one existing macOS-only skip; follow-up bounds tests passed in the 118-test run | Implemented; native terminal-window acceptance pending |
| G01 incoming drops | `feature/incoming-drop-routing-20261112` · `a452b7a` · PR #61 | 118 tests passed across six drop/operation suites and the terminal service suite; focused analysis clean | Implemented; real OS/browser drag acceptance pending |
| G02 direct Quick Open | `feature/quick-open-actions-20261112` · `baccf47` · PR #63 | 193 tests passed across nine navigation/rename suites and three conversion suites; focused analysis has no errors/warnings | Closed for the direct saved-item workflow |
| G37 FTP transport lifetime | `feature/ftp-transport-lifetime-20261112` · `c8f4561` · PR #64 | 145 tests passed across nine FTP/SOCKS/TLS suites, including 24 native lifetime cases | Closed for owned transport cleanup; queue API boundary documented |
| G04 configurable menus | `feature/configurable-menus-20261112` · `55dd210` · PR #65 | 96 tests passed across 11 menu, screen, keyboard, navigation and SQLite-runtime suites | Implemented; native presentation and keyboard acceptance pending |
| G27 SOCKS4/4a HTTP routing | `feature/socks4-http-routing-20261112` · `42ae79c` · PR #66 | 197 tests passed across six proxy/security/TLS suites including the final host-validation delta; focused analysis and independent review clean | Closed for native HTTP/HTTPS routing |
| G13 file encoding/decoding | `feature/file-conversion-20261112` · implementation `ebede8d` · PR #67 | 80 tests passed across codec, service/native-filesystem and dialog suites; no analyzer findings in new files | Closed for documented UUE/XXE and single-part MIME formats on supported exclusive-output backends |
| Integrated validation | `feature/file-conversion-20261112` · code checkpoint `ebede8d` | Full analysis: 0 errors, 96 warnings, 1,038 infos; JavaScript release web build passed with version/hash; optional WebAssembly dry run exited 247 | [Detailed evidence and limits](validation-20261112.md) |
| Continuation scope | `feature/gap-extension-scope-20261112` · `cd14477` · PR #69 | G05/G09/G25/G49 boundaries and staged validation plan | Scope preserved remotely |
| G25 FTP byte-offset resume | `feature/ftp-download-resume-20261112` · initial `6b122d6`, cleanup `5b2f1fa` · PR #70 | 285 tests passed across eight transfer/FTP suites; 89 passed in the final three-suite empty-stage/crash gate | Implemented; live-server and signed-target acceptance pending |
| G09 command entry | `feature/command-entry-20261112` · `50a9547` · PR #71 | 152 tests passed across eight command/context/keyboard suites; 62 passed in the final service/dialog/context gate | Implemented; native argument/permission/keyboard acceptance pending |
| G05 gathering stack | `feature/gathering-stack-20261112` · `8f117e7` · PR #72 | 56 service/widget/operation-dialog tests passed; focused analysis clean | Closed for the reviewed reference workflow |
| G49 localized help | `feature/localized-help-20261112` · code `e475032` · PR #73 | 35 guide/reader/real-screen integration tests passed; all three guides and revision-update workflow verified | Closed for maintained English/German/French offline help |
| Continuation integrated validation | `feature/localized-help-20261112` · compiled code `e475032` | 55 menu regressions passed; full analysis gate: 0 errors, 96 warnings, 1,039 infos; versioned JavaScript release build passed; optional WebAssembly probe exited 247 | [Continuation evidence and remaining acceptance](continuation-20261112.md#integrated-validation) |
| External tools/archive scope | `feature/external-tools-archive-scope-20261112` · `e473083` · PR #74 | G10/G11/G18 implementation and acceptance boundaries | Scope preserved remotely |
| Private tool staging | `feature/private-tool-staging-20261112` · `47b7c57` · PR #75 | 10 native staging/lifetime tests; narrow analysis clean | Shared retained-directory and lease foundation |
| Conditional remote publication | `feature/conditional-remote-publication-20261112` · `2297f8e` · PR #76 | 17 provider fixtures; narrow analysis clean | Initial Dropbox revision-guarded contract; broader providers not implied |
| G11 external comparison | `feature/external-comparison-tools-20261112` · `77af994` · PR #77 | 119 checks across nine focused suites; source capture, menus and help verified | Implemented; installed GUI-tool acceptance pending |
| Archive publication/recovery | `feature/archive-publication-recovery-20261112` · `005771b` · PR #78 | 24 verified-publication/recovery tests; narrow analysis clean | Native local foundation; remote/browser prerequisites remain implementation work |
| G10 external remote editing | `feature/external-remote-editing-20261112` · `c5ddfff` · PR #80 | 125 distinct checks across 11 suites, including final five lifecycle cases; three current offline guides | Implemented; native editor/live Dropbox acceptance pending |
| G18 native archive endpoints | `feature/writable-archive-endpoints-20261112` · core `e32401c`, UI `c74986a`, reviewed fixes `af79a89` · PR #81 | 104 archive checks plus 58 distinct host/help checks: 162 across 14 suites; three current offline guides | Native local increment delivered; remote/browser publication implementation and native acceptance remain |
| G14 viewer preparation | `feature/viewer-spool-lifecycle-20261112` · scope `57d9cfd`, code `dfb7978` · PR #83 | 29 lifecycle checks plus 81 existing viewer/archive/help checks: 110 across seven suites; three current offline guides | Native lifecycle increment delivered; broader remote paging/comparison scope remains open |
| Tools/archive/viewer integrated validation | `feature/viewer-spool-lifecycle-20261112` · compiled code `dfb7978` | Full analysis: 0 errors, 96 warnings, 1,040 infos; versioned JavaScript release build passed; packaged guide bytes verified | [Observed gates and remaining acceptance](viewer-spool-continuation-20261112.md#integrated-validation) |

Implementation status is updated only after the corresponding code and tests
are preserved remotely. Test counts from overlapping runs are not added together.
