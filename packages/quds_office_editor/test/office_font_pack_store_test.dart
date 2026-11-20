import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test(
    'reads, verifies and removes an installed pack from app support',
    () async {
      final root = await Directory.systemTemp.createTemp('font-pack-test-');
      final bytes = utf8.encode('test-font-bytes');
      final pack = OfficeFontPack(
        id: 'test-pack',
        title: 'Test pack',
        description: 'Test only',
        source: 'test',
        licence: 'OFL',
        licenceUrl: 'https://openfontlicense.org/',
        baseUrl: 'https://example.invalid',
        bytes: bytes.length,
        files: <OfficeFontPackFile>[
          OfficeFontPackFile(
            fileName: 'Test-Regular.ttf',
            family: 'Test Family',
            sha256: sha256.convert(bytes).toString(),
            bytes: bytes.length,
          ),
        ],
      );
      try {
        final directory = Directory('${root.path}/${pack.id}');
        await directory.create();
        await File('${directory.path}/Test-Regular.ttf').writeAsBytes(bytes);
        await File('${directory.path}/.installed.json').writeAsString(
          jsonEncode(<String, Object>{
            'version': 1,
            'pack': pack.id,
            'files': <String>['Test-Regular.ttf'],
          }),
        );
        final store = OfficeFontPackStore(
          root.path,
          packs: <OfficeFontPack>[pack],
        );
        final status = (await store.statuses()).firstWhere(
          (item) => item.pack.id == pack.id,
        );
        expect(status.installed, isTrue);
        expect(status.problem, isNull);
        expect(status.bytesOnDisk, bytes.length);
        final faces = await store.loadInstalled();
        expect(faces.single.family, 'Test Family');
        expect(faces.single.bytes, bytes);
        await store.remove(pack);
        expect(directory.existsSync(), isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('does not load a face whose bytes fail verification', () async {
    final root = await Directory.systemTemp.createTemp('font-pack-test-');
    final bytes = utf8.encode('test-font-bytes');
    final pack = OfficeFontPack(
      id: 'test-pack',
      title: 'Test pack',
      description: 'Test only',
      source: 'test',
      licence: 'OFL',
      licenceUrl: 'https://openfontlicense.org/',
      baseUrl: 'https://example.invalid',
      bytes: bytes.length,
      files: <OfficeFontPackFile>[
        OfficeFontPackFile(
          fileName: 'Test-Regular.ttf',
          family: 'Test Family',
          sha256: sha256.convert(utf8.encode('different')).toString(),
          bytes: bytes.length,
        ),
      ],
    );
    try {
      final directory = Directory('${root.path}/${pack.id}');
      await directory.create();
      await File('${directory.path}/Test-Regular.ttf').writeAsBytes(bytes);
      await File('${directory.path}/.installed.json').writeAsString(
        jsonEncode(<String, Object>{
          'version': 1,
          'pack': pack.id,
          'files': <String>['Test-Regular.ttf'],
        }),
      );
      final store = OfficeFontPackStore(
        root.path,
        packs: <OfficeFontPack>[pack],
      );
      expect(
        (await store.statuses())
            .firstWhere((item) => item.pack.id == pack.id)
            .installed,
        isTrue,
      );
      expect(await store.loadInstalled(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
