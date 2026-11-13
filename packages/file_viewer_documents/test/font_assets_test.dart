// SPDX-License-Identifier: MIT
import 'package:file_viewer_documents/src/hosts/font_assets.dart';
import 'package:file_viewer_documents/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const regular = DocumentPreviewFont(
    asset: 'packages/office/fonts/LiberationSans-Regular.ttf',
    family: 'Liberation Sans',
    aliases: ['Arial', 'Helvetica', 'sans-serif'],
  );
  const boldItalic = DocumentPreviewFont(
    asset: 'packages/office/fonts/LiberationSans-BoldItalic.ttf',
    family: 'Liberation Sans',
    weight: 700,
    italic: true,
  );

  test(
    'snapshots bounded family/style descriptors without copying font data',
    () {
      final aliases = ['Calibri'];
      final configured = [
        regular,
        boldItalic,
        DocumentPreviewFont(
          asset: 'assets/fonts/Carlito-Regular.ttf',
          family: 'Carlito',
          aliases: aliases,
        ),
      ];
      final fonts = snapshotDocumentPreviewFonts(configured);
      aliases.add('Unexpected');
      configured.clear();
      expect(fonts, hasLength(3));
      expect(fonts.last.aliases, ['Calibri']);
      expect(() => fonts.clear(), throwsUnsupportedError);
      expect(() => fonts.last.aliases.add('Other'), throwsUnsupportedError);
      expect(fonts[1].weight, 700);
      expect(fonts[1].italic, isTrue);
    },
  );

  test(
    'rejects URLs, traversal, escaped paths and non-font asset programs',
    () {
      for (final asset in [
        '',
        'font.ttf',
        'private/font.ttf',
        '/assets/font.ttf',
        'https://example.invalid/font.ttf',
        'file:///assets/font.ttf',
        'assets/../private/font.ttf',
        'assets/./font.ttf',
        'assets//font.ttf',
        'assets/fonts%2ffont.ttf',
        'assets/fonts%252ffont.ttf',
        'assets/fonts\\font.ttf',
        'assets/fonts/font.ttf?download=1',
        'assets/fonts/font.ttf#face',
        'assets/fonts\n/font.ttf',
        'assets/fonts/font.ttf\n',
        'assets/fonts/font.ttf.js',
        'assets/${'a' * 510}.ttf',
      ]) {
        expect(isDocumentPreviewFontAsset(asset), isFalse, reason: asset);
        expect(
          () => snapshotDocumentPreviewFonts([
            DocumentPreviewFont(asset: asset, family: 'Example'),
          ]),
          throwsArgumentError,
          reason: asset,
        );
      }
      for (final extension in ['ttf', 'OTF', 'woff', 'woff2']) {
        expect(
          isDocumentPreviewFontAsset('assets/fonts/font.$extension'),
          isTrue,
        );
      }
    },
  );

  test('caps metadata and rejects duplicate styles or invalid weights', () {
    for (final descriptor in [
      const DocumentPreviewFont(asset: 'assets/font.ttf', family: ''),
      const DocumentPreviewFont(asset: 'assets/font.ttf', family: ' Padded'),
      const DocumentPreviewFont(asset: 'assets/font.ttf', family: 'Control\n'),
      DocumentPreviewFont(asset: 'assets/font.ttf', family: 'a' * 129),
      const DocumentPreviewFont(
        asset: 'assets/font.ttf',
        family: 'Family',
        aliases: [''],
      ),
      DocumentPreviewFont(
        asset: 'assets/font.ttf',
        family: 'Family',
        aliases: List.filled(17, 'Alias'),
      ),
      const DocumentPreviewFont(
        asset: 'assets/font.ttf',
        family: 'Family',
        weight: 99,
      ),
      const DocumentPreviewFont(
        asset: 'assets/font.ttf',
        family: 'Family',
        weight: 401,
      ),
      const DocumentPreviewFont(
        asset: 'assets/font.ttf',
        family: 'Family',
        weight: 1000,
      ),
    ]) {
      expect(
        () => snapshotDocumentPreviewFonts([descriptor]),
        throwsArgumentError,
      );
    }
    expect(
      () => snapshotDocumentPreviewFonts(List.filled(65, regular)),
      throwsArgumentError,
    );
    expect(
      () => snapshotDocumentPreviewFonts([regular, regular]),
      throwsArgumentError,
    );
  });

  test('web font URLs retain app base and never escape to another origin', () {
    for (final base in [
      Uri.parse('https://app.example/'),
      Uri.parse('https://app.example/nested/app/'),
      Uri.parse('http://localhost:8123/nested/app/index.html'),
    ]) {
      final fonts = documentWebFontDescriptors(base, [regular, boldItalic]);
      expect(fonts, hasLength(2));
      expect(fonts.first.keys.toSet(), {
        'family',
        'aliases',
        'weight',
        'italic',
        'url',
      });
      final url = Uri.parse(fonts.first['url'] as String);
      expect(url.origin, base.origin);
      expect(url, base.resolve('assets/${regular.asset}'));
      expect(url.hasQuery, isFalse);
      expect(url.hasFragment, isFalse);
      expect(fonts.last['weight'], 700);
      expect(fonts.last['italic'], isTrue);
    }
    for (final base in [
      Uri.parse('file:///app/'),
      Uri.parse('data:text/plain,test'),
      Uri.parse('/app/'),
      Uri.parse('https://user:password@app.example/'),
    ]) {
      expect(
        () => documentWebFontDescriptors(base, [regular]),
        throwsArgumentError,
      );
    }
  });

  test('host overrides font URLs only on the begin envelope', () {
    final resolved = documentWebFontDescriptors(
      Uri.parse('https://app.example/'),
      [regular],
    );
    final begin = <String, dynamic>{
      'type': 'begin',
      'fonts': [
        {'url': 'https://untrusted.invalid/font.ttf'},
      ],
    };
    expect(documentHostMessageWithFonts(begin, resolved)['fonts'], resolved);
    expect(
      (begin['fonts'] as List).single['url'],
      contains('untrusted.invalid'),
    );
    final chunk = <String, dynamic>{'type': 'chunk', 'data': 'AAAA'};
    expect(
      identical(documentHostMessageWithFonts(chunk, resolved), chunk),
      isTrue,
    );
  });

  test('PS, XML and CHM retain their own font environments', () {
    for (final kind in DocumentPreviewKind.values) {
      expect(
        documentPreviewUsesSharedFonts(kind),
        {
          DocumentPreviewKind.ppt,
          DocumentPreviewKind.spreadsheet,
          DocumentPreviewKind.wordperfect,
        }.contains(kind),
      );
    }
  });
}
