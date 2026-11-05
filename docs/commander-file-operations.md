# Commander file operations

This feature extends the existing dual-panel workflows with multi-rename,
pattern selection, reusable file lists, and configurable copy/move operations.
Implementation is being checkpointed on `feature/commander-file-operations`.

## Behavior and design

- A selection belongs to its actual storage source and account. Search results
  retain their original absolute paths; duplicate basenames in different
  directories are distinct items.
- Multi-rename previews the complete plan before any change. Name and extension
  masks, counters, case conversion, and literal/regular-expression replacements
  compose in one operation. Invalid names, duplicate destinations, and existing
  targets block execution. Rename cycles are rejected rather than overwritten.
- Wildcards and regular expressions can replace, add to, subtract from, or toggle
  the visible selection. Invalid expressions leave the current selection intact.
- A results/file-list panel supports ordinary file commands, removal from the
  list without filesystem deletion, original-path export, and opening the
  containing directory. Refreshing a list must not silently turn it into an
  unrelated directory listing.
- Copy and move expose destination, conflict policy, filtering, directory merge,
  and relative-path preservation. Decisions and outcomes are per item. Failed,
  skipped, filtered, or cancelled copies must never cause source deletion.
- Operation execution captures its source/account before awaiting work and
  refuses to continue after the account changes. The editor's stronger origin
  checks remain in force.

## Implementation checkpoints

1. Establish feature branch and operation contracts.
2. Pattern selection and persistent source-aware file lists.
3. Multi-rename engine, validation, preview, and execution.
4. Configurable copy/move engine and integrated dialogs.
5. Menu/keyboard integration, regression tests, and user documentation.

## Reference behavior

- [Total Commander advanced tutorial](https://www.ghisler.com/advanced.htm)
- [Double Commander multi-rename](https://doublecmd.github.io/doc/en/multirename.html)
- [Double Commander file selection](https://doublecmd.github.io/doc/en/help.html)
- [Double Commander search results](https://doublecmd.github.io/doc/en/findfiles.html)
- [Double Commander copy/move](https://doublecmd.github.io/doc/en/copymove.html)

The implementation uses CrispCloud's Riverpod services and provider capability
contracts. Platform-specific Commander options are exposed only when the
selected storage backend can actually honor them.
