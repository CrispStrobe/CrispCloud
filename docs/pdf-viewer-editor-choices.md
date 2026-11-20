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

## Live Mac acceptance

The signed preview was opened separately from the user's running application.
A synthetic two-page PDF was used throughout; its SHA-256 remained
`616bafc7191901a659bb6e42db5b7afd1c6f7492c3d32b88af9323ba11a3ba68`.

The default viewer, native compatibility viewer and CrispOffice viewer rendered
the PDF. Native zoom visibly changed from 100% to 120%; Fit page showed the
complete page at 35%. CrispOffice fit/zoom and navigation to page two also worked.
The primary editor opened through the F3 Edit action. The chooser exposed both
PDF editors, and the CrispOffice alternative opened, rotated a page, undid that
rotation and displayed the shared unsaved-change prompt; Discard closed it.
No source file was written by these checks.

Live controls were exercised through existing callbacks in the owned debug
application, with rendered screenshots inspected. This checks the native PDFx
renderer and the real local-file host, but does not certify OS-generated
shortcuts or physical pinch gestures. Widget tests cover shortcut/routing
contracts. Repeated forced native accessibility toggles in an earlier automation
run produced a deactivated-widget error and native AX-tree update errors; that
stress run is not counted as passing. A clean launch without those toggles and
a move/resize/minimize/app-switch cycle remained healthy.

The live pass also caught a stale primary zoom percentage: the renderer changed
scale but did not notify its general controller listeners. The host now observes
`viewportChanges` as well, with regressions checking that the displayed percentage
matches the actual zoom after zoom and fit commands.

[Native 100%](validation/pdf-choices-20261120/native-100.png),
[native 120%](validation/pdf-choices-20261120/native-120.png),
[native Fit page](validation/pdf-choices-20261120/native-fit-page.png), and
[CrispOffice viewer](validation/pdf-choices-20261120/office-viewer.png).
