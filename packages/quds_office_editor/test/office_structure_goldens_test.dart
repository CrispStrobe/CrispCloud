import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import '../../quds_office_engine/tool/fidelity/word_steps.dart' as steps;

const _fixtures = '../quds_office_engine/test/fixtures/fidelity';

WmlDocument _authoredSource() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        File('$_fixtures/word_structure_source.xml').readAsStringSync(),
      );
  return WordDeserializer().read(package);
}

void _applyPhase(WmlDocument document, String phase) {
  final script = File('$_fixtures/scripts/word-structure-$phase.json');
  final values = jsonDecode(script.readAsStringSync()) as List;
  for (final value in values) {
    steps.applyStep(
      document,
      Map<String, Object?>.from(value as Map),
      assetDirectory: script.absolute.parent.path,
    );
  }
}

// Decode asynchronously rather than blessing an image-loading placeholder as a
// golden. The authored PNG is RGB (11, 177, 59), distinct from text and borders.
Future<void> _waitForPicture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('structure-page')),
  );
  var painted = false;
  for (var attempt = 0; attempt < 100 && !painted; attempt++) {
    painted =
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final ByteData pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          var matchedPixels = 0;
          for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
            final r = pixels.getUint8(offset);
            final g = pixels.getUint8(offset + 1);
            final b = pixels.getUint8(offset + 2);
            if ((r - 11).abs() <= 2 &&
                (g - 177).abs() <= 2 &&
                (b - 59).abs() <= 2) {
              matchedPixels++;
            }
          }
          if (matchedPixels >= 100) return true;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return false;
        }) ??
        false;
    await tester.pumpAndSettle();
  }
  expect(painted, isTrue, reason: 'Authored picture pixels must be visible');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);
  for (final phase in ['create', 'edit', 'remove']) {
    testWidgets('$phase structure matches reviewed pages through three saves', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1120);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var document = _authoredSource();
      for (final prior in ['create', 'edit', 'remove']) {
        _applyPhase(document, prior);
        if (prior == phase) break;
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
      for (var cycle = 0; cycle < 4; cycle++) {
        final laid = WordLayoutEngine(font: null).layout(document);
        expect(laid.pages.length, phase == 'edit' ? 2 : 1);
        for (var page = 0; page < laid.pages.length; page++) {
          final selected = laid.pages[page];
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: const ValueKey('structure-page'),
                child: WordCanvas(
                  document: document,
                  laidOut: LaidOutDocument(
                    pages: [selected],
                    pageSize: WmlPageSize(
                      width: selected.width,
                      height: selected.height,
                    ),
                  ),
                  caret: CaretEngine(),
                  config: OfficeSurfaceConfig(
                    mode: OfficeInteractionMode.viewing,
                    theme: OfficeTheme.light.copyWith(fontFamily: 'Arial'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (phase == 'create') await _waitForPicture(tester);
          await expectLater(
            find.byKey(const ValueKey('structure-page')),
            matchesGoldenFile('goldens/structure_${phase}_${page + 1}.png'),
            reason: '$phase cycle $cycle page ${page + 1}',
          );
        }
        if (cycle < 3) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
    });
  }
}
