# Brickwright CAD reference

The STL reader in `lib/services/mesh_preview.dart` adapts the binary/ASCII import
approach from CrispStrobe/brickwright-cad, revision
`bd03ee7b76b89cdd3fc4850020a9212bbd4b7575`,
`packages/geometry/src/files.ts` (Git blob
`68115c877f7346769eecaf6c155421beff45dfc1`). The reviewed file was unchanged
in that checkout. Its BSD-3-Clause license is retained here, bundled as
`assets/licenses/brickwright/LICENSE.txt`, and registered in the app license UI.

Changes include Dart implementation, smaller interactive limits, finite-coordinate
validation, exact binary length checks before ASCII fallback, and strict facet
validation. Single-triangle and open meshes are accepted for viewing; this does
not certify printable or manifold geometry. Multiple ASCII solids are refused.

The core 3MF reader is new Dart code. Brickwright's 3MF exporter informed its
interoperability tests and millimetre conventions. No CAD kernel, manifold-3d,
fflate, model-library asset or WebView runtime is copied or added as a dependency.
The reader uses Quds' existing bounded ZIP decoder and the existing XML parser.

F3 shows STL and core 3MF geometry with orbit, zoom, fit and wireframe controls.
Limits: 16 MiB packed input, 16 MiB model XML, 4,096 package entries/component
visits, 32 component levels, 150,000 unique vertices and 50,000 expanded triangles.
Repeated component meshes are decoded once, within a shared vertex budget. STL units are unknown;
3MF units/transforms are converted to millimetres. No files are extracted.
DTD/entity declarations, cycles, invalid indices, external object references,
unsafe part paths and required unimplemented 3MF extensions are refused.
Materials, colours, textures, print settings and CAD editing are not supported.
This is a bounded software-projected preview, not a CAD fidelity renderer.

The authored triangle in `tool/mesh_portability_smoke.dart` was emitted by that
exact exporter using fflate from Brickwright’s existing installation. ZIP SHA-256:
`20f6dce8a60f04758a8750da430a9dc2eade252b25a9f15a1227f845332ec77c`. Its import runs on Dart VM and actual Dart-to-JavaScript/Node.
