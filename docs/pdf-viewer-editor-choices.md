# PDF viewers and editors

Settings → **PDF viewers and editors** stores the default and secondary PDF
viewer/editor choices. These preferences affect PDFs; other formats retain their
existing routes.

| Action | Default | Alternatives |
| --- | --- | --- |
| F3 | CrispCloud PDF viewer (read-only PDF Editor surface) | CrispOffice PDF viewer; native compatibility viewer |
| Shift+F3 | Native compatibility viewer | Any configured secondary viewer |
| F4 | CrispCloud PDF Editor | CrispOffice PDF editor |
| Shift+F4 | Editor chooser | Configurable: open secondary PDF editor directly |

The F3 toolbar can switch between all three renderers without changing the file.
Its secondary-viewer button uses the configured secondary choice. All three
surfaces expose zoom, fit width/page, and page navigation. Zoom commands change
the renderer viewport. The native compatibility surface uses PDFx's pinch viewer
with panning and higher-resolution rendering, replacing the old fixed page view.

Both F3 editor-derived surfaces are read-only: no editing controller, form writer
or save callback is supplied. They load up to 64 MiB and offer the native
compatibility fallback for larger or unsupported inputs. The native local-file
route retains file-backed streaming and the host's folder access leases.

The primary editor supports its existing text, form, annotation and page tools.
The CrispOffice alternative currently exposes highlights, page rotation,
undo/redo, zoom and fit. Both share CrispCloud's save/conflict/copy host:
archive safety checks, signed-document copy-only rules, source identity checks,
and unsaved-change prompts apply to both. Switching a renderer or opening and
closing an unchanged Office editor never writes the source. Office edits made
during an in-flight save stay dirty. Escape returns to the host when there is no
selection for the Office surface to dismiss.

## Qualification, 2026-11-20

The integrated source pins CrispOffice main at
`d95e814af9556dcea448ba5673e0ba4dc81007d0`, including incoming font-download work,
current proofing/VBA/Mail changes and the PDF rotation/Escape fixes. The managed
inventory verifies all 2,991 Office files against that source.

- 187 integrated PDF preferences, settings, routing, editor, viewer, shortcut,
  file-store, save-session and Office PDF-service tests passed.
- Focused analysis of the changed services, settings, routes and PDF widgets
  reported no issues.
- Native platform behavior is qualified separately in the signed local Mac
  preview; widget tests do not substitute for a live PDFx platform renderer.

Rendering quality still depends on PDF features and renderer support. Keep the
alternative engines available for documents that render better in another one.
