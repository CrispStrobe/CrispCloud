# Incoming files and folders

Drop files or folders from the operating system or browser onto a file pane to open the normal **Copy** review. The review shows the captured destination account and directory. Select **Preview**, inspect the proposed work and conflict policy, then select **Start Copy**. Cancelling the review leaves destination files untouched.

The destination comes from the source actually displayed in that pane. A pane displaying a remote account receives the files in that account even when it occupies the usual local position. A pane displaying a local folder receives them locally even when it occupies the usual remote position. The transfer does not infer storage from pane position or the primary signed-in account.

## Destination ownership

The drop captures the current source, path, active tab, navigation intent, and verified directory listing. Destination access is checked without opening a new local access picker. A tab switch, account or grant replacement, navigation attempt, or listing refresh during preparation rejects the pending drop; repeat it at the intended destination. Search results, archive views, flat listings, and synthetic local roots without a directory grant cannot receive external drops.

Once the review opens, it owns the captured destination. Later pane navigation cannot redirect it. Changing the destination directory in the review is an explicit change within that captured source. Existing conflict checks, staged copy handling, and source-identity checks apply before execution.

## Files, folders, and lifetime

Native drops inspect the actual filesystem type rather than assuming every incoming path is a file. Regular files and accessible folder trees are supported. Links and special filesystem objects are rejected rather than followed. Exact duplicate selected paths are collapsed; distinct case-sensitive names remain in the review so destination collision checks can report a conflict.

Browser drops retain the supplied file handles and directory manifests. File contents are read when the copy executes, not written to a local folder during drop preparation. Folder drops require a browser-supplied tree of accessible child entries; incomplete directory manifests, invalid path components, and duplicate names within one captured directory are reported instead of being flattened or overwritten.

These are foreground transfers: keep the review open until copying finishes. Temporary browser handles and native security-scoped access belong to that review. They are released when it closes, and disposal cancels the operation. Scheduling, detached background execution, and durable recovery are unavailable for these temporary sources. A new drop is needed after the review closes or after an application restart.

## Bounds and validation

Captured browser trees are limited to 200,000 entries, 256 nested levels, and 8 MiB of accumulated encoded entry paths. Native directory listings are bounded by the same entry limit, and the normal copy planner applies its traversal bounds. Reads passed to the copy engine yield chunks no larger than 64 KiB and verify the captured byte count. Native file reads also check size and modification time before and after streaming. The browser or operating-system drop package may perform its own buffering before providing a file handle.

Regression coverage exercises source and destination identity, account/tab/navigation/grant changes during preparation, directory manifests, unsafe names, duplicate paths, file changes, temporary-access cleanup, actual pane drop callbacks, reviewed copy execution, and cancellation without overwriting existing content.

The final focused run passed 118 tests across six drop/operation suites plus the external-terminal service regression suite. Focused analysis found no issues. Real operating-system drag sessions, signed macOS access scopes, and actual browser handles still need the target-runtime checks recorded in G50/G51.

This entry covers external drops onto a pane's current directory. Internal file, folder-row, and tab drops retain their existing separate destination capture and review behavior.
