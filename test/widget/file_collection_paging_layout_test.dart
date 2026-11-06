import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/file_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Cloud extends Fake implements CloudStorageClient {
  static const count = 1800;
  @override
  String get providerName => 'Collection layout fixture';
  @override
  String get rootPath => '/';
  @override
  String get userId => 'original-layout-account';
  @override
  String? get bucketId => null;
  @override
  bool get isAuthenticated => true;
  String name(int index) => 'file-${index.toString().padLeft(5, '0')}.txt';
  FileItem file(int index) => FileItem(
    name: name(index),
    path: '/${name(index)}',
    uuid: 'original-$index',
    isFolder: false,
    size: index + 1,
    updatedAt: DateTime.utc(2024),
  );
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'files': [
      if (path == '/')
        for (var index = 0; index < count; index++)
          {
            'name': name(index),
            'uuid': 'original-$index',
            'size': index + 1,
            'lastModified': DateTime.utc(2024).millisecondsSinceEpoch,
          },
    ],
    'folders': [],
  };
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? userEmail = 'layout@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late MemoryFileCollectionStorage storage;
  late FileCollectionStore store;
  late _Cloud cloud;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (_) async => null,
        );
    cloud = _Cloud();
    storage = MemoryFileCollectionStorage();
    store = FileCollectionStore(storage: storage, cacheEntryLimit: 1000);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        fileCollectionStoreProvider.overrideWith((_) => store),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
  });

  Future<PanelNotifier> host(WidgetTester tester, String language) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final panel = container.read(panelProvider(PanelSide.remote));
    await tester.runAsync(() async {
      await panel.refresh();
      final source = storageReferenceForClient(cloud);
      final entries = [
        for (var index = _Cloud.count - 1; index >= 0; index--)
          FileCollectionService.capture(cloud.file(index), source),
      ];
      await store.save(
        FileCollection(
          id: 'layout',
          name: 'Collection layout',
          entries: entries,
          selectedKeys: {
            for (final index in [0, 700, 1799])
              FileCollectionService.capture(cloud.file(index), source).key,
          },
        ),
      );
      await panel.openCollection('layout');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: FilePanel(
              side: PanelSide.remote,
              isActive: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return panel;
  }

  Future<void> activate(WidgetTester tester, Finder button) async {
    expect(button.hitTestable(), findsOneWidget);
    final dynamic callback = tester.widget<IconButton>(button).onPressed;
    expect(callback, isNotNull);
    await tester.runAsync(() async => await callback());
    await tester.pumpAndSettle();
  }

  for (final language in ['de', 'ar']) {
    testWidgets(
      'paged collection controls and errors fit narrow 2x $language text without losing off-page marks',
      (tester) async {
        final panel = await host(tester, language);
        final first = find.byKey(const ValueKey('collection-first-page'));
        final previous = find.byKey(const ValueKey('collection-previous-page'));
        final next = find.byKey(const ValueKey('collection-next-page'));
        final last = find.byKey(const ValueKey('collection-last-page'));
        for (final button in [first, previous, next, last]) {
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(
          Directionality.of(tester.element(next)),
          language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );

        void checkWindow(int start, int end) {
          expect(panel.collectionPageStart, start - 1);
          expect(panel.selection.map((file) => file.path).toSet(), {
            '/file-00000.txt',
            '/file-00700.txt',
            '/file-01799.txt',
          });
          expect(
            find.text(
              CommanderStrings.forLanguage(
                language,
                '{0}–{1} of {2} · {3} marked',
                [start, end, _Cloud.count, 3],
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }

        checkWindow(1, 500);
        expect(tester.widget<IconButton>(first).onPressed, isNull);
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        await activate(tester, next);
        checkWindow(501, 1000);
        await activate(tester, previous);
        checkWindow(1, 500);
        await activate(tester, last);
        checkWindow(1501, 1800);
        expect(tester.widget<IconButton>(next).onPressed, isNull);
        expect(tester.widget<IconButton>(last).onPressed, isNull);
        await activate(tester, first);
        checkWindow(1, 500);

        // A failed page read must expose its retry control without overflowing
        // the same narrow layout or clearing the complete marked selection.
        final key = 'manifest:layout:${store.get('layout')!.revision}';
        final savedManifest = storage.values[key]!;
        storage.values[key] = 'Unreadable collection manifest';
        await activate(tester, next);
        expect(panel.collectionLoadError, isNotNull);
        checkWindow(1, 500);
        final reloadLabel = CommanderStrings.forLanguage(
          language,
          'Reload saved collection; unsaved marks are discarded',
        );
        final reload = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == reloadLabel,
        );
        expect(reload.hitTestable(), findsOneWidget);
        storage.values[key] = savedManifest;
        await activate(tester, reload);
        expect(panel.collectionLoadError, isNull);
        checkWindow(1, 500);
        expect(store.get('layout')!.selectedCount, 3);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
