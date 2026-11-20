import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Word pagination uses actual registered face and style metrics',
    () async {
      await OfficeHostFonts.ensureRegistered();
      final regular = OfficeHostFonts.wordMetrics(
        65,
        12,
        WmlRunProps(asciiFont: 'Arial'),
      )!;
      final bold = OfficeHostFonts.wordMetrics(
        65,
        12,
        WmlRunProps(asciiFont: 'Arial', bold: true),
      )!;
      final italic = OfficeHostFonts.wordMetrics(
        65,
        12,
        WmlRunProps(asciiFont: 'Arial', italic: true),
      )!;
      expect(regular.typographicLineHeight, closeTo(13.798828125, 0.0001));
      expect(identical(regular.font, bold.font), isFalse);
      expect(identical(regular.font, italic.font), isFalse);
      expect(
        OfficeHostFonts.wordMetrics(
          65,
          double.nan,
          WmlRunProps(asciiFont: 'Arial'),
        ),
        isNull,
      );
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(
          spacingBefore: 0,
          spacingAfter: 0,
          lineSpacing: 1,
        ),
        inlines: [
          WmlRun(
            text: List.filled(45, 'A line').join('\n'),
            properties: WmlRunProps(asciiFont: 'Arial', fontSizeHalfPoints: 24),
          ),
        ],
      );
      final doc = WmlDocument(
        sections: [
          WmlSection(
            pageSize: WmlPageSize(width: 612, height: 792),
            margins: const WmlPageMargins(
              top: 72,
              bottom: 72,
              left: 72,
              right: 72,
            ),
            blocks: [paragraph],
          ),
        ],
      );
      final controller = WordEditorController(document: doc);
      try {
        controller.fitPaintMetrics();
        expect(controller.documentLaidOut.pages, hasLength(1));
        expect(controller.documentLaidOut.pages.single.lines, hasLength(45));
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'bundled names resolve only verified metric-compatible aliases',
    () async {
      await OfficeHostFonts.ensureRegistered();
      await OfficeHostFonts.ensureRegistered();
      expect(
        OfficeHostFonts.registeredFamily('Arial', italic: true),
        'Liberation Sans',
      );
      expect(
        OfficeHostFonts.registeredFamily('Times New Roman'),
        'Liberation Serif',
      );
      expect(
        OfficeHostFonts.registeredFamily('Courier New'),
        'Liberation Mono',
      );
      expect(
        OfficeHostFonts.registeredFamily('Noto Naskh Arabic'),
        'Noto Naskh Arabic',
      );
      expect(
        OfficeHostFonts.registeredFamily('Noto Naskh Arabic', italic: true),
        isNull,
      );
      for (final family in ['Calibri', 'Carlito', 'Roboto', 'Georgia']) {
        expect(
          OfficeHostFonts.registeredFamily(family),
          isNull,
          reason: '$family must not claim unrelated Liberation font metrics',
        );
      }
    },
  );

  test(
    'host bytes and aliases register once and remain available after ensure',
    () async {
      final faces = [
        await rootBundle.load(
          'packages/quds_office_editor/fonts/LiberationSerif-Regular.ttf',
        ),
        await rootBundle.load(
          'packages/quds_office_editor/fonts/LiberationSerif-Italic.ttf',
        ),
      ];
      await Future.wait([
        OfficeHostFonts.registerFamily(
          family: 'Host Serif',
          faces: faces,
          aliases: ['Host Document Face'],
          hasItalic: true,
        ),
        OfficeHostFonts.registerFamily(
          family: 'Host Serif',
          faces: faces,
          aliases: ['Host Document Face'],
          hasItalic: true,
        ),
      ]);
      await OfficeHostFonts.ensureRegistered();
      expect(OfficeHostFonts.registeredFamily('Host Serif'), 'Host Serif');
      expect(
        OfficeHostFonts.registeredFamily('host document face', italic: true),
        'Host Serif',
      );
      await OfficeHostFonts.registerFamily(
        family: 'Host Serif',
        faces: faces,
        aliases: ['Another Document Alias'],
        hasItalic: true,
      );
      expect(
        OfficeHostFonts.registeredFamily('Another Document Alias'),
        'Host Serif',
      );
    },
  );

  test('host extensions cannot replace an existing alias', () async {
    final regular = await rootBundle.load(
      'packages/quds_office_editor/fonts/LiberationMono-Regular.ttf',
    );
    await expectLater(
      OfficeHostFonts.registerFamily(
        family: 'Other Family',
        faces: [regular],
        aliases: ['Arial'],
      ),
      throwsStateError,
    );
    expect(OfficeHostFonts.registeredFamily('Arial'), 'Liberation Sans');
  });

  test('empty or unbounded host requests fail before font loading', () async {
    await expectLater(
      OfficeHostFonts.registerFamily(family: '', faces: []),
      throwsArgumentError,
    );
    await expectLater(
      OfficeHostFonts.registerFamily(family: 'Empty', faces: []),
      throwsArgumentError,
    );
    await expectLater(
      OfficeHostFonts.registerFamily(family: 'x' * 257, faces: []),
      throwsArgumentError,
    );
  });

  test(
    'late font registration invalidates widths measured with a fallback',
    () async {
      await OfficeHostFonts.ensureRegistered();
      const family = 'Late Width Serif';
      final props = WmlRunProps(asciiFont: family);
      final fallbackWidth = PaintRunText.advanceOf(0x6d, 24, props);
      final before = OfficeHostFonts.registrationRevision;
      final regular = await rootBundle.load(
        'packages/quds_office_editor/fonts/LiberationSerif-Regular.ttf',
      );
      await OfficeHostFonts.registerFamily(family: family, faces: [regular]);
      expect(OfficeHostFonts.registrationRevision, greaterThan(before));
      final registeredWidth = PaintRunText.advanceOf(0x6d, 24, props);
      final referenceWidth = PaintRunText.advanceOf(
        0x6d,
        24,
        WmlRunProps(asciiFont: 'Liberation Serif'),
      );
      expect(registeredWidth, closeTo(referenceWidth, 0.001));
      expect((registeredWidth - fallbackWidth).abs(), greaterThan(0.1));

      final registeredRevision = OfficeHostFonts.registrationRevision;
      await OfficeHostFonts.registerFamily(family: family, faces: [regular]);
      expect(OfficeHostFonts.registrationRevision, registeredRevision);
      await expectLater(
        OfficeHostFonts.registerFamily(family: '', faces: [regular]),
        throwsArgumentError,
      );
      expect(OfficeHostFonts.registrationRevision, registeredRevision);
    },
  );
}
