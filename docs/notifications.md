# Notifications and transfer dialogs

Copy and move can start directly with Enter or Start. Preview remains optional;
the same internal planner, path checks, conflict decisions and verification run
before I/O. Successful foreground transfers close their dialog after refresh.
Failures and unresolved results stay available for review. Archive publication
reviews retain their own separate contracts.

The browser's embedded queue hides when every job is finished, without deleting
its records. Its X hides the panel without cancelling work; a new job shows it
again. More actions → Transfer queue and recovery still exposes the management
view and history. Pending, paused, failed and recovery work is not automatically
hidden.

Every application notification bar has an X. The default timeout is 30 seconds,
including Undo actions, which Flutter otherwise keeps indefinitely. Settings
allows 5, 10, 30 or 60 seconds, or manual dismissal, plus an automatic completed
queue option. New notifications replace older visible bars. Closing or timing
out a bar does not invoke its action or cancel the underlying operation.

Settings also exposes a session-only notification history, capped at 200 text
entries, with a clear command and a logging toggle. Disabling history clears it.
No notification callbacks, document objects or history are stored on disk.
Existing transfer recovery/history and action Undo history are independent of
the transient bar lifetime.
