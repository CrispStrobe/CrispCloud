import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/external_comparison_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_comparison_fixture.dart';
import '../support/external_drop_fixture.dart';

class _GrantedLocal extends DropTestLocal implements LocalFileSourceIdentity {
  _GrantedLocal(this.root) : super(root);
  final String root;
  Object token = Object();
  @override
  String get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) =>
      p.equals(root, path) || p.isWithin(root, path) ? token : null;
}

void main() {
  late Directory temporary;
  late _GrantedLocal local;
  late DropTestCloud primary, secondary;
  late ProviderContainer container;
  late PanelNotifier left, right;
  late WidgetRef widgetRef;
  ExternalComparisonPair? captured;

  FileItem row(PanelNotifier panel, [String name = 'same.txt']) =>
      panel.files!.firstWhere((file) => file.name == name);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp(
      'external-compare-capture-',
    );
    await File(p.join(temporary.path, 'same.txt'))
        .writeAsString('local original');
    local = _GrantedLocal(temporary.path);
    primary = DropTestCloud('primary')
      ..put('/same.txt', utf8.encode('primary original'))
      ..put('/other.txt', utf8.encode('other original'));
    secondary = DropTestCloud('secondary')
      ..put('/same.txt', utf8.encode('secondary original'));
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => DropTestAuth(primary)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'secondary',
          label: 'Same label',
          provider: CloudProvider.webdav,
          client: secondary,
        );
    left = container.read(panelProvider(PanelSide.local));
    right = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    await left.navigateToPath(
      '/',
      origin: left.resolveStorageReference(
        storageReferenceForClient(secondary),
        '/',
      ),
    );
    await right.navigateToPath(
      '/',
      origin: right.resolveStorageReference(
        storageReferenceForClient(primary),
        '/',
      ),
    );
    left.toggleSelection(row(left));
    right.toggleSelection(row(right));
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
  });
  tearDown(() async {
    captured?.dispose();
    captured = null;
    container.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same-path files in two accounts use their actual verified sources',
    (tester) async {
      await mount(tester);
      captured = captureExternalComparisonSelection(widgetRef);
      expect(captured!.left.file.path, '/same.txt');
      expect(captured!.right.file.path, '/same.txt');
      expect(captured!.left.storage, storageReferenceForClient(secondary));
      expect(captured!.right.storage, storageReferenceForClient(primary));
      expect(captured!.left.storage, isNot(captured!.right.storage));
      final host = ComparisonHost(), stages = ComparisonMemoryStages();
      final service = ExternalComparisonService(host: host, staging: stages);
      final prepared = await tester.runAsync(() async {
        await service.ready;
        return service.prepare(
          comparisonConfiguration(),
          captured!,
          control: FileOperationControl(),
          isCurrent: () => true,
        );
      });
      expect(
        utf8.decode(stages.entries[prepared!.session.id]!.files['left.txt']!),
        'secondary original',
      );
      expect(
        utf8.decode(stages.entries[prepared.session.id]!.files['right.txt']!),
        'primary original',
      );
      expect(host.launches, isEmpty);
      service.dispose();
    },
  );

  testWidgets('two selected files stay in the active actual source', (
    tester,
  ) async {
    await mount(tester);
    right.toggleSelection(row(right, 'other.txt'), ctrlKey: true);
    expect(right.selection, hasLength(2));
    captured = captureExternalComparisonSelection(widgetRef);
    expect(
      {captured!.left.file.path, captured!.right.file.path},
      {'/same.txt', '/other.txt'},
    );
    expect(captured!.left.storage, storageReferenceForClient(primary));
    expect(captured!.right.storage, storageReferenceForClient(primary));
    expect(captured!.isCurrent, isTrue);
  });

  testWidgets('later selection changes never replace a menu-captured pair', (
    tester,
  ) async {
    await mount(tester);
    captured = captureExternalComparisonPair(
      widgetRef,
      leftSide: PanelSide.local,
      leftFile: row(left),
      rightSide: PanelSide.remote,
      rightFile: row(right),
    );
    right.clearSelection();
    right.toggleSelection(row(right, 'other.txt'));
    expect(captured!.right.file.path, '/same.txt');
    expect(captured!.right.storage, storageReferenceForClient(primary));
    expect(captured!.isCurrent, isTrue);
  });

  testWidgets('navigation away and back cannot revive a captured pair', (
    tester,
  ) async {
    await mount(tester);
    captured = captureExternalComparisonSelection(widgetRef);
    final path = captured!.right.file.path;
    await tester.runAsync(
      () => right.navigateToPath(
        temporary.path,
        origin: right.captureLocalClipboardOrigin(temporary.path),
      ),
    );
    await tester.runAsync(
      () => right.navigateToPath(
        '/',
        origin: right.resolveStorageReference(
          storageReferenceForClient(primary),
          '/',
        ),
      ),
    );
    expect(captured!.isCurrent, isFalse);
    expect(captured!.right.file.path, path);
    expect(captured!.right.storage, storageReferenceForClient(primary));
  });

  testWidgets(
    'account identity change remains invalid even if that identity is restored',
    (tester) async {
      await mount(tester);
      captured = captureExternalComparisonSelection(widgetRef);
      final expected = captured!.left.storage;
      secondary.account = 'replacement';
      expect(captured!.isCurrent, isFalse);
      secondary.account = 'secondary';
      expect(captured!.isCurrent, isFalse);
      expect(captured!.left.storage, expected);
    },
  );

  testWidgets(
    'a local file in the remote visual pane keeps its original access grant',
    (tester) async {
      await tester.runAsync(
        () => right.navigateToPath(
          temporary.path,
          origin: right.captureLocalClipboardOrigin(temporary.path),
        ),
      );
      right.clearSelection();
      right.toggleSelection(row(right));
      await mount(tester);
      captured = captureExternalComparisonSelection(widgetRef);
      expect(captured!.right.storage.isLocal, isTrue);
      expect(captured!.right.file.path, p.join(temporary.path, 'same.txt'));
      expect(captured!.left.storage.isLocal, isFalse);
      expect(captured!.isCurrent, isTrue);
      final original = local.token;
      local.token = Object();
      expect(captured!.isCurrent, isFalse);
      local.token = original;
      expect(captured!.isCurrent, isFalse);
    },
  );

  testWidgets(
    'unverified lookalike rows cannot acquire a source and disposal invalidates a pair',
    (tester) async {
      await mount(tester);
      expect(
        () => captureExternalComparisonPair(
          widgetRef,
          leftSide: PanelSide.local,
          leftFile: row(left).copyWith(),
          rightSide: PanelSide.remote,
          rightFile: row(right),
        ),
        throwsStateError,
      );
      captured = captureExternalComparisonSelection(widgetRef);
      captured!.dispose();
      captured!.dispose();
      expect(captured!.isCurrent, isFalse);
    },
  );
}
