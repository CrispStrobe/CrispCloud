import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class _Picker extends FilePicker {
  String? name;
  String? title;
  List<String>? extensions;
  Uint8List? bytes;
  final result = Completer<String?>();

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) {
    title = dialogTitle;
    name = fileName;
    extensions = allowedExtensions;
    this.bytes = bytes;
    expect(type, FileType.custom);
    expect(lockParentWindow, isTrue);
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Office copy cancellation preserves extension and localized title',
    () async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final exporting = exportOfficeCopy(
        Uint8List.fromList([1, 2, 3]),
        r'C:\reports\Budget.XLSX',
        'Kopie speichern',
      );
      picker.result.complete(null);
      expect(await exporting, isNull);
      expect(picker.name, 'Budget.XLSX');
      expect(picker.extensions, ['xlsx']);
      expect(picker.title, 'Kopie speichern');
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        expect(
          picker.bytes,
          isNull,
          reason:
              'Desktop bytes must use the staged local write, not the picker.',
        );
      }
    },
  );

  test('native Office export owns bytes during the picker and stages the exact path', () async {
    final directory = await Directory.systemTemp.createTemp('office-copy-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/chosen-name');
    final source = File(
      'packages/quds_office_engine/test/fixtures/fidelity/native.pptx',
    ).readAsBytesSync();
    final original = Uint8List.fromList(source);
    final picker = _Picker();
    FilePicker.platform = picker;
    final exporting = exportOfficeCopy(source, '../slides.pptx', 'Save a copy');
    source.fillRange(0, source.length, 0);
    picker.result.complete(destination.path);
    expect(await exporting, OfficeCopyOutcome.savedCopy);
    expect(picker.name, 'slides.pptx');
    expect(picker.extensions, ['pptx']);
    expect(destination.readAsBytesSync(), orderedEquals(original));
    expect(directory.listSync().map((entry) => entry.path), [destination.path]);
  }, skip: !(Platform.isLinux || Platform.isWindows));

  test('native Office write failure never reports an exported copy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'office-copy-error-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final picker = _Picker();
    FilePicker.platform = picker;
    final exporting = exportOfficeCopy(
      Uint8List.fromList([1, 2, 3]),
      'report.docx',
      'Save a copy',
    );
    picker.result.complete(directory.path);
    await expectLater(exporting, throwsA(isA<FileSystemException>()));
    expect(directory.listSync(), isEmpty);
  }, skip: !(Platform.isLinux || Platform.isWindows));
}
