import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/gallery_device_export.dart';
import 'package:crisp_cloud/services/gallery_device_export_native.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export keeps its own bytes and the actual image extension', () async {
    final completion = Completer<GalleryExportResult?>();
    late Uint8List exported;
    final exporter = GalleryDeviceExport(exporter: (bytes, name, {
      String? mimeType,
      String? dialogTitle,
    }) {
      exported = bytes;
      expect(name, 'photo.webp');
      expect(mimeType, 'image/webp');
      expect(dialogTitle, 'Save original');
      return completion.future;
    });
    final source = Uint8List.fromList([1, 2, 3]);
    final pending = exporter.exportCopy(source, '../photo.webp',
        mimeType: 'image/webp', dialogTitle: 'Save original');
    source[0] = 9;
    expect(exported, [1, 2, 3]);
    expect(() => exported[0] = 7, throwsUnsupportedError);
    completion.complete(GalleryExportResult.savedCopy);
    expect(await pending, GalleryExportResult.savedCopy);
  });

  test('export cancellation and browser download remain distinct', () async {
    for (final outcome in <GalleryExportResult?>[
      null, GalleryExportResult.savedCopy, GalleryExportResult.downloadedCopy,
    ]) {
      final exporter = GalleryDeviceExport(exporter: (_, name, {
        String? mimeType, String? dialogTitle,
      }) async => outcome);
      expect(await exporter.exportCopy(Uint8List(1), 'image.png'), outcome);
    }
  });

  test('export sanitizes controls and path components without forcing a codec', () async {
    final exporter = GalleryDeviceExport(exporter: (_, name, {
      String? mimeType, String? dialogTitle,
    }) async {
      expect(name, 'a_b_.zip');
      return null;
    });
    await exporter.exportCopy(Uint8List(1), 'C:\\temp\\a:b\u0000.zip');
  });

  group('native export', () {
    late _Picker picker;
    late _Files files;
    setUp(() {
      picker = _Picker();
      files = _Files();
    });

    NativeGalleryDeviceExport native({bool mobile = false, bool macOS = false}) =>
        NativeGalleryDeviceExport(
          picker: picker,
          files: files,
          useNativeDocumentExport: mobile,
          requestMacOSFolderAccess: macOS,
        );

    test('cancel does not write a file', () async {
      expect(await native().exportCopy(Uint8List(2), 'contact.png'), isNull);
      expect(files.writtenPath, isNull);
      expect(picker.receivedBytes, isNull);
    });

    test('desktop writes exactly the picked path once', () async {
      picker.result = '/selected/no-extension';
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await native().exportCopy(bytes, 'original.jpg'),
          GalleryExportResult.savedCopy);
      expect(files.writtenPath, '/selected/no-extension');
      expect(files.writtenBytes, bytes);
      expect(files.calls, 1);
      expect(picker.receivedBytes, isNull);
    });

    test('mobile document provider receives bytes without a second write', () async {
      picker.result = 'content://documents/selected';
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await native(mobile: true).exportCopy(bytes, 'original.gif'),
          GalleryExportResult.savedCopy);
      expect(picker.receivedBytes, bytes);
      expect(files.calls, 0);
    });

    test('failed writes are not reported as saved copies', () async {
      picker.result = '/selected/original.jpg';
      files.failure = StateError('Destination full');
      await expectLater(native().exportCopy(Uint8List(2), 'original.jpg'),
          throwsStateError);
      expect(files.writtenPath, isNull);
      expect(files.requestedDirectory, isNull);
    });

    test('macOS folder grant cannot change the picked destination', () async {
      picker.result = '/selected/original.jpg';
      files.failure = const FileSystemException(
        'Denied', '/selected/original.jpg', OSError('Permission denied', 13),
      );
      files.grantedDirectory = '/other';
      await expectLater(native(macOS: true).exportCopy(Uint8List(2), 'original.jpg'),
          throwsA(isA<FileSystemException>()));
      expect(files.calls, 1);
      expect(files.writtenPath, isNull);
      expect(files.requestedDirectory, '/selected');
    });
  });
}

class _Picker extends FilePicker {
  String? result;
  Uint8List? receivedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    receivedBytes = bytes;
    return result;
  }
}

class _Files implements LocalFileService, LocalFileSaveReporter {
  Object? failure;
  String? writtenPath;
  Uint8List? writtenBytes;
  String? grantedDirectory;
  String? requestedDirectory;
  int calls = 0;

  @override
  Future<LocalFileSaveResult> saveFileWithResult(String path, Uint8List bytes,
      {bool overwrite = true}) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    writtenPath = path;
    writtenBytes = Uint8List.fromList(bytes);
    return LocalFileSaveResult.written;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    requestedDirectory = initialDirectory;
    return grantedDirectory;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
