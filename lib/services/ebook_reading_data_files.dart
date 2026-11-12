import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'ebook_edit_session.dart';
import 'ebook_reading_data.dart';
import 'ebook_reading_data_files_native.dart'
    if (dart.library.js_interop) 'ebook_reading_data_files_web.dart'
    as platform;

typedef EbookReadingDataPicker = Future<String?> Function();
typedef EbookReadingDataExporter = Future<EbookSaveOutcome?> Function(
  String json,
  String suggestedName,
);

/// Check the declared size before opening a stream, then bound the actual read.
/// Some providers report a stale size, so the stream limit is authoritative.
Future<String> readEbookReadingDataFile(PlatformFile file) async {
  const maximum = EbookReadingData.maximumJsonBytes;
  if (file.size < 0 || file.size > maximum) {
    throw const EbookReadingDataException(
      EbookReadingDataError.tooLarge,
      'Reading-data files must be at most 2 MiB.',
    );
  }
  final builder = BytesBuilder(copy: false);
  if (file.readStream case final stream?) {
    await for (final chunk in stream) {
      if (chunk.length > maximum - builder.length) {
        throw const EbookReadingDataException(
          EbookReadingDataError.tooLarge,
          'Reading-data files must be at most 2 MiB.',
        );
      }
      builder.add(chunk);
    }
  } else if (file.bytes case final bytes?) {
    if (bytes.length > maximum) {
      throw const EbookReadingDataException(
        EbookReadingDataError.tooLarge,
        'Reading-data files must be at most 2 MiB.',
      );
    }
    builder.add(bytes);
  } else {
    throw const EbookReadingDataException(
      EbookReadingDataError.invalid,
      'The selected reading-data file could not be read.',
    );
  }
  try {
    return utf8.decode(builder.takeBytes());
  } on FormatException {
    throw const EbookReadingDataException(
      EbookReadingDataError.invalid,
      'Reading-data files must contain UTF-8 JSON.',
    );
  }
}

Future<String?> pickEbookReadingDataFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Import reading data',
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: false,
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty) return null;
  return readEbookReadingDataFile(result.files.single);
}

Future<EbookSaveOutcome?> exportEbookReadingDataFile(
  String json,
  String suggestedName,
) {
  checkEbookJsonBounds(json, maximumBytes: EbookReadingData.maximumJsonBytes);
  var name = suggestedName
      .replaceAll(RegExp(r'[\\/\x00-\x1f<>:"|?*]'), '_')
      .trim();
  if (name.isEmpty) name = 'book.reading.json';
  if (name.length > 180) name = name.substring(0, 180);
  if (!name.toLowerCase().endsWith('.json')) name = '$name.json';
  return platform.exportReadingData(Uint8List.fromList(utf8.encode(json)), name);
}
