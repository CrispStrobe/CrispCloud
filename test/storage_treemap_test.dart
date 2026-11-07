import 'dart:math' as math;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/utils/formatters.dart';
import 'package:crisp_cloud/utils/storage_treemap_layout.dart';
import 'package:crisp_cloud/widgets/storage_treemap.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

StorageNode _file(String path, int? bytes) => StorageNode(
  item: FileItem(
    name: path.split('/').last,
    path: path,
    isFolder: false,
    size: bytes,
  ),
  bytes: bytes ?? 0,
  fileCount: 1,
  folderCount: 0,
  unknownSizeCount: bytes == null ? 1 : 0,
  isComplete: bytes != null,
);

StorageNode _folder(String path, List<StorageNode> children) => StorageNode(
  item: FileItem(name: path.split('/').last, path: path, isFolder: true),
  children: children,
  bytes: children.fold(0, (sum, node) => sum + node.bytes),
  fileCount: children.fold(0, (sum, node) => sum + node.fileCount),
  folderCount: children.fold(
    0,
    (sum, node) => sum + node.folderCount + (node.isFolder ? 1 : 0),
  ),
  unknownSizeCount: children.fold(
    0,
    (sum, node) => sum + node.unknownSizeCount,
  ),
  isComplete: children.every((node) => node.isComplete),
);

double _area(Rect rect) => rect.width * rect.height;

void _expectPartition<T>(
  List<TreemapRect<T>> cells,
  Rect bounds,
  double Function(T) weight,
) {
  final total = cells.fold<double>(0, (sum, cell) => sum + weight(cell.value));
  expect(
    cells.fold<double>(0, (sum, cell) => sum + _area(cell.rect)),
    closeTo(_area(bounds), 0.00001),
  );
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    expect(cell.rect.left, greaterThanOrEqualTo(bounds.left - 0.000001));
    expect(cell.rect.top, greaterThanOrEqualTo(bounds.top - 0.000001));
    expect(cell.rect.right, lessThanOrEqualTo(bounds.right + 0.000001));
    expect(cell.rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.000001));
    expect(cell.rect.width, greaterThan(0));
    expect(cell.rect.height, greaterThan(0));
    expect(
      _area(cell.rect) / _area(bounds),
      closeTo(weight(cell.value) / total, 0.0000001),
    );
    for (var j = i + 1; j < cells.length; j++) {
      final intersection = cell.rect.intersect(cells[j].rect);
      final overlap =
          math.max(0, intersection.width) * math.max(0, intersection.height);
      expect(overlap, lessThan(0.00001));
    }
  }
}

