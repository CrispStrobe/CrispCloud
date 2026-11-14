# CrispCloud CLI

The `crisp` companion runs on the Dart VM without Flutter. Use the repository's
pinned Dart SDK, resolve dependencies in `cli/`, then run:

```bash
cd cli
dart pub get
dart run bin/crisp.dart --help
dart test
```

For a distributable native bundle, use `dart build cli -o build/cli` and keep its
native transport libraries alongside the executable. The existing storage
commands are `connect`, `providers`, `ls`, `upload`, `download`, `search`, `share`,
`sync`, `du`, `catalog`, and `config`. `crisp completion bash`, `zsh`, or `fish` includes PDF
operations.

## Largest local files and folders

```bash
crisp du ~/Downloads                    # largest immediate children, folder totals
crisp du /some/path --files-only -n 30   # largest individual files at any depth
crisp du /some/path --dirs-only -r       # folder totals at every depth
crisp du /some/path --json --bytes       # structured report; JSON always uses bytes
```

The path defaults to the current directory. This metadata-only command works
without cloud configuration, GUI startup or credential-store access. It supports
Windows, macOS and Linux wherever the standalone CLI can run.

Sizes are **logical file bytes**, not allocated disk blocks or reclaimable space.
Hard links count once per pathname; sparse files, clones and compression can
make these totals differ from physical usage. Folder totals include descendants.
With `--recursive`, ancestor and descendant rows overlap and must not be added.
An explicitly supplied symlink root resolves once; child symlinks are skipped,
including broken links and loops. Other special entries are excluded. The scan
is a live observation, not an atomic filesystem snapshot.

Results default to the largest 20 entries (`--top 1..10000`). Live traversal has no entry cap by default (`--max-entries 0`) and a depth
budget of 200. Set an explicit `--max-entries` or `--max-depth` when needed. Unreadable or changing entries, exceeded budgets, interruption or totals
beyond the exact reporting bound produce **partial lower bounds**, never a
claim of a complete ranking. JSON includes per-row completeness, issue paths
and codes (first 100 issues, then a suppressed count), scan limits and skip
counts. Text output marks partial totals with `>=`.

Exit codes: `0` complete, `1` partial scan or inaccessible root, `2` invalid
arguments, `130` interrupted by Ctrl+C. No file contents are read or modified.

## Persistent catalogues and Cathy/Catfish CAF

```bash
# No entry/depth cap by default; storing outside the scanned tree is convenient.
crisp catalog scan /mnt/volume1 -o /var/tmp/volume1.crispindex
crisp du --index /var/tmp/volume1.crispindex --files-only -n 50 --json
crisp du --index /var/tmp/volume1.crispindex some/subfolder --dirs-only
crisp catalog search /var/tmp/volume1.crispindex invoice
crisp catalog info /var/tmp/volume1.crispindex

# Refresh by staged replacement; the previous catalogue survives failed builds.
crisp catalog scan /mnt/volume1 -o /var/tmp/volume1.crispindex --replace

# CAF import/export. Imported CAF source coverage remains explicitly unknown.
crisp catalog import archive.caf -o /var/tmp/archive.crispindex
crisp catalog export /var/tmp/volume1.crispindex -o volume1.caf
```

The native Rust backend reuses CrispSorter's MIT-licensed CAF codec, adapted to
retain empty directories, directory timestamps and legacy unknown-size records.
Python is used only for independent compatibility checks; it is not shipped.
The SQLite catalogue stores Unicode names, metadata, precomputed directory
totals, coverage diagnostics and ranking indexes. Queries work without the
original drive or credentials and are explicitly historical. SQL results are
bounded (`--top`, at most 10,000); the catalogue is not limited to that count.
There is no fixed catalogue-entry cap or GUI saved-scan count limit here.
The selected catalogue database, its staging file and SQLite journal files are
excluded from its own scan and counted in `catalogueFilesSkipped`. Available
disk space, filesystem access and the exact byte-reporting bound
still apply. The first scan reads metadata for the entire tree; refresh currently
rebuilds it, without watchers or incremental reconciliation. A partial refresh
will not replace an existing catalogue unless `--allow-partial` is explicitly
given; the first partial catalogue can be retained with exit code 1.

CAF v1–v8 input and v8 output are supported. Classic CAF export requires
Latin-1 names and representable second-resolution timestamps. Unrepresentable
names are rejected, never substituted. Root directory timestamps are not a
separate CAF field. CAF does not encode source completeness or skipped links;
exporting a partial/historical import therefore requires `--allow-lossy`.
This flag never permits changing filenames or inventing unknown sizes.
Successful import/info/search commands return 0 even when their report describes
unknown historical coverage; `du --index` returns 1 for incomplete coverage, as
does a partial live scan. Legacy v1–v6 zero-size file records are treated as unknown and excluded from
known-byte totals; modern v7/v8 zero-byte files remain exact zeroes. The reused
reader also recognizes CrispSorter's UTF-8 extension heuristically; ambiguous
Latin-1 byte sequences remain an interoperability limit. Large CAF imports and
exports currently materialize the format model in Rust memory, whereas native
scans stream rows to SQLite.

