import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/panel_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account);
  final String account;
  final reads = <String>[];
  @override
  String get userId => account;
  @override
  String get rootPath => '/account';
  @override
  Future<Map<String, dynamic>> listPath(String path) {
    reads.add(path);
    return super.listPath(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  _Cloud client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';

  void replace(_Cloud next) {
    client = next;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService, LocalFileSourceIdentity {
  @override
  String currentPath = '/Photos/Projects/Deep';
  @override
  String grantedBasePath = '/Photos';
  Object token = Object();
  final extraGrants = <String, Object>{};
  bool allowNamespaceRoot = false;
  final reads = <String>[];
  final grants = <String?>[];
  Completer<bool>? accessGate;
  Completer<void>? accessStarted;
  String? nextGrant;

  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => grantedBasePath;
  @override
  Future<bool> hasAccessToPath(String path) async {
    final gate = accessGate;
    if (gate != null) {
      accessGate = null;
      accessStarted?.complete();
      return gate.future;
    }
    return (allowNamespaceRoot && path == '/') ||
        sourceIdentityForPath(path) != null;
  }

  @override
  Object? sourceIdentityForPath(String path) {
    for (final entry in extraGrants.entries) {
      if (path == entry.key || p.posix.isWithin(entry.key, path)) {
        return entry.value;
      }
    }
    return path == grantedBasePath || p.posix.isWithin(grantedBasePath, path)
        ? token
        : null;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    reads.add(path);
    currentPath = path;
    return [];
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    grants.add(initialDirectory);
    final grant = nextGrant;
    if (grant == null) return null;
    grantedBasePath = grant;
    token = Object();
    return grant;
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  late ProviderContainer container;
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('first')..put('/account/projects/deep/report.txt', [1]);
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        drivesProvider.overrideWith(
          (_) async => const [
            DriveEntry(
              path: '/External',
              label: 'External drive',
              icon: Icons.storage,
            ),
          ],
        ),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final origin = panel.resolveStorageReference(
      storageReferenceForClient(cloud),
      '/account/projects/deep',
    );
    expect(origin, isNotNull);
    await panel.navigateToPath('/account/projects/deep', origin: origin!);
  });

  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PanelHeader(
              side: PanelSide.remote,
              isActive: true,
              showSource: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder crumb(String path) =>
      find.byKey(ValueKey('panel-breadcrumb-remote-$path'));
  Finder editor() => find.byKey(const ValueKey('panel-path-editor-remote'));

  Future<void> openLocal() async {
    const source = LocalPanelSource('/Photos/Projects/Deep');
    final origin = panel.resolveStorageReference(
      storageReferenceForSource(source),
      source.currentPath,
    );
    expect(origin, isNotNull);
    await panel.navigateToPath(source.currentPath, origin: origin!);
  }

  testWidgets(
    'cloud breadcrumbs start at the configured root and keep their account',
    (tester) async {
      await mount(tester);
      expect(crumb('/'), findsNothing);
      expect(crumb('/account'), findsOneWidget);
      expect(find.byTooltip('/account/projects'), findsOneWidget);
      cloud.reads.clear();
      await tester.tap(crumb('/account'));
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/account');
      expect(cloud.reads, ['/account']);
      expect(
        (panel.captureCurrentOrigin().source as RemotePanelSource).client,
        same(cloud),
      );
      expect(container.read(activePanelProvider), PanelSide.remote);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a right-pane local grant has no synthetic root or cloud navigation',
    (tester) async {
      await openLocal();
      await mount(tester);
      expect(crumb('/'), findsNothing);
      expect(crumb('/Photos'), findsOneWidget);
      local.reads.clear();
      cloud.reads.clear();
      await tester.tap(crumb('/Photos'));
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/Photos');
      expect(local.reads, ['/Photos']);
      expect(cloud.reads, isEmpty);
      expect(local.grants, isEmpty);
      expect(panel.captureCurrentOrigin().source.isLocal, isTrue);
    },
  );

  testWidgets(
    'a retained breadcrumb callback cannot navigate a replacement account',
    (tester) async {
      await mount(tester);
      final onTap = tester.widget<InkWell>(crumb('/account')).onTap!;
      final replacement = _Cloud('second')..put('/account/other/file.txt', [2]);
      auth.replace(replacement);
      final origin = panel.resolveStorageReference(
        storageReferenceForClient(replacement),
        '/account/other',
      );
      expect(origin, isNotNull);
      await panel.navigateToPath('/account/other', origin: origin!);
      replacement.reads.clear();
      cloud.reads.clear();
      onTap();
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/account/other');
      expect(replacement.reads, isEmpty);
      expect(cloud.reads, isEmpty);
    },
  );

  testWidgets('a path editor cancels when its owning tab changes', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Edit path'));
    await tester.pump();
    final submitted = tester.widget<TextField>(editor()).onSubmitted!;
    await panel.openSavedLocation({
      'path': '/account/other',
      'storage': storageReferenceForClient(cloud).toJson(),
    }, newTab: true);
    cloud.reads.clear();
    submitted('/account/projects');
    await tester.pumpAndSettle();
    expect(editor(), findsNothing);
    expect(panel.currentPath, '/account/other');
    expect(cloud.reads, isEmpty);
  });

  testWidgets('Escape cancels path editing without navigating', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Edit path'));
    await tester.pump();
    await tester.enterText(editor(), '/account/changed');
    cloud.reads.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor(), findsNothing);
    expect(panel.currentPath, '/account/projects/deep');
    expect(cloud.reads, isEmpty);
  });

  testWidgets(
    'typed cloud paths stay in the captured root and accept relative locations',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      await tester.enterText(editor(), '../../../../outside');
      cloud.reads.clear();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(editor(), findsOneWidget);
      expect(find.text('Choose a path within /account.'), findsOneWidget);
      expect(cloud.reads, isEmpty);
      await tester.enterText(editor(), '../sibling');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor(), findsNothing);
      expect(panel.currentPath, '/account/projects/sibling');
      expect(cloud.reads, ['/account/projects/sibling']);
    },
  );

  testWidgets(
    'same-name grant replacement invalidates mounted breadcrumb and editor callbacks',
    (tester) async {
      await openLocal();
      await mount(tester);
      final onTap = tester.widget<InkWell>(crumb('/Photos')).onTap!;
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      final submitted = tester.widget<TextField>(editor()).onSubmitted!;
      local.token = Object();
      local.reads.clear();
      onTap();
      submitted('/Photos/Projects');
      await tester.pumpAndSettle();
      expect(local.reads, isEmpty);
      expect(local.grants, isEmpty);
      expect(panel.currentPath, '/Photos/Projects/Deep');
    },
  );

  testWidgets(
    'path editing can recover an older location outside its configured cloud root',
    (tester) async {
      await panel.navigateToPath(
        '/older/location',
        origin: panel.captureCurrentOrigin(),
      );
      await mount(tester);
      expect(crumb('/'), findsNothing);
      expect(crumb('/older'), findsNothing);
      expect(crumb('/older/location'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      await tester.enterText(editor(), '/account');
      cloud.reads.clear();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/account');
      expect(cloud.reads, ['/account']);
    },
  );

  testWidgets(
    'grant replacement during access checking cannot publish a new local listing',
    (tester) async {
      await openLocal();
      await mount(tester);
      final onTap = tester.widget<InkWell>(crumb('/Photos')).onTap!;
      local.reads.clear();
      await tester.runAsync(() async {
        final gate = Completer<bool>();
        local.accessGate = gate;
        local.accessStarted = Completer<void>();
        final navigation = (onTap as dynamic)() as Future<void>;
        await local.accessStarted!.future;
        local.token = Object();
        gate.complete(true);
        await navigation;
      });
      await tester.pumpAndSettle();
      expect(local.reads, isEmpty);
      expect(local.grants, isEmpty);
      expect(panel.currentPath, '/Photos/Projects/Deep');
    },
  );

  testWidgets(
    'namespace path entry cannot adopt a replaced target grant during access checking',
    (tester) async {
      local.allowNamespaceRoot = true;
      final origin = panel.resolveStorageReference(
        storageReferenceForSource(const LocalPanelSource('/')),
        '/',
      );
      expect(origin, isNotNull);
      await panel.navigateToPath('/', origin: origin!);
      await mount(tester);
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      final submitted = tester.widget<TextField>(editor()).onSubmitted!;
      local.reads.clear();
      await tester.runAsync(() async {
        final gate = Completer<bool>();
        local.accessGate = gate;
        local.accessStarted = Completer<void>();
        final navigation =
            (submitted as dynamic)('/Photos/Projects') as Future<void>;
        await local.accessStarted!.future;
        local.token = Object();
        gate.complete(true);
        await navigation;
      });
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/');
      expect(local.reads, isEmpty);
      expect(local.grants, isEmpty);
    },
  );

  testWidgets('relative local path entry resolves inside its original grant', (
    tester,
  ) async {
    await openLocal();
    await mount(tester);
    await tester.tap(find.byTooltip('Edit path'));
    await tester.pump();
    await tester.enterText(editor(), '../Sibling');
    local.reads.clear();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/Photos/Projects/Sibling');
    expect(local.reads, ['/Photos/Projects/Sibling']);
    expect(local.grants, isEmpty);
  });

  testWidgets('an explicit local path can acquire its requested new grant', (
    tester,
  ) async {
    await openLocal();
    await mount(tester);
    local.nextGrant = '/External';
    await tester.tap(find.byTooltip('Edit path'));
    await tester.pump();
    await tester.enterText(editor(), '/External/Reports');
    local.reads.clear();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(local.grants, ['/External']);
    expect(local.reads, ['/External/Reports']);
    expect(panel.currentPath, '/External/Reports');
    expect(crumb('/External'), findsOneWidget);
    expect(crumb('/'), findsNothing);
  });

  testWidgets(
    'an explicit existing grant remains independent of the previous root',
    (tester) async {
      await openLocal();
      local.extraGrants['/External'] = Object();
      await mount(tester);
      await tester.tap(find.byTooltip('Edit path'));
      await tester.pump();
      await tester.enterText(editor(), '/External/Reports');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/External/Reports');
      expect(local.grants, isEmpty);
      final listedOrigin = panel.captureCurrentOrigin();
      local.token = Object();
      expect(listedOrigin.isCurrent, isTrue);
      local.reads.clear();
      await tester.tap(crumb('/External'));
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/External');
      expect(local.reads, ['/External']);
      expect(local.grants, isEmpty);
      expect(panel.captureCurrentOrigin().isCurrent, isTrue);
    },
  );

  testWidgets('an open volume menu cannot redirect a different local tab', (
    tester,
  ) async {
    await openLocal();
    await mount(tester);
    await tester.tap(find.byTooltip('Volumes'));
    await tester.pumpAndSettle();
    await panel.openSavedLocation({
      'path': '/Photos/Other',
      'storage': panel.captureCurrentOrigin().storageReference.toJson(),
    }, newTab: true);
    await tester.pump();
    local.reads.clear();
    local.nextGrant = '/External';
    await tester.tap(find.text('External drive'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/Photos/Other');
    expect(local.reads, isEmpty);
    expect(local.grants, isEmpty);
  });
}
