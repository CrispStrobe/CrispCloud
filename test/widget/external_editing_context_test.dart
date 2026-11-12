import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/external_remote_editing_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/external_editing_actions.dart';
import 'package:crisp_cloud/widgets/external_editing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_drop_fixture.dart';
import '../support/external_edit_fakes.dart';

class _BoundedCloud extends DropTestCloud with CloudTransferOperations {
  _BoundedCloud(super.account);
  bool bounded = true;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      StorageTransferCapabilities(boundedDownload: bounded);
}

void main() {
  late Directory directory;
  late _BoundedCloud primary, secondary;
  late DropTestAuth auth;
  late ProviderContainer container;
  late PanelNotifier left, right;
  late WidgetRef widgetRef;

  FileItem row(PanelNotifier panel, [String name = 'same.txt']) =>
      panel.files!.firstWhere((file) => file.name == name);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('external-edit-capture-');
    await File(p.join(directory.path, 'same.txt')).writeAsString('local');
    primary = _BoundedCloud('primary')
      ..put('/same.txt', utf8.encode('primary'))
      ..put('/other.txt', utf8.encode('other'));
    secondary = _BoundedCloud('secondary')
      ..put('/same.txt', utf8.encode('secondary'));
    auth = DropTestAuth(primary);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(
          DropTestLocal(directory.path),
        ),
        externalRemoteEditingServiceProvider.overrideWith(
          (_) => ExternalRemoteEditingService(staging: FakeEditStagingStore()),
        ),
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
    right.toggleSelection(row(right));
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
  });

  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
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
    'same-path rows keep their actual account in either visual pane',
    (tester) async {
      await mount(tester);
      final a = captureExternalEditingSource(
        widgetRef,
        PanelSide.local,
        row(left),
      );
      final b = captureExternalEditingSelection(widgetRef);
      expect(a.client, same(secondary));
      expect(b.client, same(primary));
      expect(a.reference.path, b.reference.path);
      expect(a.reference.storage, storageReferenceForClient(secondary));
      expect(b.reference.storage, storageReferenceForClient(primary));
      expect(a.reference.storage, isNot(b.reference.storage));
    },
  );

  testWidgets('selection changes do not substitute the captured remote row', (
    tester,
  ) async {
    await mount(tester);
    final source = captureExternalEditingSelection(widgetRef);
    right.clearSelection();
    right.toggleSelection(row(right, 'other.txt'));
    source.check(review: true);
    expect(source.reference.path, '/same.txt');
    expect(primary.writes, isEmpty);
  });

  testWidgets(
    'navigation expires launch review while preserving original account availability',
    (tester) async {
      await mount(tester);
      final source = captureExternalEditingSelection(widgetRef);
      await tester.runAsync(
        () => right.navigateToPath(
          directory.path,
          origin: right.captureLocalClipboardOrigin(directory.path),
        ),
      );
      expect(source.isReviewCurrent(), isFalse);
      expect(source.isCurrent(), isTrue);
      source.check();
      expect(
        () => source.check(review: true),
        throwsA(isA<ExternalEditException>()),
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
      expect(source.isReviewCurrent(), isFalse);
      expect(source.isCurrent(), isTrue);
    },
  );

  testWidgets(
    'disconnect and reconnect never revive original publication authority',
    (tester) async {
      await mount(tester);
      final source = captureExternalEditingSelection(widgetRef);
      auth.connection(false);
      auth.connection(true);
      expect(source.isCurrent(), isFalse);
      expect(() => source.check(), throwsA(isA<ExternalEditException>()));
    },
  );

  testWidgets(
    'observed account replacement stays invalid when its name returns',
    (tester) async {
      await mount(tester);
      final source = captureExternalEditingSource(
        widgetRef,
        PanelSide.local,
        row(left),
      );
      secondary.account = 'replacement';
      expect(source.isCurrent(), isFalse);
      secondary.account = 'secondary';
      expect(source.isCurrent(), isFalse);
    },
  );

  testWidgets('expired popup review never cancels a launched session account', (
    tester,
  ) async {
    await mount(tester);
    var reviewOpen = true;
    final source = captureExternalEditingSource(
      widgetRef,
      PanelSide.remote,
      row(right),
      isReviewCurrent: () => reviewOpen,
    );
    reviewOpen = false;
    expect(source.isReviewCurrent(), isFalse);
    expect(source.isCurrent(), isTrue);
    reviewOpen = true;
    expect(source.isReviewCurrent(), isFalse);
  });

  testWidgets(
    'local rows, unverified copies and multiple rows cannot acquire a remote source',
    (tester) async {
      await mount(tester);
      expect(
        () => captureExternalEditingSource(
          widgetRef,
          PanelSide.remote,
          row(right).copyWith(),
        ),
        throwsStateError,
      );
      right.toggleSelection(row(right, 'other.txt'), ctrlKey: true);
      expect(
        () => captureExternalEditingSelection(widgetRef),
        throwsA(isA<ExternalEditException>()),
      );
      await tester.runAsync(
        () => right.navigateToPath(
          directory.path,
          origin: right.captureLocalClipboardOrigin(directory.path),
        ),
      );
      expect(
        () => captureExternalEditingSource(
          widgetRef,
          PanelSide.remote,
          row(right),
        ),
        throwsA(isA<ExternalEditException>()),
      );
    },
  );

  testWidgets(
    'popup handoff pins its row and closing the dialog expires only the review',
    (tester) async {
      await mount(tester);
      final action = ExternalEditingMenuAction.capture(
        widgetRef.context,
        widgetRef,
        PanelSide.remote,
        [row(right)],
      )!;
      unawaited(
        showMenu<void>(
          context: widgetRef.context,
          position: const RelativeRect.fromLTRB(20, 20, 0, 0),
          items: [action.buildItem()],
        ).whenComplete(action.menuClosed),
      );
      await tester.pumpAndSettle();
      right.clearSelection();
      right.toggleSelection(row(right, 'other.txt'));
      await tester.tap(find.text('Edit with external editor'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<ExternalEditingDialog>(
        find.byType(ExternalEditingDialog),
      );
      final source = dialog.source!;
      expect(source.reference.path, '/same.txt');
      source.check(review: true);
      expect(dialog.service.sessions, isEmpty);
      await tester.tap(find.byKey(const ValueKey('external-editing-close')));
      await tester.pumpAndSettle();
      expect(source.isReviewCurrent(), isFalse);
      expect(source.isCurrent(), isTrue);
      source.check();
      expect(primary.writes, isEmpty);
    },
  );

  testWidgets(
    'account replacement while popup is open reaches no staging or publication',
    (tester) async {
      await mount(tester);
      final action = ExternalEditingMenuAction.capture(
        widgetRef.context,
        widgetRef,
        PanelSide.remote,
        [row(right)],
      )!;
      unawaited(
        showMenu<void>(
          context: widgetRef.context,
          position: const RelativeRect.fromLTRB(20, 20, 0, 0),
          items: [action.buildItem()],
        ).whenComplete(action.menuClosed),
      );
      await tester.pumpAndSettle();
      auth.connection(false);
      auth.connection(true);
      await tester.tap(find.text('Edit with external editor'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<ExternalEditingDialog>(
        find.byType(ExternalEditingDialog),
      );
      expect(
        () => dialog.source!.check(review: true),
        throwsA(isA<ExternalEditException>()),
      );
      expect(dialog.service.sessions, isEmpty);
      expect((dialog.service.staging as FakeEditStagingStore).bundles, isEmpty);
      expect(primary.writes, isEmpty);
      await tester.tap(find.byKey(const ValueKey('external-editing-close')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'providers without bounded staging are unavailable before a dialog opens',
    (tester) async {
      await mount(tester);
      primary.bounded = false;
      expect(
        () => captureExternalEditingSelection(widgetRef),
        throwsA(isA<ExternalEditException>()),
      );
      expect(
        ExternalEditingMenuAction.capture(
          widgetRef.context,
          widgetRef,
          PanelSide.remote,
          [row(right)],
        ),
        isNull,
      );
      expect(primary.writes, isEmpty);
    },
  );
}
