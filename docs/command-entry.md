# Command entry

Command entry prepares a program launch from the active pane's verified local
folder. It opens the existing command review; the separate **Run** button is
required to start the process. Opening the entry, selecting a saved program,
loading settings, importing commands, and inserting names or paths never run a
program.

## Supported sources and programs

The implemented surface is available in native Linux, Windows, and macOS
desktop builds that permit process launch. The sandboxed Mac App Store build,
web, and mobile builds cannot launch from this surface. Native acceptance on
the claimed desktop targets is still pending.

The active pane must show a verified ordinary local directory. Either visual
pane can provide that directory. The source comes from its captured storage
origin, not its screen position or a dropdown label. Remote, archive, search,
collection, and flat listings are unavailable here; no remote path is silently
treated as a local file, and this workflow does not stage remote files.

The executable field accepts an absolute installed path or a program name.
Program-name lookup checks at most the first 128 entries of the current
process's `PATH`, retaining only absolute directories. Empty and relative PATH
entries cannot cause an implicit current-directory lookup. The first available
executable is resolved to an absolute path and shown in the review. A lookup
result is transient and is never saved as a reviewed command.

On Linux and macOS, the target must be a file with an executable permission bit.
Direct executable scripts rely on the operating system's executable-file
support. On Windows, this surface accepts `.exe` files only; a program name
without an extension gets `.exe`. It does not use `PATHEXT`, application
association lookup, batch files, or a shell command string. Known shell
executables are rejected. The recognized interpreters below have a deliberately
finite option grammar: inline-code and preload modes, and any prefix option
outside the listed subset, are rejected. Programs still interpret their own
arguments and option flags; use the program's usual option delimiter where
needed.

### Interpreter option boundaries

The following rules apply to `python` (including numeric names such as
`python3.13`), `node`, `nodejs`, `ruby`, `perl`, `php`, and `lua`, with an optional
`.exe` suffix. Both the entered name and resolved executable name are checked.
Other names, renamed runtimes, executable wrappers, script contents, inherited
environment settings, and runtime configuration are not interpreted by this
check. This is a supported invocation model, not an executable sandbox.

