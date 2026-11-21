# CrispCloud plan

Current priorities for the cross-platform file manager. This page is deliberately
short; the detailed 2026-11 implementation log is preserved in the
[plan archive](PLAN-details-2026-11.md).

## Product direction

CrispCloud is a dual-pane file manager for local, network and cloud storage:
one workspace, explicit operation review, recoverable transfers and no hidden
conversion or background mutation.

Non-negotiables:

- source-account identity is captured before every operation;
- destructive work is reviewed and journaled;
- unsupported capabilities are disabled with a reason, not emulated silently;
- credentials stay in the selected store and never enter logs or paths;
- native platform builds remain the acceptance gate for native claims.

## Now

| Area | Priority |
| --- | --- |
| **Release** | Keep macOS/iOS TestFlight and desktop builds reproducible; verify signed bundles and vendor pins |
| **Reliability** | Close the remaining workspace, PDF, image and archive test-contract failures without weakening assertions |
| **Mail** | Live-account acceptance for saved accounts, restore state and provider sync |
| **Office** | Sync the CrispCloud vendor pin to the reviewed Quds source; keep format limits explicit |
| **Credentials** | System-keychain, vault and session-store recovery paths on clean installs |
| **Accessibility** | Larger text, narrow windows and keyboard-only operation for new dialogs |

## Next

- Finish the Office/ODF viewer boundary: clear read-only reasons, no false edit
  affordances, reviewed export copies.
- Make transfer review consistent for drops, restored tabs and saved
  collections.
- Complete native archive/filesystem acceptance for the shipped reader profiles.
- Expand provider interoperability tests for SMB, SFTP, WebDAV, S3 and OAuth
  providers.
- Reduce startup work and keep large-directory navigation bounded.
- Finish localization coverage for controls added after 1.3.

## Later

- Additional account persistence beyond the current session-only providers.
- Richer two-way sync conflict presentation and recovery.
- More archive writer profiles where metadata can be preserved honestly.
- Expanded CLI/catalogue interchange with stable file formats.
- Mobile-specific file-provider and share-sheet polish.

## Acceptance rules

A feature is not “done” because it compiles or has a unit test. Depending on the
claim, require:

1. focused unit/widget tests;
2. exact-head hosted tests where the repository expects CI evidence;
3. a native build on the target platform;
4. a live account or real external fixture;
5. signed release verification for distribution.

Local test results must not be described as hosted, installed, live-provider or
App Store acceptance.

## Current boundaries

- macOS App Store builds cannot launch arbitrary host shells or external editors.
- Browser builds cannot open raw SSH, SMB or local filesystem transports.
- Read-only archive/filesystem profiles do not become writers.
- Office macros and ActiveX are never executed.
- Experimental mounts stay read-only and capability-gated.
- ODF and legacy formats have documented subsets; no silent round-trip claim.

## Tracking

- [User guide](docs/USER_GUIDE.md)
- [Workspace controls](docs/workspace-ux.md)
- [Transfer queue](docs/transfer-queue.md)
- [Archive coverage](docs/archive-format-coverage.md)
- [Provider setup](docs/PROVIDER_SETUP.md)
- [Terminal](docs/terminal.md)
- [History](HISTORY.md)
