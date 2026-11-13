import 'package:crisp_cloud/services/document_font_catalog.dart';
import 'package:crisp_cloud/services/document_fonts.dart';
import 'package:crisp_cloud/services/document_preview_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    show OfficeHostFonts;
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every shared face resolves to a real packaged embeddable font',
    () async {
      final bytes = await DocumentFonts.loadExportFaces();
      expect(
        documentFontAssets.map((face) => face.asset).toSet().length,
        bytes.length,
      );
      final fonts = [for (final value in bytes) SfntFont.parse(value)];
      for (var i = 0; i < fonts.length; i++) {
        expect(
          fonts[i].hasTable('glyf'),
          isTrue,
          reason: documentFontAssets[i].asset,
        );
        expect(fonts[i].numGlyphs, greaterThan(100));
        expect(documentPreviewFonts[i].asset, documentFontAssets[i].asset);
      }
      for (final cp in 'AΩЖאع'.runes) {
        expect(
          fonts.any((font) => font.glyphIdFor(cp) != 0),
          isTrue,
          reason: 'Bundled script coverage U+${cp.toRadixString(16)}',
        );
      }
      expect(documentFontFamily('Calibri'), 'Carlito');
      expect(documentFontFamily('Georgia'), 'Georgia');
      expect(documentFontFamily('Aptos'), 'Aptos');
    },
  );

  test(
    'first preview registration selects the actual family and style aliases',
    () async {
      await Future.wait([
        DocumentFonts.ensureRegistered(),
        DocumentFonts.ensureRegistered(),
      ]);
      expect(
        OfficeHostFonts.registeredFamily('Calibri', italic: true),
        'Carlito',
      );
      expect(
        OfficeHostFonts.registeredFamily('Arial', italic: true),
        'Liberation Sans',
      );
      expect(
        OfficeHostFonts.registeredFamily('Times New Roman', italic: true),
        'Liberation Serif',
      );
      expect(OfficeHostFonts.registeredFamily('Roboto'), 'Roboto');
      expect(OfficeHostFonts.registeredFamily('Roboto', italic: true), isNull);
      expect(OfficeHostFonts.registeredFamily('Georgia'), isNull);
      expect(
        OfficeHostFonts.registeredFamily('Noto Naskh Arabic'),
        'Noto Naskh Arabic',
      );
    },
  );
}
