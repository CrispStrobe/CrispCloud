// Actual host picker actions, with independent package/media expectations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:crisp_cloud/services/office_picture.dart';
import 'package:crisp_cloud/widgets/office_editor_ribbon.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ct = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _config = OfficeSurfaceConfig(
  mode: OfficeInteractionMode.editing,
  autofocus: false,
  adaptiveChrome: false,
);

Uint8List _png(int width, int height) =>
    image.encodePng(image.Image(width: width, height: height));

FilePickerResult _result(Uint8List? bytes, {String name = 'picked.png'}) =>
    FilePickerResult([
      PlatformFile(name: name, size: bytes?.length ?? 0, bytes: bytes),
    ]);

class _Picker extends FilePicker {
  _Picker(this.response);
  final Future<FilePickerResult?> Function() response;
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.image);
    expect(withData, isTrue);
    calls++;
    return response();
  }
}

Widget _widget(
  OfficeController controller,
  GlobalKey<OfficeEditorRibbonState> key,
) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: OfficeEditorRibbon(
      key: key,
      controller: controller,
      kind: controller is WordEditorController
          ? OfficeEditorKind.word
          : OfficeEditorKind.slides,
      config: controller.config,
      onSave: () {},
      onClose: () {},
      onConfigChanged: (_) {},
      onFind: controller.requestFind,
    ),
  ),
);

Future<GlobalKey<OfficeEditorRibbonState>> _host(
  WidgetTester tester,
  OfficeController controller,
) async {
  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  final key = GlobalKey<OfficeEditorRibbonState>();
  await tester.pumpWidget(_widget(controller, key));
  await tester.pump();
  return key;
}

Future<void> _insert(
  WidgetTester tester,
  GlobalKey<OfficeEditorRibbonState> key, {
  OfficeEditorAction action = OfficeEditorAction.insertPicture,
}) async {
  await tester.runAsync(() => key.currentState!.perform(action));
  await tester.pumpAndSettle();
}

xml.XmlDocument _part(Archive archive, String name) =>
    xml.XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));

