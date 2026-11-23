import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:quds_office_editor/quds_office_editor.dart';

import 'document_fonts.dart';
import 'office_document_service.dart';

const officeStandardInputLimit = 64 * 1024 * 1024;
const officeDesktopSlideInputLimit = 256 * 1024 * 1024;

int officeSlideInputLimit(String filename, {required bool local}) =>
    local &&
        !kIsWeb &&
        const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform) &&
        (isOfficeSlidePackageName(filename) || isLegacyPowerPointName(filename))
    ? officeDesktopSlideInputLimit
    : officeStandardInputLimit;

/// Full Office canvases for viewing; PDF serialization is unnecessary here.
/// Unsupported formats retain their existing explicit preview routes.
Future<OfficeController?> loadOfficePagePreview(
  Uint8List bytes, {
  required String filename,
  bool local = false,
}) async {
  final extension = filename.toLowerCase().split('.').last;
  final word = const {'docx', 'docm', 'dotx', 'dotm'}.contains(extension);
  final slides = isOfficeSlidePackageName(filename);
  if (!word && !slides) return null;
  if (bytes.length > officeSlideInputLimit(filename, local: local)) {
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
  final controller = SlideEditorController(config: config);
  try {
    await controller.loadBytesAsync(bytes);
    return controller;
  } catch (_) {
    controller.dispose();
    rethrow;
  }
}
