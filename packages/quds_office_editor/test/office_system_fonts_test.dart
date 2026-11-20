import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/office_system_font_validation.dart';
import 'package:quds_office_editor/src/embed/office_system_fonts_io.dart'
    as installed;

import 'support/installed_font_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory primary;
  late Directory fallback;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('quds-installed-fonts-');
    primary = await Directory('${temporary.path}/primary').create();
    fallback = await Directory('${temporary.path}/fallback').create();
  });
  tearDown(() => temporary.delete(recursive: true));

  test('missing optional directories produce an empty collection', () async {
    expect(
      await installed.load(searchDirectories: ['${temporary.path}/missing']),
      isEmpty,
    );
  });

  test(
    'unreadable candidates and mismatched metadata do not hide later valid faces',
    () async {
      final arial = await installedFontFixture('Arial');
      final aptos = await installedFontFixture('Aptos');
      await Directory('${primary.path}/Arial.ttf').create();
      await File('${primary.path}/Aptos.ttf').writeAsBytes(arial);
      await File('${fallback.path}/Arial.ttf').writeAsBytes(arial);
      await File('${fallback.path}/Aptos.ttf').writeAsBytes(aptos);
      final faces = await installed.load(
        searchDirectories: [primary.path, fallback.path],
      );
      expect(faces.map((face) => face.family), ['Arial', 'Aptos']);
      expect(faces.first.bytes, orderedEquals(arial));
      expect(faces.last.bytes, orderedEquals(aptos));
    },
  );

  test(
    'collection signatures and malformed bytes are rejected despite ttf names',
    () async {
      final valid = await installedFontFixture('Arial');
      await File(
        '${primary.path}/Arial.ttf',
      ).writeAsBytes([0x74, 0x74, 0x63, 0x66, ...List.filled(20, 0)]);
      await File(
        '${primary.path}/Calibri.ttf',
      ).writeAsBytes([0, 1, 0, 0, ...List.filled(20, 0)]);
      await File('${fallback.path}/Arial.ttf').writeAsBytes(valid);
      final faces = await installed.load(
        searchDirectories: [primary.path, fallback.path],
      );
      expect(faces, hasLength(1));
      expect(faces.single.family, 'Arial');
      expect(faces.single.bytes, orderedEquals(valid));
    },
  );

  test(
    'oversized optional files are skipped before reading their body',
    () async {
      final huge = await File(
        '${primary.path}/Arial.ttf',
      ).open(mode: FileMode.write);
      await huge.writeFrom([0, 1, 0, 0]);
      await huge.truncate(maxInstalledFontBytes + 1);
      await huge.close();
      final valid = await installedFontFixture('Arial');
      await File('${fallback.path}/Arial.ttf').writeAsBytes(valid);
      final faces = await installed.load(
        searchDirectories: [primary.path, fallback.path],
      );
      expect(faces, hasLength(1));
      expect(faces.single.bytes, orderedEquals(valid));
    },
  );

  test(
    'installed Franklin Gothic Book regular and italic are discovered',
    () async {
      final regular = await installedFontFixture('Franklin Gothic Book');
      final italic = await installedFontFixture(
        'Franklin Gothic Book',
        file: 'LiberationMono-Italic.ttf',
      );
      await File(
        '${primary.path}/Franklin Gothic Book.ttf',
      ).writeAsBytes(regular);
      await File(
        '${primary.path}/Franklin Gothic Book Italic.ttf',
      ).writeAsBytes(italic);
      final faces = await installed.load(searchDirectories: [primary.path]);
      expect(faces.map((face) => (face.family, face.weight, face.italic)), [
        ('Franklin Gothic Book', 400, false),
        ('Franklin Gothic Book', 400, true),
      ]);
    },
  );

  test('first valid family and style wins with real style metadata', () async {
    final arial = await installedFontFixture('Arial');
    final differentArial = await installedFontFixture(
      'Arial',
      file: 'LiberationSerif-Regular.ttf',
    );
    final bold = await installedFontFixture(
      'Arial',
      file: 'LiberationMono-Bold.ttf',
    );
    final italic = await installedFontFixture(
      'Arial',
      file: 'LiberationMono-Italic.ttf',
    );
    await File('${primary.path}/Arial.ttf').writeAsBytes(arial);
    await File('${fallback.path}/Arial.ttf').writeAsBytes(differentArial);
    // The filename says italic, but its real style is regular: do not reserve it.
    await File('${primary.path}/Arial Italic.ttf').writeAsBytes(arial);
    await File('${primary.path}/Arial Bold.ttf').writeAsBytes(bold);
    await File('${fallback.path}/Arial Italic.ttf').writeAsBytes(italic);
    final faces = await installed.load(
      searchDirectories: [primary.path, fallback.path],
    );
    expect(faces.map((face) => (face.weight, face.italic)), [
      (400, false),
      (700, false),
      (400, true),
    ]);
    expect(faces.first.bytes, orderedEquals(arial));
    expect(faces.last.bytes, orderedEquals(italic));
  });

  test(
    'direct validation rejects wrong family, unsupported headers and truncated tables',
    () async {
      final valid = await installedFontFixture('Arial');
      expect(parseInstalledFont('Arial', valid)?.font.familyName, 'Arial');
      expect(parseInstalledFont('Calibri', valid), isNull);
      expect(parseInstalledFont('Arial\u0000', valid), isNull);
      expect(
        parseInstalledFont('Arial', Uint8List.sublistView(valid, 0, 100)),
        isNull,
      );
      final unsupported = Uint8List.fromList(valid)
        ..setRange(0, 4, [0x4f, 0x54, 0x54, 0x4f]);
      expect(parseInstalledFont('Arial', unsupported), isNull);
    },
  );
}
