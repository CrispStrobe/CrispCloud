import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_analyzer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/workflow_fake_client.dart';

StorageNode _file(String path, int? size) => StorageNode(
  item: FileItem(
    name: path.split('/').last,
    path: path,
    isFolder: false,
    size: size,
  ),
  bytes: size ?? 0,
  fileCount: 1,
  folderCount: 0,
  unknownSizeCount: size == null ? 1 : 0,
  isComplete: size != null,
);

StorageNode _folder(String path, List<StorageNode> children) => StorageNode(
  item: FileItem(
    name: path == '/' ? '/' : path.split('/').last,
    path: path,
    isFolder: true,
  ),
  children: children,
  bytes: children.fold(0, (sum, child) => sum + child.bytes),
  fileCount: children.fold(0, (sum, child) => sum + child.fileCount),
  folderCount: children.fold(
    0,
    (sum, child) => sum + child.folderCount + (child.isFolder ? 1 : 0),
  ),
  unknownSizeCount: children.fold(
    0,
    (sum, child) => sum + child.unknownSizeCount,
  ),
  isComplete: children.every((child) => child.isComplete),
);

StorageScanResult _report({bool unknown = false}) => StorageScanResult(
  root: _folder('/', [
    _folder('/movies', [
      _file('/movies/clip.mp4', 3000),
      _file('/movies/short.mp4', 1000),
    ]),
    _file('/photo.jpg', 500),
    _file('/empty.txt', 0),
    if (unknown) _file('/unknown.bin', null),
  ]),
  cancelled: false,
  limited: false,
  sourceChanged: false,
  startedAt: DateTime.utc(2026),
  completedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
);

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: content!,
  ),
  home: Scaffold(body: child),
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'folder drill-down and breadcrumbs update both map and file list',
    (tester) async {
      _viewport(tester, const Size(1200, 900));
      await tester.pumpWidget(_app(StorageAnalysisView(analysis: _report())));
      expect(find.text('4 Files'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom into folder').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'clip.mp4'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'photo.jpg'), findsNothing);
      expect(find.text('/movies'), findsOneWidget);
      await tester.tap(find.text('Scan root'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'photo.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file-type filter, text search and reveal use the selected original file',
    (tester) async {
      _viewport(tester, const Size(1200, 900));
      StorageNode? revealed;
      await tester.pumpWidget(
        _app(
          StorageAnalysisView(
            analysis: _report(),
            onReveal: (node) async => revealed = node,
          ),
        ),
      );
      await tester.ensureVisible(find.text('File types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('.mp4'));
      await tester.pumpAndSettle();
      expect(find.text('Type: .mp4'), findsOneWidget);
      expect(find.text('Showing 2 of 2 files, largest first'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'clip');
      await tester.pump();
      expect(find.text('Showing 1 of 1 files, largest first'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'clip.mp4'));
      await tester.pump();
      await tester.tap(find.text('Show in file panel'));
      expect(revealed?.path, '/movies/clip.mp4');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown sizes stay visible and explain partial totals', (
    tester,
  ) async {
    _viewport(tester, const Size(1200, 900));
    await tester.pumpWidget(
      _app(StorageAnalysisView(analysis: _report(unknown: true))),
    );
    expect(find.text('Partial results'), findsOneWidget);
    expect(find.text('Unknown size'), findsOneWidget);
    await tester.tap(find.text('Partial results'));
    await tester.pumpAndSettle();
    expect(find.text('1 files have unknown sizes'), findsOneWidget);
    expect(find.textContaining('known portion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact report and large German text remain scrollable without overflow',
    (tester) async {
      _viewport(tester, const Size(360, 640));
      await tester.pumpWidget(
        _app(
          StorageAnalysisView(analysis: _report(unknown: true)),
          locale: const Locale('de'),
          scale: 1.8,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Speicherkarte'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Ordner und Dateien'));
      await tester.tap(find.text('Ordner und Dateien'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'movies'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stopping an in-flight directory keeps a partial report and prevents traversal',
    (tester) async {
      _viewport(tester, const Size(1000, 800));
      final client = _DelayedClient()
        ..put('/blocked/nested/file.txt', [1, 2, 3]);
      await tester.pumpWidget(
        _app(
          StorageAnalyzerDialog(
            source: CloudStorageScanBackend(
              client,
              isCurrent: () => client.current,
            ),
            rootPath: '/',
            sourceLabel: 'Test cloud',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(client.paths, contains('/blocked'));
      await tester.tap(find.text('Stop scan'));
      await tester.pump();
      expect(find.text('Stopping after the current folder…'), findsOneWidget);
      client.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Scan stopped — partial results'), findsOneWidget);
      expect(client.paths, isNot(contains('/blocked/nested')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing during a pending listing cancels callbacks safely', (
    tester,
  ) async {
    _viewport(tester, const Size(1000, 800));
    final client = _DelayedClient()..put('/blocked/file.txt', [1]);
    await tester.pumpWidget(
      _app(
        StorageAnalyzerDialog(
          source: CloudStorageScanBackend(
            client,
            isCurrent: () => client.current,
          ),
          rootPath: '/',
          sourceLabel: 'Test cloud',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(client.paths, contains('/blocked'));
    await tester.pumpWidget(_app(const Text('Closed')));
    client.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rescanning refreshes sizes and stale accounts cannot reveal items',
    (tester) async {
      _viewport(tester, const Size(1200, 900));
      final client = WorkflowFakeClient()..put('/a.txt', [1]);
      var revealed = false;
      await tester.pumpWidget(
        _app(
          StorageAnalyzerDialog(
            source: CloudStorageScanBackend(
              client,
              isCurrent: () => client.current,
            ),
            rootPath: '/',
            sourceLabel: 'Test cloud',
            onReveal: (_) async => revealed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      client.put('/new.txt', List.filled(100, 1));
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'new.txt'), findsOneWidget);
      client.current = false;
      await tester.tap(find.text('Show in file panel'));
      await tester.pump();
      expect(revealed, isFalse);
      expect(
        find.textContaining('Could not open the original item'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'delayed reveal cannot run twice or pop the route below a closed dialog',
    (tester) async {
      _viewport(tester, const Size(1200, 900));
      final client = WorkflowFakeClient()..put('/a.txt', [1]);
      final release = Completer<void>();
      final observer = _PopObserver();
      var reveals = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Browser stays open'),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      routeSettings: const RouteSettings(
                        name: 'storage-analysis',
                      ),
                      builder: (_) => StorageAnalyzerDialog(
                        source: CloudStorageScanBackend(
                          client,
                          isCurrent: () => client.current,
                        ),
                        rootPath: '/',
                        sourceLabel: 'Test cloud',
                        onReveal: (_) async {
                          reveals++;
                          await release.future;
                        },
                      ),
                    ),
                    child: const Text('Launch analyzer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch analyzer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show in file panel'));
      await tester.tap(find.text('Show in file panel'));
      expect(reveals, 1);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 20));
      release.complete();
      await tester.pumpAndSettle();
      expect(observer.popped, ['storage-analysis']);
      expect(find.text('Browser stays open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PopObserver extends NavigatorObserver {
  final popped = <String?>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route.settings.name);
    super.didPop(route, previousRoute);
  }
}

class _DelayedClient extends WorkflowFakeClient {
  final release = Completer<void>();
  final paths = <String>[];

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    if (path == '/blocked') await release.future;
    return super.listPath(path);
  }
}
