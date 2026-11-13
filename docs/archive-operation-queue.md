# Archive operation queue and background packing

Implementation branch: `feature/archive-operation-queue-20261113`.
Baseline: current main `3d9a8823e9e9d0830af433241dcc09bdc73a3901` plus the
retained archive acceptance documentation through `8d17b8d28b45d987a1bb6bf8d6dae62ee000bfa2`.

## Requested behavior

Archive creation and archive repacking join the existing operation queue, with
per-job pause, resume and stop, queue admission controls, priority, scheduling
and conflicting-path reservations. Background work is owned by the application;
closing its progress dialog or navigating a pane does not cancel it.

Native writer work runs in an isolate. Bounded pull streams keep source access
and output publication with the original operation owner. Pausing waits at safe
I/O boundaries; stopping releases a paused wait and settles owned resources.
Publication retains its existing verified commit/recovery transaction, including
the rule that a completed commit remains successful after a late stop request.

Creation recipes are saved before admission, without passwords or authentication
objects. An interrupted recipe is reviewed against the original storage and
selected sources before restarting packing. A recorded installed output is
verified before it can be reconciled as complete. This is distinct from resuming
a live paused encoder; partial compression streams are not appended after a
process restart.

Background workspace jobs retain their draft and handles while the application
is running. Failed/stopped drafts remain available for review in that session;
an already-started publication continues to use the durable archive publication
journal. Arbitrary in-memory draft reconstruction after process exit is not
implied by saving a creation recipe.

## Acceptance work

Implementation and runtime verification are in progress. Required checks cover
queue admission and shared reservations, real pause/resume, stop while paused,
stalled-stream cancellation, worker termination, dialog detachment, late-stop
commit reconciliation, recipe restoration, changed-source refusal, password
omission, and actual ZIP/7z/TGZ packing plus a workspace rewrite. Completed
results will be recorded with their exact source revision and hosted receipts.

## Primary comparison references

- Double Commander operation queue and controls:
  https://doublecmd.github.io/doc/en/copymove.html
- Total Commander background archive packing:
  https://www.ghisler.com/featurel.htm
- Existing CrispCloud queue semantics: [transfer-queue.md](transfer-queue.md).
