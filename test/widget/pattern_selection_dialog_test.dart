import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/selection_pattern_history.dart';
import 'package:crisp_cloud/widgets/pattern_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  String get providerName => 'Selection test';
  @override
  String get rootPath => '/';
  @override
  String? get userId => 'selection-account';
  @override
  String? get bucketId => 'selection-bucket';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': <Map<String, dynamic>>[],
  };
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => 'selection@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late PanelNotifier panel;
  late PanelFileOrigin origin;

  List<FileItem> resultRows() => [
    for (final path in [
      '/one/report-01.PDF',
      '/two/report-01.PDF',
      '/two/report-02.pdf',
      '/two/photo.jpg',
    ])
      FileItem(name: path.split('/').last, path: path, isFolder: false),
    FileItem(name: 'report-03.PDF', path: '/two/report-03.PDF', isFolder: true),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(_Cloud())),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    origin = panel.captureRemoteSearchOrigin();
    panel.showSearchResults(resultRows(), origin: origin);
  });

  tearDown(() => container.dispose());

  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(900, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Wrap(
                children: [
                  for (final action in [
                    SelectionAction.select,
                    SelectionAction.deselect,
                  ])
                    TextButton(
                      key: ValueKey('open-${action.name}'),
                      onPressed: () => showPatternSelectionDialog(
                        context,
                        ref,
                        PanelSide.remote,
                        initialAction: action,
                      ),
                      child: Text(action.name),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, SelectionAction action) async {
    await tester.tap(find.byKey(ValueKey('open-${action.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> disposeHost(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('history recalls matching options without changing deselect intent', (
    tester,
  ) async {
    const expression = r'^/two/report-\d+\.PDF$';
    await host(tester);
    await open(tester, SelectionAction.select);
    await tester.tap(find.text('Regular expression'));
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      expression,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files only').last);
    await tester.pumpAndSettle();
    for (final label in ['Case sensitive', 'Match full original paths']) {
      final checkbox = find.widgetWithText(CheckboxListTile, label);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('apply-pattern-selection')));
    await tester.pumpAndSettle();
    expect(panel.selection.single.path, '/two/report-01.PDF');
    expect((await SelectionPatternHistory().load()).single.expression, expression);

    panel.selectAll();
    await open(tester, SelectionAction.deselect);
    await tester.tap(find.byKey(const ValueKey('selection-pattern-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regex: $expression'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('selection-pattern')))
          .controller!.text,
      expression,
    );
    expect(
      tester.widget<SegmentedButton<FilePatternMode>>(
        find.byType(SegmentedButton<FilePatternMode>),
      ).selected,
      {FilePatternMode.regex},
    );
    for (final label in ['Case sensitive', 'Match full original paths']) {
      expect(
        tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, label),
        ).value,
        isTrue,
      );
    }
    expect(find.byKey(const ValueKey('selection-kind-files')), findsOneWidget);
    expect(
      tester.widget<DropdownButtonFormField<SelectionAction>>(
        find.byType(DropdownButtonFormField<SelectionAction>),
      ).initialValue,
      SelectionAction.deselect,
    );
    await tester.tap(find.byKey(const ValueKey('apply-pattern-selection')));
    await tester.pumpAndSettle();
    expect(panel.selection.map((file) => file.path).toSet(), {
      '/one/report-01.PDF',
      '/two/report-02.pdf',
      '/two/photo.jpg',
      '/two/report-03.PDF',
    });
    expect(tester.takeException(), isNull);
    await disposeHost(tester);
  });

  testWidgets('remember and restore resolve original paths after list replacement', (
    tester,
  ) async {
    panel.applyPatternSelection(
      FileSelectionPattern('/one/*', matchFullPath: true),
    );
    final original = panel.selection.single;
    await host(tester);
    await open(tester, SelectionAction.select);
    final remember = find.byKey(const ValueKey('remember-panel-selection'));
    await tester.ensureVisible(remember);
    await tester.tap(remember);
    await tester.pumpAndSettle();
    expect(find.text('Remembered 1 selected item(s) for this tab.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    panel.showSearchResults(resultRows(), origin: origin);
    expect(panel.selection, isEmpty);
    await open(tester, SelectionAction.select);
    final restore = find.byKey(const ValueKey('restore-panel-selection'));
    await tester.ensureVisible(restore);
    expect(tester.widget<TextButton>(restore).onPressed, isNotNull);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(panel.selection.single.path, '/one/report-01.PDF');
    expect(identical(original, panel.selection.single), isFalse);
    expect(panel.captureOperationOrigin(panel.selection.toList()).isCurrent, isTrue);

    panel.setFilter('photo');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(restore).onPressed, isNull);
    expect(panel.selection.single.path, '/one/report-01.PDF');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeHost(tester);
  });

  testWidgets('invalid regex on a narrow window changes neither marks nor history', (
    tester,
  ) async {
    panel.selectAll();
    final originalPaths = panel.selection.map((item) => item.path).toSet();
    await host(tester, size: const Size(390, 700));
    await open(tester, SelectionAction.select);
    await tester.tap(find.text('Regular expression'));
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      '[',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(
        find.byKey(const ValueKey('apply-pattern-selection')),
      ).onPressed,
      isNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(panel.selection.map((item) => item.path).toSet(), originalPaths);
    expect(await SelectionPatternHistory().load(), isEmpty);
    expect(find.text('Select by pattern'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await disposeHost(tester);
  });
}
