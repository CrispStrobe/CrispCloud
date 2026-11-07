# Embedded iOS shell and staged workspaces

The iOS terminal uses a bundled `ios_system` runtime and the ported Dash shell,
connected to the existing `xterm2` viewport through `TerminalConnection`.
It runs inside CrispCloud. There are no a-Shell or iSH app integrations, URL
schemes, companion-app requirements, or Linux virtual machines.

## Runtime and ownership

`packages/crisp_ios_shell` owns the native runtime, pinned upstream sources,
patches, command dictionary, input handling and bounded output transport.
`IosTerminalConnection` adapts that API to the existing session lifecycle.
`TerminalSession` still owns the viewport, input ordering, resize ordering,
connection generations, final output and teardown. The UI identifies this
backend as **iOS shell**, separately from the pure-Dart sandbox interpreter.

The package supplies shell syntax and the explicitly bundled commands. It does
not launch arbitrary downloaded executables or promise a general Linux runtime.
The initial input transport supplies canonical line editing; it is not a kernel
PTY and should not be described as supporting every raw-mode/full-screen Unix
program. See the package documentation for its command list and input limits.
SSH remains available for a remote host's complete environment.

There is one active native shell per app process. `ios_system` and its command
ports retain process-wide state, including the working directory. CrispCloud
passes absolute paths for its own file operations. A second native session
receives an explicit busy error. Startup failures remain visible and do not
silently switch the user to a different interpreter.

Output is drained before the native session is released. Closing an unlistened
or paused output stream still releases its native resources. Hiding the
terminal preserves its session; disconnecting or disposing it closes that
session. App suspension remains subject to normal iOS lifecycle rules.

## iOS folder access

`packages/crisp_ios_files` replaces the iOS calls to the macOS-only bookmark
plugin. The native directory picker returns a user-granted folder. Native code
persists and restores bookmarks, renews stale bookmarks when possible, and
rejects revoked or unrelated paths. App-owned Documents remains the safe
fallback.

Each operation receives its own access lease. A terminal keeps its grant until
the engine exits; a concurrent transfer, preview or second reader cannot release
the terminal's access. File-browser reads and mutations use native coordination
for document-provider URLs. A long-running terminal grant does not hold a
provider-wide coordination lock. Symlinks and path ancestry are checked at the
grant boundary; a textual path prefix is not proof of access.

The terminal chooses a verified local source, starting with the active pane.
Either pane can display remote storage, so neither the pane label nor a remote
path such as `/project` authorizes a local shell directory. Without a verified
local source it uses the local file service's initial directory.

## Working on cloud files

1. Select cloud files or folders in a verified file-panel listing.
2. Open **Terminal actions → Stage selected files**. CrispCloud downloads a
   persistent local workspace bound to that storage account and namespace.
3. The terminal opens in the workspace's files directory. Edit files and run
   supported shell commands against those local copies.
4. Choose **Review uploads** to inspect additions, modifications, local
   deletions and blocked paths. Select the files to send back.
5. Upload results show which files were uploaded and which remain local,
   including conflicts and provider capability failures.

**Staged workspaces** lists saved workspaces, opens their local files in a shell,
reviews changes and resumes interrupted downloads. Local copies survive closing
the terminal and restarting the app. Reconnecting the exact original account is
required for remote reads or uploads; merely selecting another account with the
same provider name is insufficient.

The workspace manifest records the storage identity, remote paths, original
revision metadata and content hashes. It contains no authentication credentials.
Inspection yields immutable review tokens. Before upload, the service rechecks
the manifest and copies reviewed content to private upload snapshots, so a later
shell edit cannot silently change the bytes approved in the review.

Remote mutations use the existing cloud operation backend and its provider
capabilities. A remote conflict or an unsupported safe replacement keeps the
local version and reports a failure. There is no fallback to an unchecked
overwrite. Not every provider supports the same conditional commit operations.
Local deletion is never propagated as remote deletion. Newly created directories
and unsafe/symlink paths are not silently uploaded.

Staging, inspection, snapshots and manifests validate containment and reject
ambiguous paths. Cancellation and interrupted operations retain recovery state;
they never treat an unfinished download as an original baseline or blindly
replay an uncertain remote commit.

## Build and tests

Use the Flutter version pinned in `.fvmrc`. The iOS app requires iOS 15 or newer.
The shell package preparation tool downloads only pinned upstream source archives,
verifies their hashes, and applies the reviewed local patches before compiling.
It is a build-time operation, not a runtime code downloader.

```sh
flutter pub get
python3 packages/crisp_ios_shell/tool/prepare.py

(cd packages/crisp_ios_shell && flutter pub get && flutter test --coverage)
(cd packages/crisp_ios_files && flutter pub get && flutter test --coverage)

flutter test test/ios_terminal_connection_test.dart \
  test/terminal_backend_metadata_test.dart \
  test/terminal_directory_test.dart \
  test/terminal_workspace_dialog_test.dart \
  test/terminal_session_test.dart \
  test/terminal_scoped_access_test.dart

swift test --package-path packages/crisp_ios_files/ios/ScopeCore
packages/crisp_ios_shell/tool/test_native.sh SIMULATOR_UDID
flutter build ios --release --no-codesign
```

The package suites cover the native-channel contract, input, stream decoding,
backpressure, errors and lifecycle. Workspace tests use real temporary files and
fake cloud backends to exercise recovery, identity, containment, reviewed content
and remote conflicts. Folder tests cover bookmark/lease ownership and coordinated
operations. Native XCTest tests execute the actual embedded runtime on an iOS
simulator; the device build separately checks the arm64 application linkage.

Before release, exercise the signed app on a physical iPhone or iPad: choose an
external provider folder, relaunch with its grant, revoke access, open a staged
workspace, use non-ASCII filenames, interrupt a command, hide/show the terminal,
background/foreground the app, and upload after both a local and remote edit.
Simulator and Linux unit results do not replace this device check.
