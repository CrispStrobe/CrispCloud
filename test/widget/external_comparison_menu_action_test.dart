import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/external_comparison_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/external_comparison_dialog.dart';
import 'package:crisp_cloud/widgets/external_comparison_menu_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_comparison_fixture.dart';
import '../support/external_drop_fixture.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<void> refresh() async {}
}

void main() {
  late ProviderContainer container;
  late DropTestCloud cloud;
  late DropTestAuth auth;
  late ComparisonHost host;
  late ComparisonMemoryStages stages;
  late ExternalComparisonService service;
  late PanelNotifier panel;
  ExternalComparisonMenuAction? captured;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = DropTestCloud('original-account')
      ..put('/one.txt', [1, 2, 3])
      ..put('/two.txt', [4, 5, 6]);
    auth = DropTestAuth(cloud);
    host = ComparisonHost();
    stages = ComparisonMemoryStages();
    service = ExternalComparisonService(host: host, staging: stages);
    await service.ready;
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
        externalComparisonServiceProvider.overrideWith((_) => service),
      ],
    );
    container.read(externalComparisonServiceProvider);
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    captured = null;
  });

  tearDown(() {
    captured?.menuClosed();
    container.dispose();
  });

  List<FileItem> files() => [
    panel.files!.firstWhere((item) => item.path == '/one.txt'),
    panel.files!.firstWhere((item) => item.path == '/two.txt'),
  ];

  Future<void> mount(WidgetTester tester, {bool unverified = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () {
                  final rows = files();
                  captured = ExternalComparisonMenuAction.capture(
                    context,
                    ref,
                    PanelSide.remote,
                    unverified ? [rows.first.copyWith(), rows.last] : rows,
                  );
                  if (captured case final action?) {
                    showMenu<void>(
                      context: context,
                      position: const RelativeRect.fromLTRB(20, 20, 0, 0),
                      items: [action.buildItem()],
                    ).whenComplete(action.menuClosed);
                  }
                },
                child: const Text('Open menu'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
  }

  testWidgets('popup dismissal hands the original pair to the dialog', (
    tester,
  ) async {
    final expectedStorage = panel
        .captureOperationOrigin(files())
        .storageReference;
    await mount(tester);
    panel.clearSelection();
    await tester.tap(find.text('Compare with external tool'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<ExternalComparisonDialog>(
      find.byType(ExternalComparisonDialog),
    );
    expect(dialog.pair!.isCurrent, isTrue);
    expect(dialog.pair!.left.file.path, '/one.txt');
    expect(dialog.pair!.right.file.path, '/two.txt');
    expect(dialog.pair!.left.storage, expectedStorage);
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Close').last);
    await tester.pumpAndSettle();
    expect(dialog.pair!.isCurrent, isFalse);
  });

  testWidgets('reconnected account cannot revive a menu capture', (
    tester,
  ) async {
    await mount(tester);
    auth.connection(false);
    auth.connection(true);
    await tester.tap(find.text('Compare with external tool'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<ExternalComparisonDialog>(
      find.byType(ExternalComparisonDialog),
    );
    expect(dialog.pair!.isCurrent, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('external-comparison-executable')),
      '/apps/compare tool',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('external-comparison-prepare')),
    );
    await tester.tap(find.byKey(const ValueKey('external-comparison-prepare')));
    await tester.pumpAndSettle();
    expect(find.byType(ExternalComparisonReview), findsNothing);
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
  });

  testWidgets('unverified replacement rows never gain comparison authority', (
    tester,
  ) async {
    await mount(tester, unverified: true);
    expect(captured, isNull);
    expect(find.text('Compare with external tool'), findsNothing);
    expect(stages.entries, isEmpty);
    expect(host.launches, isEmpty);
  });
}
