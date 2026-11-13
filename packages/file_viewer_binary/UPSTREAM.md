# File Viewer binary inspector provenance

This directory records the Apache-2.0 source used for CrispCloud's Dart binary
header inspector. It is a provenance archive, **not** an npm package, Dart package,
JavaScript runtime, or asset bundle. Its TypeScript files are not executed by
CrispCloud. No File Viewer package or third-party dependency is installed by this
source extraction.

## Exact source

- Project: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer)
- Commit: [`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558)
- Upstream package: `@file-viewer/renderer-binary`, version `3.3.3`
- Review date: 2026-11-13
- Copyright retained in the upstream license: `Copyright 2026 Flyfish Viewer`
- License: Apache License, Version 2.0, reproduced verbatim in [LICENSE](LICENSE)

| Local file | Exact upstream path | Purpose |
| --- | --- | --- |
| `upstream/parser.ts` | `packages/renderers/binary/src/parser.ts` | Header recognition and bounded structure extraction |
| `upstream/types.ts` | `packages/renderers/binary/src/types.ts` | Reference types and limits |
| `LICENSE` | `packages/renderers/binary/LICENSE` | Original Apache-2.0 license and attribution |

These three files are unmodified byte-for-byte copies from the pinned Git commit.
[UPSTREAM.json](UPSTREAM.json) records their Git blob identities, byte lengths,
and SHA-256 checksums. It is the complete allowlist of upstream files imported in
this directory. Do not regenerate the snapshots from a moving branch or copy
additional source/assets without extending the review and allowlist.

The binary package license is identical to the repository's root license (Git
blob `59121b29efbabb216432f367c8071d1f6019c43f`). Neither the repository root nor the
binary package contains a `NOTICE` file at this commit. The two source files have
no separate copyright or third-party notices. No fixtures are copied.

## Source boundary

`parser.ts` imports only local TypeScript types. `types.ts` imports only the
`FileViewerBinaryInspectorOptions` type from `@file-viewer/core`; the Dart port
defines its own local options. The archived type import is documentation, not a
request to install or link `@file-viewer/core`. The selected algorithm uses byte
reads and scalar formatting, with no parser library, native runtime, WASM,
network call, executable loading, or remote rendering service.

This narrow source decision does **not** approve the published binary renderer's
full dependency graph or other File Viewer packages. In particular, the CAD
runtime is AGPL-3.0-only; other packages and asset bundles contain MIT, BSD, MPL,
LGPL, OFL, and additional licenses. See the
[integration assessment](../../docs/file-viewer-apache-integration.md).

## Dart adaptation

The derivative is
[`lib/services/binary_structure_service.dart`](../../lib/services/binary_structure_service.dart).
`inspectBinaryStructure(Uint8List prefix, {required int totalBytes})` accepts at
most 64 KiB of prefix data and reports both the total file length and the number
of inspected bytes. It imports only `dart:typed_data`. The existing F3 viewer
offers **Hex → Inspect structure** and lets a user select a field to highlight
its byte range in the hex view.

Changes from the upstream TypeScript include the Dart port, a bounded-prefix
API, fields restricted to bytes actually present, explicit truncated/invalid
header warnings, validation of PE pointers and ELF metadata, preservation of
byte-view offsets, exact 64-bit hexadecimal formatting with `BigInt` on web,
and conservative handling of Java/fat-Mach-O signature ambiguity. The supported
header schemas bound the work and field count. This is a read-only header
explanation, not complete format validation, archive extraction, executable
loading, image rendering, or a new hex editor.

The port carries a prominent modification notice, upstream copyright, and
references to this license/provenance. The original TypeScript snapshots remain
untouched so that reviewers can compare the derivative to the actual source.
The UI uses the current viewer source; a native source may cache its ordinary
256 KiB window, and existing remote/web materialization policy remains owned by
the viewer. The inspector itself requests only the bounded prefix.

## Distribution and maintenance

For distributions containing the derivative, retain a readable copy of the
Apache-2.0 license, preserve applicable copyright and attribution notices, and
keep prominent modification notices on changed/derived source. Include relevant
upstream NOTICE material if a future approved snapshot adds it. These obligations
come from [Apache-2.0 section 4](https://www.apache.org/licenses/LICENSE-2.0).
Upstream names may identify the source; the license does not grant trademark
rights. This record documents the evidence and engineering boundary, not a legal
guarantee about every dependency in CrispCloud.

For an upstream update:

1. Pin a new commit and inspect the selected files, their applicable licenses,
   notices, and imports.
2. Review the diff before replacing snapshots; reject any new dependency or
   non-Apache source outside the approved scope.
3. Update the SHA-256/Git blob allowlist and the Dart change notice together.
4. Run the parser and UI checks relevant to any behavioral changes, then save the
   reviewed change to the remote integration branch.
