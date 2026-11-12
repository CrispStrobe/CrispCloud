# Native metafile arc controls

All **15** authored EMF/WMF arc controls pass against both native rendering
and the generated SVG preview. The tested worktree was clean at
`24580b024979093bec85a7876b8d4f3768e05a08`. The six runtime/probe files named in
`receipt.json` are byte-identical to the remotely saved integrated checkpoint
`01b64eaa9e96ef7cf25eb8117ba0d1291a79e77f`; the latter additionally includes
separate review-preservation changes, so the complete trees are not asserted
identical.

The native renderer is LibreOfficeDev `26.8.0.0.alpha0`, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. The PDF/SVG inspector is PyMuPDF
`1.26.6`. Exact compiler/native executable hashes, source hashes, all
input/output hashes and complete measurements remain in the receipts.

| Measurement | Result |
| --- | --- |
| EMF arc/chord/pie and clockwise/counterclockwise ArcTo controls | 10 pass |
| WMF arc/chord/pie controls | 5 pass |
| Maximum native geometry error | 1.944453 logical units |
| Maximum SVG geometry error | 0.0 logical units |
| Maximum native following-line endpoint error after ArcTo | 0.972218 logical units |
| Geometry tolerance | 2.1 logical units on a 200 by 100 reference canvas |
| Independent fixture generations | 60 input files identical across two runs |
| Input bytes changed by measurement | None |

The rectangle used to measure positions is independently authored, drawn in
a distinct color, and never fitted to an observed arc. Six fixed color samples
per image distinguish the sweep, unfilled arc, chord secant and pie radial
closure. ArcTo additionally requires a subsequent differently colored line to
start at the projected ellipse endpoint. These checks do not assert GDI
edge-pixel equivalence. Coincident pie radials and unequal collinear radials
remain unavailable SVG previews because the native zero/full-sweep and
radial-outline behavior is ambiguous across those cases.

`report.json` is the complete native report. `native-artifacts.tar.xz` retains
all 136 measured artifacts: original metafiles, authored DOC inputs, converted
DOCX, SVG previews, native PDFs, RGB rasters, extracted page coordinates/text,
conversion logs and the original report. It omits disposable native user
profiles. The archive is lossless and its contents and SHA-256 are recorded in
`receipt.json`.

Reproduce from the integrated checkpoint with already installed tools:

```sh
python3 tool/fidelity/metafile_arcs_render.py \
  --office /path/to/soffice --dart /path/to/dart \
  --output build/metafile-arcs-new-run
```

The output directory must not already exist. The command checks the authored
expectations; it never replaces a golden. Installed fonts and transitive native
libraries are not a hermetic toolchain.
