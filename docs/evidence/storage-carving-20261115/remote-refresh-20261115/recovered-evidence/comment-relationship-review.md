# Comment relationship and deletion review

Read-only review of canonical Quds source
`6e4c3b16b4310f2c21b6d8b5e412af9850eb17ea`, focused on the comment roundtrip
paths in `packages/quds_office_engine/lib/src/sheet/serial/sheet_serial.dart`.
The test/fix owner is `office_parser_audit`; this reviewer changed no project
source. Findings below are static source findings, not an additional runtime
test receipt.

## Confirmed defects

1. `_readSheetExtras` receives the actual owning `sheetUri` but loads comments
   only from `/xl/comments${sheet.sheetId}.xml`. It never consults the worksheet's
   comments relationship. A valid imported workbook with its comment part at
   `/xl/annotations/note42.xml` therefore produces an empty comment model. If a
   fixed-name decoy part is present, the wrong comments are imported instead.
2. `_writeSheetExtras` always writes the fixed-name part and only adds a comments
   relationship when none exists. An existing relationship to a different part
   remains unchanged. Edits written to the fixed-name part are unreachable through
   the existing relationship; consumers continue to see the old target.
3. The entire comments writer is guarded by `sheet.comments.isNotEmpty`. Clearing
   all comments leaves the original part, content type and relationship in the
   reused package. `OpcPackage.save()` serializes all retained parts. No implicit
   cleanup removes the old comments, so they reappear on reopen.
4. The fixed relative target `../comments${sheetId}.xml` assumes the worksheet
   lives one directory below `/xl`. Imported worksheet part URIs are preserved
   by the serializer and may have another depth. Use
   `OpcUris.relativize(sheetUri, commentsUri)` for a newly created relationship.

The ownership rule is explicit in the primary documentation: the worksheet's
relationship selects the correct comments part; the filename is not the
authority. See [Microsoft's Comments documentation](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.comments?view=openxml-3.0.1).

## Minimal regression profiles

- Manually author a valid namespaced comments part with authors, commentList and
  plain `<text><t>`. Place it at `/xl/annotations/note42.xml`, retarget the sheet's
  existing comments relationship without changing its ID, and delete the fixed
  `/xl/comments1.xml` part. Save and reopen the ZIP before importing. Assert the
  authored text/author import, edit, save, and remain reachable after three
  reopen cycles.
- Add a different comment at the old fixed-name URI. The explicitly declared
  comments relationship must win. The unrelated decoy must not be silently
  overwritten when the real comments are edited.
- Clear every comment after importing each standard and relocated profile.
  Save/reopen twice; assert the model remains empty, the comments relationship
  is removed, and its owned comments part/content-type override is absent.
- Preserve the deliberate legacy fallback when there is no declared comments
  relationship and the old fixed-name part is present.

These recommendations were sent to the owner before production edits. The owner
confirmed the relocation/deletion/precedence/fallback cases were added to the
test-only baseline and exercise serialized ZIP bytes.

## Repair considerations

Resolve the actual internal comments relationship on both read and write.
Prefer updating that owned part in place and retaining its relationship ID.
When no relationship exists, retain the intentionally supported legacy fallback
and allocate a new part without overwriting an unrelated fixed-name part.
For deletion, `package.deletePart(uri)` also removes the content-type override;
remove the owning relationship separately with `removeById`. Unrelated VML and
control relationships must not be removed blindly.

The independent three-cycle lexical output oracle lives separately at
`/workspace/scratch/0b93849cdeb9/comments-qualification-20261115/verify_comments.py`.
It checks namespace, plain text containers, author indexing, edge whitespace and
external openpyxl text/author reads. Its generated-output acceptance does not
replace these relationship ownership and deletion regression cases.
