# Custom commands

Open **Custom commands** from the file toolbar or Settings. Add a command with
an executable, one argument per line, a working directory policy and a timeout.
Commands appear on the toolbar; selecting one opens a review of its captured
arguments. **Run** starts the program and shows bounded output, its exit code,
and cancellation/timeout status. The manager edits, reorders and deletes commands.
Its menu imports a reviewed JSON configuration or copies the configuration for
export. Configuration imports validate the entire list before saving.

Commands run in the desktop app on verified local files. A cloud or unresolved
collection row cannot be passed to a local program as though it were a local
path. Current and opposite-panel directories are captured before the review;
changing an account cannot redirect an invocation.

## Argument templates

| Placeholder | Expansion |
| --- | --- |
| `{SELECTED}` | One argument for every selected file/folder; must occupy a whole line. |
| `{FILE}` | The absolute path of exactly one selected item. |
| `{NAME}` | That item's complete name. |
| `{BASENAME}` | Its name without the final extension. |
| `{EXT}` | Its final extension without the dot. |
| `{CURRENT}` | The original local panel directory. |
| `{TARGET}` | The opposite panel's verified local directory. |

For example, configure an image tool as executable `/usr/local/bin/identify`
with argument lines `--` and `{SELECTED}`. Do not add shell quotes around a
placeholder. Each expanded filename stays one literal process argument,
including spaces, quotes, dollar signs and other shell characters.

Programs receive an argument array; CrispCloud does not invoke a shell around
the command. File placeholders in known interpreters' inline code arguments are
rejected. For a script, pass a fixed script path and supply file paths as separate
data arguments. A fixed POSIX shell script using `"$@"` may receive `{SELECTED}`
after its script and argument-zero parameters.

Existing saved shell command strings are preserved as **Legacy shell command**
entries. They remain inactive until reviewed and converted to executable and
argument fields. There is no silent interpretation of an old shell pipeline.

## Execution and bounds

Output is limited to 256 KiB by default and drained after truncation. Both stdout
and stderr are consumed concurrently; UTF-8 characters split across chunks are
decoded correctly. Cancellation first terminates the owned process and then
forces termination after two seconds if needed. The app stops waiting for
inherited output pipes during forced cancellation. Descendant process trees are
not guaranteed to terminate on every platform.

The default timeout is five minutes, configurable between one second and one
day. Definitions are limited to 64 KiB, at most 1,024 argument templates and 256
saved commands. Expanded invocations are capped at 10,000 arguments and 1 MiB.
Operating systems may impose smaller command-line limits, which are reported
as launch failures. Custom programs run with the user's ordinary OS permissions;
this is not an operating-system sandbox.
