import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/batch_rename_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
  final paths = <String>{'/first.txt', '/second.txt'};
  final renames = <String>[];
  @override
  String get providerName => 'Rename test';
  @override
  String get rootPath => '/';
  @override
  String? get userId => 'rename-account';
  @override
  String? get bucketId => 'rename-bucket';
  @override
  bool get isAuthenticated => true;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      for (final file in paths)
        if (p.posix.dirname(file) == path)
          {'name': p.posix.basename(file), 'path': file, 'size': 5},
    ],
  };

  @override
  Future<void> renamePath(String path, String newName) async {
    final target = p.posix.join(p.posix.dirname(path), newName);
    if (!paths.contains(path) || paths.contains(target)) {
      throw StateError('Missing source or occupied destination');
    }
    paths.remove(path);
    paths.add(target);
    renames.add(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => 'rename@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late ProviderContainer container;
  late List<FileItem> files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    files = panel.files!.where((file) => !file.isFolder).toList();
  });

  tearDown(() => container.dispose());

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => BatchRenameDialog(
                parentRef: ref,
                side: PanelSide.remote,
                files: files,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('preview uses the real engine, with no write before applying', (
    tester,
  ) async {
    await open(tester);
    final apply = find.byKey(const ValueKey('rename-apply'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'Trip_[C]',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-preview')));
    expect(find.text('→ Trip_001.txt'), findsOneWidget);
    expect(find.text('→ Trip_002.txt'), findsOneWidget);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(cloud.renames, isEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('rename-name-mask')));
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'same',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(
      find.text('Resolve the marked preview errors before renaming.'),
      findsOneWidget,
    );
    expect(cloud.renames, isEmpty);
  });

  testWidgets(
    'applying the dialog renames on its captured source and reports success',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_new',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first_new.txt', '/second_new.txt'});
      expect(cloud.renames, ['/first.txt', '/second.txt']);
      expect(
        find.text('2 renamed, 0 failed, 0 unchanged, 0 not run.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('rename-apply')), findsNothing);
    },
  );

  testWidgets('occupied destinations leave the entire batch untouched', (
    tester,
  ) async {
    cloud.paths.add('/second_new.txt');
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.renames, isEmpty);
    expect(cloud.paths, {'/first.txt', '/second.txt', '/second_new.txt'});
    expect(
      find.text(
        'Nothing was renamed. Resolve the path errors shown in the preview.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('presets persist and restore the actual mask settings', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'Trip_[C]',
    );
    await tester.tap(find.text('Save preset'));
    await tester.pumpAndSettle();
    final presetName = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Preset name',
    );
    await tester.enterText(presetName, 'Trip names');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('commander.multiRenamePresets.v1'),
      contains('Trip_[C]'),
    );
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('rename-name-mask')))
          .controller!
          .text,
      '[N]',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trip names').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('rename-name-mask')))
          .controller!
          .text,
      'Trip_[C]',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tool remains usable on a narrow window', (tester) async {
    await open(tester, size: const Size(390, 700));
    expect(find.text('Multi-rename (2 items)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_[C]',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-preview')));
    await tester.pumpAndSettle();
    expect(find.text('→ first_001.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
