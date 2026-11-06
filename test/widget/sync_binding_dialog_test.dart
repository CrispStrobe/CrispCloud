import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/sync_dialog.dart';

import '../support/sync_test_binding.dart';
import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  String account = 'reviewed-account';
  @override
  String? get userId => account;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late SyncDatabase database;
  late ProviderContainer container;
  late _Cloud cloud;
  late int pairId;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-bind-ui-');
    database = SyncDatabase.forTesting(NativeDatabase.memory());
    cloud = _Cloud();
    pairId = await database.insertPair(
      SyncPairsCompanion.insert(
        name: 'Legacy pair',
        localPath: directory.path,
        remotePath: '/documents',
        provider: 'sftp',
      ),
    );
    await bindTestPair(database, await database.getPair(pairId), cloud);
    await (database.update(database.syncPairs)
          ..where((t) => t.id.equals(pairId)))
        .write(const SyncPairsCompanion(sourceBinding: Value(null)));
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        syncProvider.overrideWith(
          (ref) => SyncNotifier.forTesting(ref, database),
        ),
        transferJournalProvider.overrideWithValue(
          TransferJournal(MemoryTransferJournalStorage()),
        ),
      ],
    );
    await container.read(syncProvider).togglePair(pairId, true);
  });
  tearDown(() async {
    container.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSyncDialog(context),
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
    'legacy pair requires a concrete source review before comparison',
    (tester) async {
      await open(tester);
      final compare = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Compare and Review',
      );
      expect(tester.widget<IconButton>(compare).onPressed, isNull);
      await tester.tap(find.text('Bind to connected account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reviewed-account'), findsOneWidget);
      expect(find.textContaining('/documents'), findsWidgets);
      await tester.tap(find.text('Bind sources'));
      await tester.pumpAndSettle();
      expect((await database.getPair(pairId)).sourceBinding, isNotNull);
      expect(tester.widget<IconButton>(compare).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account changes during source review cannot rebind the pair', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Bind to connected account'));
    await tester.pumpAndSettle();
    cloud.account = 'unreviewed-account';
    await tester.tap(find.text('Bind sources'));
    await tester.pumpAndSettle();
    expect((await database.getPair(pairId)).sourceBinding, isNull);
    expect(find.textContaining('changed during review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
