import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/office_system_font_validation.dart';

import 'support/installed_font_fixture.dart';

double _paintWidth(String family, {bool italic = false}) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'mmmmWW',
      style: TextStyle(
        fontFamily: family,
        fontSize: 24,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );
  try {
    painter.layout();
    return painter.width;
  } finally {
    painter.dispose();
  }
}

Future<Uint8List> _diagramPixels(String family) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PaintOfficeVisual.paint(
    canvas,
    const Rect.fromLTWH(0, 0, 360, 180),
    OfficeVisual(
      kind: OfficeVisualKind.diagramProcess,
      title: 'mmmmWW',
      points: const [ChartPoint(label: 'mmmmWW', value: 1)],
    ),
    fontFamily: family,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 180);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test(
    'installed alias moves actual paint and metrics together exactly once',
    () async {
      final regular = await installedFontFixture('Arial');
      final italic = await installedFontFixture(
        'Arial',
        file: 'LiberationMono-Italic.ttf',
      );
      final faces = [
        ByteData.sublistView(regular),
        ByteData.sublistView(italic),
      ];
      expect(OfficeHostFonts.registeredFamily('Arial'), 'Liberation Sans');
      final beforePaint = PaintRunText.familyFor(
        text: 'mmmmWW',
        runFamily: 'Arial',
      );
      final beforeWidth = _paintWidth(beforePaint);
      final previousMetric = OfficeHostFonts.wordMetrics(
        65,
        24,
        WmlRunProps(asciiFont: 'Arial'),
      )!;
      final before = OfficeHostFonts.registrationRevision;

      // The original generic extension API intentionally refuses alias takeover.
      await expectLater(
        OfficeHostFonts.registerFamily(
          family: 'Arial',
          faces: faces,
          hasItalic: true,
        ),
        throwsStateError,
      );
      expect(OfficeHostFonts.registrationRevision, before);
      await Future.wait([
        OfficeHostFonts.registerInstalledFamily(family: 'Arial', faces: faces),
        OfficeHostFonts.registerInstalledFamily(family: 'Arial', faces: faces),
      ]);
      expect(OfficeHostFonts.registrationRevision, before + 1);
      final paintName = PaintRunText.familyFor(
        text: 'mmmmWW',
        runFamily: 'Arial',
      );
      expect(paintName, startsWith('Quds Installed '));
      expect(
        OfficeHostFonts.registeredFamily('Arial', italic: true),
        paintName,
      );
      final metric = OfficeHostFonts.wordMetrics(
        65,
        24,
        WmlRunProps(asciiFont: 'Arial'),
      )!;
      final italicMetric = OfficeHostFonts.wordMetrics(
        65,
        24,
        WmlRunProps(asciiFont: 'Arial', italic: true),
      )!;
      expect(metric.font.bytes, orderedEquals(regular));
      expect(italicMetric.font.bytes, orderedEquals(italic));
      expect(identical(metric.font, previousMetric.font), isFalse);
      expect(
        _paintWidth(paintName),
        closeTo(_paintWidth('Liberation Mono'), 0.001),
      );
      expect(
        _paintWidth(paintName, italic: true),
        closeTo(_paintWidth('Liberation Mono', italic: true), 0.001),
      );
      expect((_paintWidth(paintName) - beforeWidth).abs(), greaterThan(1));
      expect(OfficeHostFonts.registeredFamily('Helvetica'), 'Liberation Sans');
      expect(
        OfficeHostFonts.registeredFamily('Times New Roman'),
        'Liberation Serif',
      );
      expect(
        OfficeHostFonts.registeredFamily('Courier New'),
        'Liberation Mono',
      );
      await OfficeHostFonts.ensureRegistered();
      expect(OfficeHostFonts.registeredFamily('Arial'), paintName);

      // Registration owns a snapshot of accepted bytes, not the caller's buffer.
      final accepted = metric.font.bytes.first;
      regular[0] ^= 0xff;
      expect(metric.font.bytes.first, accepted);
    },
  );

  test(
    'installed family cannot overwrite accepted bytes or custom host owners',
    () async {
      final replacement = await installedFontFixture(
        'Arial',
        file: 'LiberationSerif-Regular.ttf',
      );
      final revision = OfficeHostFonts.registrationRevision;
      final family = OfficeHostFonts.registeredFamily('Arial');
      await expectLater(
        OfficeHostFonts.registerInstalledFamily(
          family: 'Arial',
          faces: [ByteData.sublistView(replacement)],
        ),
        throwsStateError,
      );
      expect(OfficeHostFonts.registeredFamily('Arial'), family);
      expect(OfficeHostFonts.registrationRevision, revision);

      final custom = await installedFontFixture('App Face');
      await OfficeHostFonts.registerFamily(
        family: 'App Face',
        faces: [ByteData.sublistView(custom)],
        aliases: ['Tahoma'],
      );
      final ownedRevision = OfficeHostFonts.registrationRevision;
      await expectLater(
        OfficeHostFonts.registerInstalledFamily(
          family: 'App Face',
          faces: [ByteData.sublistView(custom)],
        ),
        throwsStateError,
      );
      final tahoma = await installedFontFixture('Tahoma');
      await expectLater(
        OfficeHostFonts.registerInstalledFamily(
          family: 'Tahoma',
          faces: [ByteData.sublistView(tahoma)],
        ),
        throwsStateError,
      );
      expect(OfficeHostFonts.registeredFamily('Tahoma'), 'App Face');
      expect(OfficeHostFonts.registrationRevision, ownedRevision);
      await expectLater(
        OfficeHostFonts.registerFamily(
          family: 'Other',
          faces: [ByteData.sublistView(custom)],
          aliases: ['Arial'],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'new installed family preserves parsed styles and invalidates measured fallback',
    () async {
      final regular = await installedFontFixture('Aptos');
      final bold = await installedFontFixture(
        'Aptos',
        file: 'LiberationMono-Bold.ttf',
      );
      final props = WmlRunProps(asciiFont: 'Aptos');
      final beforeWidth = PaintRunText.advanceOf(0x6d, 24, props);
      final before = OfficeHostFonts.registrationRevision;
      await OfficeHostFonts.registerInstalledFamily(
        family: 'Aptos',
        faces: [ByteData.sublistView(regular), ByteData.sublistView(bold)],
      );
      final metric = OfficeHostFonts.wordMetrics(
        65,
        24,
        WmlRunProps(asciiFont: 'Aptos', bold: true),
      )!;
      expect(metric.font.bytes, orderedEquals(bold));
      expect(OfficeHostFonts.registeredFamily('Aptos', italic: true), isNull);
      expect(OfficeHostFonts.registrationRevision, before + 1);
      final afterWidth = PaintRunText.advanceOf(0x6d, 24, props);
      expect(
        afterWidth,
        closeTo(
          PaintRunText.advanceOf(
            0x6d,
            24,
            WmlRunProps(asciiFont: 'Liberation Mono'),
          ),
          0.001,
        ),
      );
      expect((afterWidth - beforeWidth).abs(), greaterThan(0.1));
    },
  );

  test(
    'invalid installed bytes, families and bounded collections retain fallback',
    () async {
      final regular = await installedFontFixture('Courier New');
      final valid = ByteData.sublistView(regular);
      final tooLarge = ByteData(maxInstalledFontBytes + 1);
      final boundedLarge = ByteData(maxInstalledFontBytes);
      final before = OfficeHostFonts.registrationRevision;
      final requests = <(String, List<ByteData>)>[
        ('', [valid]),
        ('x' * 257, [valid]),
        ('Courier\u0000New', [valid]),
        ('Courier New', []),
        ('Courier New', List.filled(17, valid)),
        ('Courier New', [tooLarge]),
        ('Courier New', List.filled(5, boundedLarge)),
        ('Courier New', [ByteData(8)]),
        (
          'Courier New',
          [
            ByteData.sublistView(
              Uint8List.fromList([
                0x74,
                0x74,
                0x63,
                0x66,
                ...List.filled(12, 0),
              ]),
            ),
          ],
        ),
        ('Times New Roman', [valid]),
        ('Courier New', [valid, valid]),
      ];
      for (final (family, faces) in requests) {
        await expectLater(
          OfficeHostFonts.registerInstalledFamily(family: family, faces: faces),
          throwsArgumentError,
          reason: family,
        );
      }
      expect(
        OfficeHostFonts.registeredFamily('Courier New'),
        'Liberation Mono',
      );
      expect(
        OfficeHostFonts.registeredFamily('Times New Roman'),
        'Liberation Serif',
      );
      expect(OfficeHostFonts.registrationRevision, before);
    },
  );

  test(
    'pending authored names cannot be reused as internal paint names',
    () async {
      final warmup = await installedFontFixture('Warmup');
      await OfficeHostFonts.registerInstalledFamily(
        family: 'Warmup',
        faces: [ByteData.sublistView(warmup)],
      );
      final current = int.parse(
        OfficeHostFonts.registeredFamily('Warmup')!.split(' ').last,
      );
      final requested = 'Quds Installed ${current + 2}';
      final named = await installedFontFixture(
        requested,
        file: 'LiberationSerif-Regular.ttf',
      );
      final other = await installedFontFixture('Calibri');
      await Future.wait([
        OfficeHostFonts.registerInstalledFamily(
          family: requested,
          faces: [ByteData.sublistView(named)],
        ),
        OfficeHostFonts.registerInstalledFamily(
          family: 'Calibri',
          faces: [ByteData.sublistView(other)],
        ),
      ]);
      final namedPaint = PaintRunText.familyFor(
        text: 'mmmmWW',
        runFamily: requested,
      );
      final otherPaint = PaintRunText.familyFor(
        text: 'mmmmWW',
        runFamily: 'Calibri',
      );
      expect(namedPaint, isNot(otherPaint));
      expect(namedPaint, isNot(requested));
      expect(otherPaint, isNot(requested));
      expect(
        OfficeHostFonts.wordMetrics(
          65,
          24,
          WmlRunProps(asciiFont: requested),
        )!.font.bytes,
        orderedEquals(named),
      );
      expect(
        _paintWidth(namedPaint),
        closeTo(_paintWidth('Liberation Serif'), 0.001),
      );
      expect(
        _paintWidth(otherPaint),
        closeTo(_paintWidth('Liberation Mono'), 0.001),
      );
    },
  );

  test(
    'visual labels use installed paint bytes for their authored family',
    () async {
      final font = await installedFontFixture('Visual Face');
      await OfficeHostFonts.registerInstalledFamily(
        family: 'Visual Face',
        faces: [ByteData.sublistView(font)],
      );
      final registered = OfficeHostFonts.registeredFamily('Visual Face')!;
      final actual = await _diagramPixels('Visual Face');
      final reference = await _diagramPixels(registered);
      expect(actual, orderedEquals(reference));
      expect(
        actual,
        isNot(orderedEquals(await _diagramPixels('Liberation Sans'))),
      );
    },
  );

  test(
    'visual labels preserve families registered directly with Flutter',
    () async {
      const family = 'Direct Visual Face';
      final loader = FontLoader(family);
      for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
        loader.addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSerif-$style.ttf',
          ),
        );
      }
      await loader.load();
      expect(OfficeHostFonts.registeredFamily(family), isNull);
      expect(OfficeHostFonts.paintFamily(family), family);
      expect(
        await _diagramPixels(family),
        orderedEquals(await _diagramPixels('Liberation Serif')),
      );
    },
  );

  test('pending internal paint names reject authored ownership', () async {
    final seed = await installedFontFixture('Reserve Seed');
    await OfficeHostFonts.registerInstalledFamily(
      family: 'Reserve Seed',
      faces: [ByteData.sublistView(seed)],
    );
    final sequence = int.parse(
      OfficeHostFonts.registeredFamily('Reserve Seed')!.split(' ').last,
    );
    final reserved = 'Quds Installed ${sequence + 1}';
    final owner = await installedFontFixture('Reserve Owner');
    final collision = await installedFontFixture(
      reserved,
      file: 'LiberationSerif-Regular.ttf',
    );
    // The first load reserves an internal paint name before Flutter has
    // finished accepting its bytes. A simultaneous authored name cannot take it.
    final loadingOwner = OfficeHostFonts.registerInstalledFamily(
      family: 'Reserve Owner',
      faces: [ByteData.sublistView(owner)],
    );
    final conflicting = OfficeHostFonts.registerInstalledFamily(
      family: reserved,
      faces: [ByteData.sublistView(collision)],
    );
    await Future.wait([
      loadingOwner,
      expectLater(conflicting, throwsStateError),
    ]);
    expect(OfficeHostFonts.registeredFamily('Reserve Owner'), reserved);
    expect(OfficeHostFonts.registeredFamily(reserved), reserved);
    expect(
      OfficeHostFonts.wordMetrics(
        65,
        24,
        WmlRunProps(asciiFont: 'Reserve Owner'),
      )!.font.bytes,
      orderedEquals(owner),
    );
  });
}
