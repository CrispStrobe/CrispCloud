// test/widget/viewer_edit_action_test.dart
//
// The F3 viewer offers an Edit handoff only when F4 can save the file, and
// returns InternalViewerAction.edit to the host.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';

class _TextFileService implements LocalFileService {
  _TextFileService(this.bytes);

  final Uint8List bytes;

  @override
  String currentPath = Directory.systemTemp.path;

  @override
  String? get grantedBasePath => currentPath;

  @override
  Future<bool> ensureAccess(String path) async => true;

  @override
  Future<bool> beginStreamAccess(String path) async => true;

  @override
  Future<void> endStreamAccess() async {}

  @override
  Future<int?> fileLength(String path) async => bytes.length;

  @override
  Future<String> getInitialPath() async => currentPath;

  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;

  @override
  Future<bool> hasAccessToPath(String path) async => true;

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => const [];

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async =>
      currentPath;

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async => bytes;

  @override
  Future<void> saveFile(String path, Uint8List data) async {}

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {}

  @override
  Future<void> refresh() async {}

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) async =>
      const <FileItem>[];
}

void main() {
  testWidgets('text viewer exposes Edit and returns the edit action', (
    tester,
  ) async {
    final bytes = Uint8List.fromList('one\ntwo\n'.codeUnits);
    late Future<InternalViewerAction> result;
    final file = FileItem(
      name: 'notes.txt',
      path: '/tmp/notes.txt',
      isFolder: false,
      size: bytes.length,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileServiceProvider.overrideWithValue(_TextFileService(bytes)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    result = showInternalViewer(
                      context,
                      file: file,
                      side: PanelSide.local,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit (F4)'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit (F4)'));
    await tester.pumpAndSettle();

    expect(await result, InternalViewerAction.edit);
  });

  testWidgets('view-only formats do not expose Edit', (tester) async {
    final bytes = Uint8List.fromList(<int>[0, 1, 2, 3]);
    final file = FileItem(
      name: 'blob.bin',
      path: '/tmp/blob.bin',
      isFolder: false,
      size: bytes.length,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileServiceProvider.overrideWithValue(_TextFileService(bytes)),
        ],
        child: MaterialApp(
          home: InternalViewerDialog(
            file: file,
            side: PanelSide.local,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit (F4)'), findsNothing);
  });
}
