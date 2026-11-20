// Explicit real-canvas producer. Does not regenerate test goldens.
// flutter test --no-pub tool/render_word_native_corpus.dart \
//   --dart-define=QUDS_WORD_LAYOUT_CORPUS=/absolute/corpus
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _corpus = String.fromEnvironment('QUDS_WORD_LAYOUT_CORPUS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture native Word reference corpus with the real WordCanvas', (
    tester,
  ) async {
    if (_corpus.isEmpty) {
      throw StateError('QUDS_WORD_LAYOUT_CORPUS is required.');
    }
    final cases =
        jsonDecode(File('$_corpus/manifest.json').readAsStringSync()) as List;
    if (cases.isEmpty) {
      throw StateError('Empty corpus cannot qualify rendering.');
    }
    await OfficeHostFonts.ensureRegistered();
    final results = <Object>[];
    for (final value in cases) {
      final entry = value as Map<String, dynamic>;
      final name = entry['name'] as String;
      if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(name)) {
        throw FormatException('Invalid fixture name: $name');
      }
      final family = entry['family'] as String;
      if (OfficeHostFonts.registeredFamily(family) == null) {
        await OfficeHostFonts.registerFamily(
          family: family,
          faces: [
            ByteData.sublistView(
              File(entry['font'] as String).readAsBytesSync(),
            ),
          ],
        );
      }
      final document = WordDeserializer().readBytes(
        File('$_corpus/$name.docx').readAsBytesSync(),
      );
      final controller = WordEditorController(document: document);
      try {
        controller.fitPaintMetrics();
        final layout = controller.documentLaidOut;
        final pageResults = <Object>[];
        for (final page in layout.pages) {
          const scale = 2.0;
          final width = (page.width * scale).round();
          final height = (page.height * scale).round();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width + 142, height.toDouble());
          final viewport = VirtualViewport(
            origin: Offset(0, layout.pageStackTop(page.index, scale)),
            scale: 1.5,
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: const ValueKey('native-page'),
                child: WordCanvas(
                  document: document,
                  laidOut: layout,
                  caret: CaretEngine(),
                  viewport: viewport,
                  config: const OfficeSurfaceConfig(
                    mode: OfficeInteractionMode.viewing,
                    showRulers: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('native-page')),
          );
          await tester.runAsync(() async {
            final screenshot = await boundary.toImage();
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawImageRect(
              screenshot,
              Rect.fromLTWH(64, 0, width.toDouble(), height.toDouble()),
              Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
              Paint(),
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(width, height);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              File(
                '$_corpus/$name-flutter-${page.index + 1}.png',
              ).writeAsBytesSync(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
              picture.dispose();
              screenshot.dispose();
            }
          });
          pageResults.add({
            'width': page.width,
            'height': page.height,
            'lines': [
              for (final line in page.lines)
                {
                  'text': line.text,
                  'x': line.x,
                  'y': line.y,
                  'height': line.height,
                  'width': line.width,
                },
            ],
          });
        }
        results.add({
          'name': name,
          'requestedFamily': family,
          'referenceFontSha256': sha256
              .convert(File(entry['font'] as String).readAsBytesSync())
              .toString(),
          'resolvedFamily': OfficeHostFonts.registeredFamily(family),
          'pages': pageResults,
        });
      } finally {
        controller.dispose();
      }
    }
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    File('$_corpus/flutter-layout.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(results)}\n',
    );
  });
}
