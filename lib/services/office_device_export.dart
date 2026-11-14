import 'dart:typed_data';

import 'office_device_export_native.dart'
    if (dart.library.html) 'office_device_export_web.dart'
    as platform;
import 'office_device_export_types.dart';

export 'office_device_export_types.dart';

const int kOfficeCopyOutputLimitBytes = 128 * 1024 * 1024;

String officeCopyName(String suggestedName) {
  final name = suggestedName
      .replaceAll('\\', '/')
      .split('/')
      .last
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  return name.isEmpty || name == '.' || name == '..' ? 'document.docx' : name;
}

Future<OfficeCopyOutcome?> exportOfficeCopy(
  Uint8List bytes,
  String suggestedName,
  String dialogTitle,
) {
  if (bytes.length > kOfficeCopyOutputLimitBytes) {
    throw StateError('The Office document exceeds the 128 MiB export limit.');
  }
  return platform.exportOfficeCopy(
    Uint8List.fromList(bytes).asUnmodifiableView(),
    officeCopyName(suggestedName),
    dialogTitle,
  );
}
