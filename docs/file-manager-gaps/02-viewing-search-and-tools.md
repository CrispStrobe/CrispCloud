# Viewing, search and tools

[Gap register and closure rules](README.md). Baseline: `28b7b9c`.

Every item below has a separate completion boundary. A prototype, reader-only
codec or passing loopback test does not imply the broader platform or write
capability. Required live/device checks remain visible after code implementation.

## G10

### External remote editing

**Status:** Implementing. **Dependencies:** Captured editor session; conflict review.

**Scope:** Watch a staged remote file and safely upload edits to the captured original source.

**Implementation:** Create a source-bound external-editor session with a private local staging file, original fingerprint and watched save generations. Queue verified uploads to the original path and expose conflicts against remote changes.

**Boundary:** A launched editor does not authorize unreviewed replacement of a changed remote file. Preserve unsent local edits after network failure/restart. Clean staging only after explicit close and durable outcome; never persist provider secrets in session metadata.

**Acceptance:**

- Save bursts coalesce without overwriting a newer edit; stale uploads cannot replace a later generation.
- Concurrent remote changes, reconnects, path replacement and account switches require conflict handling against the original source.
- Editor exit, app crash, offline save and retry retain recoverable edits and avoid duplicate or wrong-account uploads.

**Starting points:** Existing editor save identity/recovery; local process launcher; operation queue.

## G11

### External comparison tools

**Status:** Implementing. **Dependencies:** G10 staging lifetime.

**Scope:** Configure text/image comparison tools and stage reviewed local or remote pairs.

**Implementation:** Persist preferred comparison executables and argument templates for text/image comparisons. Capture both inputs, stage remote inputs with explicit limits and invoke the configured tool with separate arguments.

**Boundary:** Initial comparison is read-only. Any merge-back path needs G10 conflict-safe publication. Detect unsupported or unavailable tools without replacing them silently; external software is not bundled by default.

**Acceptance:**

- Two local/remote same-path files from different sources remain distinct in the tool invocation.
- Argument quoting, Unicode, spaces, cancellation and tool failure are handled without shell injection or stale-source use.
- Staged data stays available for the tool session and is cleaned only when safe; supported OS integration is accepted separately.

**Starting points:** file_comparison_service.dart; captured viewer/editor sources; external command service.

## G12

### Preferred external terminal

**Status:** Implemented / native acceptance pending. **Dependencies:** Installed terminal application on each target OS.

**Scope:** Choose a terminal application and open it at the verified local path.

**Implementation:** Add platform-aware external terminal preferences and a captured-local-directory launch action. Allow a configured executable/argument template and retain the embedded terminal as its own workflow.

**Boundary:** Remote locations require an explicitly configured SSH/session action; they are not treated as local paths. Respect local grants and executable availability. Do not execute commands merely to open a directory.

**Acceptance:**

- Local paths with spaces, quotes and Unicode are passed as arguments without evaluation.
- Source/path/tab changes during launch preparation invalidate the old request.
- Missing terminals show actionable selection/reset behavior; current-path opening is verified on each claimed desktop OS.

**Starting points:** Existing terminal and custom command launch services; native process adapters.

**Delivered:** [External terminal preferences](../external-terminal.md) provides
per-OS executable/argument configuration, reset, and an explicit reviewed launch
from Settings or Terminal actions. Launch preparation uses the active pane's
captured local source and existing grants; it rejects newer navigation, missing
paths, batch files and common shell interpreters. Argument placeholders never
become shell command strings. No dependency was added.

**Observed validation:** 45 tests passed across the new service/dialog and
existing settings, terminal-panel and directory-resolution suites. One existing
macOS-only terminal test was skipped on Linux. Focused analysis has no errors or
warnings. Literal-argument, stale-preparation, unavailable-path, persistence,
disposal and narrow German/Arabic cases are covered.

**Remaining acceptance:** Open an installed terminal on each claimed desktop OS
and verify its actual working folder and signed/sandbox behavior. Application
argument conventions and native window behavior are not inferred from mocks.

## G13

### UUE, XXE and MIME conversion

**Status:** Closed for the documented streaming formats and exclusive-output backends. **Dependencies:** Destination capability gates remain explicit.

**Scope:** Stream file encoding/decoding into verified exclusive outputs.

**Implementation:** Implement streaming UUE and XXE block codecs and a precisely scoped MIME file/attachment encoder-decoder. Prepare outputs through captured operation backends, validate complete decoding and publish exclusively.

**Boundary:** Define line length, padding, filename encoding, checksums where available, and multipart/transfer-encoding support. Decoded filenames are suggestions only: reject traversal/absolute paths and never trust payload-controlled destinations.

**Acceptance:**

- Known independent fixtures and roundtrips cover empty files, Unicode suggested names, all byte values and chunk boundaries.
- Truncation, invalid lengths/alphabet, oversized headers and malicious member names fail without a published partial output.
- Large-file conversion is bounded and cancellable; collision review, same-source checks and recovery behavior are explicit.

