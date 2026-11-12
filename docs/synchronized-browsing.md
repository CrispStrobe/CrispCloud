# Synchronized browsing

Open matching folder roots in the two panes, then choose **Start synchronized
browsing** from the link button, the tools/overflow menu or the command palette.
The chosen roots may have different names and can belong to different local or
remote sources. A status strip shows the linked roots while the feature is on.

Navigation below either root opens the same relative folder in the other pane.
For example, `/work/photos/2026` can follow `/backup/photos/2026` when `/work`
and `/backup` are the chosen roots. Going back up to a chosen root works too.
Selection, sorting and refresh do not cause extra navigation. The active pane
and keyboard focus remain with the user.

This feature only browses folders. It does not synchronize file contents,
create missing directories or start transfers. Use the folder comparison or
sync workflows for those operations.

## When the link stops

- A matching folder is missing, inaccessible, or reported as a symbolic link
  by a remote provider.
- Either pane leaves its chosen root, changes tabs, enters an archive or
  collection, or switches storage accounts.
- A source disconnects or reconnects, even with the same persisted account ID.
- A tab becomes locked, or a newer navigation supersedes an asynchronous
  counterpart check.

The status strip explains why browsing stopped. A missing counterpart is
checked before navigating the other pane, so its existing folder remains
visible. Open the desired roots and start again to establish a new link. Links
are transient and are not automatically restored after application restart.

The service uses the verified source behind each pane rather than inferring a
source from its left/right position. It captures the account session, tab and
root, and revalidates after asynchronous checks. Linked navigation only uses
access already granted; it never opens a folder picker. New manual navigation
takes priority even while its access check is still pending. Stopping the link
also cancels a pending follow before it changes the destination path.
Path components are mapped
between native and remote path styles without allowing traversal outside the
chosen roots. Root containment uses the displayed paths; local directory links
follow normal filesystem rules within existing access grants. Normal filesystem
permission and provider listing rules apply.

## Verification

`test/synchronized_browsing_service_test.dart` exercises navigation in both
directions, loading states, missing folders, root containment, source/session/tab
changes, superseded checks, explicit stop/restart, permissions and Windows/POSIX
path mapping. `test/synchronized_browsing_panel_test.dart` exercises real panel
controllers with independent remote sources and native local directories.