void _expectPicture(
  Uint8List bytes,
  Uint8List source, {
  required bool word,
  required double width,
  required double height,
  String mime = 'image/png',
  int? x,
  int? y,
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final main = word ? 'word/document.xml' : 'ppt/slides/slide1.xml';
  final document = _part(archive, main);
  final picture = word
      ? document.findAllElements('drawing', namespace: _w).single
      : document.findAllElements('pic', namespace: _p).single;
  final extent = word
      ? picture.findAllElements('extent', namespace: _wp).single
      : picture
            .findAllElements('xfrm', namespace: _a)
            .single
            .findElements('ext', namespace: _a)
            .single;
  expect(extent.getAttribute('cx'), '${(width * 12700).round()}');
  expect(extent.getAttribute('cy'), '${(height * 12700).round()}');
  if (!word) {
    final offset = picture
        .findAllElements('xfrm', namespace: _a)
        .single
        .findElements('off', namespace: _a)
        .single;
    expect(offset.getAttribute('x'), '${x ?? 914400}');
    expect(offset.getAttribute('y'), '${y ?? 514350}');
    final slideSize = _part(
      archive,
      'ppt/presentation.xml',
    ).findAllElements('sldSz', namespace: _p).single;
    expect(
      int.parse(offset.getAttribute('x')!) +
          int.parse(extent.getAttribute('cx')!),
      lessThanOrEqualTo(int.parse(slideSize.getAttribute('cx')!)),
    );
    expect(
      int.parse(offset.getAttribute('y')!) +
          int.parse(extent.getAttribute('cy')!),
      lessThanOrEqualTo(int.parse(slideSize.getAttribute('cy')!)),
    );
  }
  final id = picture
      .findAllElements('blip', namespace: _a)
      .single
      .getAttribute('embed', namespace: _r);
  final rels = word
      ? 'word/_rels/document.xml.rels'
      : 'ppt/slides/_rels/slide1.xml.rels';
  final relationship = _part(archive, rels)
      .findAllElements('Relationship', namespace: _pr)
      .singleWhere((entry) => entry.getAttribute('Id') == id);
  expect(relationship.getAttribute('Type'), '$_r/image');
  final target = Uri(path: '/$main')
      .resolve(relationship.getAttribute('Target')!)
      .path
      .substring(1);
  expect(archive.findFile(target)!.content, orderedEquals(source));
  final extension = target.split('.').last;
  final contentTypes = _part(archive, '[Content_Types].xml');
  final declared =
      contentTypes
          .findAllElements('Override', namespace: _ct)
          .where((entry) => entry.getAttribute('PartName') == '/$target')
          .firstOrNull ??
      contentTypes
          .findAllElements('Default', namespace: _ct)
          .singleWhere((entry) => entry.getAttribute('Extension') == extension);
  expect(declared.getAttribute('ContentType'), mime);
}

void _expectImageOnlyWordPage(Uint8List bytes) {
  final document = _part(ZipDecoder().decodeBytes(bytes), 'word/document.xml');
  final body = document.findAllElements('body', namespace: _w).single;
  final paragraphs = body.findElements('p', namespace: _w).toList();
  expect(paragraphs, hasLength(2));
  expect(
    document
        .findAllElements('t', namespace: _w)
        .map((node) => node.innerText)
        .join(),
    isEmpty,
  );
  expect(paragraphs.first.findAllElements('drawing', namespace: _w), isEmpty);
  expect(
    paragraphs.last.findAllElements('inline', namespace: _wp),
    hasLength(1),
  );
  final spacing = paragraphs.first
      .findAllElements('spacing', namespace: _w)
      .single;
  for (final (name, value) in [
    ('before', '0'),
    ('after', '0'),
    ('line', '240'),
    ('lineRule', 'exact'),
  ]) {
    expect(spacing.getAttribute(name, namespace: _w), value);
  }
  final page = document.findAllElements('pgSz', namespace: _w).single;
  expect(page.getAttribute('w', namespace: _w), '11906');
  expect(page.getAttribute('h', namespace: _w), '16838');
  final margins = document.findAllElements('pgMar', namespace: _w).single;
  for (final name in ['left', 'right', 'top', 'bottom']) {
    expect(margins.getAttribute(name, namespace: _w), '1440');
  }
  for (final name in ['header', 'footer']) {
    expect(margins.getAttribute(name, namespace: _w), '720');
  }
}

void _cycles(
  OfficeController controller,
  String name,
  void Function(Uint8List bytes) check,
) {
  var bytes = controller.saveBytes();
  final word = controller is WordEditorController;
  for (var cycle = 1; cycle <= 3; cycle++) {
    check(bytes);
    final output = File(
      'build/fidelity-host/$name-$cycle.${word ? 'docx' : 'pptx'}',
    );
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes);
    if (cycle < 3) {
      final reopened = word
          ? WordEditorController.fromBytes(bytes)
          : SlideEditorController.fromBytes(bytes);
      try {
        bytes = reopened.saveBytes();
      } finally {
        reopened.dispose();
      }
    }
  }
}

