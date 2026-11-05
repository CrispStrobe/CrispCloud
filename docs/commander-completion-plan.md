# Commander completion implementation plan

Authorized scope: finish the Commander workflows and the broader correctness,
recovery, search, comparison, archive, and desktop integration work identified
in the parity audit. Development checkpoints are pushed incrementally to
`feature/commander-file-operations`.

Baseline: `0728973` (the first Commander implementation). This document records
implementation status, not a claim of universal Total/Double Commander parity.

## Delivery rules

- Keep the Riverpod/service boundaries and existing storage adapters.
- Bind every operation to its original storage/account and object/path.
- Persist references and operation state, never credentials or authenticated
  client objects.
- Describe backend guarantees precisely; never silently turn trash into
  permanent deletion, resume into append, or an accepted copy into a completed
  move.
- Commit and push reviewable increments, with focused behavioral tests.
- Treat unsupported platform/provider operations explicitly. Distributed atomic
  rollback and compatibility with every legacy binary plugin are outside a
  universal guarantee; usable recovery and first-party extension workflows are
  part of this plan.

## 1. Correctness and file identity

- [ ] Serializable storage/account/file references and captured target resolver.
- [ ] Consistent source binding and external-change checks for text/Office saves.
- [ ] Explicit trash/permanent-delete/restore contracts and native trash support.
- [ ] Sync Keep both preserves both versions end to end.
- [ ] Duplicate candidates require content confirmation before being called copies.
- [ ] Archive containment, expansion limits, format dispatch and folder packing.
- [ ] Precise per-operation capabilities and preview/execution validation.

## 2. Persistent history, operations and collections

- [ ] Versioned operation records with completed/staged/failed/recovery states.
- [ ] Batch rename history, reverse preview and complete-batch undo.
- [ ] Named collections with original source identity and missing/offline states.
- [ ] Refresh collection items separately from rerunning saved search definitions.
- [ ] Saved tabs/bookmarks retain storage identity; selection save/restore.

## 3. Rename and selection completion

- [ ] Editable proposed names, names from clipboard/files, row exclusion/order.
- [ ] Multiple transformation rules and applying results to the next transform.
- [ ] Explicit mask compatibility, richer path/date/metadata fields.
- [ ] Previewed collision numbering and case-sensitive name equivalence.
- [ ] Rename chains/cycles/case-only/nested selections with recorded staging.
- [ ] Selection memory, same-name/extension/path commands and pattern history.
- [ ] Reusable criteria across search, selection and transfers.

## 4. Copy/move options and efficient execution

- [ ] Destination filename/masks and saved options/profiles.
- [ ] Per-conflict rename/compare/apply-to-all and rename-existing-target.
- [ ] Additional size/date/content decisions and filter templates.
- [ ] Native and provider-side exact-destination fast paths with completion checks.
- [ ] Safe empty-directory cleanup and empty-result exclusion.
- [ ] Capability-based metadata, link, allocation and copy-on-write behavior.
- [ ] Separate data-copy and metadata-failure outcomes.

## 5. Recovery, queue and scale

- [ ] Persist queued jobs and validated resumable transfer state.
- [ ] Resume interrupted/retry remaining/restart with source-version checks.
- [ ] Queue reorder/priority/concurrency controls and waiting-for-decision state.
- [ ] Bounded streaming/spooling and incremental large-tree planning.
- [ ] Explicit recovery copies, cancellation outcomes and ambiguous-failure handling.

## 6. Complete desktop workflows

- [ ] Unified recursive search, scope/exclusions/content options and faithful presets.
- [ ] Compare/review/execute synchronization with per-item decisions.
- [ ] Editable text merge, binary comparison and large-file handling.
- [ ] Consistent archive member copy-out and supported edit/repack operations.
- [ ] Native file clipboard copy/cut/paste integration.
- [ ] Selected-file viewer navigation, reload/tail and remote read capabilities.
- [ ] Functional custom-command configuration/execution and extension lifecycle.
- [ ] Tab groups/locks, paired source-aware locations and column profiles.
- [ ] Checksum/split manifests, missing-part checks and cancellation.
- [ ] Keyboard/accessibility/localization completion for the added workflows.

## Acceptance scenarios

1. Rename and undo a batch larger than the old 50-action history limit.
2. Recover after interruption during a swap/cycle or transfer commit step.
3. Keep identical paths from separate accounts distinct after restarting.
4. Switching accounts cannot redirect editor saves, delete, undo, or paste.
5. Keep both really preserves two contents; duplicate confirmation compares content.
6. Trash returns a restorable identity and permanent delete remains explicit.
7. A reviewed search/sync/transfer plan cannot silently change source or destination.
8. Large files/jobs use bounded resources and respond to cancellation.
9. Archive extraction cannot escape its destination or exceed configured budgets.
10. Supported keyboard/menu/clipboard routes use the same operation semantics.

## Checkpoints

- Baseline audit and completion scope recorded. Parallel implementation uses
  isolated worktrees; finished commits are integrated and pushed to the feature
  branch in order. Remaining unchecked items are not represented as complete.

### 2026-11-05: requested workflow integration pass

The user-facing rename, selection, file-list and transfer workflows are now
connected and documented in `commander-file-operations.md`. This pass adds
editable/imported rename targets, row control, dialect/date/variable settings,
pipelines, collision numbering, one-action batch undo, remembered selections,
persisted pattern history, and source-aware panel drops. It also fixes transfer
conflict and profile edge cases and protects asynchronous history mutations.

Checkpoints `851158e`, `f069979`, `0739465`, and `44841b6` were pushed on the
original feature branch. Because that branch was receiving concurrent work,
the final pass continues on `feature/commander-workflow-polish`, forked from
`cb58160` with the incoming synchronization, clipboard and rename-journal work
preserved. The broader unchecked roadmap above remains separate from the
completed user-facing integration; in particular, the new journal engine has
its own contracts and tests, while this dialog currently executes independent
renames and uses session-bound batch undo.
