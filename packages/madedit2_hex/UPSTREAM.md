# MadEdit2 hex editor provenance

- Upstream: https://github.com/madedit/madedit2
- Source revision: `288d35747faccb1cb997c4a30afc40c6cb48b0ae` (v1.0.2)
- License: MIT; the upstream copyright and permission notice are retained in `LICENSE`.
- Maintained extraction: `packages/madedit2_hex` in CrispCloud.

This package extracts and adapts MadEdit2's native Flutter hex rendering and
piece-tree approach for use inside another application. The complete upstream
application is not a dependency. Rust, Tree-sitter grammars, JavaScript/Lua
scripting, menus, localization and application settings are outside the scope
of this extraction.

The byte model is independent of text encodings and newline indexing. Host
applications supply an immutable range-readable byte source and own persistence.
Changes are represented as original-byte ranges and inserted data, with bounded
undo history. Save operations use immutable snapshots and do not clear edits
made while a save is running.

Keep changes to this package isolated and preserve this provenance when syncing
the extraction to a maintained MadEdit2 fork. The GitHub fork is a separate
repository operation; this file does not assert that it has been created.