Builds require Cargo and a C compiler for bundled SQLite. The Dart native-assets
hook packages the library with `dart build cli`; users of the finished bundle
need neither Rust nor Python. Desktop target mappings cover macOS, Linux and
Windows (arm64/x64); only macOS was locally executed. Hosted CI covers all three.
The package is independent of Flutter and ready for future GUI consumption.
The existing GUI analyzer still uses its own saved-report store; no automatic
migration or live actions from imported CAFs are enabled.

## Storage providers and engines

| Provider | Current standalone CLI implementation | Engine choice |
| --- | --- | --- |
| S3 | Dart HTTP/crypto adapter | Existing adapter |
| SFTP | Dart `dartssh2` adapter | Existing adapter |
| WebDAV | Dart HTTP adapter | Existing adapter |
| SMB | Shared `crisp_storage` adapter | `libsmb2` (default), strict `rust`, or `auto` |
| Filen / Internxt | Not implemented in this CLI factory | Proposed shared Dart/Rust adapters; no engine flag exists yet |

The CLI runs independently of the GUI. Its profiles and credentials are in its
private YAML configuration (owner-only permissions on Unix), not the GUI's secure
store. SMB values and security behavior match the GUI, even though the stores
are separate. Current commands and native build instructions are in
[SMB_RUST_ROLLOUT.md](../docs/SMB_RUST_ROLLOUT.md).

The proposed Filen/Internxt integration keeps application scheduling in Dart and
reuses Rust provider code with the GUI and other Crisp apps. Native library
absence may permit an explicitly configured Auto fallback before login/work;
authentication, crypto or transfer failures must not replay work through another
engine. Proposed modes are not accepted by today's CLI. See
[the complete storage-engine design](../docs/STORAGE_ENGINE_ARCHITECTURE.md) for
capabilities, session/resume compatibility, web limits and acceptance tests.

## PDF operations

`crisp pdf` uses the same `pdf_operations` package as the graphical application.
There is no Flutter or platform PDF viewer dependency. Every mutating operation
requires an explicit, separate output path; the input PDF is never a permitted
output, even with `--overwrite`.

| Command | Purpose | Main options |
| --- | --- | --- |
| `pdf info` | Page geometry, encryption/signature flags, named AcroForm fields and options | `--json` |
| `pdf text` | Extract an existing text layer | `--pages`, `--json` |
| `pdf search` | Search text with page numbers, offsets and bounding boxes | query argument, `--pages`, `--regex`, `--case-sensitive`, `--whole-word` |
| `pdf merge` | Combine PDFs in input order | two or more inputs, repeated `--source-pages`, `--passwords-file` |
| `pdf extract` | Export selected pages | required `--pages` |
| `pdf rotate` | Rotate selected pages clockwise | `--pages`, `--degrees` |
| `pdf reorder` | Reorder the entire page set | required `--pages` permutation |
| `pdf delete-pages` | Remove pages from a copy | required `--pages`; at least one page must remain |
| `pdf watermark` | Foreground text or PNG/JPEG watermark | `--text`, `--text-file` or `--image`, placement/style options |
| `pdf fill` | Fill named fields using typed data | required `--data`, optional `--font` |
| `pdf insert-image` | Place a PNG/JPEG on selected pages | `--image`, `--pages`, `--x`, `--y`, `--width`, `--height` |
| `pdf ocr` / `pdf import-ocr` | Import externally recognized text as an invisible searchable layer | required `--data`, optional `--font`, `--min-confidence` |

Pass `--help` to any command for its complete options. `--json` writes structured
result metadata to stdout and structured errors to stderr, including argument
validation errors; successful results do not include PDF bytes or passwords.
Malformed configuration or data input is reported without quoting its contents. Exit code `0` indicates success, `1` a file,
configuration or transport failure, and `2` command usage or PDF validation
failure. A successful search with no matches returns `0` and `count: 0`.

### Files, cloud profiles and output safety

Ordinary relative or absolute paths always refer to local files. Prefix a cloud
file with `cloud://PROFILE/` to select a configured S3, SFTP or WebDAV profile:

```bash
crisp pdf merge cover.pdf cloud://my-s3/reports/report.pdf \
  --output cloud://my-dav/reviews/combined.pdf --json

crisp pdf rotate cloud://my-sftp/inbox/report.pdf \
  --pages 2,4-6 --degrees 90 --output rotated.pdf
```

