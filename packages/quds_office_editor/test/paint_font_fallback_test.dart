import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('unloaded document fonts use explicit bundled paint fallbacks', () {
    for (final family in ['Calibri', 'Carlito', 'Roboto', 'Missing Face']) {
      expect(OfficeHostFonts.registeredFamily(family), isNull);
      expect(
        PaintRunText.familyFor(text: 'Example', runFamily: family),
        'Liberation Sans',
      );
    }
    expect(
      PaintRunText.familyFor(text: 'مرحبا', runFamily: 'Missing Face'),
      'Noto Naskh Arabic',
    );
  });

  test('registered document faces keep their requested names', () {
    expect(
      PaintRunText.familyFor(text: 'Example', runFamily: 'Times New Roman'),
      'Times New Roman',
    );
    expect(
      PaintRunText.familyFor(text: 'Example', runFamily: 'Arial'),
      'Arial',
    );
  });
}
