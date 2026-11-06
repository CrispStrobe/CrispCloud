# Commander completion implementation plan

Authorized scope: finish the Commander workflows and the broader correctness,
recovery, search, comparison, archive, and desktop integration work identified
in the parity audit. Development checkpoints are pushed incrementally to
`feature/commander-file-operations`.

Baseline: `0728973` (the first Commander implementation). This document records
implementation status, not a claim of universal Total/Double Commander parity.

## Current completion review

**Feature completion is still under verification in draft PR #15.** The earlier
checkboxes recorded broad areas as delivered but did not establish that each
promised workflow worked. A source-level review on 6 November found missing
selection actions, buffered sync transfers, incomplete directory/native metadata,
archive filtering and nested-navigation gaps, background conflict handling,
and viewer/comparison limits. This follow-up implements those behaviors and
records the remaining acceptance work explicitly.

| Workflow | Current follow-up state | Acceptance evidence |
| --- | --- | --- |
| Sync copy, move and Keep both | Staged streaming, reviewed-row validation and optional full-content comparison | Stream-only 33 MiB upload, failed replacement, same-size/time edits, stale equal rows, ambiguous baselines, cancellation |
| Saved sync sources and cloud-only files | Account/device/root binding, explicit legacy rebind, safe placeholders and hydration | Wrong account/endpoint/bucket/device, old queued token, placeholder must not delete remote original, verified eviction |
| Transfer metadata | Post-order folder metadata, source retention, selective reads; Windows SID/DACL/attribute/creation-time implementation integrated | File/folder metadata failure, retry without recopy, Linux ownership/xattrs/access/default ACLs; macOS/Windows runtime fixes remain in the platform gate |
| Duplicate names and rate controls | Configurable template and cancellable client stream rate | Preview/late collision/recovery consistency; pause/cancel/multiple-file byte pacing |
| Selection and saved filters | Same extension/stem/parent, paths as marks, exclusion consistency | Captured source, same path on different accounts, list/cursor unchanged, Shift+Numpad routes |
| Content and archive search | Full-stream literal search; bounded regex/Office/archive extraction with reported limits | Hit beyond 64 MiB, split encodings, late read failure, archive dates/exclusions and retained member evidence |
| Background Ask transfers | Waiting state and Resolve action; does not occupy a worker | Restart/revalidate/resolve, durable cancel, later jobs continue |
| Bulk attributes | Reviewed mode/owner/time edits and masked Windows attributes | Stale source/revision/metadata, directory access-time enumeration, child-before-parent, unrelated Windows flags retained, German/Arabic controls |
| Large-file viewer | Full-file decoded/byte search, complete match navigation and bounded Unicode text windows | Match after 64 MiB, 2,002-match navigation, split UTF-8/16, reload/debounce cancellation, decimal/hex offsets |
| Nested archives | Integrated bounded browser snapshots and owned nested workspaces | Generated 257 MiB native stream, exact member identity, parent restoration, nested save/retry and outer-file conflict |
| Text/binary comparison | Integrated per-side decoding, guarded merge and full binary-range navigation | BOM-less UTF-16/32, repeated CRLF saves, sparse difference index, all range navigation, cancellation, German/Arabic layout |
| Background sync recovery | Integrated isolated leased journals and idempotent foreground discovery | Same-process isolate exclusion, process kill, import retry/receipt/compaction, successful and failed background tasks; OS checks in desktop CI |
| Split/combine review | Complete effective manifest definition rechecked before destination writes | Same-path/same-size/mtime replacement blocked, harmless formatting accepted, explicit new review required |
| Legacy rename/New Folder routes | Source-binding and truthful outcome follow-up in progress | Captured prompt destination, durable single-rename/Undo fingerprints and visible submit errors |
| Final integration | In progress | Current-head analysis, deterministic app suite, focused platform tests and builds; earlier baseline CI is not evidence for new code |

## Delivery history

The implementation reached `main` through
[PR #13](https://github.com/CrispStrobe/CrispCloud/pull/13) at `0b35b16` on
6 November 2026. The original [PR #12](https://github.com/CrispStrobe/CrispCloud/pull/12)
was closed after that integration. Its final documentation and S3 spool-cleanup
regression checkpoints are retained on `feature/commander-file-operations`,
reconciled with the merged fixes for follow-up review.

The [merged-head CI run](https://github.com/CrispStrobe/CrispCloud/actions/runs/42139152722)
passed the deterministic application suite (6,006 passed, 12 skipped), storage
and CLI contracts, desktop crypto checks, and all six platform builds. These
results describe `0b35b16`; validation of a later follow-up belongs to that
follow-up's own CI run. See the [workflow guide](commander-file-operations.md#verification)
for the validation scope and platform boundaries.

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
- [x] Saved tabs/bookmarks retain storage identity; selection save/restore.

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
- [x] Bounded streaming/spooling and incremental large-tree planning.
- [x] Explicit recovery copies, cancellation outcomes and ambiguous-failure handling.

## 6. Complete desktop workflows

- [x] Unified recursive search, scope/exclusions/content options and faithful presets.
- [x] Compare/review/execute synchronization with per-item decisions.
- [x] Editable text merge, binary comparison and large-file handling.
- [x] Consistent archive member copy-out and supported edit/repack operations.
- [x] Native file clipboard copy/cut/paste integration.
- [x] Selected-file viewer navigation, reload/tail and remote read capabilities.
- [x] Functional custom-command configuration/execution and extension lifecycle.
- [x] Tab groups/locks, paired source-aware locations and column profiles.
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
- Tab lock/order/label/source snapshots, named groups, paired bookmarks, editable
  column/view profiles and their managers are integrated. Custom command editing,
  review, bounded execution, extension lifecycle and the active file-panel
  command bar are integrated. Native/overflow/palette and both ordinary/collection
  context menus reach the verified action hosts.
- Native allocation/copy-on-write and cancellable bounded planning are integrated.
  Conditional object-store staging, Drive/Dropbox/WebDAV bounded streams, dedicated
  FTP/FTPS transfer sessions and disk/OPFS spooling are integrated.
  pCloud/B2/Nextcloud/SMB/Filen/Internxt streams, large S3 parts and exact saved
  multipart-session binding are integrated. The optional AES-GCM wrapper
  authenticates private spools before exposing plaintext; each provider retains
  its documented encryption format. Unbounded adapter defaults are rejected.
- Rename, selection, lists, transfer/recovery, workspaces, viewers, archives,
  comparison, integrity, extension and provider-action controls are localized
  across all nine app languages, with narrow German/Arabic layout regressions.
  Command palette keyboard navigation, locale changes and dialog handoff are
  covered by focused tests. New follow-up controls are checked against the
  expanded catalog and are included in the final integration gate.
- Parallel lanes use isolated worktrees. Finished checkpoints are integrated and
  pushed separately. Platform/provider boundaries remain explicit in the
  [workflow guide](commander-file-operations.md).
