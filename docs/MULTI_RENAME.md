# Multi-rename and recovery

The multi-rename tool accepts files and folders from an ordinary panel or a verified search/file list. Each batch captures its storage account and the complete original paths before any asynchronous work. Selecting another pane, account or directory cannot redirect an existing batch.

## Prepare a batch

The preview combines a name mask, an extension mask, search and replacement, case conversion, and an ordered counter. Folders use the name mask only. Dotfiles keep their leading dot as part of the name. Names are validated before execution, including duplicate final paths and portable filename restrictions.

The preview order controls counters. Sort, reverse, or move individual rows earlier/later. Exclude rows to retain their files; excluded rows can be restored to the preview. **Edit / import names** accepts one complete target basename per included row. It supports pasted text and UTF-8 `.txt` / `.lst` files, checks the row count, and preserves the exact original-path mapping when rows are reordered. A manual target overrides that row's transformation rules. **Export names** copies or saves the proposed list for an external editor.

Use **Add transformation** for another pass over the proposed names. Earlier steps remain editable and can be moved or removed. No intermediate names are written while editing the pipeline. Presets save the complete ordered rules, selected syntax, date settings, replacement mode, variables and counter options. The preset exchange dialog exports/imports versioned JSON; importing explicitly replaces same-named saved presets.

**Number colliding targets** checks the actual sibling listings and adds ` (1)`, ` (2)` and so on before the extension. Existing unselected files and unchanged selected rows retain their names. Execution checks paths again because another application may have changed the directory since preview.

## Supported mask syntax

Presets record a syntax mode so ambiguous date and range tokens retain their meaning.

| Purpose | Tokens and behavior |
| --- | --- |
| Original name and extension | `[N]`, `[E]`; folders have no separate extension |
| Counter | `[C]`, `[C:4]`, `[C7+2:4]`; start, increment and width also have independent controls |
| Name ranges | `[N1-4]`, `[N3-]`, `[N-4--1]`; positions are one-based Unicode code points |
| TC/DC range forms | `[N1:4]` selects a range; `[N2,3]` selects three characters; DC supports negative/backwards range forms |
| Parent folders | `[P]`, `[P1]`, `[P-1]`; `[B0]` is the immediate parent and `[B1]` the grandparent; `[B+0]` selects the drive/root label |
| Full path | `[A]` and `[A...]` ranges; the final transformed basename must still be valid |
| CrispCloud/TC dates | `[YMD]`, `[hms]`, or individual `[Y]`, `[M]`, `[D]`, `[h]`, `[m]`, `[s]`, `[v]` fields |
| DC dates | `[YYYY][MM][DD]`, `[hh][nn][ss]`; unpadded numeric fields and abbreviated/full English month/day names are supported |
| Date source | `[T1]` modified, `[T2]` created, `[T3]` accessed, `[T4]` captured, `[T5]` time the batch was opened; offsets such as `[T4+60m]` are supported |
| Captured metadata | `[meta:artist]`, `[meta:exif.DateTimeOriginal]`; nested keys and direct metadata keys are supported |
| Built-in content fields | `[=tc.name]`, `[=tc.ext]`, `[=tc.fullname]`, `[=tc.path]`, `[=tc.size]`, and write/create/access date fields with optional date format |
| Variables and identifiers | `[V:Project]` uses a `Project=value` variable; `[G]` generates a deterministic GUID-shaped value tied to the transformation's input path and fixed batch time |
| TC inline case | `[U]`, `[L]`, `[F]`, `[n]` select uppercase, lowercase, title case and unchanged text for following fragments |
| Literal brackets | CrispCloud `[[` / `]]`; TC/DC also accept `[[]` / `[]]` |

Creation/access/capture dates and arbitrary metadata must be present in the captured file information. Missing data is shown as a preview error, so it cannot silently become an empty filename. The date-source and time-zone controls also support local time, UTC and a minute offset. An explicit offset in a supplied date string is preserved when original time-zone fields are selected. The current-time source stays fixed throughout a batch.

Regular-expression replacement expands numbered and named captures. Multiple literal pairs use `|` separators in the find/replace fields and apply in one simultaneous pass; this mode does not cascade replacements and is separate from regex mode. Unsupported tokens and malformed expressions block the preview. Commander binary content plugins are not loaded by this tool.

## Execute and undo

Independent changes are direct sibling renames. Case-only names, swaps, rename chains, and selected parent/child folders use unique temporary sibling names. Descendants are staged before their parents; parents receive final names before their children. The preview shows the complete final paths, including every selected renamed ancestor. Existing unrelated destinations are never intentionally replaced.

On supported native filesystems, the move primitive enforces no replacement at the actual OS rename. A provider's optional native operation is used only when declared. Sources without an exclusive move contract retain a destination precheck; the dialog identifies that weaker guarantee. Provider-specific authentication and path namespaces remain bound to the captured account. Version preconditions are sent only to providers that declare conditional moves.

Object storage uses a separate path: individual files require an exclusive, source-version-conditional copy and conditional deletion of the captured source version. The confirmed destination version is saved before deletion and checked again, so an interrupted deletion can resume without copying twice. An unchanged original remains intact when either object changes or the receipt cannot be saved. This is still a copy/delete sequence, not an atomic rename. Providers without these contracts are rejected before any item is changed. Virtual folders are object-key prefixes and require a recursive move; a batch does not attempt to rename a prefix as though it were a directory.

Stopping is cooperative between physical operations. A dependent batch stops on its first failure. Independent batches may continue after an error if that option was selected. The result and report distinguish confirmed final names, failures, untouched rows and intermediate recovery paths.

A completed batch adds **one** normal Undo entry. That entry restores the whole batch rather than relying on the action menu's item limit. **Undo batch** in the dialog and **History / recovery** use the same checked reverse operation. After a completed batch or restore, **Continue with these items** rereads the actual current files and starts a new preview.

Undo is a new sequence of file operations, not an atomic rollback. It checks the source objects and destination names again. New files occupying original names, changed file fingerprints, disconnected accounts, or missing paths block unsafe reversal.

## Persistent history and interruption recovery

Every physical move has a saved intent before it runs and a saved completion afterwards. Native records are written to a temporary file, flushed, then atomically replace the previous record. Browser records use acknowledged whole-record browser storage updates. Records have checksums, contain only whitelisted identifiers and fingerprints, and never store raw provider metadata or credentials. A write failure stops execution before the next mutation. Corrupt records are retained and reported without hiding other readable batches.

The persistent batch history has no 50-item truncation. It keeps original, intended and last-confirmed current paths for the entire batch, including temporary names. Reports can be copied or exported as JSON.

Local storage references include a random installation identity saved before the app opens its panels. A report or collection from another computer cannot bind to an unrelated file merely because its absolute path is identical. If the installation identity cannot be saved, references remain session-only and cross-restart recovery is unavailable. The identity contains no hardware serial number or credentials.

After reconnecting the same storage account, open **History / recovery** to resume a batch or restore its completed work. Native files are hashed as streams; directory manifests hash names and contents without following symlinks. Those digests, or stable provider object IDs, allow an interrupted move to be reconciled without blindly repeating it. Path-shaped UUID fields used by some protocol adapters are not accepted as stable object identities.

When a provider supplies neither a stable identity nor a digest, an interrupted request may be ambiguous. The history view displays both paths and offers explicit verification of the observed destination. This only accepts a missing original and one destination whose available fingerprint still agrees; a known mismatch or two existing paths remains blocked. Manual verification is recorded in the report. Browser history durability follows the browser's storage policy. Content hashing and provider checks add I/O, particularly for large folders or remote listings.