Widget _host({
  required StorageNode root,
  StorageNode? selected,
  ValueChanged<StorageNode>? onSelected,
  ValueChanged<StorageNode>? onOpenFolder,
  Size size = const Size(600, 320),
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox.fromSize(
            size: size,
            child: StorageTreemap(
              root: root,
              selected: selected,
              onSelected: onSelected ?? (_) {},
              onOpenFolder: onOpenFolder ?? (_) {},
              aggregateLabel: (count) => '$count grouped items',
              emptyLabel: 'No known file sizes',
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('squarified layout', () {
    test('fills the bounds with proportional, nonoverlapping rectangles', () {
      const weights = {'a': 60.0, 'b': 25.0, 'c': 10.0, 'd': 5.0};
      const bounds = Rect.fromLTWH(17, 31, 800, 480);
      final cells = squarifyTreemap(
        weights.keys,
        bounds,
        (item) => weights[item]!,
      );
      expect(cells, hasLength(weights.length));
      _expectPartition(cells, bounds, (item) => weights[item]!);
    });

    test('four equal sizes become four squares, preserving tie order', () {
      final names = ['d', 'c', 'b', 'a'];
      final cells = squarifyTreemap(
        names,
        const Rect.fromLTWH(0, 0, 400, 400),
        (_) => 1,
      );
      expect(cells.map((cell) => cell.value), names);
      expect(names, ['d', 'c', 'b', 'a']);
      for (final cell in cells) {
        expect(cell.rect.size, const Size(200, 200));
      }
    });

    test('ignores zero, negative and nonfinite values', () {
      final cells = squarifyTreemap(
        [0.0, -5.0, double.nan, double.infinity, 30.0],
        const Rect.fromLTWH(0, 0, 200, 80),
        (weight) => weight,
      );
      expect(cells, hasLength(1));
      expect(cells.single.value, 30);
      expect(cells.single.rect, const Rect.fromLTWH(0, 0, 200, 80));
      expect(
        squarifyTreemap([0.0], const Rect.fromLTWH(0, 0, 10, 10), (n) => n),
        isEmpty,
      );
    });

    test('returns no rectangles for empty or nonfinite bounds', () {
      for (final bounds in [
        Rect.zero,
        const Rect.fromLTWH(0, 0, -10, 100),
        const Rect.fromLTWH(0, 0, double.infinity, 100),
        const Rect.fromLTWH(double.nan, 0, 100, 100),
      ]) {
        expect(squarifyTreemap([10], bounds, (n) => n.toDouble()), isEmpty);
      }
    });

    test('normalizes exceptionally large weights before summing', () {
      final cells = squarifyTreemap(
        [1e308, 1e308, 5e307],
        const Rect.fromLTWH(0, 0, 600, 200),
        (weight) => weight,
      );
      expect(cells, hasLength(3));
      expect(_area(cells[0].rect), closeTo(48000, 0.00001));
      expect(_area(cells[1].rect), closeTo(48000, 0.00001));
      expect(_area(cells[2].rect), closeTo(24000, 0.00001));
    });

    test('preserves area across varied viewport shapes and distributions', () {
      final random = math.Random(51403);
      for (final size in [
        const Size(320, 640),
        const Size(1200, 120),
        const Size(0.2, 600),
        const Size(500, 500),
      ]) {
        for (var example = 0; example < 8; example++) {
          final weights = List.generate(
            4 + random.nextInt(30),
            (_) => 1.0 + random.nextInt(100000),
          );
          final bounds = const Offset(4, 8) & size;
          final cells = squarifyTreemap(weights, bounds, (weight) => weight);
          expect(cells, hasLength(weights.length));
          _expectPartition(cells, bounds, (weight) => weight);
        }
      }
    });
  });

  group('storage tree layout', () {
    test(
      'nests files within folder headers without changing sibling areas',
      () {
        final folder = _folder('/root/photos', [
          _file('/root/photos/large.jpg', 900),
          _file('/root/photos/small.jpg', 100),
        ]);
        final root = _folder('/root', [
          folder,
          _file('/root/archive.zip', 2000),
        ]);
        final tiles = layoutStorageTreemap(root, const Size(800, 400));
        final folderTile = tiles.singleWhere(
          (tile) => identical(tile.node, folder),
        );
        expect(folderTile.isExpanded, isTrue);
        expect(_area(folderTile.rect), closeTo(800 * 400 / 3, 0.00001));
        final children = tiles.where((tile) => tile.depth == 1).toList();
        expect(children, hasLength(2));
        _expectPartition(
          children.map((tile) => TreemapRect(tile, tile.rect)).toList(),
          folderTile.contentRect!,
          (tile) => tile.bytes.toDouble(),
        );
      },
    );

    test(
      'caps rendered tiles and keeps every byte in an explicit aggregate',
      () {
        final root = _folder(
          '/root',
          List.generate(5000, (index) => _file('/root/$index.dat', 1)),
        );
        final tiles = layoutStorageTreemap(
          root,
          const Size(1000, 600),
          maxTiles: 80,
          minTileArea: 0,
        );
        expect(tiles, hasLength(80));
        final aggregate = tiles.singleWhere((tile) => tile.isAggregate);
        expect(aggregate.aggregateCount, 4921);
        expect(aggregate.bytes, 4921);
        expect(aggregate.node, same(root));
        expect(tiles.fold<int>(0, (sum, tile) => sum + tile.bytes), 5000);
        _expectPartition(
          tiles.map((tile) => TreemapRect(tile, tile.rect)).toList(),
          const Rect.fromLTWH(0, 0, 1000, 600),
          (tile) => tile.bytes.toDouble(),
        );
      },
    );

    test('tiny-item groups keep their combined area next to a large file', () {
      final root = _folder('/root', [
        _file('/root/large.bin', 100000),
        for (var i = 0; i < 20; i++) _file('/root/small-$i.txt', 1),
      ]);
      final tiles = layoutStorageTreemap(root, const Size(400, 200));
      expect(tiles, hasLength(2));
      expect(tiles.last.isAggregate, isTrue);
      expect(tiles.last.aggregateCount, 20);
      expect(tiles.last.bytes, 20);
      expect(
        _area(tiles.last.rect) / (400 * 200),
        closeTo(20 / 100020, 0.0000001),
      );
    });

    test('does not invent area for unknown sizes or zero-byte files', () {
      final root = _folder('/root', [
        _file('/root/empty', 0),
        _file('/root/unknown', null),
        _folder('/root/empty-folder', []),
      ]);
      expect(layoutStorageTreemap(root, const Size(800, 400)), isEmpty);
      expect(root.children, hasLength(3));
      expect(root.unknownSizeCount, 1);
    });

    test(
      'respects depth and tile budgets while leaving folders selectable',
      () {
        final folder = _folder('/root/folder', [
          _file('/root/folder/file', 10),
        ]);
        final root = _folder('/root', [folder, _file('/root/other', 10)]);
        final shallow = layoutStorageTreemap(
          root,
          const Size(600, 400),
          maxDepth: 0,
        );
        expect(shallow, hasLength(2));
        expect(shallow.every((tile) => !tile.isExpanded), isTrue);
        expect(shallow.any((tile) => identical(tile.node, folder)), isTrue);

        final single = layoutStorageTreemap(
          root,
          const Size(600, 400),
          maxTiles: 1,
        );
        expect(single, hasLength(1));
        expect(single.single.isAggregate, isTrue);
        expect(single.single.bytes, 20);
        expect(single.single.aggregateCount, 2);
      },
    );

    test(
      'repeated layouts are deterministic and preserve input child order',
      () {
        final root = _folder('/root', [
          _file('/root/z', 10),
          _file('/root/a', 10),
          _file('/root/b', 5),
        ]);
        final first = layoutStorageTreemap(root, const Size(500, 200));
        final second = layoutStorageTreemap(root, const Size(500, 200));
        expect(first.map((tile) => tile.rect), second.map((tile) => tile.rect));
        expect(first.map((tile) => tile.node.path), [
          '/root/a',
          '/root/z',
          '/root/b',
        ]);
        expect(root.children.map((node) => node.path), [
          '/root/z',
          '/root/a',
          '/root/b',
        ]);
      },
    );
  });

  test(
    'extension colors match the legend regardless of extension spelling',
    () {
      expect(storageExtensionColor('PDF'), storageExtensionColor('.pdf'));
      expect(storageExtensionColor('pdf'), isNot(storageExtensionColor('png')));
      expect(storageExtensionColor(''), storageExtensionColor('.'));
      expect(
        storageExtensionColor('pdf', brightness: Brightness.dark),
        isNot(storageExtensionColor('pdf', brightness: Brightness.light)),
      );
    },
  );

  testWidgets(
    'selects a leaf and opens a folder by double-click or long-press',
    (tester) async {
      final report = _file('/root/docs/report.pdf', 4000);
      final folder = _folder('/root/docs', [report]);
      final root = _folder('/root', [folder, _file('/root/video.mp4', 6000)]);
      StorageNode? selected;
      final opened = <StorageNode>[];
      await tester.pumpWidget(
        _host(
          root: root,
          onSelected: (node) => selected = node,
          onOpenFolder: opened.add,
        ),
      );
      final offset = tester.getTopLeft(find.byType(StorageTreemap));
      final tiles = layoutStorageTreemap(root, const Size(600, 320));
      final reportRect = tiles
          .singleWhere((tile) => identical(tile.node, report))
          .rect;
      await tester.tapAt(offset + reportRect.center);
      await tester.pump(const Duration(milliseconds: 350));
      expect(selected, same(report));

      final folderRect = tiles
          .singleWhere((tile) => identical(tile.node, folder))
          .rect;
      final header = offset + Offset(folderRect.center.dx, folderRect.top + 8);
      await tester.tapAt(header);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(header);
      await tester.pump();
      expect(opened, [folder]);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.longPressAt(header);
      await tester.pump();
      expect(opened, [folder, folder]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hover shows the full path and size and resets for a new root', (
    tester,
  ) async {
    final first = _file('/root/first.pdf', 4096);
    final second = _file('/other/second.mp4', 8192);
    StorageNode? selected;
    await tester.pumpWidget(
      _host(
        root: _folder('/root', [first]),
        onSelected: (node) => selected = node,
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(StorageTreemap)));
    await tester.pump();
    expect(
      find.text('${first.path}\n${formatBytes(first.bytes)}'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _host(
        root: _folder('/other', [second]),
        onSelected: (node) => selected = node,
      ),
    );
    expect(
      find.text('${first.path}\n${formatBytes(first.bytes)}'),
      findsNothing,
    );
    await tester.tapAt(tester.getCenter(find.byType(StorageTreemap)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(selected, same(second));
    expect(tester.takeException(), isNull);
  });

  testWidgets('file and folder semantics expose selection and drill-down', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final report = _file('/root/docs/report.pdf', 4000);
      final folder = _folder('/root/docs', [report]);
      await tester.pumpWidget(_host(root: _folder('/root', [folder])));
      // CustomPainter creates semantic nodes without corresponding widgets.
      final fileNodes = find.semantics
          .byLabel('${report.path}\n${formatBytes(report.bytes)}')
          .evaluate();
      expect(fileNodes, hasLength(1));
      final fileData = fileNodes.single.getSemanticsData();
      expect(fileData.hasAction(SemanticsAction.tap), isTrue);
      final folderNodes = find.semantics
          .byLabel('${folder.path}\n${formatBytes(folder.bytes)}')
          .evaluate();
      expect(folderNodes, hasLength(1));
      final folderData = folderNodes.single.getSemanticsData();
      expect(folderData.hasAction(SemanticsAction.tap), isTrue);
      expect(folderData.hasAction(SemanticsAction.longPress), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('supports narrow RTL layouts and larger text without overflow', (
    tester,
  ) async {
    final root = _folder('/root', [
      _folder('/root/مجلد طويل جدا', [
        _file('/root/مجلد طويل جدا/report.pdf', 4000),
      ]),
      _file('/root/a-very-long-file-name-without-whitespace.mp4', 6000),
    ]);
    await tester.pumpWidget(
      _host(
        root: root,
        size: const Size(240, 150),
        direction: TextDirection.rtl,
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains an empty map using the supplied localized text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(root: _folder('/root', [_file('/root/unknown', null)])),
    );
    expect(find.text('No known file sizes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