**Starting points:** FileOperationBackend; existing verified split/combine/publication helpers; new streaming codecs.

**Delivered:** [File encoding and decoding](../file-conversion.md) defines
streaming UUE, XXE and single-part Base64 MIME conversion. The context menu
opens a captured-source review with an explicit new filename. All decoders
reject unsafe embedded names before staging; safe names remain metadata.
Full syntax validation, repeated source/output hashing, staged read-back and
exclusive publication preserve original files and existing destinations.
No dependency was added.

**Observed validation:** All 80 codec, service and dialog tests passed, including
a real native local-filesystem encode/decode/collision roundtrip. Tests cover
independent vectors, all byte values, chunk boundaries, Unicode MIME names,
malformed/truncated input, source replacement, same-size mutations, corrupt
staging, stalled-stream cancellation and translated error/layout behavior.
New files have no analyzer findings; the existing context-menu file retains
three pre-existing unused-import warnings and two style findings.

**Boundary retained:** MIME multipart messages, quoted-printable and filename
continuations are explicitly unsupported. The UI converts one file in its
captured folder, creates a new output and retains the input. Destinations without
bounded streaming, staged verification and exclusive publication are unavailable;
this includes the current browser-local destination contract. Native macOS
grant acceptance remains under G50.

## G14

### Large-file viewer and comparison limits

**Status:** Scoped. **Dependencies:** Provider range capabilities.

**Scope:** Extend remote paging, spooling and text comparison without unbounded buffers.

**Implementation:** Replace whole remote staging where feasible with verified range readers or bounded temporary spools. Add capability-aware paging/search and investigate chunked text comparison/merge with a clear editable-size contract.

**Boundary:** Do not remove limits without a memory, disk, cancellation and consistency design. A provider without stable range/version semantics may need a verified spool. Rich renderers keep documented format-specific bounds.

**Acceptance:**

- Large local and remote fixtures show bounded peak memory and preserve correct byte offsets/Unicode boundaries.
- Remote mutation between ranges, retry, truncated responses and source reconnection cannot produce a mixed-version document.
- Search, hex/binary paging and comparison report limits/partial results accurately; large edit saves retain conflict and recovery safeguards.

**Starting points:** internal_viewer_service.dart; viewer_streaming/search services; file_comparison_service.dart.

## G15

### Nested and encrypted archive search

**Status:** Scoped. **Dependencies:** G18 archive identity; reader capabilities.

**Scope:** Search nested archive contents with explicit budgets, passwords and partial-result reporting.

**Implementation:** Traverse archive members through a bounded search context that carries container identity, nesting depth, expanded-byte and entry budgets. Add explicit password requests and reuse supported readers without extracting uncontrolled paths.

**Boundary:** Each nested container contributes to a shared expansion budget. Passwords are session-only or held by the existing secure mechanism, never embedded in search history. Unsupported/encrypted members produce visible partial results.

**Acceptance:**

- Nested, encrypted, malformed, cyclic-name and expansion-heavy fixtures stop within configured budgets.
- Results retain the full original container/member identity and open the correct member after review.
- Cancel, disconnect or container replacement cannot append stale results or expose another account’s contents.

**Starting points:** FileSearchQuery/search traversal; archive_viewer_service.dart; G18 identities.

## G16

### Native indexed search

**Status:** Scoped. **Dependencies:** Native search bridge.

**Scope:** Add supported operating-system index adapters with source-bound results.

**Implementation:** Add native index adapters that return stable local item references, metadata and query limitations. Merge/index results into the existing source-bound result/selection model with cancellation.

**Boundary:** Index results may be stale or inaccessible; every open/mutation revalidates the object and grant. Recursive application search remains a separately described capability. No index claim for unsupported providers.

**Acceptance:**

- Queries respect type/date/name/content criteria supported by the native index and label unsupported filters.
- Deleted/replaced files, revoked grants and stale index entries cannot authorize operations.
- Cancellation, pagination and live updates preserve selection identity; target-platform index behavior is tested.

**Starting points:** Existing search results/collections; new native search bridge.

## G17

### Additional viewer adapters

**Status:** Scoped. **Dependencies:** Existing viewer dispatch; extension review.

**Scope:** Add a capability registry for supported document/image renderers and isolated external viewers.

**Implementation:** Define viewer capabilities by format and operation, then integrate additional permitted renderers through bounded adapters. External viewers use explicit executable configuration and staging lifetime rules.

**Boundary:** Reader support does not imply editing. Isolate untrusted external tools, bound output and preserve HTML/document sandboxing. Each dependency or bundled renderer needs its own license/provenance and platform support record.

**Acceptance:**

- Independent valid/corrupt fixtures exercise every advertised format and unsupported features are explicit.
- Large dimensions, embedded resources, external URLs and malformed data cannot bypass resource/source boundaries.
- Stale loads, cancellation and viewer failure leave the original file untouched and release temporary data.

**Starting points:** internal_viewer_service.dart; preview dispatch; first-party extension manifests.
