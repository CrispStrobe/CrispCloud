# Selection memory

Use **Restore Selection** from the selection menu or command palette, or press
**Numpad /**, to restore the last remembered marks in the current tab. The
keyboard action is configurable under **Settings → Customize shortcuts**.
The ordinary slash key retains its usual behavior, and text fields, dialogs and
terminals retain ownership of their input.

Copy and move reviews capture the marked source rows when opened. The capture
becomes the tab's remembered selection only after the transfer has passed its
checks and entered the durable operation queue. Cancelling a review, failing
preflight or failing to save the queued transfer preserves the earlier memory.
Later changes to the live selection cannot change the captured set.

Deletion and trash remember the selection after the first successful removal.
Single and multiple rename remember it once the rename journal contains work
that can be restored. A partially completed batch therefore retains its original
marks as well. An invalid name or a destination conflict found before any rename
preserves the earlier memory. **Remember Selection** remains available for an
explicit snapshot without running an operation.

Memory belongs to the original tab, storage account, connection and access
grant. A delayed completion cannot replace the memory after the user changes
the tab, listing or source. Cursor-only actions and external clipboard rows do
not replace an existing marked selection with unrelated files.

Restoration resolves the original paths against fresh, verified rows. It checks
object identifiers when the source supplies them. Missing paths, replacement
objects and unavailable sources are skipped; when nothing matches, existing
marks remain intact. A move, rename or delete may leave no original paths to
select until it is undone. Restore Selection does not undo file operations.

Paged collections retain marked rows from every page, including off-screen
rows, and revalidate them before restoration. Automatic snapshots are bounded
to 100,000 entries and 4 MiB of selection metadata. Collection memory shares
those bounds across tabs. Memory remains in the current app session.
