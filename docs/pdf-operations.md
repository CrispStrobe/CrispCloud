# PDF operations in the GUI and CLI

CrispCloud uses the same Apache-2.0 `pdf_operations` service in its graphical
application and standalone Dart CLI. Operations accept immutable byte snapshots
and return a new PDF with result metadata. Storage, passwords, save destinations
and platform dialogs belong to the host.

## Capabilities

| Task | Graphical application | CLI |
| --- | --- | --- |
| Select/search existing text | PDF editor, plus searchable operation preview | `pdf text`, `pdf search` |
| Inspect pages and known fields | Operation dialog and typed form controls | `pdf info --json` |
| Merge PDFs | Select PDFs, then **Merge selected PDFs**; drag sources into order | `pdf merge` |
| Extract pages | **Extract these pages**; preview and save a separate file | `pdf extract` |
| Rotate pages | **Rotate selected pages** with a page expression | `pdf rotate` |
| Reorder/delete pages | Selected-file dialogs and the editor thumbnail tools | `pdf reorder`, `pdf delete-pages` |
| Insert PNG/JPEG images | **Insert an image**, or the editor image tool | `pdf insert-image` |
| Add a text/logo watermark | **Add a watermark**, with exact output preview | `pdf watermark` |
| Fill named fields | Typed controls, multiline fields and editable/imported JSON | `pdf fill` |
| Add externally recognized text | **Import OCR text**, then search the preview | `pdf ocr` / `pdf import-ocr` |

The file context menu and Ctrl+Shift+P command palette expose the operations for
the current selection. Merge requires multiple selected PDFs; the other actions
operate on one selected PDF. Open the editor with F4 for direct text selection,
annotations, form entry, page thumbnails and content editing. The editor's
Insert PDF dialog also supports multiple protected sources, independent page
selections, ordering and placement.

## Preview and storage

Choose an operation, review its page selection and options, then create the
preview. Saving uses those exact preview bytes. Changing an option invalidates
the previous result; it cannot silently save an outdated preview. New outputs
are saved as a sibling file or exported to a device destination. The original
listing's verified storage/account identity is captured before source reads.
Switching accounts or losing the connection cannot retarget a pending write.
Device export remains available for a generated result.

Native GUI work runs in a worker isolate; the web compute adapter runs in the
browser's main execution context. Large or complex PDFs can therefore occupy
the browser while an operation runs. Input 64 MiB/output 128 MiB/combined 256 MiB
limits and page/image limits constrain admission, not peak parser memory.

CLI paths are local unless explicitly written as `cloud://PROFILE/path`.
The existing S3, SFTP and WebDAV profiles can supply independent inputs and
outputs, including a merge across providers. Every mutating command requires
`--output`; an existing output requires `--overwrite`. Recognized source aliases
and symbolic-link destinations are rejected. Cloud writes require complete
fresh listings and a read-back verification; provider APIs still lack atomic
conditional creation/overwrite, leaving a final check/write race.

## CLI examples

```sh
crisp pdf info form.pdf --json
crisp pdf search report.pdf 'invoice' --json
crisp pdf merge cover.pdf report.pdf --output combined.pdf
crisp pdf extract report.pdf --pages 1-3,7 --output excerpt.pdf
crisp pdf rotate report.pdf --pages 2,4-6 --degrees 90 --output rotated.pdf
crisp pdf reorder report.pdf --pages 3,1,2 --output reordered.pdf
crisp pdf delete-pages report.pdf --pages 2 --output shorter.pdf
crisp pdf watermark report.pdf --text DRAFT --opacity .2 --output draft.pdf
crisp pdf fill form.pdf --data fields.json --output completed.pdf --json
crisp pdf insert-image report.pdf --image logo.png --pages 1 --output illustrated.pdf
crisp pdf ocr scan.pdf --data recognized-spans.json --font covering-font.ttf \
  --output searchable.pdf
```

