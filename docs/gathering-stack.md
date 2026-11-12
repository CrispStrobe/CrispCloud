# Gathering stack

The gathering stack keeps references to files and folders from independent
locations and accounts. Select items in a file panel and choose **Add selection
to gathering stack**. Repeat from other folders, then open the intended
destination folder and choose **Gathering stack**.

The stack is saved between sessions. It contains references and display details;
adding an item does not copy its contents. You can remove references or change
their order without changing the original files. Gathering an existing object
again refreshes its saved details in the same position. Identical filenames in
different accounts remain separate references, with their source and original
path shown in the stack.

## Check and transfer

**Refresh** checks the original sources. Missing paths, offline accounts, and
replaced objects remain visible. A replacement is not accepted automatically:
remove that reference and gather the current original from its folder. If a
source only supplies path and metadata evidence, the check can establish only
what that source exposes. It cannot prove that a same-path replacement with
identical metadata is the original object.

Choose **Review copy** or **Review move** to check the whole stack and review the
captured destination. The overview shows every reference before any transfer
starts. The destination stays fixed through the following transfer reviews.
Each source account then opens the existing transfer options and conflict
workflow. Matching names use the normal conflict decisions. Accounts run in
sequence; this is not an atomic transaction across accounts.

Only confirmed successful references leave the stack. Canceling a preview keeps
all its references. After a partial transfer, copied or moved files are removed
while failed, skipped, filtered, canceled, and untouched references remain.
A folder stays until its whole planned tree succeeds. A moved folder also needs
confirmation that its original directory was removed. Successful earlier
accounts stay recorded even if a later account review is canceled.

## Availability and limits

Saved references resolve only to the original account and storage namespace.
Changing the destination tab, folder, or account while preparing a review stops
that review. Reconnecting does not silently replace a source captured by an
already open review; refresh or reopen it to start a new attempt.

Browser folder grants and anonymous source sessions cannot be restored from a
saved path. Their references remain visible after the session ends, but must be
gathered again. Files are not staged for later recovery, and stack transfers stay
in the foreground. Existing transfer history may have its own backend-specific
recovery support; the stack does not add any recovery guarantee.

The stack holds at most 1,000 references and 2 MiB of saved reference details.
Verification has a 30-second deadline and can be canceled without waiting for a
slow provider response. The normal transfer planner retains its own limits of
200,000 planned entries and 256 folder levels for each source group. Canceling
verification or a preview writes no destination data.

Native dragging from the stack to another application is outside this feature.
Native outgoing drag remains the separate G06 scope. Signed sandbox behavior,
actual browser handles, and live-provider behavior still require their target
runtime acceptance checks.

## Technical notes

The stack reuses `FileCollectionEntry`, `FileReference`, collection verification,
and the existing native/browser collection record storage. One bounded,
versioned record is published with compare-and-swap. A failed publication leaves
the previous saved record intact; a post-commit adapter error is checked by
reading the committed value back. No dependency was added.

Reference identity includes the storage ID and namespace root, then the stable
object ID when available or the exact normalized path. It never uses a filename
alone. Each explicit gather receives a new ticket, including a deduplicated
reference, so a late operation result cannot delete a newer gather of the same
object. Completion cleanup compares both the ticket and its original evidence.

All source capabilities and the destination are captured before asynchronous
inspection. A review also captures stack intent; edits and newer checks
invalidate older work. Original object evidence is compared again with the
ordinary planner's root snapshots before its preview becomes executable. The
existing execution path then performs its normal source and conflict checks.

The host functions are `addPanelSelectionToGatheringStack` and
`showGatheringStackDialog`. `FileOperationDialog` provides optional fixed
destination, preview-validation, and settled-foreground-plan callbacks.
Existing callers keep their previous behavior. Gathering consumes each settled
account plan immediately and persists only its confirmed removals before the
next account can proceed.

Verification reuses the collection service's bounded directory snapshot cache
in batches of at most 128 references. Canceling or timing out stops acceptance
of any late results; an underlying provider request may still finish its
read-only work. No network request is advertised as forcibly interruptible.
