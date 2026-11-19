import 'dart:io';

import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Use the application's real bundled faces for review geometry and captures.
Future<void> loadReviewFonts() async {
  await OfficeHostFonts.ensureRegistered();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final path =
      Platform.environment['QUDS_REVIEW_ICON_FONT'] ??
      (sdk == null
          ? null
          : '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (path == null) return;
  final file = File(path);
  if (!await file.exists()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(file.readAsBytes().then(ByteData.sublistView));
  await loader.load();
}
