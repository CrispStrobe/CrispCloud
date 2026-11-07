import 'dart:math' as math;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/utils/formatters.dart';
import 'package:crisp_cloud/utils/storage_sunburst_layout.dart';
import 'package:crisp_cloud/widgets/storage_analysis_view.dart';
import 'package:crisp_cloud/widgets/storage_sunburst.dart';
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

Widget _host({
  required StorageNode root,
  StorageNode? selected,
  ValueChanged<StorageNode>? onSelected,
  ValueChanged<StorageNode>? onOpenFolder,
  ValueChanged<StorageNode>? onInspectGroup,
  VoidCallback? onOpenParent,
  Size size = const Size(480, 440),
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox.fromSize(
            size: size,
            child: StorageSunburst(
              root: root,
              selected: selected,
              onSelected: onSelected ?? (_) {},
              onOpenFolder: onOpenFolder ?? (_) {},
              onInspectGroup: onInspectGroup,
              onOpenParent: onOpenParent,
              aggregateLabel: (count) => '$count grouped items',
              shareLabel: (percent) => '$percent% of this folder',
              centerLabel: onOpenParent == null ? 'Scan root' : 'Parent folder',
              emptyLabel: 'No known file sizes',
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('sunburst layout', () {
    test('partitions each expanded parent by bytes without overlap', () {
      final docs = _folder('/root/docs', [
        _file('/root/docs/a.pdf', 600),
        _file('/root/docs/b.pdf', 300),
      ]);
      final root = _folder('/root', [docs, _file('/root/photo.jpg', 100)]);
      final layout = layoutStorageSunburst(root, const Size(600, 600));
      final top = layout.segments.where((s) => s.depth == 0).toList();
      expect(top, hasLength(2));
      expect(top.fold<int>(0, (sum, s) => sum + s.bytes), root.bytes);
      expect(
        top.fold<double>(0, (sum, s) => sum + s.sweepAngle),
        closeTo(math.pi * 2, 1e-12),
      );
      expect(top.first.sweepAngle / (math.pi * 2), closeTo(0.9, 1e-12));
      final nested = layout.segments.where((s) => s.depth == 1).toList();
      expect(nested, hasLength(2));
      expect(top.first.isExpanded, isTrue);
      expect(nested.first.startAngle, top.first.startAngle);
      expect(
        nested.last.startAngle + nested.last.sweepAngle,
        closeTo(top.first.startAngle + top.first.sweepAngle, 1e-12),
      );
      expect(
        nested.first.sweepAngle / top.first.sweepAngle,
        closeTo(2 / 3, 1e-12),
      );
      for (final segment in layout.segments) {
        expect(segment.innerRadius, greaterThanOrEqualTo(layout.holeRadius));
        expect(segment.outerRadius, lessThanOrEqualTo(layout.radius));
        expect(
          layout.hitTest(segment.middlePoint(layout.center)),
          same(segment),
        );
      }
      // A file's bytes are not repeated into the next ring.
      expect(
        layout.hitTest(
          layout.center +
              Offset.fromDirection(top.last.middleAngle, layout.radius - 2),
        ),
        isNull,
      );
    });

    test('groups siblings at the sector budget and conserves exact totals', () {
      final root = _folder(
        '/root',
        List.generate(5000, (i) => _file('/root/$i.bin', 1)),
      );
      final layout = layoutStorageSunburst(
        root,
        const Size(600, 600),
        maxSegments: 20,
        minSweepAngle: 0,
      );
      expect(layout.segments, hasLength(20));
      final group = layout.segments.singleWhere((s) => s.isAggregate);
      expect(group.node, same(root));
      expect(group.aggregateCount, 4981);
      expect(group.bytes, 4981);
      expect(layout.segments.fold<int>(0, (sum, s) => sum + s.bytes), 5000);
      expect(group.sweepAngle / (math.pi * 2), closeTo(4981 / 5000, 1e-12));
      final one = layoutStorageSunburst(
        root,
        const Size(600, 600),
        maxSegments: 1,
      );
      expect(one.segments.single.aggregateCount, 5000);
      expect(one.segments.single.bytes, 5000);
      expect(one.segments.single.sweepAngle, math.pi * 2);
    });

    test('tiny siblings retain their angle in an explicit group', () {
      final root = _folder('/root', [
        _file('/root/large.bin', 100000),
        for (var i = 0; i < 20; i++) _file('/root/$i.txt', 1),
      ]);
      final layout = layoutStorageSunburst(root, const Size(600, 600));
      expect(layout.segments, hasLength(2));
      expect(layout.segments.last.aggregateCount, 20);
      expect(layout.segments.last.bytes, 20);
      expect(
        layout.segments.last.sweepAngle / (math.pi * 2),
        closeTo(20 / 100020, 1e-12),
      );
    });

    test('a last available sector represents all children of its folder', () {
      final folder = _folder(
        '/root/docs',
        List.generate(100, (i) => _file('/root/docs/$i.pdf', 20)),
      );
      final root = _folder('/root', [folder, _file('/root/a.txt', 1)]);
      final layout = layoutStorageSunburst(
        root,
        const Size(600, 600),
        maxSegments: 3,
        minSweepAngle: 0,
      );
      expect(layout.segments, hasLength(3));
      final outer = layout.segments.singleWhere((s) => s.depth == 1);
      expect(outer.isAggregate, isTrue);
      expect(outer.bytes, folder.bytes);
      expect(outer.aggregateCount, 100);
      expect(outer.sweepAngle, layout.segments.first.sweepAngle);
    });

    test('bounds depth and adapts ring count to small displays', () {
      var root = _file('/leaf.txt', 9007199254740991);
      for (var i = 0; i < 200; i++) {
        root = _folder('/depth-$i', [root]);
      }
      final layout = layoutStorageSunburst(root, const Size(800, 800));
      expect(layout.ringCount, 5);
      expect(layout.segments, hasLength(5));
      expect(layout.segments.last.isExpanded, isFalse);
      expect(
        layout.segments.every(
          (s) => s.bytes == 9007199254740991 && s.sweepAngle.isFinite,
        ),
        isTrue,
      );
      expect(layoutStorageSunburst(root, const Size(70, 70)).ringCount, 1);
    });

    test('does not invent angle for zero-byte and unknown-size entries', () {
      final root = _folder('/root', [
        _file('/root/empty', 0),
        _file('/root/unknown', null),
      ]);
      expect(
        layoutStorageSunburst(root, const Size(400, 400)).segments,
        isEmpty,
      );
      for (final size in [
        Size.zero,
        const Size(-1, 100),
        const Size(double.infinity, 100),
        const Size(double.nan, 100),
      ]) {
        expect(layoutStorageSunburst(_file('/a', 10), size).segments, isEmpty);
      }
    });

    test('stable path ordering does not mutate children and hit testing excludes center', () {
      final root = _folder('/root', [_file('/root/b', 1), _file('/root/a', 1)]);
      final layout = layoutStorageSunburst(root, const Size(500, 500));
      expect(layout.segments.map((s) => s.node.name), ['a', 'b']);
      expect(root.children.map((s) => s.name), ['b', 'a']);
      expect(layout.hitTest(layout.center), isNull);
      expect(layout.hitTest(Offset.zero), isNull);
    });
  });

  testWidgets(
    'selects files and opens folders by double-click and long-press',
    (tester) async {
      final file = _file('/root/docs/report.pdf', 4000);
      final folder = _folder('/root/docs', [file]);
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
      final origin = tester.getTopLeft(find.byType(StorageSunburst));
      final layout = layoutStorageSunburst(root, const Size(480, 440));
      Offset point(StorageNode node) =>
          origin +
          layout.segments
              .singleWhere((s) => identical(s.node, node))
              .middlePoint(layout.center);
      await tester.tapAt(point(file));
      await tester.pump(const Duration(milliseconds: 350));
      expect(selected, same(file));
      await tester.tapAt(point(folder));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point(folder));
      await tester.pump();
      expect(opened, [folder]);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.longPressAt(point(folder));
      await tester.pump();
      expect(opened, [folder, folder]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('groups open their containing folder list and center goes up', (
    tester,
  ) async {
    final root = _folder(
      '/root',
      List.generate(1000, (i) => _file('/root/$i.txt', 1)),
    );
    StorageNode? inspected;
    var wentUp = false;
    await tester.pumpWidget(
      _host(
        root: root,
        onInspectGroup: (node) => inspected = node,
        onOpenParent: () => wentUp = true,
      ),
    );
    final layout = layoutStorageSunburst(root, const Size(480, 440));
    final origin = tester.getTopLeft(find.byType(StorageSunburst));
    await tester.tapAt(
      origin + layout.segments.single.middlePoint(layout.center),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(inspected, same(root));
    await tester.tap(find.byTooltip('Parent folder'));
    expect(wentUp, isTrue);
  });

  testWidgets('hover identifies path, size, share and resets on root change', (
    tester,
  ) async {
    final first = _file('/root/first.pdf', 4096);
    final root = _folder('/root', [first]);
    await tester.pumpWidget(_host(root: root));
    final layout = layoutStorageSunburst(root, const Size(480, 440));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(
      tester.getTopLeft(find.byType(StorageSunburst)) +
          layout.segments.single.middlePoint(layout.center),
    );
    await tester.pump();
    expect(
      find.text(
        '${first.path}\n${formatBytes(first.bytes)} · 100.0% of this folder',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(
      _host(root: _folder('/other', [_file('/other/second.mp4', 10)])),
    );
    expect(find.textContaining('/root/first.pdf'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('semantics offer selection, folder zoom and an actionable center', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final file = _file('/root/docs/report.pdf', 4000);
      final folder = _folder('/root/docs', [file]);
      await tester.pumpWidget(
        _host(root: _folder('/root', [folder]), onOpenParent: () {}),
      );
      final nodes = find.semantics
          .byLabel(
            '${folder.path}\n${formatBytes(folder.bytes)} · 100.0% of this folder',
          )
          .evaluate();
      expect(nodes, hasLength(1));
      expect(
        nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        nodes.single.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      final center = find.semantics
          .byLabel('Parent folder\n/root\n${formatBytes(folder.bytes)}')
          .evaluate();
      expect(center, hasLength(1));
      expect(
        center.single.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('dark, RTL and enlarged text stay within compact bounds', (
    tester,
  ) async {
    final root = _folder('/root', [
      _folder('/root/folder', [_file('/root/folder/long-file-name.pdf', 300)]),
      _file('/root/a.jpg', 100),
    ]);
    for (final size in [
      const Size(320, 200),
      const Size(80, 80),
      const Size(24, 24),
    ]) {
      await tester.pumpWidget(
        _host(
          root: root,
          size: size,
          brightness: Brightness.dark,
          direction: TextDirection.rtl,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'switching visualizations retains selection and folder navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final file = _file('/root/photo.jpg', 500);
      final folder = _folder('/root/docs', [
        _file('/root/docs/report.pdf', 4000),
      ]);
      final root = _folder('/root', [folder, file, _file('/root/empty', 0)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageAnalysisView(
              analysis: StorageScanResult(
                root: root,
                cancelled: false,
                limited: false,
                sourceChanged: false,
                startedAt: DateTime.utc(2026),
                completedAt: DateTime.utc(2026),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ListTile, 'photo.jpg'));
      await tester.tap(find.byKey(const ValueKey('storage-view-sunburst')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StorageSunburst>(find.byType(StorageSunburst)).selected,
        same(file),
      );
      expect(find.widgetWithText(ListTile, 'empty'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom into folder').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StorageSunburst>(find.byType(StorageSunburst)).root,
        same(folder),
      );
      await tester.tap(find.byTooltip('Parent folder').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StorageSunburst>(find.byType(StorageSunburst)).root,
        same(root),
      );
      await tester.tap(find.byKey(const ValueKey('storage-view-treemap')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StorageTreemap>(find.byType(StorageTreemap)).root,
        same(root),
      );
      expect(find.text('Largest files'), findsOneWidget);
      expect(find.text('File types'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact enlarged report scrolls map controls and keeps lists accessible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = _folder('/root', [
        _file('/root/photo.jpg', 400),
        _file('/root/empty', 0),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.4)),
            child: child!,
          ),
          home: Scaffold(
            body: StorageAnalysisView(
              analysis: StorageScanResult(
                root: root,
                cancelled: false,
                limited: false,
                sourceChanged: false,
                startedAt: DateTime.utc(2026),
                completedAt: DateTime.utc(2026),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('storage-view-sunburst')),
      );
      await tester.tap(find.byKey(const ValueKey('storage-view-sunburst')));
      await tester.pumpAndSettle();
      expect(find.byType(StorageSunburst), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Folders & files'));
      await tester.tap(find.text('Folders & files'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
