# Office fidelity consolidation — 12 November 2026

This continuation is on `feature/office-fidelity-consolidation-20261112`.
It combines app `main` at `f8dd29db4a00607513b7f687b21e4dc16e075735` with
the newer Office coverage branch at
`86338bdab58f46eeb68bb24d0916690874dfdca5`.

The corresponding source history combines current suite `main` and the newer
native fidelity work. The app now pins **308 shared source files** to
`6a9d858312dffe4a408df6844aed1639348a37f7`. The guarded synchronization verified
the previous vendor baseline, copied committed source bytes, and checked every
pinned hash against the consolidated suite.

## User-visible behavior retained and repaired

The app retains the newer paragraph/margin precision controls, styles, native
note marker preservation, note pane, localized Footnote/Endnote ribbon commands,
and actual heading/paragraph/note/image upload workflows from both branches.

The save guard now uses the controller's monotonic content revision. Typing in
the notes pane changes the model before it becomes an undo command; a counter
based only on command notifications missed that interval. A save captures the
revision after committing existing pending note edits. An older upload can
clear dirty state or close the editor only if that revision still matches.

Two real widget regressions pause an upload, type into the notes pane, verify
that no command notification has yet occurred, then release the upload. Both
Save and Save and Close must preserve the newer dirty edit. The next upload
must contain its exact note text before clearing state or closing.

The shared source also retains both branches' bookmark/content-control/note
regressions, image-cache disposal, richer native editing/history, native note
separator definitions and their absence, and strict per-part bookmark identity
checks. See the
[source consolidation report](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-consolidation-20261112/docs/office-fidelity-consolidation-20261112.md)
for the merge decisions and bounded support claims.

## Acceptance requirements

The merged engine inventory requires **241 Office packages**. The app's own
inventory requires **48 captured DOCX files**, including old/new uploads from
both pending-note scenarios. The gate verifies the vendor pin, runs the shared
scripted corpus and independent controls, executes the full declared Office
host test set with fresh coverage, and rejects missing or unexpected artifacts.

```sh
python3 tool/verify_office_fidelity.py
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
dotnet run --project tool/office-validation -- --self-test
```

The Office integration workflow additionally validates the exact engine and host
export bytes with Open XML SDK. The suite workflow covers reviewed Flutter page
goldens and independent source/repeated-save rendering. Those are separate
claims: an unsupported external renderer does not turn schema success into a
visual pass.

Fresh complete acceptance is in progress for this checkpoint. Older coverage,
schema, and render reports remain historical; the source run at `adcccb4` had
14 schema failures and 15 rendering-gate failures. This continuation regenerates
those outputs and receipts after the fixes instead of reusing the old evidence.

## Other remote work

The earlier Office completion/oracle branches and file-manager/SMB work are
already represented in `main`. No open PRs were found in the initial audit.
The separate ebook feature and explicitly unfinished Rust cloud-engine branch
were inspected and remain outside this Office consolidation.
