# Native platforms and release

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G39

### Native share targets

**Status:** Scoped. **Dependencies:** Native share bridge.

**Scope:** Expose supported operating-system share sheets for captured local files or reviewed staged copies.

**Implementation:** Add native share-sheet adapters for captured local items and explicitly staged remote copies. Bind staging lifetime to the platform share activity and expose supported item types.

**Boundary:** Sharing is a user-directed handoff; it does not authorize sending to a guessed recipient. Read permissions and remote download limits still apply. Provider-generated links remain their existing workflow.

**Acceptance:**

- Native targets receive the reviewed files/URIs with supported temporary read access only.
- Cancel, target failure, disconnect and app lifecycle changes clean staging safely and preserve originals.
- Signed platform acceptance verifies actual share activity completion and access-grant lifetime.

**Starting points:** Existing share actions; new native share bridge.

## G40

### Default file-viewer registration

**Status:** Platform research. **Dependencies:** Packaging/registration per OS.

**Scope:** Provide explicit opt-in registration and reversible platform association handling.

**Implementation:** Implement explicit opt-in registration for supported file/folder associations with a visible restore/unregister path and packaging metadata.

**Boundary:** System association APIs and app-store/sandbox constraints differ by OS. Registering an app is not proof that every external navigation request routes to it. Never silently replace unrelated associations.

**Acceptance:**

- Supported external open-folder/file requests resolve to the correct local path/tab and handle malformed inputs safely.
- Registration and reversal survive upgrade/uninstall without damaging previous associations.
- Packaging/signing and actual OS association acceptance are recorded for each supported target.

**Starting points:** Native app entry points; desktop packaging; OS association APIs.

## G41

### Process viewer

**Status:** Scoped. **Dependencies:** Native process metadata/control.

**Scope:** List available processes and review termination requests against stable process identity.

**Implementation:** Add a cancellable process inventory with stable process identity, useful metrics where available and an explicit termination review. Use native adapters for platform-specific information.

**Boundary:** A PID can be reused: revalidate executable/start identity before termination. Do not imply elevated visibility or termination rights; protected processes remain unavailable. Background monitoring needs bounded refresh cost.

**Acceptance:**

- Process exit/reuse between selection and confirmation cannot terminate a different process.
- Permission denial and unsupported metrics are explicit; sorting/filtering handles live updates without selection drift.
- Termination/cancel behavior and UI responsiveness are tested on each supported desktop target.

**Starting points:** New native process service and review UI; G43 only if elevation is separately approved in-app.

## G42

### Application removal

**Status:** Platform research. **Dependencies:** Platform ownership and protected-path rules.

**Scope:** Review an application and attributable support files before native uninstall/removal.

**Implementation:** Build a reviewed removal plan from a selected application bundle/package and attributable support files, showing ownership evidence and protected exclusions. Prefer platform uninstall mechanisms where available.

**Boundary:** Do not infer that every same-named file belongs to the application. Shared user data and system components require explicit separate handling. Permanent deletion is never an automatic cleanup default.

**Acceptance:**

- Fixtures cover shared files, symlinks, ambiguous ownership and application updates between scan and removal.
- Cancellation, partial failure and restore/trash behavior preserve reviewable outcomes.
- Native install/uninstall mechanisms and signed permission flows are accepted on target systems before support claims.

**Starting points:** Native package/application inventory; reviewed delete/trash planner.

## G43

### Privileged file operations

**Status:** Platform research. **Dependencies:** Platform privilege service and signing.

**Scope:** Add an authenticated minimal elevation broker with explicit scoped operation review.

**Implementation:** Design a minimal authenticated broker for explicitly reviewed filesystem operations, with allowlisted verbs and handle-based path validation where available. Keep UI and provider sessions unprivileged.

**Boundary:** Elevation requires a platform-specific trust/signing boundary. No blanket root shell, persistent broad grant or silent retry as administrator. Remote provider credentials never enter the broker.

**Acceptance:**

