## 0.1.0-dev.1

- Extract the bounded DOC/DOT parser and structured document model from
  CrispCloud as a Flutter-independent Dart package under MPL-2.0.
- Retain MIT compound-file and 0BSD JSDoc provenance notices.
- Preserve main-story formatting, basic tables, section geometry and supported
  tracked insertions/deletions, with explicit partial-support diagnostics.
- Add referenced headers/footers, footnotes/endnotes, comment metadata, bookmarks,
  nested fields, list definitions, and linked textbox stories to the typed model.
- Add custom/default tab stops, paragraph borders, paragraph/table-cell shading,
  and exact underline variants, including bounded binary property handling.
- Add a Flutter-independent DOCX/DOCM OPC writer using `archive`, with actual
  document parts and relationships for supported content. Retain the existing
  structured DOCX and explicit text-only conversion entry points.
- Retain referenced PNG/JPEG/TIFF images, crop and supported floating positions;
  preserve hidden/revision presentation and keep deleted shapes inactive.
- Preserve eligible embedded OLE and structurally complete explicit-DOCM VBA
  projects with compound-storage metadata and exact raw FILETIME bytes. DOCX
  output remains free of active VBA relationships.
- Retain unsupported content and original signatures as inert evidence with a
  manifest. Never activate copied signatures or claim signature validity.
- Keep hidden/private note/comment content out of active output references;
  lock supported fields, retain cached results, and avoid external resources.
- Add standalone parser/writer regression suites, a runnable file-copy example,
  detailed preservation contracts, and offline JavaScript/Node acceptance using
  an authored DOC plus OLE/VBA metadata fixtures.
- Host development at https://github.com/CrispStrobe/legacy-doc-parser.
