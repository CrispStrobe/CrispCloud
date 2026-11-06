import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/permissions_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:crisp_cloud/widgets/permissions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _FailingSftp extends SFTPClientAdapter {
  _FailingSftp() : super(config: null);
  @override
  bool get isAuthenticated => true;
  @override
  String get userId => 'permissions-fixture';
  @override
  String get bucketId => 'server';
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      {'name': 'a.txt', 'path': '/a.txt', 'size': 1},
    ],
  };
  @override
  Future<SftpFileAttrs> getAttributes(String path) async =>
      throw SftpOperationException(
        SftpOperationCode.chmodFailed,
        'chmod failed: denied',
        {'output': 'denied'},
      );
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final CloudStorageClient client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => 'permissions@example.test';
  @override
  CloudProvider get currentProvider =>
      client is SFTPClientAdapter ? CloudProvider.sftp : CloudProvider.filen;
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
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

Future<ProviderContainer> _container(CloudStorageClient client) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((_) => _Auth(client)),
      localFileServiceProvider.overrideWithValue(_Local()),
    ],
  );
  await container.read(panelProvider(PanelSide.remote)).refresh();
  return container;
}

void main() {
  test('permissions translations preserve keys and placeholders', () {
    final translations = PermissionsStrings.translations;
    expect(translations.keys.toSet(), {
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    expect(
      PermissionsStrings.forLanguage('de').format('Permissions — {name}', {
        'name': '{error}.txt',
        'error': 'not a replacement',
      }),
      'Berechtigungen — {error}.txt',
    );
  });

  testWidgets('permissions error translates a typed SFTP cause', (
    tester,
  ) async {
    final container = await _container(_FailingSftp());
    addTearDown(container.dispose);
    final file = container.read(panelProvider(PanelSide.remote)).files!.single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) => TextButton(
                onPressed: () => showPermissionsDialog(context, ref, file),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('chmod fehlgeschlagen: denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('unsupported-provider error is shown in the selected language', (
    tester,
  ) async {
    final client = WorkflowFakeClient()..put('/a.txt', [1]);
    final container = await _container(client);
    addTearDown(container.dispose);
    final file = container.read(panelProvider(PanelSide.remote)).files!.single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                return TextButton(
                  onPressed: () => showPermissionsDialog(context, ref, file),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Berechtigungen — a.txt'), findsOneWidget);
    expect(
      find.text('Berechtigungen sind nur für SFTP-Verbindungen verfügbar'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
