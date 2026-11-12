import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/external_edit_copy_export.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/external_edit_fakes.dart';

class _Picker extends FilePicker {
  String? destination, suggestedName;
  Future<void> Function()? beforeReturn;
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
    suggestedName = fileName;
    expect(bytes, isNull);
    await beforeReturn?.call();
    return destination;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FakeEditStagingStore store;
  late FakeReadOnlyEditClient client;
  late ExternalRemoteEditingService service;
  late ExternalEditSession session;
  late _Picker picker;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('retained-edit-export-');
    store = FakeEditStagingStore();
    client = FakeReadOnlyEditClient();
    service = ExternalRemoteEditingService(staging: store);
    session = await service.prepare(client.source());
    store.edit(session, [3, 4, 5]);
    await session.scan();
    picker = _Picker();
  });
  tearDown(() async {
    await service.close();
    await temporary.delete(recursive: true);
  });

  test('verified export writes exactly the chosen independent path and never marks original saved', () async {
    picker.destination = p.join(temporary.path, 'chosen-name.data');
    expect(
      await ExternalEditCopyExporter(picker: picker)
          .export(session, 'Export copy'),
      isTrue,
    );
    expect(await File(picker.destination!).readAsBytes(), [3, 4, 5]);
    expect(picker.suggestedName, 'document.txt');
    expect(client.bytes, [1, 2]);
    expect(session.record!.savedGeneration, 0);
    expect(session.record!.hasLocalChanges, isTrue);
    expect(session.record!.baseline, isNull);
    expect(store.bundles[session.id]!.files[session.record!.workingName], [
      3,
      4,
      5,
    ]);
  });

  test(
    'cancelled export preserves retained edits and creates no destination',
    () async {
      expect(
        await ExternalEditCopyExporter(picker: picker)
            .export(session, 'Export copy'),
        isFalse,
      );
      expect(await temporary.list().isEmpty, isTrue);
      expect(session.record!.hasLocalChanges, isTrue);
    },
  );

  test('source changed while choosing a destination cannot replace the existing local file', () async {
    picker.destination = p.join(temporary.path, 'existing.txt');
    await File(picker.destination!).writeAsString('existing content');
    picker.beforeReturn = () async {
      store.edit(session, [9]);
    };
    await expectLater(
      ExternalEditCopyExporter(picker: picker).export(session, 'Export copy'),
      throwsA(anything),
    );
    expect(await File(picker.destination!).readAsString(), 'existing content');
    expect(client.bytes, [1, 2]);
    expect(store.bundles[session.id]!.files[session.record!.workingName], [9]);
  });

  test(
    'export cannot overwrite its own retained working file or manifest',
    () async {
      picker.destination = '${session.directoryPath}/manifest.json';
      await expectLater(
        ExternalEditCopyExporter(picker: picker).export(session, 'Export copy'),
        throwsA(isA<ExternalEditException>()),
      );
      expect(store.bundles[session.id]!.manifest, isNotNull);
      expect(session.record!.hasLocalChanges, isTrue);
    },
  );
}
