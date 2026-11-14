import 'dart:async';
import 'dart:io';

import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:crisp_cloud/services/catalogue_format.dart';
import 'package:crisp_cloud/services/catalogue_files.dart';
import 'package:crisp_cloud/services/catalogue_library.dart';
import 'package:crisp_cloud/services/catalogue_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/catalogue_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  @override
  String currentPath = '/unchanged';
  final scopes = <String>[];
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    scopes.add(path);
    try {
      return await action();
    } finally {
      scopes.remove(path);
    }
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Backend implements CatalogBackend {
  @override
  bool supported = true;
  final requests = <Map<String, Object?>>[];
  Completer<Map<String, dynamic>>? pending;
  bool deferCancel = false;
  Map<String, dynamic> info() => {
    'root': '/offline',
    'bytes': 100000,
    'files': 400,
    'directories': 1,
    'indexedAtUnix': 1700000000,
    'origin': 'native_scan',
    'complete': true,
    'issueCount': 0,
    'catalogueId': 'fixture-id',
    'schemaVersion': 2,
  };
  @override
  Future<Map<String, dynamic>> execute(Map<String, Object?> request) async {
    requests.add(Map.of(request));
    switch (request['op']) {
      case 'cancel':
        if (!deferCancel && pending != null && !pending!.isCompleted) {
          pending!.completeError(
            CatalogException('Stopped', code: 'cancelled'),
          );
        }
        return {'stopRequested': true};
      case 'status':
        return {'phase': 'scanning', 'entries': 200};
      case 'forget_job':
        return {};
      case 'validate':
        if (pending != null) return pending!.future;
        return info();
      case 'scan':
        File(request['output'] as String).writeAsStringSync('managed fixture');
        return info();
      case 'import':
        File(request['output'] as String)
            .writeAsStringSync('managed CAF fixture');
        return {...info(), 'origin': 'caf_import', 'complete': false};
      case 'copy':
      case 'export':
        return {'output': request['output']};
      case 'query':
        final path = request['path'] as String? ?? '';
        var rows = <Map<String, dynamic>>[
          if (path.isEmpty)
            {
              'path': '/offline/empty',
              'relativePath': 'empty',
              'type': 'directory',
              'bytes': 0,
              'files': 0,
              'directories': 0,
              'complete': true,
              'mtimeUnix': 1700000000,
            },
          if (path.isEmpty)
            for (var i = 0; i < 400; i++)
              {
                'path': '/offline/file${i.toString().padLeft(4, '0')}.txt',
                'relativePath': 'file${i.toString().padLeft(4, '0')}.txt',
                'type': 'file',
                'bytes': i,
                'files': 1,
                'directories': 0,
                'complete': true,
                'mtimeUnix': 1700000000,
              },
        ];
        final search = request['search'] as String? ?? '';
        if (search.isNotEmpty) {
          rows = rows
              .where((r) => (r['relativePath'] as String).contains(search))
              .toList();
        }
        if (request['filesOnly'] == true) {
          rows = rows.where((r) => r['type'] == 'file').toList();
        }
        if (request['directoriesOnly'] == true) {
          rows = rows.where((r) => r['type'] == 'directory').toList();
        }
        final offset = request['offset'] as int? ?? 0;
        final limit = request['top'] as int? ?? 20;
        return {
          ...info(),
          'root': {
            'path': path.isEmpty ? '/offline' : '/offline/$path',
            'type': 'directory',
            'bytes': path.isEmpty ? 100000 : 0,
            'files': path.isEmpty ? 400 : 0,
            'directories': path.isEmpty ? 1 : 0,
            'complete': true,
          },
          'entries': rows.skip(offset).take(limit).toList(),
          'totalMatches': rows.length,
          'hasMore': offset + limit < rows.length,
          'issues': <dynamic>[],
        };
      default:
        return info();
    }
  }
}

class _AckLost extends MemoryFileCollectionStorage {
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final result = await super.compareAndSwap(key, expected, value);
    if (result) throw StateError('ack lost');
    return result;
  }
}

