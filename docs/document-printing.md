# Document printing

File → Print and Cmd/Ctrl+P print the current visible document. The command
is disabled while loading, saving or capturing, behind another modal, and
while a print request is already active. Print commits pending inline fields
but does not save the source or mark it clean. Errors return control to the
document; the user can retry.

Supported editors: PDF, Office documents, text/code, images and EPUB.
Supported F3 modes: PDF, supported Office documents, text/code/XML, CSV,
images, Markdown, HTML and saved email. Unsupported modes do not offer an
image/screenshot fallback. CSV prints as a table with literal cell values.
Images preserve aspect ratio. Text uses the bundled monospace font.

Markdown, HTML and EPUB print a reflowed **text layout**, labelled explicitly
in the job title. This is not a browser or publisher layout: CSS, scripts and
remote resources are not executed or fetched; images are labelled placeholders.
Animated images print their first frame. Large inputs have explicit limits;
printing does not silently truncate a streamed file to its cached viewport.

The Apache-2.0 `dart_pdf_printing` plugin is pinned to 0.11.0, compatible with
the maintained PDF 14.0.0 packages. It uses system print facilities on native
targets and browser PDF printing on web, without introducing another PDF
engine. Sandboxed macOS builds include the printing entitlement. The preview
is cancellable; tests never submit a physical print job.

## Checks

`test/document_printing_test.dart` independently reopens generated PDFs.
`test/widget/document_print_scope_test.dart` checks menus, shortcuts, duplicate
requests, printer failure/retry and covered/disposed routes.
`integration_test/image_text_lifecycle_test.dart` checks native plugin
registration with an invalid request that cannot create a print job.