Profile names in these locations may contain letters, digits, `_`, `-`, and `.`;
their case is retained. URI-encode spaces and reserved characters in filenames.
Embedded credentials, ports, query strings, fragments, empty path segments, and
encoded path separators are rejected. Provider credentials stay in the existing
CLI configuration; the default provider never changes the meaning of a PDF path.

An output directory must already exist. Existing outputs are rejected unless
`--overwrite` is explicit. Source aliases, hard links, symbolic-link output files,
and destinations that differ only in case from an existing cloud entry are
refused. A second profile pointing to the same recognized resource cannot be used
to replace an input, including WebDAV profiles whose base directories differ.

New local files reserve their name exclusively and are written with `0600`
permissions on POSIX. Replacing a separate existing local output stages the
complete result beside it and rechecks the previous bytes before replacement;
mode bits are retained, but ownership, ACLs and extended attributes may change.
A failed write to a newly reserved file can leave an incomplete output; keep the
inputs and retry to a new name.

Cloud writes require fresh successful directory listings, reject a changed
destination, and verify the uploaded bytes by reading them back. S3 and WebDAV
listings parse XML namespaces and escaped names, including Unicode filenames;
malformed responses, incomplete pagination, and failed WebDAV resource
properties block output creation. Listing responses are bounded to 16 MiB. The shared
provider interface does not support an atomic conditional create/overwrite:
another client can still change a destination between the last check and upload.
Source files are not deliberately overwritten. Remote names that alias through
server-specific rules beyond the available account/path information cannot be
detected reliably.

### Page expressions, text and search

Page numbers are **one-based**. `all`, `1-3,7`, and descending ranges such as
`5-1` are supported. Repeated, zero, negative and out-of-range page numbers are
rejected. Extraction and merge selections retain the requested order. Reordering
requires every page exactly once; deleting every page is invalid.

```bash
crisp pdf info report.pdf --json
crisp pdf text report.pdf --pages 2-4 > report.txt
crisp pdf search report.pdf 'invoice|receipt' --regex --json
crisp pdf extract report.pdf --pages 1-3,7 --output excerpt.pdf
crisp pdf reorder report.pdf --pages 3,1,2 --output reordered.pdf
crisp pdf delete-pages report.pdf --pages 4-6 --output shorter.pdf
crisp pdf rotate report.pdf --pages 2 --degrees=-90 --output rotated.pdf
```

Plain text output separates pages with a form-feed character. Search JSON reports
one-based `page`, zero-based `pageIndex`, character `start`/`end`, matched `text`
and PDF-space bounds. These commands read existing text; an image-only scan
requires recognition before it can be searched.

### Merge and password handling

The positional input order is the merge order. To select pages independently,
repeat `--source-pages` **once per input**; commas stay within that expression:

```bash
crisp pdf merge cover.pdf report.pdf appendix.pdf \
  --source-pages all --source-pages 1-5,9 --source-pages 3-1 \
  --output combined.pdf
```

PDF passwords are not command-line values. Use a private one-line file with
`--password-file`, or pipe one into `--password-file -`. One final newline is
removed; other whitespace is retained. On POSIX, password files must grant no
group or other permissions, for example `chmod 600 password.txt`. Interactive
terminal input is refused so a password is not echoed. A command can read stdin
only once.

For encrypted merge inputs with different passwords, `--passwords-file` reads a
private JSON array of strings in input order; use `""` for an unencrypted input.
It is mutually exclusive with `--password-file`. Passwords are omitted from
diagnostics and result JSON; malformed password JSON is reported without echoing
its contents.

```bash
crisp pdf rotate protected.pdf --password-file password.txt \
  --pages all --output protected-rotated.pdf

crisp pdf merge a.pdf protected.pdf --passwords-file passwords.json \
  --allow-decryption --output combined.pdf
```

Ordinary edits retain the source PDF's encryption. Extraction creates a new,
unencrypted PDF, so protected input requires `--allow-decryption`. A merge keeps
the first complete input's encryption policy; later sources use that policy.
If the result would expose encrypted input in an unencrypted PDF—including a
subset of an encrypted first input—`--allow-decryption` is required.

### Watermarks and inserted images

Text and image watermarks are foreground marks. They can be applied to all pages
or a selection, with an anchor, opacity, visual clockwise angle, maximum width
fraction and margin. Font sizes and margins are in PDF points. For inserted
images, `x`, `y`, `width`, and optional `height` are fractions of the displayed
crop box, with the origin at its top-left. Omitting image height preserves the
aspect ratio. The operations account for page rotation and different page sizes.

