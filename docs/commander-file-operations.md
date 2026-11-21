# Commander file operations

CrispCloud captures each item’s original storage account and path before a
command runs. The left/right pane label never decides which account an
operation changes.

The full implementation and recovery contract is preserved in the
[Commander details](commander-file-operations-details.md).

## Entry points

| Action | Default |
| --- | --- |
| Multi-rename | `Ctrl+M` |
| Select/deselect by wildcard/regex | `Numpad +` / `-` |
| Same extension | `Shift+Numpad +` / `-` |
| Invert selection | `Numpad *` |
| Copy / move review | `F5` / `F6` |
| File clipboard | `Ctrl+C` / `Ctrl+X` / `Ctrl+V` |
| Import path list | `Ctrl+Shift+L` |
| View / edit | `F3` / `F4` |

Relevant Ctrl shortcuts accept Command on macOS. The three-dot menu, context
menus and command palette expose the same actions.

## Source identity

- Identical paths in different accounts remain different items.
- Search results, archive members and saved collections keep their origin.
- A different object at the same path requires review before mutation.
- Unavailable accounts, missing items and changed metadata are reported
  separately.
- A collection from another computer cannot bind to unrelated local files with
  the same path.

## Collections

Named collections persist source-aware references, marks and optional search
definitions. They load through bounded pages; sorting and filtering scan the
full match set while keeping only a small result window.

- Removing a collection or row does not delete its files.
- Delete files is a separate operation.
- Marked off-page items are validated before use.
- Reloading discards unsaved marks.
- Collection JSON preserves accounts; plain path lists must be imported against
  the correct source.

## Search and selection

Search supports explicit roots, recursion/depth, wildcard/regex names, hidden
items, extensions, size/date ranges and content matching.

- Literal text search streams the whole source.
- Regex, Office extraction and archive-member search use explicit budgets.
- Reaching a budget is reported, not treated as “no match”.
- Parent-directory entries are never marked.
- Select by pattern applies to the current filtered scope, including all pages
  of a saved collection.

## Multi-rename

Multi-rename supports masks, counters, date/time variables, transformations,
proposed-name editing/import, row ordering and collision preview.

- Review the complete batch before execution.
- Whole-batch undo captures target metadata.
- Remaining rows can be retried after a partial failure.
- Closing a dialog during execution does not silently discard its history.

## Copy and move

F5/F6 open a review, not an immediate mutation. The review shows:

- planned items and actual destination;
- name rules and exclusions;
- conflict policy;
- metadata and capability warnings.

Execution can run in the foreground, be queued or be scheduled. The queue
supports pause, priority, reorder, retry and per-item outcomes. Journaled work
resumes through reviewed recovery rather than blindly repeating destructive
steps.

Cancellation stops remaining work. It does not roll back completed items.

## Attributes and integrity

Reviewed bulk attributes are provider-dependent. Checksums, split, combine and
split/combine recovery use the same source identity and output verification as
other operations.

Unsupported metadata preservation is reported before a move or rewrite.
Permanent deletion is not generally undoable.

## Comparison, archives and viewers

- `F3`/`F4` use the focused file, not the entire marked set.
- Folder comparison and synchronization require an explicit plan.
- Archive workspaces expose only eligible writers; unsupported structures are
  read-only with a reason.
- Binary comparison reads complete streams; text comparison has separate size
  limits.
- Viewers are scoped to the original source/account and close when it expires.

## Large files and limits

- Remote staging, archive extraction and rich-document preview each have
  separate budgets.
- Ordinary remote staging has a 2 GiB ceiling; numbered 7z first parts have a
  larger dedicated budget.
- Native temporary-copy preparation has inactivity and overall deadlines.
- A provider without immutable versions cannot guarantee a frozen snapshot even
  when metadata checks pass.

## Related

- [Workspace UX](workspace-ux.md)
- [Transfer queue](transfer-queue.md)
- [Archive coverage](archive-format-coverage.md)
- [User guide](USER_GUIDE.md)
- [Full Commander archive](commander-file-operations-details.md)
