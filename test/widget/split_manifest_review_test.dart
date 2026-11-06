import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_split_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/integrity_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Combine binds execution to the displayed manifest review', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = WorkflowFakeClient()..put('/data.bin', [1, 2, 3, 4]);
    final backend = CloudOperationBackend(
      cloud,
      isCurrent: () => cloud.current,
    );
    final result = await FileSplitService.splitToBackend(
      source: backend,
      file: (await backend.stat('/data.bin'))!,
      destination: backend,
      targetDirectory: '/',
      chunkSizeBytes: 2,
    );
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    addTearDown(container.dispose);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final manifest = panel.files!.firstWhere(
      (file) => file.path == result.manifestPath,
    );
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showCombinePartsDialog(
                  context,
                  ref,
                  PanelSide.remote,
                  [manifest],
                ),
                child: const Text('Open combine'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open combine'));
    await tester.pumpAndSettle();
    expect(find.text('data.bin.combined'), findsOneWidget);
    final reviewed = result.manifest;
    final replacement = SplitManifest(
      originalName: 'next.bin',
      totalBytes: reviewed.totalBytes,
      chunkSize: reviewed.chunkSize,
      status: reviewed.status,
      parts: reviewed.parts,
      sha256: reviewed.sha256,
    );
    cloud.put(
      result.manifestPath,
      replacement.encode(),
      date: manifest.updatedAt,
    );
    final writesBefore = cloud.writes.length;
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and combine'));
    await tester.pumpAndSettle();
    expect(find.text(SplitManifestChangedException.message), findsOneWidget);
    expect(cloud.writes.length, writesBefore);
    expect(cloud.files['/data.bin.combined'], isNull);
    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
