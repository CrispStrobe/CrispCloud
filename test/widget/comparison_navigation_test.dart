import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/diff_viewer_dialog.dart';

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

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WorkflowFakeClient cloud;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    if (narrow) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => showDiffViewerDialog(
                  context,
                  ref,
                  panel.files!.firstWhere((file) => file.name == 'left.txt'),
                  panel.files!.firstWhere((file) => file.name == 'right.txt'),
                  leftSide: PanelSide.remote,
                  rightSide: PanelSide.remote,
                ),
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
    'right encoding selection controls verified merge bytes and follows file swapping',
    (tester) async {
      cloud.put('/left.txt', utf8.encode('left\n'));
      const right = EditorDocument(
        text: 'right\n',
        encoding: EditorEncoding.utf16le,
        lineEnding: EditorLineEnding.crlf,
        writeBom: false,
      );
      cloud.put('/right.txt', right.encode());
      await open(tester);
      final picker = find.byKey(const ValueKey('diff-right-auto'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTF-16 LE').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use left block'));
      await tester.tap(find.text('Use left block'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved merge'), findsOneWidget);
      await tester.ensureVisible(find.text('Save merge to right'));
      await tester.tap(find.text('Save merge to right'));
      await tester.pumpAndSettle();
      expect(cloud.files['/right.txt'], right.encode('left\n'));
      expect(find.text('Unsaved merge'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Swap files and merge target'));
      await tester.tap(find.byTooltip('Swap files and merge target'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diff-left-utf16le')), findsOneWidget);
      expect(find.byKey(const ValueKey('diff-right-auto')), findsOneWidget);
      expect(find.text('No differences'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final narrow in [false, true]) {
    testWidgets(
      'binary ranges and hex jumps work${narrow ? " with large narrow text" : ""}',
      (tester) async {
        cloud.put('/left.txt', [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        cloud.put('/right.txt', [1, 99, 3, 4, 77, 66, 7, 8, 9, 0]);
        await open(tester, narrow: narrow);
        final binary = find.widgetWithText(FilterChip, 'Binary');
        await tester.ensureVisible(binary);
        await tester.tap(binary);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        expect(find.text('4 differing bytes in 3 ranges'), findsOneWidget);
        expect(find.text('Difference 1 / 3: bytes 1–1'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Next difference'));
        await tester.tap(find.byTooltip('Next difference'));
        await tester.pumpAndSettle();
        expect(find.text('Difference 2 / 3: bytes 4–5'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Last difference'));
        await tester.tap(find.byTooltip('Last difference'));
        await tester.pumpAndSettle();
        expect(find.text('Difference 3 / 3: bytes 9–9'), findsOneWidget);
        final address = find.byType(TextField);
        await tester.ensureVisible(address);
        await tester.enterText(address, '0x7');
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('binary-row-7')), findsOneWidget);
        expect(find.text('Bytes 7–10 of 10'), findsOneWidget);
        expect(cloud.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