Page expressions are one-based and inclusive: `all`, `1-3,7`, or descending
ranges such as `4-1`. Order is retained. Invalid, repeated or out-of-range pages
are rejected. Reordering requires every page exactly once; deleting every page
is rejected. `--json` provides structured results/errors; invalid requests use
exit code 2, while file/configuration/transport failures use exit code 1. See
[the CLI guide](../cli/README.md) for passwords, per-source merge ranges, output
safety, full watermark placement options and OCR interchange.

## Forms and fonts

Known-field filling uses full AcroForm names. Text takes strings, checkboxes
booleans, radios and single choices export values, and multiple choices string
arrays. The entire map is checked before output: unknown or ambiguous names,
invalid types/options, read-only/password/signature fields, unsupported scripts
and missing font glyphs reject the request. A checkbox is set, not toggled.
Recognized validation/calculation helpers run; arbitrary JavaScript does not.

The GUI supplies a bundled font and supports choosing a covering TTF/OTF. The
CLI accepts `--font`. Embedded Unicode appearances and ToUnicode mappings are
used for supported fonts. Cyrillic and Greek are exercised alongside Latin
text. Font coverage alone does not establish correct Arabic/Indic or other
complex-script shaping; those layouts require representative visual checks.
Filling known fields does not detect or create fields in an ordinary static PDF.

## Preservation and encryption

- Extraction creates a fresh file with selected content, resources, annotations
  and supported AcroForm branches/defaults/calculation order. Bookmarks and
  named destinations are remapped; links to omitted pages are removed. Source
  revision history, unrelated attachments and document JavaScript are not copied.
  Resources shared by selected pages may still contain unused data.
- Ordinary edits retain encryption. Extraction is unencrypted; protected inputs
  require explicit acknowledgement. Merge uses the first complete source's
  encryption policy; an extracted first-source subset creates a plain base.
  The CLI requires `--allow-decryption` when this would remove protection.
- Colliding imported form/destination names are renamed. Later source
  attachments, XFA and arbitrary document JavaScript are not merged.
- XFA editing and redaction remain disabled in CrispCloud. A signed source does
  not certify a changed output; keep the signed original separately. Page
  deletion is incremental and can retain old content in historical bytes.
- Watermarks are foreground overlays. Default flattening bakes only the new
  mark into page content; unrelated forms and comments remain interactive.
  An editable mark is also supported. Neither form is a removal deterrent.
- OCR import writes supplied recognition spans. It does not bundle, launch or
  contact an OCR model. Existing text is skipped by default; recognition quality
  belongs to the chosen backend. The package exposes an injected backend seam.

## Repository and fork

Application and engine changes are preserved incrementally on
`feature/pdf-editor-integration` in [draft PR #6](https://github.com/CrispStrobe/CrispCloud/pull/6).
A dedicated `CrispStrobe/dart-pdf` fork was requested, but its creation needs
authenticated GitHub access unavailable after browser sign-in was cancelled.
The connector can push existing repositories but cannot create a fork.

The complete, binary-safe [fork transfer](../packages/pdf_fork_transfer/README.md)
contains the shared package and general engine extensions. Its patch hash,
immutable upstream base and exact expected Git tree are recorded and checked.
No changes have been pushed to the original author's repository.

`packages/pdf_document/UPSTREAM.patch` and the editor's existing patch reproduce
the maintained runtime snapshots. `tool/update_pdf_vendor_patches.py` verifies
them byte-for-byte against upstream 14.0.0. Package code remains Apache-2.0;
bundled/test fonts retain their separate notices.

## Validation status

Hosted validation is in progress. The focused workflow runs maintained core and
service analysis/tests, all CLI tests, native and Chrome host/widget tests,
real PDF round trips, an independent pypdf parser/geometry check, and release
web compilation. The full application workflow supplies the broader tests and
platform builds. Generated PDFs and bounded performance observations are kept
as reviewable CI artifacts. No physical-device or live-account smoke-test
coverage is implied by these automated checks.