void main() {
  late Directory tmp;
  late _Backend backend;
  late _Local local;
  late CatalogueLibrary library;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisp_catalogue_gui_');
    backend = _Backend();
    local = _Local();
    library = CatalogueLibrary(storage: MemoryFileCollectionStorage());
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(tmp.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  Future<void> launch(
    WidgetTester tester, {
    String? initialPath,
    Size size = const Size(1200, 900),
    double scale = 1,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CatalogueDialog(
                  local: local,
                  backend: backend,
                  library: library,
                  initialPath: initialPath,
                  chooseFolder: () async => tmp.path,
                  chooseOpen: (caf) async => caf
                      ? '${tmp.path}/source.caf'
                      : '${tmp.path}/external.crispindex',
                  chooseSave: (caf) async =>
                      '${tmp.path}/export.${caf ? 'caf' : 'crispindex'}',
                ),
              ),
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Launch'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test(
    'header detection separates Core Audio CAF and generic SQLite files',
    () {
      expect(catalogueFormat('audio.caf', 'caff123456789012'.codeUnits), null);
      expect(
        catalogueFormat('db.sqlite', 'SQLite format 3\u0000'.codeUnits),
        null,
      );
      expect(
        catalogueFormat('index.crispindex', 'SQLite format 3\u0000'.codeUnits),
        CatalogueFormat.native,
      );
      expect(
        catalogueFormat('index.caf', [39, 48, 164, 208, 8, 0]),
        null,
      ); // invalid sentinel
      final data = File('cli/test/fixtures/catalog/catfish-v8-windows.caf')
          .readAsBytesSync();
      expect(
        catalogueFormat('offline.caf', data.take(16).toList()),
        CatalogueFormat.caf,
      );
    },
  );
  test(
    'library recovers a committed write after lost acknowledgement',
    () async {
      final store = _AckLost();
      final library = CatalogueLibrary(storage: store);
      await library.remember(
        CatalogueRecord(
          id: 'one',
          path: '/index',
          label: 'One',
          managed: false,
          root: '/offline',
          savedAt: DateTime(2026),
        ),
      );
      expect((await library.list()).single.label, 'One');
      await library.forget('one');
      expect(await library.list(), isEmpty);
    },
  );
  test(
    'scopes remain held after stop acknowledgement until native work settles',
    () async {
      backend.pending = Completer();
      backend.deferCancel = true;
      final job = CatalogueJob(
        backend,
        local,
        {'op': 'validate', 'index': '/index'},
        ['/index'],
      );
      await Future<void>.delayed(Duration.zero);
      expect(local.scopes, ['/index']);
      await job.stop();
      expect(local.scopes, ['/index']);
      final check = expectLater(job.future, throwsA(isA<CatalogException>()));
      backend.pending!.completeError(
        CatalogException('Stopped', code: 'cancelled'),
      );
      await check;
      expect(local.scopes, isEmpty);
    },
  );
  testWidgets(
    'large catalogue uses paging and empty folders retain parent navigation',
    (tester) async {
      await launch(tester, initialPath: '/catalogue.crispindex');
      expect(find.text('file0000.txt'), findsOneWidget);
      expect(
        backend.requests.where((r) => r['op'] == 'query').first['top'],
        200,
      );
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Next'));
      await tester.tap(find.widgetWithText(TextButton, 'Next'));
      await tester.pumpAndSettle();
      expect(
        backend.requests.lastWhere((r) => r['op'] == 'query')['offset'],
        200,
      );
      expect(find.text('file0199.txt'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Previous'));
      await tester.tap(find.widgetWithText(TextButton, 'Previous'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalogue-row-empty')),
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-row-empty')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('catalogue-parent')), findsOneWidget);
      expect(
        backend.requests.lastWhere((r) => r['op'] == 'query')['path'],
        'empty',
      );
      await tester.tap(find.byKey(const ValueKey('catalogue-parent')));
      await tester.pumpAndSettle();
      expect(backend.requests.lastWhere((r) => r['op'] == 'query')['path'], '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('search is debounced and tied to the opened catalogue ID', (
    tester,
  ) async {
    await launch(tester, initialPath: '/catalogue.crispindex');
    await tester.enterText(
      find.byKey(const ValueKey('catalogue-search')),
      'file0399',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('file0399.txt'), findsOneWidget);
    final query = backend.requests.lastWhere((r) => r['op'] == 'query');
    expect(query['expectedCatalogueId'], 'fixture-id');
    expect(query['recursive'], true);
  });
  testWidgets(
    'small screen at large text scale can scroll all controls without overflow',
    (tester) async {
      await launch(
        tester,
        initialPath: '/catalogue.crispindex',
        size: const Size(320, 480),
        scale: 2.5,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('catalogue-search')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('create and reopen library without changing pane path', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('New catalogue'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r['op'] == 'scan'), hasLength(1));
    expect((await library.list()).single.managed, true);
    expect(local.currentPath, '/unchanged');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Launch'), findsOneWidget);
    expect(local.scopes, isEmpty);
  });
  testWidgets('CAF import is retained with explicit unknown coverage', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Import CAF'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Partial or unknown source coverage'), findsOneWidget);
    expect((await library.list()).single.managed, true);
    expect(find.text('Refresh from folder'), findsNothing);
  });
  testWidgets(
    'removing external catalogue forgets reference without deleting its file',
    (tester) async {
      final file = File('${tmp.path}/external.crispindex')
        ..writeAsStringSync('external');
      await launch(tester, initialPath: file.path);
      await tester.tap(find.text('Remove from library'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(file.readAsStringSync(), 'external');
      expect(await library.list(), isEmpty);
    },
  );
  testWidgets('stop cannot publish or add a cancelled open to the library', (
    tester,
  ) async {
    backend.pending = Completer();
    await launch(tester, initialPath: '/catalogue.crispindex', settle: false);
    await tester.tap(find.widgetWithText(TextButton, 'Stop'));
    await tester.pumpAndSettle();
    expect(await library.list(), isEmpty);
    expect(local.scopes, isEmpty);
    expect(
      find.text('Stopped. Unpublished changes were discarded.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'linked references reject traversal and symlinks escaping the root',
    () async {
      final root = Directory('${tmp.path}/root')..createSync();
      File('${root.path}/inside.txt').writeAsStringSync('hello');
      final resolved = await resolveCatalogueReference(root.path, 'inside.txt');
      expect(resolved['bytes'], 5);
      await expectLater(
        resolveCatalogueReference(root.path, '../outside'),
        throwsStateError,
      );
      final outside = Directory('${tmp.path}/outside')..createSync();
      File('${outside.path}/secret.txt').writeAsStringSync('private');
      Link('${root.path}/link').createSync(outside.path);
      await expectLater(
        resolveCatalogueReference(root.path, 'link/secret.txt'),
        throwsStateError,
      );
      await expectLater(
        resolveCatalogueReference(root.path, 'link'),
        throwsStateError,
      );
    },
  );
  testWidgets('library search opens the captured catalogue and exact path', (
    tester,
  ) async {
    await library.remember(
      CatalogueRecord(
        id: 'one',
        path: '/catalogue.crispindex',
        label: 'Saved disk',
        managed: false,
        root: '/offline',
        savedAt: DateTime.now(),
      ),
    );
    await launch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('catalogue-library-search')),
      'file0399',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('file0399.txt'));
    await tester.pumpAndSettle();
    final query = backend.requests.lastWhere((r) => r['op'] == 'query');
    expect(query['expectedCatalogueId'], 'fixture-id');
    expect(query['exactPath'], 'file0399.txt');
  });
  test('corrupt library is reported without erasing earlier bytes', () async {
    final storage = MemoryFileCollectionStorage();
    storage.values[CatalogueLibrary.key] = 'invalid';
    final library = CatalogueLibrary(storage: storage);
    await expectLater(library.list(), throwsFormatException);
    expect(storage.values[CatalogueLibrary.key], 'invalid');
  });
}
