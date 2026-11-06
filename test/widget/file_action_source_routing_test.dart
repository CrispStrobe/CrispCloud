import 'dart:io';
import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:crisp_cloud/widgets/share_link_dialog.dart';
import 'package:crisp_cloud/widgets/permissions_dialog.dart';
import 'package:crisp_cloud/widgets/version_history_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

class _Drive extends WorkflowFakeClient implements GDriveClientAdapter {
  _Drive(this.account);
  final String account;
  @override
  String get providerName => 'Google Drive';
  @override
  String get userId => account;
  @override
  String get accessToken => account;
  @override
  bool get supportsSharing => true;
  @override
  bool get supportsVersioning => true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final result = await super.listPath(path);
    for (final file in result['files'] as List) {
      file['uuid'] = '$account-file';
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) =>
      listPath(path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Dropbox extends WorkflowFakeClient implements DropboxClientAdapter {
  @override
  String get providerName => 'Dropbox';
  @override
  String get userId => 'dropbox';
  @override
  String get accessToken => 'dropbox-account';
  @override
  bool get supportsSharing => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sftp extends WorkflowFakeClient implements SFTPClientAdapter {
  bool disconnectOnChmod = false;
  int modes = 0;
  int owners = 0;
  @override
  String get providerName => 'SFTP';
  @override
  String get userId => 'sftp';
  @override
  String get storageNamespace => 'fixture:22';
  @override
  Future<SftpFileAttrs> getAttributes(String path) async =>
      SftpFileAttrs(mode: const SftpFileMode.value(420));
  @override
  Future<Map<String, String>> getOwnership(String path) async => {
    'user': 'operator',
    'group': 'staff',
  };
  @override
  Future<void> chmod(String path, String mode) async {
    modes++;
    if (disconnectOnChmod) current = false;
  }

  @override
  Future<void> chown(String path, String owner) async {
    owners++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Drive client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'primary@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProviderContainer container;
  late _Drive primary;
  late _Drive selected;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    primary = _Drive('primary')..put('/chosen.txt', 'primary'.codeUnits);
    selected = _Drive('selected')..put('/chosen.txt', 'chosen'.codeUnits);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(primary)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'selected',
          label: 'Selected',
          provider: CloudProvider.gdrive,
          client: selected,
        );
    panel = container.read(panelProvider(PanelSide.local));
    await panel.refresh();
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(
          RemotePanelSource(
            providerName: selected.providerName,
            client: selected,
            path: '/',
          ),
        );
    await Future<void>.delayed(Duration.zero);
    await panel.refresh();
    expect(panel.files!.where((item) => !item.isFolder), hasLength(1));
  });
  tearDown(() => container.dispose());

  FileItem getFile() => panel.files!.firstWhere((item) => !item.isFolder);
  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext, WidgetRef) action, {
    String language = 'en',
    bool narrow = false,
  }) async {
    if (narrow) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
            child: child!,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => action(context, ref),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a cloud row in the left pane never exposes native path actions',
    (tester) async {
      container.read(preferExternalEditorProvider.notifier).setValue(true);
      await open(
        tester,
        (context, ref) => showFileContextMenu(
          context,
          ref,
          PanelSide.local,
          getFile(),
          const Offset(50, 30),
        ),
      );
      expect(find.text('Edit (Built-in)'), findsOneWidget);
      expect(find.text('Open with System Editor'), findsNothing);
      expect(find.text('Edit (System Editor)'), findsNothing);
      expect(find.textContaining('Secure Wipe'), findsNothing);
      expect(find.textContaining('Create Link'), findsNothing);
      expect(find.text('Version History'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system editor entry point rejects cloud paths before native access',
    (tester) async {
      await open(
        tester,
        (context, ref) =>
            openListedFileWithSystemEditor(context, ref, getFile()),
      );
      expect(find.textContaining('requires a local file'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'share request uses selected secondary account and exact file ID',
    (tester) async {
      final requests = <http.Request>[];
      final httpClient = MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      });
      await open(
        tester,
        (context, ref) => showShareLinkDialog(
          context,
          ref,
          getFile(),
          httpClient: httpClient,
        ),
      );
      await tester.tap(find.text('Generate Link'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.headers['Authorization'], 'Bearer selected');
      expect(
        requests.single.url.path,
        '/drive/v3/files/selected-file/permissions',
      );
      expect(
        find.textContaining('https://drive.google.com/file/d/selected-file/'),
        findsOneWidget,
      );
      expect(primary.writes, isEmpty);
    },
  );

  testWidgets('a rejected permission request never produces a share link', (
    tester,
  ) async {
    final httpClient = MockClient((_) async => http.Response('denied', 403));
    await open(
      tester,
      (context, ref) =>
          showShareLinkDialog(context, ref, getFile(), httpClient: httpClient),
    );
    await tester.tap(find.text('Generate Link'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Google Drive share failed (403)'),
      findsOneWidget,
    );
    expect(find.text('Copy Link'), findsNothing);
  });

  testWidgets(
    'disconnecting after opening the share dialog prevents mutation',
    (tester) async {
      var requests = 0;
      final httpClient = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      await open(
        tester,
        (context, ref) => showShareLinkDialog(
          context,
          ref,
          getFile(),
          httpClient: httpClient,
        ),
      );
      selected.current = false;
      await tester.tap(find.text('Generate Link'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.textContaining('no longer connected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unverified cloned rows cannot open provider actions', (
    tester,
  ) async {
    final cloned = getFile().copyWith();
    await open(
      tester,
      (context, ref) => showShareLinkDialog(context, ref, cloned),
    );
    expect(find.text('Generate Link'), findsNothing);
    expect(find.textContaining('Refresh or reopen this file'), findsOneWidget);
  });

  testWidgets('version history reads the captured secondary account', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('{"revisions":[]}', 200);
    });
    await open(
      tester,
      (context, ref) => showVersionHistoryDialog(
        context,
        ref,
        getFile(),
        httpClient: httpClient,
      ),
    );
    expect(requests.single.headers['Authorization'], 'Bearer selected');
    expect(requests.single.url.path, '/drive/v3/files/selected-file/revisions');
    expect(find.text('No version history available'), findsOneWidget);
  });

  testWidgets(
    'upload action reviews the actual selected source before writes',
    (tester) async {
      panel.toggleSelection(getFile());
      await open(tester, (context, ref) => uploadSelected(context, ref));
      final dialog = tester.widget<FileOperationDialog>(
        find.byType(FileOperationDialog),
      );
      expect(
        (dialog.sourceOrigin!.source as RemotePanelSource).client,
        same(selected),
      );
      expect(primary.writes, isEmpty);
      expect(selected.writes, isEmpty);
    },
  );
  Future<void> selectClient(
    WidgetTester tester,
    WorkflowFakeClient client,
  ) async {
    client.put('/chosen.txt', 'chosen'.codeUnits);
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'another',
          label: client.providerName,
          provider: CloudProvider.sftp,
          client: client,
        );
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(
          RemotePanelSource(
            providerName: client.providerName,
            client: client,
            path: '/',
          ),
        );
    await tester.pump();
    await panel.refresh();
  }

  for (final language in ['de', 'ar']) {
    String tr(String key) => CommanderStrings.forLanguage(language, key);
    testWidgets(
      'password and expiration sharing options fit large $language text',
      (tester) async {
        final client = _Dropbox();
        await selectClient(tester, client);
        final requests = <http.Request>[];
        final httpClient = MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"url":"https://www.dropbox.com/s/selected/file"}',
            200,
          );
        });
        await open(
          tester,
          (context, ref) => showShareLinkDialog(
            context,
            ref,
            getFile(),
            httpClient: httpClient,
          ),
          language: language,
          narrow: true,
        );
        final passwordToggle = find.widgetWithText(
          SwitchListTile,
          tr('Password Protection'),
        );
        await tester.ensureVisible(passwordToggle);
        await tester.tap(passwordToggle);
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        await tester.ensureVisible(field);
        await tester.enterText(field, 'secret');
        final expiry = find.widgetWithText(SwitchListTile, tr('Expiration'));
        await tester.ensureVisible(expiry);
        await tester.tap(expiry);
        await tester.pumpAndSettle();
        expect(find.text(tr('7 days')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(tr('Generate Link')));
        await tester.pumpAndSettle();
        final data = json.decode(requests.single.body) as Map;
        expect(data['settings']['link_password'], 'secret');
        expect(data['settings']['expires'], isNotEmpty);
        expect(find.text(tr('Copy Link')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'permission controls remain reachable with large $language text',
      (tester) async {
        final client = _Sftp();
        await selectClient(tester, client);
        await open(
          tester,
          (context, ref) => showPermissionsDialog(context, ref, getFile()),
          language: language,
          narrow: true,
        );
        expect(find.byType(Checkbox), findsNWidgets(9));
        final checkbox = find.byType(Checkbox).first;
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pump();
        await tester.tap(find.text(tr('Apply')));
        await tester.pumpAndSettle();
        expect(client.modes, 1);
        expect(client.owners, 1);
        expect(primary.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('version restore review fits large $language text', (
      tester,
    ) async {
      final httpClient = MockClient(
        (_) async => http.Response(
          '{"revisions":[{"id":"revision-1","modifiedTime":"2025-01-01T00:00:00Z","size":"8"},{"id":"revision-2","modifiedTime":"2025-02-01T00:00:00Z","size":"9"}]}',
          200,
        ),
      );
      await open(
        tester,
        (context, ref) => showVersionHistoryDialog(
          context,
          ref,
          getFile(),
          httpClient: httpClient,
        ),
        language: language,
        narrow: true,
      );
      final restore = find.text(tr('Restore')).first;
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.text(tr('Restore Version?')), findsOneWidget);
      expect(find.text(tr('Cancel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'permission follow-up ownership write stops after disconnection',
    (tester) async {
      final client = _Sftp()..disconnectOnChmod = true;
      await selectClient(tester, client);
      await open(
        tester,
        (context, ref) => showPermissionsDialog(context, ref, getFile()),
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(client.modes, 1);
      expect(client.owners, 0);
      expect(find.textContaining('no longer connected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
