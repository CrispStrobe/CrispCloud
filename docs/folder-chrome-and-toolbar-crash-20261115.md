# Folder chrome and native toolbar follow-up — 15 November 2026

The centre splitter now paints a one-pixel neutral line inside its existing
six-pixel drag target. Horizontal/vertical dragging and double-click reset remain
available. File → New offers nine editor/format tiles with selected state and
responsive wrapping. Editing a folder path opens a separate full-width row below
the navigation controls; Enter/Escape retain their existing navigation/cancel
behavior and captured account/tab safeguards.

## Observed native crashes

macOS recorded matching main-thread SIGSEGV/EXC_BAD_ACCESS reports for builds
723ab5b4 and 8bf1a11f on macOS 26.2. Both stacks enter `objc_retain` from the
cached `MainFlutterWindow.browserNativeToolbar` getter in the method-channel
configure handler. The second report identifies process 58896 and an incident
time of 09:55:20 local time. These are actual crashes, rather than intentional
termination by the startup smoke test.

The native toolbar implementation now has a separate controller with a weak
window reference, serial main-queue updates and explicit teardown. AppKit's
`window.toolbar` owns the installed toolbar; a detached toolbar is no longer
cached and reused. Changing command sets installs a fresh toolbar; stable
command sets update in place. Hiding/closing clears the delegate and releases
the toolbar, unregisters the channel on close, and rejects a queued update after
teardown. Native actions also validate the current enabled command set.

`python3 tool/test_macos_browser_toolbar.py` compiles the production controller
against real Cocoa/AppKit with only a Flutter-channel stub. It checks 900 native
configure updates, folder/editor command transitions, light/dark appearance,
hide/show, release of detached toolbars and queued teardown rejection. The same
check runs in the existing macOS CI test job. This isolates the observed failing
ownership path; it does not establish the cause of arbitrary native memory
corruption elsewhere or promise that every possible app crash is eliminated.

The isolated legacy control also completed 900 updates without crashing. The
intermittent crash therefore has not been reproduced by this harness; longer
interactive use of the full app remains necessary to confirm the mitigation.
