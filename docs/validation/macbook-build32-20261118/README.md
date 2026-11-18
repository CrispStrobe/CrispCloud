# MacBook preview: CrispCloud 1.3.4, build 32

The installed Apple Silicon preview is built from host `42555b54`, with canonical Quds `f383c826` and CrispEmbed `28d8ce0e`. It includes the current native spelling, Zotero workspace, document review/comparison, native German analysis and optional named-entity model. The exact sources and artifact identities are in [receipt.json](receipt.json).

## User-visible behavior

- Word Review exposes **Spell check**, **German analysis**, **Review changes** and **Compare documents**. Comparison inputs stay separate from the active document and reports export through the existing copy flow.
- German analysis runs in an owned native worker only after Analyze. **People, places and organizations** defaults off and explicitly attaches the separately authenticated NER model. These actions never rewrite document text.
- The signed native component, original five-file F32 bundle, optional NER model and notices are inside the app. Analysis uses no runtime download, Python, daemon or pipe.
- Optional native grammar remains off. The updated Mac library does not inherit the historical Linux grammar qualification. Existing deterministic proofing remains available.

## Regressions and source reconciliation

The footer PAGE failure reproduced before repair. The canonical DOCX builder now emits begin/instruction/separator/formatted-result/end instead of an empty incomplete packet. Field-preservation and independent note-numbering tests pass.

Reviewed Mac references retain corrected note numbering and improved underlines. Exact pixel comparison and repeated native save/reopen checks remain enabled. Existing Linux and legacy images are preserved; no new Linux raster execution is claimed. Host selection is independent of the invoking working directory.

Incoming Zotero narrow-window failures were reproduced. The final source uses the latest Zotero branch's targeted layout repairs, preserving its compact paging and reference workflow. The temporary broader scrolling implementation was superseded before the accepted final run.

All captured current main and relevant follow-up heads are preserved. The final Quds reconciliation after engine/editor execution changes publication metadata, changelogs and test host selection; the tested engine/editor runtime libraries are byte-identical. The optional package was rerun after its Mac/NER publication record arrived. The final inventory verifies 2,723 managed files, retaining the independent legacy parser pin and existing host report customizations.

## Verification and scope

Accepted local runs: **1,171 engine**, **146 editor**, **87 spaCy package**, four native model-free CTests and nine vendor-sync controls. Host runs pass 47 initial and 13 final focused checks; those cohorts overlap. Targeted analysis reports no issues. Failed attempts and golden generation are not acceptance runs.

The installed signed app passed the actual Runner/native-worker probe: three warmups and 25 measured operations, stable descriptor count 9/9/9, copied results surviving disposal, and a separate successful NER request identifying a person, organization and place. Repetitions are operational evidence, not additional linguistic examples or broad accuracy measurements.

Normal LaunchServices startup then remained running for 15 seconds, reached Credential policy ready, and did not enter the diagnostic probe. The preview is left open. Both app and Finder extension report 1.3.4/build 32. Strict signatures, sandbox and library validation are retained. No store upload or release occurred.

The first universal attempt failed because the local Rust toolchain lacks its Intel target. A short superseded retry was stopped before rebuilding with Flutter's explicit ARM64 setting. The final build targets ARM64 and succeeds. Toolchain/plugin, Metal search-path, deprecated keychain API and stale debug-symbol module warnings remain in the build log; it is not warning-free.

[evidence-index.json](evidence-index.json) distinguishes accepted evidence from original failures and binds both original and redacted published hashes. Startup receipts contain bounded status only; private application startup logs and signing material are not published. No Actions jobs or CI status endpoints were queried, dispatched or awaited.
