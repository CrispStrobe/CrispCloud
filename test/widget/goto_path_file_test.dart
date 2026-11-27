import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  @override
  String get userId => 'account-a';
  @override
  String get rootPath => '/';
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? userEmail = 'a@example.test';
  @override
  String get providerName => client.providerName;
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

void main() {
  testWidgets(
    'Go to path reveals a file in the pane active when the dialog opened',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final cloud = _Cloud()
        ..put('/one/same.txt', <int>[1])
        ..put('/two/same.txt', <int>[2])
        ..directories.addAll(<String>{'/', '/one', '/two'});
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _Auth(cloud)),
          localFileServiceProvider.overrideWithValue(_Local()),
        ],
      );
      addTearDown(container.dispose);
      final remote = container.read(panelProvider(PanelSide.remote));
      await remote.refresh();
      container.read(activePanelProvider.notifier).state = PanelSide.remote;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showGoToDialog(context, ref),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Focus moves to the other pane while the dialog is open. The captured
      // remote pane must still receive the navigation.
      container.read(activePanelProvider.notifier).state = PanelSide.local;
      await tester.enterText(find.byType(TextField), '/two/same.txt');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(remote.currentPath, '/two');
      expect(remote.selection.single.path, '/two/same.txt');
      expect(remote.cursorItem?.path, '/two/same.txt');
      expect(
        container.read(panelProvider(PanelSide.local)).currentPath,
        isNot('/two'),
      );
    },
  );
}
