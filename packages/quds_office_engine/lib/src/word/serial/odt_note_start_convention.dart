/// The explicit editable-export convention for LibreOffice-compatible note
/// offsets. ODF 1.3 section 19.874.5 describes an initial number, while
/// LibreOffice imports/exports the zero-based `StartAt` value. A versioned
/// producer declaration keeps that distinction out of generic ODF imports.
const odtZoteroNoteOffsetGenerator = 'CrispOffice Zotero ODT note-offsets/1';

/// LibreOffice's note-configuration importer accepts a signed 16-bit offset.
/// The largest representable positive initial note number is offset + 1.
const odtNoteStartMaximum = 32768;
