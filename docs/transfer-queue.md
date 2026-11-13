# File and archive job management

CrispCloud owns the plan, queue, progress and recovery history. Its existing
provider adapters execute the work. The rclone and Robocopy comparisons below
inform the behavior; this feature does not install or invoke either executable.

## Working with the queue

1. Select files and use Copy or Move. Choose conflict handling, filters,
   preservation, verification and performance options, then **Preview**.
2. **Start** keeps the operation dialog open. **Queue in background** closes it
   after the complete plan has been saved. **Schedule** records an earliest
   start date and time and queues the reviewed plan.
3. The operations panel shows running, queued, scheduled, paused, waiting,
   completed, cancelled and review states. Search matches names and paths;
   filters and selection provide bulk pause, resume and cancel controls.
4. A queued job's menu changes priority, moves it to the front/end, or changes
   its start time. Run now clears the start-time restriction; queue pause,
   individual pause, capacity and conflicting paths still apply.
5. **History and recovery** reviews stopped work, resolves deferred conflicts,
   and resumes remaining entries using the existing reconciliation service.

### Two different pause controls

**Pause queue** stops admission of new work. It preserves the configured
parallelism and lets already-running jobs finish. It also applies to jobs added
while the queue is paused. Resuming the queue preserves individually paused
jobs. Queue pause is saved separately from concurrency.

**Pause selected** cooperatively pauses those operations at their existing
transfer checkpoints. A provider-native operation may reach a checkpoint only
after its current request completes. An active paused job retains its slot and
path reservations because it may still own a staging file or a mutation in
progress. Cancel also cooperates with the backend; it is not a rollback of
completed copies or moves.

### Scheduling and parallelism

Start times are selected in the device's local time and persisted as UTC
instants. They are earliest eligibility times, not deadlines. Delayed jobs do
not occupy transfer slots, and ready unrelated work can pass them. One wake
timer services scheduled starts and provider pacing.

Scheduled starts run while CrispCloud and its foreground queue are alive.
After process termination, active and queued plans become interrupted records
requiring review and account rebinding. A saved date does not authorize
automatic destructive recovery. Mobile background execution and browser tab
suspension retain their platform restrictions. This is a one-time start, not a
cron rule, operating-system wake alarm or recurring synchronization policy.

The concurrency setting bounds scheduler tasks. A reviewed copy/move plan uses
one task and executes its entries serially; existing upload/download batches
can use a task per file. The panel counts distinct jobs rather than displaying
a 100-file upload as 100 jobs. Increasing the setting does not turn a copy/move
plan into unbounded per-file parallelism.

## Archive jobs

Native archive creation and edited-archive publication use this same queue.
**Queue in background** saves a credential-free creation recipe before admission;
**Run in background** detaches an already-running progress view. A workspace’s
**Save in background** confirms its current changes and transfers draft ownership
to the job. Compression runs in a native isolate with bounded streams.

Per-job Pause/Resume/Stop, bulk controls, priority, reorder and scheduling apply.
Queue pause holds new work; selected-row pause controls cooperatively pause eligible live jobs.
Stop wakes paused workers. The original-to-backup/install-or-restore
transaction is not suspended with the original absent. Verified publication
remains completed when a late Stop or completion observer fails.

History routes archive jobs to archive recovery. A saved creation recipe binds
its original storage, selection and output, and restarts into a fresh private
candidate after review. Passwords must be entered again. Once recorded, the
source manifest digest also detects changed bytes with restored size/time.
An occupied output is reconciled only by a complete matching hash/length check.
In-session stopped workspace drafts remain available for reviewed retry;
arbitrary draft reconstruction after process exit is not implemented. Existing
archive publication recovery still owns any recorded candidate and backup.

See [archive operation queue](archive-operation-queue.md) for the implementation
and exact acceptance evidence.

## Admission and path reservations

The journal admits one owner for each stable job ID before any asynchronous
job mutation. Ownership remains live through execution and completion
persistence. A second recovery, history removal or backup restore cannot take
over that job during admission or finalization.

Each copy/move job declares reservations before execution:

| Resource | Copy | Move |
| --- | --- | --- |
| Selected source paths | Shared read | Exclusive write |
| Destination directory and planned output paths | Exclusive write | Exclusive write |
| Saved staging and backup locations used by recovery | Covered by destination reservations | Covered by destination reservations |

Claims use the backend/account identity and its normalized collision path
segments. Parent/child paths overlap; similarly named siblings do not. Read
claims can coexist. Write/write and read/write overlap waits. Whole destination
directories are intentionally reserved so keep-both names, staging names and
backup paths cannot race another queued job in that directory. Disjoint
directories and independent accounts can still run in parallel.

Claims are indexed by storage namespace and path segments. Large flat selections
do not compare every selected file with every file in another job, and changing
priority or start time reuses the existing index.

Both source and destination identities participate in configured provider
capacity and rate limits. Existing single-provider scheduler callers remain
compatible. Provider pacing waits outside active slots where possible.

Reservations stay in place until execution **and the asynchronous completion
callback** have settled. Cancelling a running job never releases reservations
while its executor can still mutate storage. Pending cancellation, reordering
and priority changes retain exactly one completion callback. A finalization
callback error is recorded/reported, releases resources, and never causes
execution replay.

These are in-process queue reservations, not filesystem locks or distributed
transactions. Other applications, independently configured aliases for the
same remote storage, and other CrispCloud processes can still change files.
Existing execution-time source and destination checks remain necessary.
Legacy upload/download and unrelated editor/sync paths are not automatically
covered by a copy/move plan's reservations unless they declare the same claims.

## Progress that reflects current work

