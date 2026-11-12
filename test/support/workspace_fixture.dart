import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'workflow_fake_client.dart';

class WorkspaceTestAuth extends ChangeNotifier implements AuthNotifier {
  WorkspaceTestAuth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => 'workspace@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class WorkspaceTestHarness {
  WorkspaceTestHarness._(this.container, this.cloud);
  final ProviderContainer container;
  final WorkflowFakeClient cloud;
  static Future<WorkspaceTestHarness> create({
    List<Override> extraOverrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = WorkflowFakeClient()..put('/one/file.txt', [1, 2, 3]);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        ...extraOverrides,
      ],
    );
    for (final side in PanelSide.values) {
      await container.read(panelProvider(side)).refresh();
    }
    return WorkspaceTestHarness._(container, cloud);
  }

  void dispose() => container.dispose();
}
