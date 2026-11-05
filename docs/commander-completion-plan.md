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

- [x] Serializable storage/account/file references and captured target resolver.
- [x] Consistent source binding and external-change checks for text/Office saves.
- [x] Explicit trash/permanent-delete/restore contracts and native trash support.
- [x] Sync Keep both preserves both versions end to end.
- [x] Duplicate candidates require content confirmation before being called copies.
- [x] Archive containment, expansion limits, format dispatch and folder packing.
- [x] Precise per-operation capabilities and preview/execution validation.

## 2. Persistent history, operations and collections

- [x] Versioned operation records with completed/staged/failed/recovery states.
- [x] Batch rename history, reverse preview and complete-batch undo.
- [x] Named collections with original source identity and missing/offline states.
- [x] Refresh collection items separately from rerunning saved search definitions.
- [ ] Saved tabs/bookmarks retain storage identity; selection save/restore.

## 3. Rename and selection completion

- [x] Editable proposed names, names from clipboard/files, row exclusion/order.
- [x] Multiple transformation rules and applying results to the next transform.
- [x] Explicit mask compatibility, richer path/date/metadata fields.
- [x] Previewed collision numbering and case-sensitive name equivalence.
- [x] Rename chains/cycles/case-only/nested selections with recorded staging.
- [x] Selection memory, same-name/extension/path commands and pattern history.
- [x] Reusable criteria across search, selection and transfers.

## 4. Copy/move options and efficient execution

- [x] Destination filename/masks and saved options/profiles.
- [x] Per-conflict rename/compare/apply-to-all and rename-existing-target.
- [x] Additional size/date/content decisions and filter templates.
- [x] Native and provider-side exact-destination fast paths with completion checks.
- [x] Safe empty-directory cleanup and empty-result exclusion.
- [ ] Capability-based metadata, link, allocation and copy-on-write behavior.
- [x] Separate data-copy and metadata-failure outcomes.

## 5. Recovery, queue and scale

- [x] Persist queued jobs and validated resumable transfer state.
- [x] Resume interrupted/retry remaining/restart with source-version checks.
- [x] Queue reorder/priority/concurrency controls and waiting-for-decision state.
- [ ] Bounded streaming/spooling and incremental large-tree planning.
- [x] Explicit recovery copies, cancellation outcomes and ambiguous-failure handling.

## 6. Complete desktop workflows

- [x] Unified recursive search, scope/exclusions/content options and faithful presets.
- [x] Compare/review/execute synchronization with per-item decisions.
- [x] Editable text merge, binary comparison and large-file handling.
- [x] Consistent archive member copy-out and supported edit/repack operations.
- [x] Native file clipboard copy/cut/paste integration.
- [x] Selected-file viewer navigation, reload/tail and remote read capabilities.
- [ ] Functional custom-command configuration/execution and extension lifecycle.
- [ ] Tab groups/locks, paired source-aware locations and column profiles.
- [x] Checksum/split manifests, missing-part checks and cancellation.
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

- Source identity, captured saves, trash/restore, comparison, archive workspace,
  rename pipelines/cycles/history, persistent collections, branch/search/selection,
  transfer profiles/decisions, durable queue/recovery, clipboard, viewer playlist/
  tail, checksums and verified split/combine are integrated and pushed.
- Tab lock/order/label/source snapshots are integrated; named groups, paired
  bookmarks, profiles, custom commands and extension lifecycle are in progress.
- Native allocation/copy-on-write, bounded planning and the remaining legacy
  adapter streams are in progress. Conditional object-store staging and bounded
  Drive/Dropbox/WebDAV stream checkpoints are integrated.
- Commander localization/accessibility is in progress. Final broad tests, web
  build and platform CI follow integration.
- Parallel lanes use isolated worktrees. Finished checkpoints are integrated and
  pushed separately. Unchecked items are not represented as complete.
