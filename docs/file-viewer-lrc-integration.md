# Apache-only LRC lyrics integration

Date: 2026-11-13. Follow-up to the
[File Viewer source assessment](file-viewer-apache-integration.md).
Upstream remains pinned at
[`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558),
version 3.3.3. The integration is on
[`feature/apache-file-viewer-20261113`](https://github.com/CrispStrobe/CrispCloud/tree/feature/apache-file-viewer-20261113),
with review in [draft PR #95](https://github.com/CrispStrobe/CrispCloud/pull/95).

## What users can do

Open an `.lrc` file in F3. **Timeline** sorts timed lyric lines chronologically,
preserving source order when times are equal. It shows metadata, the timing
offset, voice markers and expandable word timing. Untimed text remains visible.
**Lyrics** shows expanded cues in their original source order without the line
timestamps. Repeated timestamps create repeated lyric cues in both views.

**Source** opens the existing text viewer. Encoding selection, search and Copy
All use CrispCloud's text decoder; Copy All from Lyrics retains the original
decoded text, including its line endings. **Hex** retains the original bytes.
F4 recognizes LRC as an ordinary editable text format. UTF-8/UTF-16 BOMs select
the decoder without discarding the LRC route. Archive member display names also
retain format detection.

This is a static lyrics preview. It does not play music, synchronize with a
player, discover sidecar files or fetch album art. Lyrics and metadata are
rendered as literal Flutter text; markup and URLs are not evaluated or opened.

## Exact Apache source boundary

Only these two upstream files are imported verbatim:

| Upstream path | Git blob | SHA-256 |
| --- | --- | --- |
| `packages/renderers/text/LICENSE` | `59121b29efbabb216432f367c8071d1f6019c43f` | `55ce5d9fb8138a058b60c431cb9e68e13dd3f90691f73a757e38f06fed81e69b` |
| `packages/renderers/text/src/lrcParser.ts` | `c701adce35bc0c2d8be239aa077543aaf6fbad60` | `b0f42a4f200dd32a37f11cc3bae1ea49b47feffb8fac7bf274ddaf0ec935b59b` |

The original parser is 4,281 bytes and has no imports. The package license is
identical to upstream's Apache-2.0 root license. Review found no per-file
exception or applicable ancestor NOTICE. The exact files, source pin and
modification record are in
[packages/file_viewer_lrc](../packages/file_viewer_lrc/UPSTREAM.md).

The Dart derivative preserves `Copyright 2026 Flyfish Viewer`, the Apache SPDX
notice and a prominent modification notice. Its license is explicitly bundled
and registered through `LicenseRegistry`. No npm package, complete text renderer,
WASM, font, music, sample lyrics or upstream test fixture is imported. All new
test inputs are synthetic. No Pub dependency or lockfile change is needed.

The independent source allowlist in
[verify_file_viewer_lrc.py](../tool/verify_file_viewer_lrc.py) checks exact hashes,
paths, metadata, notices and the derivative's zero-import boundary. It rejects
unexpected files, symlinks, traversal, hidden import/export/part directives, and
altered snapshots even if their manifest is rehashed. The common verifier also
checks nested JSON value types exactly. This control covers the selected File
Viewer subsets, not every pre-existing CrispCloud dependency.

## Resource limits and timing behavior

| Boundary | Limit or behavior |
| --- | --- |
| Source read | A complete file of at most 4 MiB, copied from the existing viewer source in windows of at most 256 KiB |
| Parser source | 2,000,000 UTF-16 code units |
| Expanded cues | 10,000 |
| Expanded words | 50,000 across repeated cues |
| Metadata entries | 1,000 |
| Timeline arithmetic | Explicit bounds keep all clock arithmetic below 20,000,000,000,000 ms and exact in compiled JavaScript |
| Per-row text layout | At most 8,192 code units, without cutting a surrogate pair; shortened rows explain how to open Source |
| Expanded word details | At most 100 words per row and 128 code units per word, with a disclosure when shortened |

The adapter checks the source size before allocating or reading, validates
native file snapshots before and after the read, and checks source identity,
mode/encoding generation and size between windows. It borrows the current
viewer source and does not open a new provider connection or download path.
Existing viewer materialization and provider policies still apply: the preview
limit is not a claim that every remote file transfer is limited to 4 MiB.

The full permitted source is read before parsing so a late offset can apply to
earlier lines. A positive offset advances lyrics and is subtracted once from
line and word clocks. Repeated timestamps shift inline word times with their
corresponding cue. Negative effective times remain visible. Malformed timing
markers remain literal source text.

If **any** parser budget is exceeded, the UI offers Source instead of displaying
a partial timeline. This avoids presenting times calculated without possible
later offset metadata. Oversized byte sources are rejected before the preview
read. Original text and bytes remain accessible through the normal viewer.

## Maintained hex fork repair

The previous branch CI exposed an inherited fingerprint mismatch in the
pre-existing hex editor. CrispCloud commit
[`87333f4557c47bc9034be04b96e2aeac61f0d01a`](https://github.com/CrispStrobe/CrispCloud/commit/87333f4557c47bc9034be04b96e2aeac61f0d01a)
had added a scrollbar selection fix and its regression test without updating
the maintained fork. The source verifier correctly rejected the mismatch.

Those exact two files are now preserved on a separate fork review branch in
[`CrispStrobe/madedit2` commit `912b1f7`](https://github.com/CrispStrobe/madedit2/commit/912b1f7527e5f48793a8e0834cc7c7ab8dbb7f5f).
All 12 tracked package files were independently compared with that immutable
tree. CrispCloud's manifest now references the real commit; no source behavior,
dependency, license or verifier rule was changed. All 25 standalone package
tests passed before the fork checkpoint. See the
[detailed provenance record](../packages/madedit2_hex/UPSTREAM.md).

This repairs the existing MIT hex package's provenance. It does not enlarge the
Apache-only File Viewer import or introduce MIT source from File Viewer.

## Validation and remote checkpoints

The [continuation validation record](file-viewer-lrc-validation.md) contains the
executed commands, counts, receipts and remaining CI constraints. Native testing
uses Flutter 3.47.8 / Dart 3.13.7 and the real production dependency graph with
unchanged Rust/native build hooks. A separate smoke runs under the Dart VM and
genuine Dart2js compilation followed by Node.

Saved checkpoints before the UI integration:

| Commit | Contents |
| --- | --- |
| [`dbc90c7`](https://github.com/CrispStrobe/CrispCloud/commit/dbc90c7dda73fed8228e5e6fb4fbefa4e5efc1cb) | Repair the inherited hex fork provenance using the independently verified maintained source |
| [`226bd41`](https://github.com/CrispStrobe/CrispCloud/commit/226bd41fe9090a7cb20b4222afd0865e798aeeeb) | Apache LRC parser, bounded source reader, exact upstream snapshots, provenance guards, tests and portability checks |

The integration remains a review branch. No main merge, release or deployment
is part of this work.