The queue summary groups underlying tasks by operation ID and separates
running, queued, scheduled, paused and attention states. Completed historical
bytes do not inflate the progress of current work. Only running, unpaused jobs
contribute to the displayed throughput. Unknown byte totals stay indeterminate.

Per-batch counters distinguish successfully copied/moved items from processed
items. Skipped and filtered rows are processed, but are not reported as copies.
Pause/resume and a restarted stream reset the speed-sampling window, preventing
negative throughput and stale estimates. Displayed bytes describe logical
transfer progress; they are not a measurement of all network traffic, including
verification, metadata and server-side work.

## Recovery and move safety

The existing journal is the authoritative record. It persists the complete
reviewed plan before storage mutation and checkpoints individual entries.
Recovery validates captured storage identity, source changes, existing outputs,
partial copies and committed destinations before choosing remaining actions.

Journaled copy/move tasks explicitly disable the scheduler's whole-task retry
loop. Retrying a partially executed destructive plan without reconciliation
could repeat publication or source deletion. Request-level adapter behavior and
the existing bounded retries for ordinary transfer tasks are separate concerns.

Keep the existing staged publication, requested verification, metadata handling,
source revalidation and empty-directory cleanup. When a move has copied content
but still needs metadata or source cleanup, review uses that checkpoint rather
than blindly copying everything again. Content verification remains an explicit
operation option; a size check is not presented as a cryptographic verification.

Restoring a saved backup requires running transfers to finish first. Restoration
holds new queue dispatch until verification, rename and completion persistence
settle, then restores the user's dispatch policy. This deliberately serializes
rare backup restores and also protects them from legacy upload/download workers.
Queued and scheduled plans can remain in the queue during restoration.

## Reference feature mapping

The comparison is based on the official documentation accessed on 2026-11-06.

| Requirement | rclone / Robocopy reference | CrispCloud behavior |
| --- | --- | --- |
| Preview | `--dry-run`; `/L` | Existing reviewed path and conflict plan |
| Bounded concurrency | `--transfers`, `--checkers`; `/MT` | Shared task budget, endpoint accounting, path-aware admission |
| Start control | Bandwidth timetables; `/RH`, `/PF` | Earliest start, independent queue pause, individual pause |
| Retry | CLI retries and low-level retries; `/R`, `/W` | Bounded ordinary task retries; reviewed recovery for partial copy/move jobs |
| Selection | Include/exclude, age and size; `/XF`, `/XD`, `/MIN`, `/MAX` | Existing file/directory filters and shared search criteria |
| Existing destinations | `--update`, `--ignore-existing`, `--immutable`; `/XO`, `/XN` | Existing ask, skip, replace, conditional replace, keep-both, append and verified-prefix resume policies |
| Metadata | `--metadata`; `/COPY`, `/DCOPY`, `/SEC` | Existing backend-capability-controlled preservation options |
| Verification | `check`, `--download`, available hashes | Existing explicit content verification and recovery evidence |
| Efficient transfer | Server-side copy/move; restartable `/Z` | Existing native/server-side operations, clones, provider multipart and verified-prefix recovery where supported |
| History | RC job status/stats and logs; `/LOG`, `/UNILOG` | App-owned journal, per-entry results, history and reviewed recovery |
| Destination purge | `sync`; `/MIR`, `/PURGE` | Outside ordinary copy/move queue semantics; never inferred from a copy request |

Important differences from blindly exposing command-line flags:

- rclone RC job IDs are scoped to a process execution, finished jobs expire,
  and the transferred-item statistics are bounded. They cannot replace a
  durable app journal. An external rclone adapter would need versioned identity
  and reconciliation, not polling alone. [Remote Control API][rclone-rc]
- rclone's checksum comparison may fall back to size when a usable checksum
  is absent. Backend capability and actual verification evidence determine
  what the UI can promise. [Global flags][rclone-flags]
- Robocopy defaults to a very large retry count; its return codes below 8 do
  not mean copy failure. A future Windows execution adapter would need explicit
  retry settings and status decoding. `/MOV` and `/MOVE` would bypass an
  application-controlled verification-before-deletion gate. [Robocopy][robocopy]
- Queue restart recovery is different from resuming the current file at an
  arbitrary byte. Capability checks remain necessary for provider resumable
  uploads, range reads, server-side operations and metadata.

## Validation

Focused deterministic regressions cover dispatch pause and its persistence,
scheduled wake/reschedule/cancel, resource hierarchy and endpoint boundaries,
asynchronous finalization, duplicate recovery admission, operation-level
summaries, skipped-item counts, throughput resets, schedule journal replay and
compaction, responsive filters/selection and deferred conflict review.

Run the focused suite with the pinned SDK:

```sh
flutter test test/transfer_job_scheduler_test.dart \
  test/transfer_job_management_test.dart test/transfer_job_schedule_test.dart \
  test/transfer_queue_controls_test.dart test/transfer_queue_reorder_test.dart \
  test/transfer_queue_test.dart test/transfer_recovery_test.dart \
  test/operation_progress_test.dart test/widget/operations_panel_test.dart \
  test/widget/file_operation_dialog_test.dart \
  test/widget/transfer_history_dialog_test.dart test/commander_strings_test.dart \
  test/file_operation_phase_guard_test.dart test/file_operation_service_test.dart \
  test/file_operation_backend_test.dart test/file_operation_metadata_test.dart \
  test/transfer_stream_control_test.dart test/background_transfer_journal_test.dart
```

Provider-specific resumability, native Windows/macOS metadata, disk-full behavior
and mobile background lifecycle continue to require their existing platform and
live-provider tests. The deterministic queue suite does not establish those
external guarantees.

[rclone-rc]: https://rclone.org/rc/
[rclone-flags]: https://rclone.org/flags/
[robocopy]: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