```bash
crisp pdf watermark report.pdf --text 'DRAFT' --pages all \
  --font-size 40 --opacity .15 --angle=-35 --anchor center \
  --output draft.pdf

crisp pdf watermark report.pdf --image logo.png --anchor bottomRight \
  --width .2 --margin 24 --opacity .4 --angle 0 --output branded.pdf

crisp pdf insert-image report.pdf --image photo.jpg --pages 2 \
  --x .1 --y .2 --width .5 --output illustrated.pdf
```

By default only newly added marks are flattened into content; unrelated forms
and annotations are retained. `--no-flatten` keeps the new mark editable as an
annotation. A watermark is not a redaction or an access-control mechanism.

### Filling known form fields

Use `info --json` to discover exact field names, types, choices, export states and
page locations. `fill --data fields.json` accepts a JSON object such as:

```json
{
  "customer.name": "Zoë Example",
  "approved": true,
  "shipping": "express",
  "department": "Engineering",
  "selectedRegions": ["Europe", "Asia"]
}
```

Text fields take strings; checkboxes take booleans; radio groups and single-choice
fields use their documented export values; multi-select lists take arrays of
strings. Names and types must match the document. The complete mapping is
validated before the result is saved: unknown, ambiguous, read-only, password,
signature, unsupported-script and invalid-option fields produce field-specific
errors and no partially filled output. Calculated fields must be filled through
their supported source fields.

```bash
crisp pdf fill form.pdf --data fields.json --output completed.pdf --json
crisp pdf fill form.pdf --data fields.json --font fonts/Roboto-Regular.ttf \
  --output completed-unicode.pdf
```

XFA is not supported. A static PDF with no AcroForm fields needs field authoring
or positioned text; a field-name map does not infer visual field locations.

For Unicode text outside the default font's coverage, supply a suitable TTF/OTF
font with `--font`. Missing glyphs are rejected instead of silently substituting
characters. Complex scripts can still require shaping beyond the writer's
supported layout; review the visible output when the operation reports that
warning. Existing password values or history already present in the input are
not scrubbed by these commands.

### Searchable scans and OCR import

The CLI does not bundle an OCR model or send documents to a recognition service.
It can import output from an external recognizer using the same typed OCR seam
as the application. Recognition JSON is an array of pages with one-based `page`
numbers and spans whose `bounds` are `[left, bottom, right, top]` in the source
PDF's user-space points. Pixel coordinates must first be transformed to those
coordinates, including the source page crop and rotation.

```json
[
  {
    "page": 1,
    "spans": [
      {"text": "Invoice", "bounds": [72, 700, 140, 718], "confidence": 0.97}
    ]
  }
]
```

```bash
crisp pdf ocr scan.pdf --data recognized.json --min-confidence .8 \
  --font fonts/Roboto-Regular.ttf --output searchable.pdf
```

Pages that already contain searchable text are skipped by default to avoid
duplicates. `--no-skip-existing-text` explicitly permits adding another layer.
Unicode OCR needs a font with the relevant glyphs. Recognition accuracy and
bounding boxes belong to the supplied recognition result; review them before
relying on search or extracted text.

### Preservation and resource limits

Page content, retained page resources, form registration and supported
navigation structures follow the fork's operations implementation. Extraction
creates a fresh document; attachments, document JavaScript and signature
validity are not retained, and navigation to omitted pages can be removed. Merge
uses the first PDF's document metadata and renames colliding imported form field
names and named destinations. Later attachments and document JavaScript are not
merged. Source signatures do not certify modified or merged output.

Page deletion and ordinary edits use the engine's normal save model; removed
content may remain in earlier PDF revisions. Neither deletion, extraction,
watermarking nor image insertion promises secure erasure. Redaction is not a CLI
command.

Limits are 64 MiB per input PDF, 256 MiB across PDF merge inputs and 128 MiB for
output/verification. Font and image inputs are limited to 16 MiB, form JSON to
4 MiB, OCR JSON to 16 MiB, and password input to 64 KiB. The shared engine also
caps page counts, decoded image pixels and extracted text. Parsing, decoding and
PDF construction can use more memory than the raw file sizes. Remote downloads
are bounded while reading, including when the server omits its content length.

## PDF verification

The command tests use real encrypted and unencrypted PDF fixtures and reopen
outputs through the shared engine. Storage tests cover account aliases,
conflicting outputs, changed destinations, bounded streams, private password
input, read-back verification and fake cloud adapters. To retain the generated
PDFs for independent inspection in CI:

```bash
PDF_CLI_VERIFY_DIR=../build/pdf_cli_verification \
  dart test test/pdf_command_test.dart test/pdf_io_test.dart
```

Hosted CI is required when the current development sandbox cannot execute Dart.
Successful tests with fake adapters do not establish live provider permissions
or physical-device behavior.