void main() {
  test(
    'picture validation rejects corrupt, unsupported and excessive input',
    () {
      expect(inspectOfficePicture(Uint8List(0)), isNull);
      expect(
        inspectOfficePicture(Uint8List(officePictureMaxBytes + 1)),
        isNull,
      );
      expect(
        inspectOfficePicture(Uint8List.fromList(utf8.encode('<svg/>'))),
        isNull,
      );
      expect(
        inspectOfficePicture(Uint8List.fromList(_png(2, 2).take(24).toList())),
        isNull,
      );
      final huge = Uint8List.fromList(_png(2, 2));
      ByteData.sublistView(huge).setUint32(16, officePictureMaxPixels + 1);
      expect(inspectOfficePicture(huge), isNull);
      expect(
        inspectOfficePicture(image.encodeBmp(image.Image(width: 2, height: 2))),
        isNull,
      );
    },
  );

  test(
    'picture sizing retains 96dpi size and rejects unrepresentable boxes',
    () {
      final info = inspectOfficePicture(_png(40, 20))!;
      expect(info.fit(maxWidth: 360, maxHeight: 240), (
        width: 30.0,
        height: 15.0,
      ));
      expect(const OfficePictureInfo(1, 1).fit(maxWidth: 360, maxHeight: 240), (
        width: 1.0,
        height: 1.0,
      ));
      expect(info.fit(maxWidth: double.nan, maxHeight: 240), isNull);
      expect(info.fit(maxWidth: 360, maxHeight: double.infinity), isNull);
      expect(info.fit(maxWidth: 0, maxHeight: 240), isNull);
      expect(
        const OfficePictureInfo(0, 10).fit(maxWidth: 360, maxHeight: 240),
        isNull,
      );
      expect(
        const OfficePictureInfo(10000, 1).fit(maxWidth: 360, maxHeight: 240),
        isNull,
      );
    },
  );

  for (final word in [true, false]) {
    for (final scenario in [
      (
        name: 'landscape',
        pixelsX: 800,
        pixelsY: 400,
        width: 360.0,
        height: 180.0,
      ),
      (
        name: 'portrait',
        pixelsX: 400,
        pixelsY: 800,
        width: 120.0,
        height: 240.0,
      ),
      (name: 'square', pixelsX: 600, pixelsY: 600, width: 240.0, height: 240.0),
    ]) {
      testWidgets(
        '${word ? 'Word' : 'Slide'} picture ${scenario.name} keeps its ratio',
        (tester) async {
          final picture = _png(scenario.pixelsX, scenario.pixelsY);
          final picker = _Picker(() async => _result(picture));
          FilePicker.platform = picker;
          final OfficeController controller = word
              ? WordEditorController(
                  document: WmlDocument.empty(text: 'Picture insertion'),
                  config: _config,
                )
              : SlideEditorController(config: _config);
          final key = await _host(tester, controller);
          await _insert(
            tester,
            key,
            action: word
                ? OfficeEditorAction.insertPicture
                : OfficeEditorAction.slidePicture,
          );
          expect(picker.calls, 1);
          expect(controller.isDirty, isTrue);
          void check(Uint8List bytes) => _expectPicture(
            bytes,
            picture,
            word: word,
            width: scenario.width,
            height: scenario.height,
          );
          check(controller.saveBytes());
          controller.undo();
          if (controller is WordEditorController) {
            expect(controller.document.visuals, isEmpty);
          } else {
            expect((controller as SlideEditorController).slide.shapes, isEmpty);
          }
          controller.redo();
          _cycles(
            controller,
            '${word ? 'word' : 'slide'}-picture-${scenario.name}',
            check,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final format in ['jpeg', 'gif']) {
    testWidgets('Word retains the original $format media bytes and type', (
      tester,
    ) async {
      final pixels = image.Image(width: 80, height: 40);
      final picture = format == 'jpeg'
          ? image.encodeJpg(pixels)
          : image.encodeGif(pixels);
      // Decoding is also run in this isolate so host line coverage includes
      // the inspector used by the production compute worker.
      final info = inspectOfficePicture(picture)!;
      expect((info.widthPixels, info.heightPixels), (80, 40));
      FilePicker.platform = _Picker(
        () async => _result(picture, name: 'picked.$format'),
      );
      // Keep this image-only while giving native readers a known
      // 12-point lead-in, independent of the empty paragraph's font metrics.
      final document = WmlDocument.empty();
      document.paragraphs.single.properties
        ..lineSpacing = 12
        ..lineSpacingRule = WmlLineSpacingRule.exact
        ..spacingBefore = 0
        ..spacingAfter = 0
        ..explicitLineSpacing = true
        ..explicitSpacingBefore = true
        ..explicitSpacingAfter = true;
      final controller = WordEditorController(
        document: document,
        config: _config,
      );
      final key = await _host(tester, controller);
      await _insert(tester, key);
      _cycles(controller, 'word-picture-$format', (bytes) {
        _expectPicture(
          bytes,
          picture,
          word: true,
          width: 60,
          height: 30,
          mime: 'image/$format',
        );
        _expectImageOnlyWordPage(bytes);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Word picture stays within the current column', (tester) async {
    final picture = _png(800, 400);
    FilePicker.platform = _Picker(() async => _result(picture));
    final document = WmlDocument.empty(text: 'Column picture');
    document.sections.first
      ..pageSize = const WmlPageSize(width: 300, height: 400)
      ..margins = const WmlPageMargins(left: 20, right: 20, top: 20, bottom: 20)
      ..columnCount = 2
      ..columnSpace = 20;
    final controller = WordEditorController(
      document: document,
      config: _config,
    );
    final key = await _host(tester, controller);
    await _insert(tester, key);
    _cycles(
      controller,
      'word-picture-bounds',
      (bytes) =>
          _expectPicture(bytes, picture, word: true, width: 120, height: 60),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Slide picture stays within a small imported slide', (
    tester,
  ) async {
    final picture = _png(800, 400);
    FilePicker.platform = _Picker(() async => _result(picture));
    final controller = SlideEditorController(
      // Native slide dimensions must be at least 72 points on each side.
      presentation: PmlPresentation(slideWidth: 1270000, slideHeight: 914400),
      config: _config,
    );
    final key = await _host(tester, controller);
    await _insert(tester, key);
    _cycles(
      controller,
      'slide-picture-bounds',
      (bytes) => _expectPicture(
        bytes,
        picture,
        word: false,
        width: 90,
        height: 45,
        x: 127000,
        y: 91440,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'canceled and invalid picks leave document and history untouched',
    (tester) async {
      final controller = WordEditorController(config: _config);
      final key = await _host(tester, controller);
      FilePicker.platform = _Picker(() async => null);
      await _insert(tester, key);
      expect(find.byType(SnackBar), findsNothing);
      for (final bytes in <Uint8List?>[
        null,
        Uint8List(0),
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List(officePictureMaxBytes + 1),
      ]) {
        FilePicker.platform = _Picker(() async => _result(bytes));
        await _insert(tester, key);
        expect(controller.document.visuals, isEmpty);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
        expect(find.byType(SnackBar), findsOneWidget);
        ScaffoldMessenger.of(key.currentContext!).clearSnackBars();
        await tester.pumpAndSettle();
      }
      FilePicker.platform = _Picker(
        () => Future.error(StateError('picker unavailable')),
      );
      await _insert(tester, key);
      expect(find.text('Could not read the selected image.'), findsOneWidget);
      expect(controller.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mode in ['replacement', 'selection', 'viewing', 'disposed']) {
    testWidgets('Word ignores $mode changes during an outstanding image pick', (
      tester,
    ) async {
      final picture = _png(40, 20);
      late Completer<FilePickerResult?> picked;
      FilePicker.platform = _Picker(() => picked.future);
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Original'),
        config: _config,
      );
      final key = await _host(tester, controller);
      WordEditorController? replacement;
      await tester.runAsync(() async {
        picked = Completer<FilePickerResult?>();
        final pending = key.currentState!.perform(
          OfficeEditorAction.insertPicture,
        );
        switch (mode) {
          case 'replacement':
            replacement = WordEditorController(config: _config);
            addTearDown(replacement!.dispose);
            await tester.pumpWidget(_widget(replacement!, key));
          case 'selection':
            controller.caret.logicalIndex = 3;
          case 'viewing':
            controller.config = const OfficeSurfaceConfig(
              mode: OfficeInteractionMode.viewing,
            );
          case 'disposed':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        picked.complete(_result(picture));
        await pending;
      });
      expect(controller.document.visuals, isEmpty);
      expect(controller.isDirty, isFalse);
      if (replacement != null) {
        expect(replacement!.document.visuals, isEmpty);
        expect(replacement!.isDirty, isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Slide ignores a pick that finishes on another slide', (
    tester,
  ) async {
    late Completer<FilePickerResult?> picked;
    FilePicker.platform = _Picker(() => picked.future);
    final controller = SlideEditorController(
      presentation: PmlPresentation(
        slides: [PmlSlide(id: 256), PmlSlide(id: 257)],
      ),
      config: _config,
    );
    final key = await _host(tester, controller);
    await tester.runAsync(() async {
      picked = Completer<FilePickerResult?>();
      final pending = key.currentState!.perform(
        OfficeEditorAction.slidePicture,
      );
      controller.setActiveSlide(1);
      picked.complete(_result(_png(40, 20)));
      await pending;
    });
    expect(
      controller.presentation.slides.every((slide) => slide.shapes.isEmpty),
      isTrue,
    );
    expect(controller.isDirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final picture in [true, false]) {
    testWidgets(
      '${picture ? 'Picture' : 'Drawing'} history remains on its owning slide',
      (tester) async {
        FilePicker.platform = _Picker(() async => _result(_png(40, 20)));
        final controller = SlideEditorController(
          presentation: PmlPresentation(
            slides: [PmlSlide(id: 256), PmlSlide(id: 257)],
          ),
          config: _config,
        );
        final key = await _host(tester, controller);
        await _insert(
          tester,
          key,
          action: picture
              ? OfficeEditorAction.slidePicture
              : OfficeEditorAction.rectangle,
        );
        final original = controller.presentation.slides.first;
        expect(original.shapes, hasLength(1));
        controller.setActiveSlide(1);
        controller.undo();
        expect(original.shapes, isEmpty);
        expect(controller.slide.shapes, isEmpty);
        expect(controller.selected, isNull);
        controller.redo();
        expect(original.shapes, hasLength(1));
        expect(controller.slide.shapes, isEmpty);
        expect(controller.selected, isNull);
        // Independently inspect the owning package part after the history cycle.
        final archive = ZipDecoder().decodeBytes(controller.saveBytes());
        final element = picture ? 'pic' : 'sp';
        expect(
          _part(
            archive,
            'ppt/slides/slide1.xml',
          ).findAllElements(element, namespace: _p),
          hasLength(1),
        );
        expect(
          _part(
            archive,
            'ppt/slides/slide2.xml',
          ).findAllElements(element, namespace: _p),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
