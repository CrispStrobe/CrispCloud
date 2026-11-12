# Connections and transfers

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G25

### FTP byte-offset resume

**Status:** Scoped. **Dependencies:** Existing transfer recovery.

**Scope:** Resume verified partial downloads using server restart capabilities and durable checkpoints.

**Implementation:** Negotiate FTP restart capability, persist verified partial-file evidence and use REST with the correct binary offset before RETR. Reconcile source identity/size and destination prefix before resuming.

**Boundary:** Fallback is an explicit reviewed restart, never an unreported append. Establish which servers and secure modes support reliable restart. Upload resume is separate until its truncate/offset semantics are verified.

**Acceptance:**

- A loopback server confirms exact REST/RETR order and bytes for plain/implicit/explicit TLS.
- Changed sources, incorrect prefixes, refused offsets, short transfers and interrupted reconnection preserve prior verified data.
- Queue recovery and cancellation resume from a proven offset without duplicating or skipping bytes; live interoperability is recorded.

**Starting points:** ftp_transfer_session.dart; FTP capabilities; transfer recovery/checkpoint service.

## G26

### Server-to-server FTP transfer

**Status:** Scoped. **Dependencies:** G25 transfer evidence; server support.

**Scope:** Negotiate direct remote transfer and confirm destination completion before optional deletion.

**Implementation:** Implement explicit server-to-server negotiation using each captured control session and a reviewed source/destination pair. Verify server replies and resulting destination evidence before reporting success.

**Boundary:** Server policies, passive endpoint restrictions and TLS data-channel compatibility vary. Never silently route through the client while reporting direct transfer. Source deletion for moves requires confirmed destination completion.

**Acceptance:**

- Both sessions negotiate endpoints only under the reviewed server identities and reject unexpected third-party addresses.
- Refusal, timeout, TLS incompatibility and partial transfer produce accurate recoverable outcomes.
- Verified direct-copy fixtures and live accepted servers are recorded separately from existing client-mediated transfers.

**Starting points:** FTP control sessions; G25 destination evidence; transfer planner.

## G27

### SOCKS4 HTTP routing

**Status:** Scoped. **Dependencies:** Existing SOCKS5 connector boundaries.

**Scope:** Add an explicit SOCKS4/4a connector and preserve HTTPS trust and routing rules.

**Implementation:** Add explicit SOCKS4 and SOCKS4a negotiation under the native HTTP connection factory. Reuse bounded raw transport ownership, HTTPS verification and configured bypass behavior.

**Boundary:** SOCKS4 does not provide the same authentication or address-family capabilities as SOCKS5. Expose only supported options and choose local versus proxy DNS explicitly; never downgrade selected modes.

**Acceptance:**

- Independent IPv4/domain fixtures verify wire bytes, rejection codes, fragmented replies and preserved payload bytes.
- HTTPS hostname/certificate failures, cancellation and stalled negotiation close the transport without direct fallback.
- Invalid mode/address/authentication combinations fail before a connection is attempted.

**Starting points:** socks5_connector.dart ownership pattern; proxy_service.dart.

## G28

### Direct-protocol proxy routing

**Status:** Scoped. **Dependencies:** Per-protocol socket factories.

**Scope:** Apply explicit supported proxy modes to FTP, SSH/SFTP and SMB sockets.

**Implementation:** Introduce per-protocol injectable socket factories and explicit proxy settings for control/data channels and SSH/SMB sessions. Preserve each protocol’s trust, authentication and cancellation contracts.

**Boundary:** HTTP proxy CONNECT, SOCKS and FTP application-proxy schemes are distinct capabilities. A proxy setting must cover every required connection or fail clearly; never proxy credentials to an inferred destination.

**Acceptance:**

- Control and secondary data channels follow the chosen route, with no hidden direct fallback.
- Host-key/certificate verification remains end-to-end for the destination; auth failures never weaken protection.
- Loopback protocol fixtures cover reconnect, timeout, cancellation and source identity; each native backend reports its supported modes.

**Starting points:** FTP/SFTP/SMB adapters; proxy_service.dart; native backend boundaries.

## G29

### Global transfer bandwidth limits

**Status:** Scoped. **Dependencies:** Shared transfer scheduler.

**Scope:** Coordinate independent upload/download limits across simultaneous transfers.

**Implementation:** Create a shared fair bandwidth allocator with separate upload/download buckets and per-job participation. Apply it at actual stream boundaries, integrate existing per-operation limits and expose settings/activity state.

