/// Native Flutter hex editing over immutable, range-readable byte sources.
///
/// The host owns persistence; use [HexDocument.snapshot] for a consistent save
/// and close each snapshot in a `finally` block.
library;

export 'src/core/hex_byte_source.dart'
    show
        HexByteSource,
        MemoryHexByteSource,
        CallbackHexByteSource,
        HexRangeReader,
        HexSourceCloser;
export 'src/core/hex_document.dart' show HexDocument, HexSnapshot;
export 'src/ui/hex_editor_controller.dart'
    show HexEditorController, HexEditorSelection, HexEditorArea;
export 'src/ui/hex_editor.dart' show HexEditor, HexEditorTheme, HexEditorLabels;
