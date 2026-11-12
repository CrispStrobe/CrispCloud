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
| [G05](01-workspace-and-interaction.md#g05) | Gathering stack | Scoped | G01; existing collections |
| [G06](01-workspace-and-interaction.md#g06) | Native outgoing drag | Scoped | G01; native bridge |
| [G07](01-workspace-and-interaction.md#g07) | General file tags | Scoped | Stable file identity; native metadata bridge |
| [G08](01-workspace-and-interaction.md#g08) | Favorite synchronization | Scoped | Versioned favorites; selected sync backend |
| [G09](01-workspace-and-interaction.md#g09) | Command entry and keyboard conventions | Scoped | G04; existing terminal/custom commands |
| [G10](02-viewing-search-and-tools.md#g10) | External remote editing | Scoped | Captured editor session; conflict review |
| [G11](02-viewing-search-and-tools.md#g11) | External comparison tools | Scoped | G10 staging lifetime |
| [G12](02-viewing-search-and-tools.md#g12) | Preferred external terminal | Implemented / native acceptance pending | Verify installed terminals on each claimed desktop OS |
| [G13](02-viewing-search-and-tools.md#g13) | UUE, XXE and MIME conversion | Scoped | Existing operation backend |
| [G14](02-viewing-search-and-tools.md#g14) | Large-file viewer and comparison limits | Scoped | Provider range capabilities |
| [G15](02-viewing-search-and-tools.md#g15) | Nested and encrypted archive search | Scoped | G18 archive identity; reader capabilities |
| [G16](02-viewing-search-and-tools.md#g16) | Native indexed search | Scoped | Native search bridge |
| [G17](02-viewing-search-and-tools.md#g17) | Additional viewer adapters | Scoped | Existing viewer dispatch; extension review |
| [G18](03-archives-and-containers.md#g18) | Writable archive endpoints | Scoped | Existing archive workspace |
| [G19](03-archives-and-containers.md#g19) | Directory-to-archive synchronization | Scoped | G18 |
| [G20](03-archives-and-containers.md#g20) | Archive-to-archive transfer | Scoped | G18 |
| [G21](03-archives-and-containers.md#g21) | Large background archive jobs | Scoped | G18; transfer queue |
| [G22](03-archives-and-containers.md#g22) | Archive format coverage | Scoped | License and format review per codec |
| [G23](03-archives-and-containers.md#g23) | Remote and browser archive creation | Scoped | G18; G21 where streaming is required |
| [G24](03-archives-and-containers.md#g24) | External packer adapters | Scoped | G17 extension isolation |
| [G25](04-connections-and-transfers.md#g25) | FTP byte-offset resume | Scoped | Existing transfer recovery |
| [G26](04-connections-and-transfers.md#g26) | Server-to-server FTP transfer | Scoped | G25 transfer evidence; server support |
| [G27](04-connections-and-transfers.md#g27) | SOCKS4 HTTP routing | Implementing: final regression pending | Final host-validation delta; direct-protocol proxy work remains G28 |
| [G28](04-connections-and-transfers.md#g28) | Direct-protocol proxy routing | Scoped | Per-protocol socket factories |
| [G29](04-connections-and-transfers.md#g29) | Global transfer bandwidth limits | Scoped | Shared transfer scheduler |
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
| [G49](06-localization-and-acceptance.md#g49) | Localized help | Scoped | Canonical English guide; documentation localization |
| [G50](06-localization-and-acceptance.md#g50) | Native and live-provider acceptance | Acceptance pending | Target machines; explicit test accounts and fixtures |
| [G51](06-localization-and-acceptance.md#g51) | Web runtime and WebAssembly acceptance | Acceptance pending | Browser test harness; dependency compatibility |

## Execution order

1. G01 incoming-drop identity, G02 direct Quick Open actions and G03 conflict previews form the first batch. Preserve each verified increment separately as it becomes ready.
2. G04 menu configuration, G05 gathering stack, G09 command entry, G12 external terminal, and G13 file conversion.
3. G18 archive endpoints, followed by G19–G24; run G25/G27/G29/G37 transport increments as their prerequisites are ready.
4. Remaining provider, native, localization and release lanes, with required target-specific evidence recorded independently.

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
| G27 SOCKS4/4a HTTP routing | `feature/socks4-http-routing-20261112` | 196 tests passed across six proxy/security suites before the final host-validation delta; focused analysis and independent review clean | Implementation preserved; final regression pending |

Implementation status is updated only after the corresponding code and tests
are preserved remotely. Test counts from overlapping runs are not added together.
