# CrispCloud 1.3.4 (29), macOS TestFlight

The release combines CrispCloud source `d17ec349` with Quds main `ee725946`, including the captured rendering, proofing, Zotero, spreadsheet and ODF work, plus the incoming ODT list writer. The final PR-ancestry merge `46d66de4` has an identical Git tree; it changes no source or metadata bytes. Later branches created after the release freeze are separate work.

Functional host, engine/editor regression and terminal unit/live checks passed. Actual signed startup, sandbox/component checks and Apple's archive validation passed. Apple accepted the package upload with delivery ID `ec9a28d8-b390-4f1a-bacc-4150e114d46c`. Apple marked the exact macOS build VALID. It is IN_BETA_TESTING internally and assigned to the reviewed external group; external review is WAITING_FOR_REVIEW. See receipt.json for the independently fetched final state.

Broad and focused test cohorts overlap. The broad editor run retains 16 golden failures; the identical tests and pixel-difference measurements fail on the unchanged baseline on this Mac. No golden images were refreshed. Two live SSH PTY cases require login-record permissions and were skipped. Native Harper execution on macOS, live Zotero/Word interoperability and pixel-identical Microsoft Office rendering are not claimed.

The app and Finder extension both carry version 1.3.4/build 29. The shipped profile is App Store, sandboxed, ARM64, without the optional direct-distribution FUSE helper. Existing signing identities, country policy and TestFlight membership were used.

Earlier superseded build attempts and a telemetry/network compiler stall were resolved before final delivery; they are not accepted builds. Accepted commands, source identities, hashes and compressed logs are recorded here. The original analytics preference and temporary build configuration were restored.
