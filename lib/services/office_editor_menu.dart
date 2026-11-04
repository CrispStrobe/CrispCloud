// lib/services/office_editor_menu.dart
//
// Bridge between the Office editor dialog and the macOS native menu bar. The
// dialog registers a perform callback while it is open; the browser screen
// turns that into real NSMenu entries.

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OfficeEditorKind { word, sheet, slides, unsupported }

enum OfficeEditorAction {
  save,
  close,
  undo,
  redo,
  cut,
  copy,
  paste,
  selectAll,
  bold,
  italic,
  underline,
  find,
  replace,
  font,
  paragraph,
  insertTable,
  insertHyperlink,
  insertPicture,
  insertComment,
  pageBreak,
  sectionBreak,
  tableOfContents,
  header,
  footer,
  pageNumber,
  watermark,
  pageSetup,
  wordCount,
  trackChanges,
  protect,
  readingView,
  keyboardShortcuts,
  about,
  rowsAbove,
  rowsBelow,
  columnsLeft,
  columnsRight,
  deleteRows,
  deleteColumns,
  sortAscending,
  sortDescending,
  filter,
  clearFilter,
  freezePanes,
  protectSheet,
  sheetComment,
  fillColor,
  fontColor,
  clearFormatting,
  mergeCells,
  unmergeCells,
  newSlide,
  duplicateSlide,
  deleteSlide,
  textBox,
  rectangle,
  ellipse,
  line,
  slideTable,
  slidePicture,
  speakerNotes,
  slideShow,
  transitions,
  animations,
  background,
  textColor,
  shapeFill,
}

class OfficeEditorMenuActions {
  const OfficeEditorMenuActions({
    required this.kind,
    required this.perform,
  });

  final OfficeEditorKind kind;
  final void Function(OfficeEditorAction action) perform;
}

/// Null while no Office editor is open.
final StateProvider<OfficeEditorMenuActions?> officeEditorMenuProvider =
    StateProvider<OfficeEditorMenuActions?>((Ref ref) => null);
