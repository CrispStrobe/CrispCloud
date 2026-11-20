import 'dart:typed_data';

import 'package:quds_office_editor/quds_office_editor.dart';

import 'document_fonts.dart';

/// Full Office canvases for viewing; PDF serialization is unnecessary here.
/// Unsupported formats retain their existing explicit preview routes.
Future<OfficeController?> loadOfficePagePreview(
  Uint8List bytes, {
  required String filename,
}) async {
  final extension = filename.toLowerCase().split('.').last;
  final word = const {'docx', 'docm', 'dotx', 'dotm'}.contains(extension);
  final slides = const {
    'pptx',
    'pptm',
    'potx',
    'potm',
    'ppsx',
    'ppsm',
  }.contains(extension);
  if (!word && !slides) return null;
  if (bytes.length > 64 * 1024 * 1024) {
    throw const FormatException(
      'This document is too large to preview safely.',
    );
  }
  await DocumentFonts.ensureRegistered();
  const config = OfficeSurfaceConfig(
    mode: OfficeInteractionMode.viewing,
    showRulers: false,
    showSlideHandles: false,
    enableUndo: false,
    adaptiveChrome: false,
  );
  if (word) {
    final controller = WordEditorController(
      document: WordDeserializer().readBytes(bytes),
      config: config,
    );
    controller.fitPaintMetrics();
    return controller;
  }
  return SlideEditorController.fromBytes(bytes, config: config);
}
