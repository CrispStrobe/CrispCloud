import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/gallery_media_provider.dart';
import 'package:crisp_cloud/providers/gallery_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_collection_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/file_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  static const count = 1200;
  int listings = 0;
  @override
  String get providerName => 'S3';
  @override
  String get rootPath => '/';
  @override
  String get userId => 'gallery-original-account';
  @override
  String get bucketId => 'original-bucket';
  @override
  bool get isAuthenticated => true;
  @override
  bool get supportsThumbnails => false;
  String name(int index) => 'photo${index.toString().padLeft(5, '0')}.raw';
  FileItem file(int index) => FileItem(
    name: name(index),
    path: '/${name(index)}',
    uuid: 'image-$index',
    isFolder: false,
    size: index + 1,
    updatedAt: DateTime.utc(2024),
  );
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listings++;
    return {
      'files': [
        if (path == '/')
          for (var index = 0; index < count; index++)
            {
              'name': name(index),
              'uuid': 'image-$index',
              'size': index + 1,
              'lastModified': DateTime.utc(2024).millisecondsSinceEpoch,
            },
      ],
      'folders': [],
    };
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? userEmail = 'gallery@example.test';
  @override
  String get providerName => client.providerName;
  void reconnect() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService, LocalFileSourceIdentity {
  @override
  String currentPath = Directory.systemTemp.path;
  Object rootToken = Object();
  @override
  String get grantedBasePath => currentPath;
  @override
  Object? sourceIdentityForPath(String path) => rootToken;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Media extends Fake implements GalleryMediaService {
  @override
  Future<Uint8List?> loadThumbnail(
    GalleryMediaRequest request, {
    int size = 256,
    bool retry = false,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FileCollectionStore store;
  late PanelNotifier panel;
  late _Cloud cloud;
  late _Local local;
  late _Auth auth;
  late WidgetRef widgetRef;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    local = _Local();
    auth = _Auth(cloud);
    store = FileCollectionStore(
      storage: MemoryFileCollectionStorage(),
      cacheEntryLimit: 1000,
    );
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        fileCollectionStoreProvider.overrideWith((_) => store),
        galleryMediaServiceProvider.overrideWithValue(_Media()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
  });
  tearDown(() => container.dispose());

  FileReference reference(int index) => FileCollectionService.capture(
    cloud.file(index),
    storageReferenceForClient(cloud),
  ).reference;

  Future<void> host(WidgetTester tester, {bool gallery = true}) async {
    await tester.runAsync(() async {
      await panel.refresh();
      await store.save(
        FileCollection(
          id: 'gallery-collection',
          name: 'Paged gallery',
          entries: [
            for (var index = _Cloud.count - 1; index >= 0; index--)
              FileCollectionService.capture(
                cloud.file(index),
                storageReferenceForClient(cloud),
              ),
          ],
          selectedKeys: {
            '${reference(0).storage.id}\u0000${reference(0).path}',
            '${reference(900).storage.id}\u0000${reference(900).path}',
          },
        ),
      );
      await panel.openCollection('gallery-collection');
      await container.read(galleryCatalogProvider).load();
    });
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                final current = ref.watch(panelProvider(PanelSide.remote));
                return gallery
                    ? FileGridView(
                        side: PanelSide.remote,
                        files: current.files ?? const [],
                        scrollController: scroll,
                        galleryOnly: true,
                      )
                    : const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (gallery) await tester.runAsync(panel.reloadCollectionQuery);
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, GalleryQuery query) async {
    container.read(galleryQueryProvider(PanelSide.remote).notifier).state =
        query;
    await tester.pump();
    await tester.runAsync(panel.reloadCollectionQuery);
    await tester.pumpAndSettle();
    expect(panel.collectionLoadError, isNull);
    expect(tester.takeException(), isNull);
  }

  Future<void> selectionAction(
    WidgetTester tester,
    String action,
    int count,
  ) async {
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuButton<String> &&
            widget.tooltip == 'More actions',
      ),
    );
    final dynamic callback = menu.onSelected;
    await tester.runAsync(() async {
      final done = Completer<void>();
      void check() {
        if (!done.isCompleted &&
            !panel.collectionBusy &&
            panel.selection.length == count) {
          done.complete();
        }
      }

      panel.addListener(check);
      try {
        await callback(action);
        check();
        await done.future.timeout(const Duration(seconds: 15));
      } finally {
        panel.removeListener(check);
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'gallery names, tags, rating order and marks cover off-page collection rows',
    (tester) async {
      await host(tester);
      expect(panel.files, hasLength(500));
      final identities = captureGalleryCatalogIdentityLookup(
        widgetRef,
        PanelSide.remote,
      );
      final catalog = container.read(galleryCatalogProvider);
      await tester.runAsync(() async {
        await catalog.update(
          [identities.assetId(reference(20))!],
          rating: 1,
          tags: ['featured'],
        );
        await catalog.update(
          [identities.assetId(reference(700))!],
          rating: 3,
          tags: ['featured'],
        );
        await catalog.update(
          [identities.assetId(reference(1199))!],
          rating: 5,
          tags: ['featured'],
        );
      });
      await query(
        tester,
        const GalleryQuery(
          text: 'featured',
          sort: GallerySort.rating,
          descending: true,
        ),
      );
      expect(panel.collectionMatchingCount, 3);
      expect(panel.files!.map((file) => file.path), [
        reference(1199).path,
        reference(700).path,
        reference(20).path,
      ]);
      expect(panel.selection.map((file) => file.path).toSet(), {
        reference(0).path,
        reference(900).path,
      });

      await query(tester, const GalleryQuery(text: 'photo01199'));
      expect(panel.collectionMatchingCount, 1);
      expect(panel.files!.single.path, reference(1199).path);
      await query(tester, const GalleryQuery(minimumRating: 4));
      expect(panel.files!.single.path, reference(1199).path);
      await tester.runAsync(
        () => catalog.update([identities.assetId(reference(20))!], rating: 5),
      );
      await tester.pump();
      await tester.runAsync(panel.reloadCollectionQuery);
      await tester.pumpAndSettle();
      expect(panel.files!.map((file) => file.path).toSet(), {
        reference(20).path,
        reference(1199).path,
      });

      await query(tester, const GalleryQuery());
      await selectionAction(tester, 'select_all', _Cloud.count);
      expect(store.get('gallery-collection')!.selectedCount, _Cloud.count);
      await selectionAction(tester, 'invert', 0);
      expect(store.get('gallery-collection')!.selectedCount, 0);
      expect(panel.retainedSavedCollectionRows, lessThanOrEqualTo(500));
      expect(store.residentEntryCount, lessThanOrEqualTo(1000));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(panel.reloadCollectionQuery);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'leaving gallery removes its projection without a disposed WidgetRef callback',
    (tester) async {
      await host(tester);
      await query(tester, const GalleryQuery(text: 'photo01199'));
      expect(panel.collectionMatchingCount, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(panel.reloadCollectionQuery);
      await tester.pumpAndSettle();
      expect(panel.collectionMatchingCount, _Cloud.count);
      expect(panel.files, hasLength(500));
      expect(panel.files!.first.path, reference(0).path);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog lookup matches captured media scopes and never borrows another account',
    (tester) async {
      await host(tester, gallery: false);
      final file = panel.files!.first;
      final request = captureGalleryMediaRequest(
        widgetRef,
        PanelSide.remote,
        file,
      );
      final lookup = captureGalleryCatalogIdentityLookup(
        widgetRef,
        PanelSide.remote,
      );
      final reads = cloud.listings;
      expect(lookup.assetId(reference(0)), request.assetId);
      expect(
        lookup.assetId(
          FileReference(
            storage: const StorageReference(
              kind: 'remote',
              provider: 'S3',
              accountKey: 'different-account',
            ),
            path: reference(0).path,
            objectId: reference(0).objectId,
          ),
        ),
        isNull,
      );
      expect(cloud.listings, reads);
      auth.reconnect();
      await tester.pump();
      expect(lookup.isCurrent, isFalse);
      expect(lookup.assetId(reference(0)), isNull);
      final fresh = captureGalleryCatalogIdentityLookup(
        widgetRef,
        PanelSide.remote,
      );
      expect(fresh.assetId(reference(0)), isNot(request.assetId));

      final path = p.join(local.currentPath, 'local-photo.raw');
      final origin = panel.captureLocalClipboardOrigin(local.currentPath);
      panel.showSearchResults([
        FileItem(name: 'local-photo.raw', path: path, isFolder: false),
      ], origin: origin);
      await tester.pump();
      final localFile = panel.files!.single;
      final localReference = FileCollectionService.capture(
        localFile,
        origin.storageReference,
      ).reference;
      final localRequest = captureGalleryMediaRequest(
        widgetRef,
        PanelSide.remote,
        localFile,
      );
      final localLookup = captureGalleryCatalogIdentityLookup(
        widgetRef,
        PanelSide.remote,
      );
      expect(localLookup.assetId(localReference), localRequest.assetId);
      local.rootToken = Object();
      expect(localLookup.assetId(localReference), isNot(localRequest.assetId));
      expect(cloud.listings, reads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
