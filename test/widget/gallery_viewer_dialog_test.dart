import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/gallery_device_export.dart';
import 'package:crisp_cloud/services/gallery_media_service.dart';
import 'package:crisp_cloud/widgets/gallery_viewer_dialog.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

FileItem _file(String name) => FileItem(
  name: name,
  path: '/photos/$name',
  isFolder: false,
  size: 1024,
  updatedAt: DateTime(2026, 1, 2, 3, 4, 5),
);

GalleryImageData _image({int width = 64, int height = 32, int red = 64}) {
  final pixels = image.Image(width: width, height: height);
  image.fill(pixels, color: image.ColorRgba8(red, 128, 192, 255));
  return GalleryImageData(
    bytes: Uint8List.fromList(image.encodePng(pixels)),
    width: width,
    height: height,
    metadata: const {'Camera': 'Test camera'},
  );
}

class _Result {
  GalleryViewerResult? value;
}

Future<void> _open(
  WidgetTester tester, {
  List<FileItem>? files,
  GalleryImageLoader? loader,
  GalleryThumbnailLoader? thumbnailLoader,
  GalleryOriginalExporter? exporter,
  ValueNotifier<bool>? sourceCurrent,
  bool compare = false,
  bool slideshow = false,
  bool editable = false,
  _Result? result,
  Size size = const Size(1200, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final images = files ?? [_file('one.png'), _file('two.png'), _file('three.png')];
  final data = _image();
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () async {
          final value = await showDialog<GalleryViewerResult>(
            context: context,
            builder: (_) {
              Widget viewer(bool current) => GalleryViewerDialog(
                files: images,
                imageLoader: loader ?? (_) async => data,
                thumbnailLoader: thumbnailLoader ?? (_) async => null,
                originalExporter: exporter,
                canEdit: editable ? (_) => true : null,
                compare: compare,
                slideshow: slideshow,
                isSourceCurrent: current,
              );
              return Dialog.fullscreen(child: sourceCurrent == null
                  ? viewer(true)
                  : ValueListenableBuilder<bool>(
                      valueListenable: sourceCurrent,
                      builder: (_, current, __) => viewer(current),
                    ));
            },
          );
          result?.value = value;
        },
        child: const Text('Open gallery'),
      ),
    )),
  ));
  await tester.tap(find.text('Open gallery'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

String _title(WidgetTester tester) => tester.widget<Text>(
  find.byKey(const ValueKey('gallery-viewer-title')),
).data!;

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keyboard navigation follows supplied order and Escape restores route', (tester) async {
    final result = _Result();
    await _open(tester, result: result);
    await _settleImages(tester);
    expect(_title(tester), 'one.png');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settleImages(tester);
    expect(_title(tester), 'two.png');
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _settleImages(tester);
    expect(_title(tester), 'three.png');

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settleImages(tester);
    expect(_title(tester), 'one.png');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryViewerDialog), findsNothing);
    expect(result.value?.file.name, 'one.png');
    expect(result.value?.edit, isFalse);
    expect(find.text('Open gallery'), findsOneWidget);
  });

  testWidgets('late load cannot replace a newer image or resurrect a disposed slot', (tester) async {
    final first = Completer<GalleryImageData>();
    final second = Completer<GalleryImageData>();
    await _open(tester, files: [_file('one.png'), _file('two.png')],
        loader: (file) => file.name == 'one.png' ? first.future : second.future);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    first.complete(_image(red: 255));
    await tester.pump();
    expect(_title(tester), 'two.png');
    expect(find.byType(InteractiveViewer), findsNothing);

    second.complete(_image(red: 16));
    await _settleImages(tester);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(_title(tester), 'two.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('source expiration clears loaded images and metadata and stops slideshow', (tester) async {
    final current = ValueNotifier(true);
    addTearDown(current.dispose);
    var reads = 0;
    var exports = 0;
    final data = _image();
    await _open(tester,
        sourceCurrent: current,
        slideshow: true,
        loader: (_) async { reads++; return data; },
        thumbnailLoader: (_) async => data.bytes,
        exporter: (_) async { exports++; return null; });
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Test camera'), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-filmstrip')), findsOneWidget);

    current.value = false;
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Test camera'), findsNothing);
    expect(find.text('/photos/one.png'), findsNothing);
    expect(find.text('one.png'), findsNothing);
    expect(find.byKey(const ValueKey('gallery-filmstrip')), findsNothing);
    expect(find.text('This image’s source has changed. Close the viewer and reopen the folder.'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 1);
    expect(exports, 0);

    // A later connection notification cannot resurrect the old captured file.
    current.value = true;
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryViewerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source expiration rejects a pending full image and thumbnail completion', (tester) async {
    final current = ValueNotifier(true);
    addTearDown(current.dispose);
    final full = Completer<GalleryImageData>();
    final thumbnail = Completer<Uint8List?>();
    await _open(tester, sourceCurrent: current,
        loader: (_) => full.future, thumbnailLoader: (_) => thumbnail.future);
    current.value = false;
    await tester.pump();
    final data = _image();
    full.complete(data);
    thumbnail.complete(data.bytes);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('This image’s source has changed. Close the viewer and reopen the folder.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reads show retry and a successful retry replaces the error', (tester) async {
    var reads = 0;
    await _open(tester, files: [_file('one.png')], loader: (_) async {
      if (reads++ == 0) throw const GalleryMediaException('Storage unavailable');
      return _image();
    });
    await tester.pumpAndSettle();
    expect(find.text('Could not load this image.'), findsOneWidget);
    expect(find.text('Storage unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _settleImages(tester);
    expect(reads, 2);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Could not load this image.'), findsNothing);
  });

  testWidgets('actual size is 100 percent and metadata reports original dimensions', (tester) async {
    await _open(tester, files: [_file('one.png')]);
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(find.text('64 × 32'), findsOneWidget);
    expect(find.text('Test camera'), findsOneWidget);
    expect(find.text('/photos/one.png'), findsOneWidget);
  });

  testWidgets('comparison synchronizes zoom until link is disabled', (tester) async {
    await _open(tester, files: [_file('one.png'), _file('two.png')], compare: true);
    await _settleImages(tester);
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    List<double> scales() => tester.widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
        .map((view) => view.transformationController!.value.getMaxScaleOnAxis()).toList();
    expect(scales(), everyElement(closeTo(1.25, 0.00001)));

    await tester.tap(find.byTooltip('Unlink zoom and pan'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gallery-canvas-1')));
    // Finish the canvas's single-tap recognition window. Zero-duration pumps
    // leave Flutter's minimum double-tap countdown pending at test teardown.
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(scales()[0], closeTo(1.25, 0.00001));
    expect(scales()[1], closeTo(1.5625, 0.00001));
  });

  testWidgets('slideshow waits for loaded pixels and pauses after a read failure', (tester) async {
    final first = Completer<GalleryImageData>();
    await _open(tester, files: [_file('one.png'), _file('two.png')],
        slideshow: true, loader: (file) => file.name == 'one.png'
            ? first.future : Future<GalleryImageData>.error(const GalleryMediaException('Offline')));
    await tester.pump(const Duration(seconds: 8));
    expect(_title(tester), 'one.png');
    first.complete(_image());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(_title(tester), 'one.png');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_title(tester), 'two.png');
    expect(find.text('Offline'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(_title(tester), 'two.png');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preview rotation leaves export identity unchanged and copy cancellation is silent', (tester) async {
    FileItem? exported;
    await _open(tester, files: [_file('one.png')], exporter: (file) async {
      exported = file;
      return null;
    });
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    final rotations = tester.widgetList<RotatedBox>(find.byType(RotatedBox));
    expect(rotations.any((rotation) => rotation.quarterTurns == 1), isTrue);
    await tester.tap(find.byTooltip('Save original copy'));
    await tester.pumpAndSettle();
    expect(exported?.path, '/photos/one.png');
    expect(find.byType(SnackBar), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(find.text('Preview transforms only. Use Edit image to save changes.'), findsOneWidget);
  });

  testWidgets('edit hands off the currently displayed image', (tester) async {
    final result = _Result();
    await _open(tester, editable: true, result: result);
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pumpAndSettle();
    expect(result.value?.edit, isTrue);
    expect(result.value?.file.name, 'two.png');
  });

  testWidgets('four-image compare and metadata fit a small portrait screen', (tester) async {
    await _open(tester,
        files: [_file('one.png'), _file('two.png'), _file('three.png'), _file('four.png')],
        compare: true, size: const Size(360, 640));
    await _settleImages(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
