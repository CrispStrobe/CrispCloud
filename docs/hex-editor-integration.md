# Native hex editor integration

Implementation branch: `feature/madedit2-hex-editor`.

## Scope

Use the MIT-licensed MadEdit2 source as the basis for a reusable native Flutter
hex editor, maintained in `packages/madedit2_hex`. Keep the existing specialized
text, image, office, PDF and media editors. Add an explicit hex-edit action in
the internal viewer, and route unsupported binary files to the hex editor from
the normal Edit action.

## Required behavior

- Byte-accurate insert, overwrite and delete, independent of the text preview's
  encoding and without scanning a file's newline index before the first edit.
- Windowed hex/ASCII rendering, byte selection, keyboard navigation, clipboard,
  undo/redo, search and offset navigation.
- Injectable byte sources; immutable original bytes while an editing session or
  save snapshot still references them.
- Captured storage identity, conflict checks, serialized saves, and preserved
  unsaved changes after failed or cancelled writes.
- Native file preparation and saves stream through bounded buffers. Browser
  memory limits must be explicit. A downloaded copy is not a successful save
  back to the original file.
- Unsaved-change confirmation on close; errors remain visible and recoverable.

## Validation targets

Binary edit/reference-model tests, undo/redo and dirty-state tests, huge synthetic
range sources, snapshot consistency during concurrent edits, widget interaction,
source routing and conflict/failure save tests. Run the package tests and relevant
CrispCloud tests with the repository's pinned Flutter 3.47.8 toolchain.

This document is an initial implementation checkpoint and will be updated with
the completed integration and its verified limits.
