# File Viewer LRC parser provenance

This directory records the Apache-2.0 source used for CrispCloud's native static
LRC lyrics preview. It is a provenance archive, not an npm package, Dart package,
JavaScript runtime, or asset bundle. The TypeScript snapshot is not executed by
CrispCloud. No File Viewer package or third-party dependency is installed by this
source extraction.

## Exact source and license boundary

- Project: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer)
- Commit: [`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558)
- Upstream package: `@file-viewer/renderer-text`, version `3.3.3`
- Review date: 2026-11-13
- Upstream copyright: `Copyright 2026 Flyfish Viewer`
- License: Apache License, Version 2.0, reproduced verbatim in [LICENSE](LICENSE)

| Local snapshot | Exact upstream path | Purpose |
| --- | --- | --- |
| `upstream/lrcParser.ts` | `packages/renderers/text/src/lrcParser.ts` | Standalone static LRC model, timestamps, metadata and repeated word timing |
| `LICENSE` | `packages/renderers/text/LICENSE` | Applicable Apache-2.0 license and attribution |

Both snapshots are exact byte-for-byte copies from the pinned commit.
[UPSTREAM.json](UPSTREAM.json) records their Git blob identities, byte lengths
and SHA-256 checksums. These two files are the complete allowlist of upstream
material imported into this directory. Tests use locally constructed synthetic
text; no upstream fixtures, song lyrics, artwork or fonts are copied.

The selected parser has **no imports** and no separate license exception or
third-party notice. The complete pinned Git tree contains no NOTICE in the
repository root, `packages`, `packages/renderers`, `packages/renderers/text`, or
`packages/renderers/text/src`. The text package's license is identical to the
root license (Git blob `59121b29efbabb216432f367c8071d1f6019c43f`). Notices inside
the separate XML profile dependency directory do not apply to this standalone
parser, and that directory is not imported.

The published text renderer has separately licensed dependencies. Its browser
wrapper, code renderer, syntax highlighter, formatter, sanitizers and dependency
tree are not part of this extraction. The upstream LRC browser wrapper is also
excluded. This record approves only the identified source file and its Dart
derivative, not the complete npm package or existing CrispCloud dependencies.

## Native adaptation

The derivative is
[`lib/services/lrc_parser.dart`](../../lib/services/lrc_parser.dart). It imports
no libraries and exposes `parseLrc`, `parseLrcTimestamp` and
`formatLrcTimestamp`. The model keeps the exact supplied source, metadata,
one-based source line numbers, source-order cues, optional M/F/D voice markers,
and line/word timestamps. A separate `timedCues` list is stably ordered by time
and source order; untimed lines remain in the original `cues` list.

The adaptation intentionally changes the following behavior and implementation:

- It uses immutable Dart models and local types instead of TypeScript objects.
- It scans source lines lazily rather than allocating all split lines before
  applying the cue limit.
- It enforces resource limits before allocating excess metadata, cue copies or
  repeated word segments.
- It returns an explicit limit reason and `isTruncated` flag while retaining
  the exact source. A truncated result is not a complete timing model; the host
  must offer the original Source/Text view instead of claiming complete lyrics.
- It strictly checks timestamp length and the end of the match, including
  trailing newline rejection. Invalid markers remain literal text.
- It bounds offset parsing before integer conversion. Malformed or excessive
  offset values remain visible metadata and do not replace the last valid
  offset. Valid offset bounds are plus or minus 1,000,000,000,000 milliseconds.
- It applies the final valid offset once to all line and word clocks. Repeated
  line timestamps shift inline word clocks relative to the first timestamp.
- It adds stable chronological ordering without rearranging source-order cues
  or discarding whitespace and untimed lines.

| Bound | Value | Behavior at the limit |
| --- | --- | --- |
| `lrcMaxSourceCodeUnits` | 2,000,000 UTF-16 code units | Larger sources are retained exactly but not parsed into a preview model |
| `lrcMaxCues` | 10,000 | Further line/timestamp expansion returns a disclosed partial result |
| `lrcMaxExpandedWords` | 50,000 | The word count includes repeated cue copies; multiplication is checked before expansion |
| `lrcMaxMetadata` | 1,000 | Further metadata entries return a disclosed partial result |

Timestamp minute components have at most eight digits. Combining the largest
supported timestamp, repeated-line shift and offset remains below
`lrcMaxTimelineMilliseconds` (20,000,000,000,000), well within JavaScript's exact
integer range. The formatter rejects values beyond that bound. The source cap
does not slice strings or split surrogate pairs: oversize input returns no
parsed cues and preserves the original source.

The parser is a static text transformation. It does not execute document markup,
open URLs, search for audio files, start playback, or synchronize with a media
session. CrispCloud's existing decoder and native widgets own byte decoding and
presentation; they do not require the upstream DOM renderer.

## Distribution and updates

Retain the supplied Apache-2.0 license and applicable attribution with the
derivative. The Dart file carries a prominent modification notice and refers to
this record. The exact upstream snapshot remains unchanged for review.
If a future approved source revision introduces applicable NOTICE material,
retain it as required by Apache-2.0 section 4. The license does not grant
trademark rights.

For an update, pin a new commit, review the selected file's imports and governing
license/notices, compare behavioral changes, update the checksum allowlist, and
run relevant parser and native preview tests. Do not expand this directory into
a full package import without a separate dependency and license review.
