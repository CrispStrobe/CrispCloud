import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/pdf_device_export.dart';
import 'package:crisp_cloud/services/pdf_device_export_native.dart';
import 'package:crisp_cloud/services/pdf_edit_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int value) => Uint8List.fromList([37, 80, 68, 70, value]);

void main() {
  test('owns the exported revision while the destination picker is open',
      () async {
    final picker = Completer<PdfSaveOutcome?>();
    late Uint8List captured;
    final exporter = PdfDeviceExport(exporter: (bytes, name) {
      captured = bytes;
      expect(name, 'edited.pdf');
      return picker.future;
    });
    final editingBuffer = _bytes(2);
    final exporting = exporter.exportCopy(editingBuffer, '../edited');
    editingBuffer[4] = 3;
    expect(captured, _bytes(2));
    expect(() => captured[4] = 4, throwsUnsupportedError);
    picker.complete(PdfSaveOutcome.savedCopy);
    expect(await exporting, PdfSaveOutcome.savedCopy);
  });

  for (final outcome in [
    null,
    PdfSaveOutcome.savedCopy,
    PdfSaveOutcome.downloadedCopy,
  ]) {
    test('independent export outcome $outcome never marks the original saved',
        () async {
      final session = PdfEditSession(initialBytes: _bytes(1));
      addTearDown(session.dispose);
      session.updateBytes(_bytes(2));
      final exporter = PdfDeviceExport(exporter: (_, name) async => outcome);
      expect(await exporter.exportCopy(session.bytes, 'report.pdf'), outcome);
      expect(session.isDirty, isTrue);
      expect(session.bytes, _bytes(2));
    });
  }

  test('export errors preserve the editor revision', () async {
    final session = PdfEditSession(initialBytes: _bytes(1));
    addTearDown(session.dispose);
    session.updateBytes(_bytes(2));
    final exporter = PdfDeviceExport(exporter: (_, name) async {
      throw StateError('Destination unavailable');
    });
    await expectLater(
      exporter.exportCopy(session.bytes, 'report.pdf'),
      throwsStateError,
    );
    expect(session.isDirty, isTrue);
    expect(session.bytes, _bytes(2));
  });

  group('native PDF device export', () {
    late _Picker picker;
    late _Files files;

    setUp(() {
      picker = _Picker();
      files = _Files();
    });

    NativePdfDeviceExport native({bool mobile = false, bool macOS = false}) =>
        NativePdfDeviceExport(
          picker: picker,
          files: files,
          useNativeDocumentExport: mobile,
          requestMacOSFolderAccess: macOS,
        );

    test('cancelled desktop dialog never writes or hands bytes to the picker',
        () async {
      picker.result = null;
      expect(await native().exportCopy(_bytes(2), 'copy.pdf'), isNull);
      expect(picker.receivedBytes, isNull);
      expect(files.writeCalls, 0);
    });

    test('writes exactly the desktop path confirmed by the save dialog',
        () async {
      picker.result = '/chosen/no-extension';
      expect(await native().exportCopy(_bytes(2), 'copy.pdf'),
          PdfSaveOutcome.savedCopy);
      expect(picker.receivedBytes, isNull);
      expect(files.writtenPath, '/chosen/no-extension');
      expect(files.writtenBytes, _bytes(2));
      expect(files.overwrite, isTrue);
      expect(files.writeCalls, 1);
    });

    test('mobile hands bytes to the document provider without a second write',
        () async {
      picker.result = 'content://provider/exported.pdf';
      expect(await native(mobile: true).exportCopy(_bytes(2), 'copy.pdf'),
          PdfSaveOutcome.savedCopy);
      expect(picker.receivedBytes, _bytes(2));
      expect(files.writeCalls, 0);
    });

    test('mobile cancellation remains cancellation', () async {
      picker.result = null;
      expect(await native(mobile: true).exportCopy(_bytes(2), 'copy.pdf'), isNull);
      expect(files.writeCalls, 0);
    });

    test('desktop write failure is never reported as an exported copy', () async {
      picker.result = '/chosen/copy.pdf';
      files.failures.add(StateError('Write failed'));
      await expectLater(
        native().exportCopy(_bytes(2), 'copy.pdf'),
        throwsStateError,
      );
      expect(files.committedWrites, 0);
    });

    test('macOS requests a folder scope only after an actual access denial',
        () async {
      picker.result = '/chosen/copy.pdf';
      files.failures.add(const FileSystemException(
        'Denied',
        '/chosen/copy.pdf',
        OSError('Permission denied', 13),
      ));
      files.grantedFolder = '/chosen';
      expect(await native(macOS: true).exportCopy(_bytes(2), 'copy.pdf'),
          PdfSaveOutcome.savedCopy);
      expect(files.requestedDirectory, '/chosen');
      expect(files.writeCalls, 2);
      expect(files.committedWrites, 1);
    });

    test('cancelled folder access does not report a completed export', () async {
      picker.result = '/chosen/copy.pdf';
      files.failures.add(const FileSystemException(
        'Denied',
        '/chosen/copy.pdf',
        OSError('Permission denied', 13),
      ));
      files.grantedFolder = null;
      expect(await native(macOS: true).exportCopy(_bytes(2), 'copy.pdf'), isNull);
      expect(files.writeCalls, 1);
      expect(files.committedWrites, 0);
    });

    test('a grant for another folder does not retarget the export', () async {
      picker.result = '/chosen/copy.pdf';
      files.failures.add(const FileSystemException(
        'Denied',
        '/chosen/copy.pdf',
        OSError('Permission denied', 13),
      ));
      files.grantedFolder = '/different';
      await expectLater(
        native(macOS: true).exportCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<FileSystemException>()),
      );
      expect(files.writeCalls, 1);
      expect(files.committedWrites, 0);
    });

    test('non-permission failures do not ask for another grant or retry',
        () async {
      picker.result = '/chosen/copy.pdf';
      files.failures.add(const FileSystemException(
        'No space',
        '/chosen/copy.pdf',
        OSError('Disk full', 28),
      ));
      await expectLater(
        native(macOS: true).exportCopy(_bytes(2), 'copy.pdf'),
        throwsA(isA<FileSystemException>()),
      );
      expect(files.requestedDirectory, isNull);
      expect(files.writeCalls, 1);
      expect(files.committedWrites, 0);
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
  final failures = <Object>[];
  int writeCalls = 0;
  int committedWrites = 0;
  String? writtenPath;
  Uint8List? writtenBytes;
  bool? overwrite;
  String? grantedFolder;
  String? requestedDirectory;

  @override
  Future<LocalFileSaveResult> saveFileWithResult(
    String path,
    Uint8List bytes, {
    bool overwrite = true,
  }) async {
    writeCalls++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    writtenPath = path;
    writtenBytes = Uint8List.fromList(bytes);
    this.overwrite = overwrite;
    committedWrites++;
    return LocalFileSaveResult.written;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    requestedDirectory = initialDirectory;
    return grantedFolder;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
