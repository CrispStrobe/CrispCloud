import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/cloud_object_reader.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

class _Drive extends Fake implements CloudStorageClient, CloudObjectReader {
  final objects = <String, Map<String, dynamic>>{
    'folder': {
      'id': 'folder',
      'name': 'Reports/2026',
      'mimeType': 'application/vnd.google-apps.folder',
      'parents': ['root'],
    },
    'doc': {
      'id': 'doc',
      'name': 'Budget/actual',
      'mimeType': 'application/vnd.google-apps.document',
      'downloadExtension': 'docx',
      'parents': ['folder'],
    },
    'normal': {
      'id': 'normal',
      'name': 'café.txt',
      'mimeType': 'text/plain',
      'size': '5',
      'parents': ['folder'],
    },
  };
  final readIds = <String>[];
  @override
  String get rootPath => '/';
  @override
  String get providerName => 'Google Drive';
  @override
  String? get userId => 'fixture';
  @override
  String? get bucketId => 'drive';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Map<String, dynamic>> readObjectMetadata(String id) async =>
      objects[id]!;
  @override
  Future<List<Map<String, dynamic>>> listObjectChildren(String id) async =>
      objects.values.where((m) => (m['parents'] as List).contains(id)).toList();
  @override
  Stream<List<int>> readObjectContents(String id) async* {
    readIds.add(id);
    yield utf8.encode(id == 'doc' ? 'exported document' : 'hello');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Drive folders and documents with separators copy by ID with reviewed portable names', () async {
    final root = await Directory.systemTemp.createTemp('drive-copy-');
    addTearDown(() => root.delete(recursive: true));
    final drive = _Drive();
    final target = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final plan = await const FileOperationService().prepare(
      files: [
        FileItem(
          name: 'Reports/2026',
          path: '/Reports/2026',
          uuid: 'folder',
          isFolder: true,
        ),
      ],
      source: CloudOperationBackend(drive, isCurrent: () => true),
      destination: target,
      targetDirectory: root.path,
      options: const FileOperationOptions(verifyContents: true),
    );
    expect(plan.errors, isEmpty);
    expect(
      plan.entries.map((e) => e.destination),
      contains('${root.path}/Reports_2026/Budget_actual.docx'),
    );
    expect(
      plan.entries.where((e) => !e.source.isFolder).map((e) => e.source.uuid),
      containsAll(['doc', 'normal']),
    );
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(plan.entries.where((e) => e.failed), isEmpty);
    expect(
      await File('${root.path}/Reports_2026/Budget_actual.docx').readAsString(),
      'exported document',
    );
    expect(
      await File('${root.path}/Reports_2026/café.txt').readAsString(),
      'hello',
    );
    expect(drive.readIds, containsAll(['doc', 'normal']));
  });

  test(
    'mapped names that collide require a conflict decision before writing',
    () async {
      final root = await Directory.systemTemp.createTemp('drive-collision-');
      addTearDown(() => root.delete(recursive: true));
      final drive = _Drive()
        ..objects['collision'] = {
          'id': 'collision',
          'name': 'Budget_actual.docx',
          'mimeType': 'text/plain',
          'size': '5',
          'parents': ['folder'],
        };
      final plan = await const FileOperationService().prepare(
        files: [
          FileItem(
            name: 'Reports/2026',
            path: '/Reports/2026',
            uuid: 'folder',
            isFolder: true,
          ),
        ],
        source: CloudOperationBackend(drive, isCurrent: () => true),
        destination: LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => true,
        ),
        targetDirectory: root.path,
      );
      expect(plan.errors, isNotEmpty);
      expect(await root.list().isEmpty, isTrue);
      expect(drive.readIds, isEmpty);
    },
  );
}