- Adversarial symlink/path-replacement and malformed-request tests cannot escape reviewed objects.
- Cancel, authorization denial, broker restart and partial failure produce auditable recoverable outcomes.
- Signed installer/service and native authentication acceptance are complete on each supported platform.

**Starting points:** Platform privilege service, secure IPC and signing; operation review/journal.

## G44

### Git workspace integration

**Status:** Scoped. **Dependencies:** Installed Git; credential and conflict handling.

**Scope:** Discover repositories, show status and review add/commit/push/pull actions.

**Implementation:** Discover repositories from captured local paths, parse machine-readable status and expose reviewed add/commit/push/pull workflows. Integrate conflict state, cancellation and credential handoff without storing secrets in ordinary preferences.

**Boundary:** Use explicit argument vectors and repository roots; never interpolate filenames into a shell. Remote file-provider folders are not automatically Git worktrees. Destructive history operations are separate and excluded from the first increment.

**Acceptance:**

- Status handles spaces, Unicode, rename pairs, submodules and worktrees without path confusion.
- Index/worktree/branch changes between review and action invalidate stale plans; commit content and target remote/branch are reviewable.
- Authentication failures, merge conflicts, hooks and cancellation preserve repository state and report actual results.

**Starting points:** Native process launch; local file/source identity; new Git service/UI.

## G45

### 32-bit desktop distribution

**Status:** Toolchain research. **Dependencies:** Compatible Flutter/Dart and native dependencies.

**Scope:** Establish supported runtime/plugin targets before creating release artifacts.

**Implementation:** Audit official runtime target support and every native/plugin dependency, then establish reproducible build/test/sign/package jobs for each feasible 32-bit target.

**Boundary:** Do not produce a relabeled x64 binary or claim unsupported Flutter/Dart targets. If no supported compatible toolchain exists, record that evidence and the required architecture change rather than shipping an unmaintained runtime silently.

**Acceptance:**

- Target/runtime and dependency compatibility are documented with pinned versions and licenses.
- Artifact architecture is verified independently and installed on a real 32-bit system/emulator.
- File sizes, offsets, memory pressure, crypto and native transports pass architecture-specific tests before release.

**Starting points:** Toolchain/provider compatibility audit; native CI runners.

## G46

### Direct cable transfer

**Status:** Hardware research. **Dependencies:** Hardware/protocol fixtures; compatible runtime.

**Scope:** Specify a transport and supported legacy endpoints, then test against actual hardware.

**Implementation:** Define supported cable hardware, electrical/protocol interfaces, endpoint operating systems and a standalone transport boundary. Prototype against actual devices before app integration.

**Boundary:** This is a hardware/runtime project. Current USB/network adapters are not evidence of legacy parallel-port compatibility. No support claim without reproducible hardware and endpoint testing.

**Acceptance:**

- Protocol framing, checksums, retries, interrupted transfer and connection loss are validated on actual target hardware.
- Endpoints verify byte-for-byte content and safe destination publication for large files and directory trees.
- Drivers, permissions, supported cable wiring and distributable licensing are documented.

**Starting points:** Hardware access; legacy endpoints; transport specifications.

## G47

### Native binary extension compatibility

**Status:** Architecture research. **Dependencies:** ABI specification; bitness/OS hosts; license review.

**Scope:** Design isolated hosts for archive, metadata, filesystem and viewer extension interfaces.

**Implementation:** Specify isolated native hosts for archive, metadata-column, filesystem and viewer extension ABIs. Map each operation to a capability contract and isolate crashes, bitness and untrusted plugin code.

**Boundary:** The existing first-party extension system is separate. Each legacy ABI/OS/bitness combination needs a maintained host; no arbitrary binary is loaded into the main Flutter process.

**Acceptance:**

- Independent fixture plugins verify ABI calling conventions, path/Unicode handling, ownership and cancellation.
- Crashes, hangs, malformed outputs and unsupported capabilities cannot corrupt the app or reviewed files.
- Plugin/package license, provenance, installation consent and platform host distribution are reviewed before support claims.

**Starting points:** Native worker/IPC architecture; plugin ABI specifications.
