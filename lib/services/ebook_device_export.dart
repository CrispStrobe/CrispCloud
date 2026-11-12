import 'dart:typed_data';

import 'ebook_device_export_native.dart'
    if (dart.library.html) 'ebook_device_export_web.dart'
    as platform;
import 'ebook_edit_session.dart';
import 'ebook_file_store.dart';

typedef EbookDeviceExporter = Future<EbookSaveOutcome?> Function(
  Uint8List bytes,
  String suggestedName,
);

Future<EbookSaveOutcome?> exportEbookCopy(
  Uint8List bytes,
  String suggestedName,
) {
  if (bytes.length > kEbookOutputLimitBytes) {
    throw StateError('The ebook exceeds the 128 MiB export limit.');
  }
  var name = suggestedName
      .replaceAll('\\', '/')
      .split('/')
      .last
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  if (name.isEmpty || name == '.' || name == '..') name = 'book.epub';
  if (!const {
    'epub',
    'mobi',
    'azw3',
  }.contains(name.toLowerCase().split('.').last)) {
    name = '$name.epub';
  }
  return platform.exportEbookCopy(
    Uint8List.fromList(bytes).asUnmodifiableView(),
    name,
  );
}