**Boundary:** Client-stream pacing cannot measure all protocol overhead or server-side copies. Describe the enforced unit and exempt non-client-mediated operations explicitly. Zero/unlimited values and pauses need stable semantics.

**Acceptance:**

- Concurrent transfers respect aggregate configured byte rates within defined burst tolerance and avoid starvation.
- Limit changes, pause/resume, cancel and failed consumers release permits without deadlock or double-accounting.
- Uploads and downloads are independent; bypassing or unsupported adapters cannot falsely report enforced wire limits.

**Starting points:** Transfer scheduler/service; existing bandwidth-limited stream helpers.

## G30

### Network volume discovery

**Status:** Scoped. **Dependencies:** Native discovery adapters.

**Scope:** Discover supported network services and require explicit connection selection.

**Implementation:** Add bounded, cancellable native discovery adapters for supported network service advertisements and explicit host/share probing. Present discovered endpoints for user selection and normal authenticated connection setup.

**Boundary:** Discovery does not grant access. Avoid broad or privileged network scanning by default, never infer credentials, and label advertisement identities as unverified until connection trust checks pass.

**Acceptance:**

- Duplicate/changed advertisements, unreachable hosts and cancellation do not create duplicate or phantom connections.
- Selecting a result captures its endpoint and opens normal trust/authentication review.
- Target-network and OS discovery behavior is tested; manual host/share configuration remains available.

**Starting points:** SMB connection setup; available source catalog; new discovery bridges.

## G31

### SCP provider

**Status:** Scoped. **Dependencies:** SSH host verification; streaming adapters.

**Scope:** Add capability-limited SCP transfer over verified SSH sessions.

**Implementation:** Implement SCP upload/download over captured verified SSH sessions with explicit path encoding, stream framing and exit-status handling. Publish through existing transfer staging/review.

**Boundary:** SCP is a transfer protocol, not a full remote filesystem. Enumeration, stat, rename and deletion require separately advertised capabilities; do not fabricate them from shell commands without an explicit adapter contract.

**Acceptance:**

- Independent server fixtures verify framing, filenames, partial reads, exit codes and arbitrary byte content.
- Remote filenames and paths cannot become shell syntax; host-key and account identity remain captured.
- Cancellation, failed acknowledgements and partial destination writes preserve source data and expose honest recovery limits.

**Starting points:** Existing SSH/SFTP session verification; CloudStorageClient capability interfaces.

## G32

### AFP provider

**Status:** Platform research. **Dependencies:** Permissive implementation; target server/OS.

**Scope:** Choose a permitted implementation and expose only tested filesystem capabilities.

**Implementation:** First document a feasible licensed AFP implementation and target platforms, then build a capability-limited adapter with explicit session, path and metadata behavior.

**Boundary:** No support claim until a permitted maintained implementation and an accessible server fixture exist. Mounted AFP directories only establish local filesystem access, not a native provider.

**Acceptance:**

- Record license/provenance, protocol/version support and native build targets.
- Conformance covers authentication, Unicode paths, pagination/listing, streaming and claimed mutation semantics.
- Disconnect/reconnect, permission failures and original-source binding pass on actual supported server/OS combinations.

**Starting points:** New provider/native bridge; provider conformance suite; platform fixture.

## G33

### Native NFS provider

**Status:** Platform research. **Dependencies:** Permissive implementation; target server/OS.

**Scope:** Implement native NFS access with explicit version/authentication/mutation capabilities.

**Implementation:** Select protocol versions and an approved native/client implementation, define export/authentication configuration and map file handles to stable source identities. Add adapter operations only as validated.

**Boundary:** Mounted NFS access and a read-only helper do not establish a native read/write provider. UID/GID mapping, permissions, symbolic links, locking and unstable handles need explicit behavior.

**Acceptance:**

- Record license/provenance and version/security support before enabling the provider.
- Real or isolated server conformance tests cover stale handles, export changes, denied access, streaming and supported mutations.
- Reconnect and path replacement cannot redirect a queued operation; no guessed privilege or identity mapping is applied.

**Starting points:** New NFS client/native bridge; provider capability tests.

## G34

### Cloud Files provider

**Status:** Scoped. **Dependencies:** Account/API compatibility fixtures.

**Scope:** Implement identity, containers, pagination, object transfers and sharing through the service API.

