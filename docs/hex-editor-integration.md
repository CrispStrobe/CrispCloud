# Native hex editor integration

Branch: `feature/madedit2-hex-editor`. No merge to main is authorized.

## Entry points and features

Unsupported binary F4 requests open the native editor. The file context menu
also offers **Edit as Hex**, including for files normally handled by specialized
editors. Archive-member previews and unverified rows remain blocked. Text/code
stays in Re-Editor; PDF, image, media and Office routes remain separate.

The MIT `packages/madedit2_hex` package includes virtualized hex/ASCII rows,
byte/nibble input, selection, insert/overwrite, undo/redo, strict hex clipboard
parsing, bounded-memory byte search, goto-offset and a touch hex keypad. ASCII
and Latin-1 interpretation never change the granularity of binary edits.
Undo roots and save snapshots share a persistent AVL byte rope with no line index.

## Persistence and limits

The original account and path are captured before navigation. Native files are
streamed to an owned immutable disk snapshot before editing; browser files are
bounded at 32 MiB. Native editing/save has an explicit 8 GiB cap. This version
chooses a fully verified snapshot, not instant lazy remote opening. Opening can
require two full input reads and disk space approximately equal to file size.
Saves also read/verify original and staged content and rewrite the full result.

Save uses the application's staged-write backend, checks SHA-256 plus metadata,
verifies staged output before replacement, serializes writes and only marks the
saved revision clean. Concurrent newer edits, failed writes and Save Copy retain
unsaved status. Backends without safe staged verification are read-only. Native
source files remain immutable even after saving, making undo across save safe.

External modification protection is conservative. Backends without server-side
conditional writes still have a check/commit race; this is not a universal
atomic compare-and-swap guarantee. Cancellation stops before commit, never in
the middle of a backup/replacement sequence. Existing backend recovery applies.

Undo is capped by steps (500), and a single inserted edit/clipboard is capped
at 16 MiB; this is not a strict total memory budget. Rendering caches at most
eight 64 KiB pages. Search needles are capped at 1 MiB and use streaming KMP.

## Validation

See `hex-editor-validation.md` for executed results. The regression tests cover
random byte edits against a reference model, snapshots/history, >4 GiB offsets,
short reads, chunk-boundary search, keyboard input, mixed newline policies,
strict Unicode decoding, staged writes, same-size external changes, cancellation,
copy collisions and account changes. Test presence is not proof of passing.
Physical-device IME/touch/accessibility testing remains a release gate.