| Interpreter | Supported options before a script |
| --- | --- |
| [Python](https://docs.python.org/3/using/cmdline.html) | Short flags `b B d E h i I O P q R s S u v V x ?`; `-W` with a warning filter; `--help`, `--help-env`, `--help-xoptions`, `--help-all`, `--version`; `--check-hash-based-pycs` with a value. |
| [Node / nodejs](https://nodejs.org/api/cli.html) | `-c`, `--check`, `-h`, `--help`, `-v`, `--version`, `--no-warnings`, `--trace-warnings`, `--enable-source-maps`. |
| [Ruby](https://docs.ruby-lang.org/en/3.4/ruby/options_md.html) | Short flags `a c d l h n p s v w`; `-C`, `-E`, `-I` with values; exact `-W`, `-W0`, `-W1`, `-W2`; `--debug`, `--verbose`, `--version`, `--help`; `--encoding`, `--external-encoding`, `--internal-encoding` with values. |
| [Perl](https://perldoc.perl.org/perlrun) | Short flags `a c f h l n p T t u v V w W X`; `-I` with a directory; `--help`, `--version`. |
| [PHP CLI](https://www.php.net/manual/en/features.commandline.options.php) | Short flags `e H h i l m n s v w ?`; `-f` or `--file` with a filename; `--profile-info`, `--no-php-ini`, `--help`, `--usage`, `--info`, `--lint`, `--modules`, `--version`, `--syntax-highlight`, `--syntax-highlighting`, `--strip`, `--ini`. |
| [Lua](https://www.lua.org/manual/5.4/lua.html) | Exact options `-i`, `-v`, `-E`, `-W`. |

In the rows that list short flags, the letters follow a single `-` and may be
combined. A short option that takes a value consumes the rest of its argument,
or the next argument when its value is separate. Listed long options with
values accept `--option=value` or `--option value`. Missing required values are
rejected. Other forms, including unlisted optional-value suffixes and runtime
specific options, are outside this subset.

Inspection stops at a positional script filename, `--`, or the stdin marker
`-`. Later arguments remain unchanged even when they look like interpreter
flags. For example, `python3 /work/script.py -- -report.txt -c` passes those
values to the script. `python3 -ic "print(1)"` is rejected before review, as are
Node's `-p`/`--print`, Ruby's `-e`/`-r`, Perl's `-e`/`-E`/`-m`/`-M`, PHP's
`-r`/`-B`/`-R`/`-E`, and Lua's `-e`/`-l` before a script. Python module dispatch
(`-m`), Node's `inspect` subcommand, loader/configuration switches, and unknown
options are also unavailable. An ordinary Node script named `inspect` can use
an explicit path such as `./inspect`.

PHP's `-f`/`--file` consumes the filename while option parsing continues. Use
`php -f /work/script.php -- -r` to pass `-r` as data. Omitting `--` in this form
would select an interpreter mode and is rejected. The positional form
`php /work/script.php -r` already ends interpreter option parsing at the script.
These checks do not modify the final executable or argument list shown in the
review.

## Typed and saved programs

Choose **Type a program** to supply the executable and literal arguments.
Alternatively, select a configured program from the existing **Custom
commands** store. Its executable, timeout, working-directory preference, and
saved parameter templates are captured for this review. Saved templates expand
once from the captured local context. Typed arguments are appended after the
expanded saved arguments, and are never processed as templates.

For example, a saved `{NAME}` template can produce a filename containing the
literal text `{FILE}`. That text is passed unchanged. Typing `{NAME}` directly
in the entry also passes the literal text `{NAME}`. Old shell-string definitions
remain visible in the custom-command manager and cannot be selected for launch
until they have a valid executable/arguments definition. Shell launchers or
inline-code definitions are outside command entry's supported execution model.

The current local folder is the default working directory. A saved explicit
working directory must be absolute, accessible, and present. A saved `{TARGET}`
parameter requires a separately captured, current local folder in the opposite
pane. Its navigation and filesystem evidence are checked too.

## Argument syntax and insertion

Typed arguments use one platform-independent syntax. ASCII spaces, tabs, and
line breaks separate arguments. An argument beginning with a double quote must
be a complete JSON string followed by a separator or the end of the field.
JSON escapes apply inside those strings. Outside quotes, backslashes, single
quotes, braces, dollar signs, semicolons, pipes, and glob characters are literal
characters. There are no substitutions, variable expansion, glob expansion,
shell escapes, or adjacent quoted-fragment concatenation.

| Entry text | Arguments passed to the program |
| --- | --- |
| `--label "two words"` | `--label`, `two words` |
| `""` | One empty argument |
| `C:\work\report.txt` | One argument containing those literal backslashes |
| `"a\"b.txt"` | One argument containing `a"b.txt` |
| `"$(id); café {FILE}.txt"` | One argument containing that exact filename |
| `--label="two words"` | Rejected; use `--label "two words"` or quote the whole argument |

Insertion uses JSON encoding for every captured filename or full path. Spaces,
quotes, Unicode, backslashes, line breaks, and shell punctuation survive as
argument data. A caret between arguments inserts new arguments with separators.
A caret inside an existing argument, or a selection intersecting an argument,
replaces each intersected argument in full. This avoids leaving partial quotes
or concatenating a selected filename with existing text. The caret is placed
after the inserted text, and text composition is cleared.

The captured selection consists of the selected verified rows, or the cursor
row when no rows are selected. Parent-navigation rows are excluded. The entry
supports at most 256 captured items. Typed argument text is limited to 64 KiB
and 1,024 arguments; the expanded and appended invocation is limited to 10,000
arguments and 1 MiB of UTF-8 argument data. NUL characters are rejected.

## Keyboard ownership

| Stable action | Default | Scope |
| --- | --- | --- |
| `commandEntry` | Ctrl+Shift+O; Command+Shift+O on macOS | File browser command host |
| `insertCommandFilename` | Ctrl+Enter, including Control on macOS | Command entry only |
| `insertCommandPath` | Ctrl+Shift+Enter, including Control on macOS | Command entry only |

All three actions appear in the shortcut editor. Insertion actions have a
translated **Command entry only** label and their own conflict scope. They do
not appear as enabled ordinary browser menu actions. Their recorded modifiers
are exact; insertion defaults are Control conventions on every desktop target.
The entry shows the current saved binding beside each insertion button.

Custom bindings replace the corresponding defaults. Held-key repeats are
consumed after the initial insertion. Browser Ctrl+Enter retains its existing
other-pane navigation behavior outside the entry. The browser opener follows
the existing modal-route, text-input, editor, and terminal ownership guards.
Opening a command review is a separate button action and does not run the
program; the existing review's Run button remains mandatory.

## Review lifetime and execution

Capture occurs before asynchronous preferences loading, access probes, or
executable lookup. The capture retains the actual storage origin, panel
operation session, tab, navigation revision, directory, selected row identities,
and available selected-file metadata. A listener invalidates the capture when
its panel or selection changes; returning to the old selection does not revive
it. The dialog owns and releases that listener.

Preparation checks existing local access without opening a permission picker.
It inspects the selected files, working directory, any required target
directory, and the executable. Resolved symlink targets must have existing
access too. It compares selected rows with their available size, modification
time, and file/directory type, then records resolved path, type, size,
modification/change timestamps, and mode for the review.

Before Run reaches process creation, those paths and grants are checked again.
Every asynchronous boundary rechecks the original source and draft lifetime;
the final callback also checks that its review is still active. A changed
saved definition, typed draft, source, selection, executable, directory, grant,
or required target invalidates the review. Closing during preparation, closing
an unstarted review, or canceling final validation starts no process. A prepared
review is single-use. Once execution has begun, the existing cancellation,
timeout, bounded output, and exit-code display apply.

The runner receives one immutable `PreparedToolbarCommand`: executable,
separate literal argument strings, and working directory. The entry's path
does not perform a second template expansion or reparse an argument string.
`Process.start` uses `runInShell: false`. The existing review also checks that
its displayed prepared executable, arguments, and working directory still
match its ordinary saved-command inputs before launching.

Filesystem verification uses metadata available through Dart's filesystem API.
It is not an atomic executable handle or a cryptographic content identity.
Another native process can still replace a path between the last filesystem
check and the operating system opening it. Native acceptance must verify the
operating system's argument transport and permissions without claiming that
this path-based launch API eliminates that race.

## Validation and remaining acceptance

Focused tests cover argument parsing and encoding, caret/selection replacement,
literal saved-template output, PATH selection, Windows executable boundaries,
immutable argv, source and grant changes, executable replacement, cancellation
during final validation, and single-use reviews. Widget coverage exercises the
actual Run review, saved programs with typed arguments, default and customized
keys, narrow enlarged German and Arabic layouts, and all nine translated
string sets. Panel tests capture a local source in either visual position and
reject actual remote sources, navigation, tab, selection, and grant changes.

Real native acceptance remains pending for Windows argument quoting and
installed `.exe` programs, Linux/macOS executable permissions and symlink
behavior, signed macOS permissions and store-build restrictions, and operating
system keyboard dispatch while document editors and the terminal own input.
No new dependency was added.
