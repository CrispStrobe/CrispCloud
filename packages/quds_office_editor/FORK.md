# Local fork notes

This is a vendored copy of `quds_office_editor` 1.6.0 (MIT), used through
`dependency_overrides` in the CrispCloud app.

Changes made in this fork:

- `lib/src/editor_word/render_word_canvas.dart`: selection is painted with
  the surface theme's `selectionFill` / `selectionStroke` instead of the
  inverse of the text colour. Inverting black text produced a white highlight
  on a white page, so selection and Select All looked like no-ops.
- `lib/src/embed/office_controller.dart`: while editing a header or footer,
  `relayout()` forces a full page layout instead of the incremental reuse
  path. Header/footer stories are chrome, not body content; incremental layout
  reused stale page chrome, so typed header text did not appear in the header
  band (and could appear in the wrong place).
