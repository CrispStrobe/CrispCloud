# External terminal preferences

Use **Settings → External terminal**, or **Terminal actions → Open folder in
external terminal**, to choose an installed terminal executable and review the
folder to open. Preferences are saved separately for macOS, Windows and Linux.
The embedded terminal remains available independently.

Enter the executable's absolute path and one argument per line. Each line is
passed as one argument without shell parsing. Put `{directory}` on its own line
when the terminal needs its folder as an argument. The process working directory
is also set to the captured folder. Quoting characters in the editor are literal;
do not add shell quotes around the placeholder or a path containing spaces.
Blank argument lines represent empty arguments.

**Save** stores the preference. **Save and open** stores it and explicitly
launches the reviewed application. Opening Settings or loading a saved preference
does not run a process. **Reset** removes this operating system's preference.
Missing executables leave the review open so the installed path can be corrected.

## Source and launch boundary

The folder comes from the actual source in the active pane, captured before
asynchronous preparation. A local folder works in either visual pane. Remote
paths, archives, search results and flat listings cannot become local working
directories. Preferences remain editable when no eligible folder is open.

The review captures the source session, tab, listing, path and navigation intent.
It checks existing local access, directory availability and executable
availability before dispatching a launch. Changes during those checks cancel the
old request; there is no home-directory fallback or automatic access picker.
Closing or disposing the review prevents a pending preparation from launching.
After the operating system accepts the process launch, the external application
owns its window and lifetime. Closing CrispCloud does not terminate that terminal.

Executables use absolute paths rather than a platform-dependent command lookup.
Windows configurations require a native `.exe`; batch files and common command
interpreters are rejected. The launcher never constructs a `cd` command or a
shell command string. Only the standalone `{directory}` placeholder is supported;
unknown or embedded placeholders are rejected. Configuration is bounded to 64
arguments, 4096 characters per field, and 32768 characters in total.

Applications differ in their folder-opening arguments and whether they reuse an
existing window. Set arguments documented by the chosen terminal. This feature
does not inspect the launched terminal's internal state or claim that every
application supports working-directory arguments. Browser/mobile builds and
sandboxed store builds that prohibit external application launch show the feature
as unavailable. No SSH launch, remote file staging or privilege elevation is
implied.

## Implementation and validation

The implementation uses Dart's process API with `runInShell: false` and a
detached process. Dart documents that Windows batch files can still invoke a
shell despite this flag; rejecting batch executables avoids that fallback.
See the [official process API](https://api.dart.dev/dart-io/Process/start.html).
No library dependency was added.

Service tests cover literal arguments on both path styles, stale asynchronous
checks, missing/revoked paths, unsupported runtimes, safe errors, bounded settings,
per-OS persistence and localization completeness. Widget tests cover explicit
launch, preference-only saving, missing executable recovery, disposal, and narrow
German/Arabic layouts. Recorded execution results and remaining native GUI checks
are tracked under [G12](file-manager-gaps/02-viewing-search-and-tools.md#g12).

Native acceptance still requires launching an installed terminal on each claimed
desktop OS, checking the resulting folder, closing the review during preparation,
and verifying signed macOS access/sandbox behavior. Mocked process tests do not
replace these checks.