**Implementation:** Add service identity/authentication, region/container listing, object pagination, conditional streaming upload/download and supported share-link creation. Retain original account/container/object identity in all operations.

**Boundary:** Specify supported identity API and object-store features explicitly. Temporary URLs, metadata, ACLs and server-side copies require distinct capability checks. Credentials use existing secure storage.

**Acceptance:**

- Recorded/loopback API fixtures cover authentication refresh, pagination, conditional writes, error mapping and bytes.
- Region/container/account changes invalidate captured work; cross-source operations never reuse another token.
- Live conformance is recorded with a dedicated test account before claiming production interoperability.

**Starting points:** CloudStorageClient; existing object-store patterns and conformance tests.

## G35

### Managed cloud filesystem integration

**Status:** Platform research. **Dependencies:** Apple entitlements; target device.

**Scope:** Add dedicated account/container-aware access and hydration behavior for Apple-managed cloud files.

**Implementation:** Design dedicated Apple-managed cloud-container access with account availability, hydration/eviction progress, coordinated reads/writes and stable item identity. Integrate favorites only through G08 portable records.

**Boundary:** Existing access through a granted local folder remains a separate capability. Entitlements, account changes, offline placeholders and signed sandbox behavior require real-device validation.

**Acceptance:**

- Hydration, offline access, conflict versions and account sign-out produce truthful file states.
- Coordinated writes preserve current versions and grants; background transfers cannot outlive their permitted session.
- Signed supported-device acceptance covers container access and recovery without storing account credentials in app preferences.

**Starting points:** Native Apple file coordination/provider work; G50 target acceptance.

## G36

### Local synced-file sharing links

**Status:** Scoped. **Dependencies:** Provider/account mapping; explicit share capability.

**Scope:** Resolve a verified local sync-folder item to its provider identity and share link.

**Implementation:** Resolve an explicitly configured local sync root to the correct provider account and remote object, then use the provider’s existing share-link capability. Track stable object/revision mapping when available.

**Boundary:** A matching path or filename alone is insufficient proof. Unsynced/conflicted/local-only files remain unavailable for provider links. Native share sheets are G39, not a substitute for correct remote identity.

**Acceptance:**

- Same paths under different accounts/roots cannot produce links for the wrong object.
- Pending sync, moved files, stale indexes and removed accounts invalidate mappings rather than guessing.
- Link creation uses the provider’s normal permission review and reports whether an existing or new link was returned.

**Starting points:** Provider-aware sharing; local root mappings; source identities.

## G37

### FTP stalled-handshake cleanup

**Status:** Scoped. **Dependencies:** Cancelable native socket ownership.

**Scope:** Prove and enforce underlying transport cleanup during stalled TLS upgrades.

**Implementation:** Refactor FTP TLS upgrades around owned cancellable raw transports, covering metadata and streaming transfer sessions. Add fixtures that stall after the greeting or ClientHello and observe actual peer closure.

**Boundary:** Caller-side Future timeouts are not sufficient evidence of socket cleanup. Preserve certificate/hostname validation, protocol order and existing connection-mode migration.

**Acceptance:**

- Timeout/cancel closes control and data transports during every stalled upgrade stage.
- Late handshake completion cannot resurrect a closed session or send credentials after cancellation.
- Existing plain/implicit/explicit TLS listing and transfer suites continue to pass, with cleanup counts stable under repeated failures.

**Starting points:** ftp_transfer_session.dart; packages/ftpconnect transport; existing TLS fixtures.

## G38

### Browser protocol access

**Status:** Architecture research. **Dependencies:** Gateway deployment/trust model.

**Scope:** Define an authenticated gateway for browser-incompatible protocols with explicit capabilities.

**Implementation:** Specify an authenticated gateway API for browser-incompatible protocols, with per-request capabilities, end-to-end source identity, stream backpressure, cancellation and destination trust reporting.

**Boundary:** A gateway changes the trust/deployment model. No browser FTP/SSH/SMB claim until an explicit supported gateway and credential flow exist. Do not embed native secrets in browser bundles or silently reuse unrelated service sessions.

**Acceptance:**

- Threat/data-flow design identifies who sees credentials/content and how trust decisions are presented.
- Gateway integration tests cover isolation, streaming, reconnect, expired capabilities, cancellation and upload publication.
- Browser acceptance and an explicitly configured deployment are required before enabling the capability.

**Starting points:** Gateway architecture; browser client; G50/G51 acceptance.
