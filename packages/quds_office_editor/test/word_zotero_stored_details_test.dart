import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_stored_details.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

ZoteroCitationItem _item(
  Map<String, Object?>? data, {
  Object id = 'offline-id',
  List<String> uris = const [],
}) => ZoteroCitationItem.fromJson({'id': id, 'uris': uris, 'itemData': ?data});

Map<String, String> _fields(ZoteroCitationItem item) => {
  for (final field in zoteroStoredReferenceDetailFields(item))
    field.$1: field.$2,
};

void main() {
  test('shows complete stored publication metadata and full creator names', () {
    final item = _item({
      'id': 'offline-id',
      'type': 'article-journal',
      'title': 'A <i>complete</i> study &amp; القدس',
      'author': [
        {'family': 'First'},
        {'family': 'Second'},
        {
          'given': 'Amal',
          'dropping-particle': 'van',
          'non-dropping-particle': 'der',
          'family': 'Hassan',
          'suffix': 'Jr.',
        },
        {'literal': 'Research Council 東京'},
      ],
      'editor': [
        {'given': 'Léa', 'family': 'Moreau'},
      ],
      'container-title': '<b>Journal of Research</b>',
      'collection-title': 'Complete <i>Studies</i>',
      'edition': 2,
      'volume': 'XIV',
      'issue': 3,
      'page': '12–34',
      'issued': {
        'date-parts': [
          [2026, 3, 6],
        ],
      },
      'publisher': 'Research &amp; Press',
      'publisher-place': 'Berlin',
      'DOI': '10.1234/δοκιμή',
      'URL': 'https://example.test/research?x=1&y=2',
      'ISBN': '978-0-00-000000-0',
      'ISSN': '1234-5678',
      'language': 'ar',
      'abstract': 'A < B and C > D; <b>literal stored markup</b>.',
    });

    final fields = _fields(item);

    expect(fields['Title'], 'A complete study & القدس');
    expect(
      fields['Authors'],
      'First\nSecond\nAmal van der Hassan Jr.\nResearch Council 東京',
    );
    expect(fields['Editors'], 'Léa Moreau');
    expect(fields['Reference type'], 'article-journal');
    expect(fields['Publication'], 'Journal of Research');
    expect(fields['Collection'], 'Complete Studies');
    expect(fields['Edition'], '2');
    expect(fields['Volume'], 'XIV');
    expect(fields['Issue'], '3');
    expect(fields['Pages'], '12–34');
    expect(fields['Issued date'], '2026-03-06');
    expect(fields['Publisher'], 'Research & Press');
    expect(fields['Publisher place'], 'Berlin');
    expect(fields['DOI'], '10.1234/δοκιμή');
    expect(fields['URL'], 'https://example.test/research?x=1&y=2');
    expect(fields['ISBN'], '978-0-00-000000-0');
    expect(fields['ISSN'], '1234-5678');
    expect(fields['Language'], 'ar');
    expect(fields['Reference ID'], 'offline-id');
    expect(fields['Source linkage'], 'Embedded source only');
    expect(
      fields['Abstract'],
      'A < B and C > D; <b>literal stored markup</b>.',
    );
  });

  test('includes every supplied CSL creator role without truncation', () {
    const roles = [
      'author',
      'chair',
      'collection-editor',
      'compiler',
      'composer',
      'container-author',
      'contributor',
      'curator',
      'director',
      'editor',
      'editor-translator',
      'editorial-director',
      'executive-producer',
      'guest',
      'host',
      'illustrator',
      'interviewer',
      'narrator',
      'organizer',
      'original-author',
      'performer',
      'producer',
      'recipient',
      'reviewed-author',
      'script-writer',
      'series-creator',
      'translator',
    ];
    final item = _item({
      'title': 'Many creators',
      for (final role in roles)
        role: [
          {'literal': 'First $role'},
          {'literal': 'Second $role'},
          {'literal': 'Third $role'},
        ],
    });

    final values = _fields(item).values;

    for (final role in roles) {
      expect(
        values,
        contains('First $role\nSecond $role\nThird $role'),
        reason: role,
      );
    }
  });

  test('retains date ranges and each stored literal date representation', () {
    final fields = _fields(
      _item({
        'title': 'Collected works',
        'issued': {
          'date-parts': [
            ['1998', '2', '3'],
            [2000, 11],
          ],
          'literal': 'Winter 1998 to autumn 2000',
          'raw': '1998-02-03/2000-11',
          'season': 1,
          'circa': true,
        },
      }),
    );

    expect(fields['Issued date'], '1998-02-03 – 2000-11');
    expect(fields['Issued date (literal)'], 'Winter 1998 to autumn 2000');
    expect(fields['Issued date (raw)'], '1998-02-03/2000-11');
    expect(fields['Issued season'], '1');
    expect(fields['Approximate date'], 'Yes');
  });

  test('does not invent missing date precision or a modern year', () {
    for (final (issued, label, expected) in <(Object, String, String)>[
      (
        {
          'date-parts': [
            [-44],
          ],
        },
        'Issued date',
        '-44',
      ),
      (
        {
          'date-parts': [
            [2026, 3],
          ],
        },
        'Issued date',
        '2026-03',
      ),
      ({'literal': 'forthcoming'}, 'Issued date (literal)', 'forthcoming'),
      ({'raw': '2026~'}, 'Issued date (raw)', '2026~'),
      ('2026-03/2026-05', 'Issued date', '2026-03/2026-05'),
    ]) {
      expect(_fields(_item({'issued': issued}))[label], expected);
    }
  });

  test('missing snapshot remains inspectable by its existing identity', () {
    final item = _item(null, id: 17);

    expect(_fields(item), {
      'Title': '17',
      'Reference ID': '17',
      'Source linkage': 'Embedded source only',
    });
    expect(item.itemData, isNull);
  });

  test('malformed optional values are skipped while valid names survive', () {
    final item = _item({
      'title': {'unexpected': true},
      'type': false,
      'author': [
        null,
        false,
        ['not a name'],
        {'literal': '', 'family': 'Valid family'},
        {'family': 7, 'given': false},
        {'literal': 'Institution', 'family': 'Unused family'},
      ],
      'editor': {'family': 'Wrong shape'},
      'translator': 'Wrong shape',
      'container-title': ['Wrong shape'],
      'edition': true,
      'volume': {'value': 7},
      'DOI': ['Wrong shape'],
      'URL': false,
      'ISBN': 17,
      'ISSN': null,
      'abstract': {'unexpected': 'data'},
      'issued': {'season': <Object?>[], 'circa': 'unknown'},
    });

    expect(_fields(item), {
      'Title': 'offline-id',
      'Authors': 'Valid family\nInstitution',
      'Reference ID': 'offline-id',
      'Source linkage': 'Embedded source only',
    });
  });

  test('malformed date ranges are not displayed as a partial single date', () {
    for (final parts in <Object>[
      '2026',
      <Object>[],
      [2026],
      [
        [2026],
        <Object>[],
      ],
      [
        [2026],
        [2027, false],
      ],
      [
        [2026, 3, 6, 12],
      ],
      [
        [2026],
        [2027],
        [2028],
      ],
    ]) {
      final fields = _fields(
        _item({
          'issued': {'date-parts': parts, 'literal': 'Source supplied date'},
        }),
      );
      expect(fields.containsKey('Issued date'), isFalse, reason: '$parts');
      expect(fields['Issued date (literal)'], 'Source supplied date');
    }
  });

  test(
    'shows every linked and opaque URI without inventing linked identity',
    () {
      const local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
      const synced = 'https://www.zotero.org/users/42/items/ABCD1234';
      const opaque = 'opaque:original-uri';
      final item = _item(
        {
          'id': 'stored-csl-id',
          'title': 'Aliased reference',
          'uri': opaque,
          'uris': [synced, opaque, 17, local, 'javascript:alert("inert")'],
        },
        id: 'citation-id',
        uris: [local, synced, local, 'opaque:citation-uri'],
      );
      final before = jsonEncode(item.toJson());

      final fields = _fields(item);

      expect(fields['Reference ID'], 'citation-id');
      expect(fields['Stored CSL ID'], 'stored-csl-id');
      expect(fields['Zotero links'], '$local\n$synced');
      expect(
        fields['Stored URI metadata'],
        'opaque:citation-uri\n$opaque\njavascript:alert("inert")',
      );
      expect(fields.containsKey('Source linkage'), isFalse);
      expect(jsonEncode(item.toJson()), before);
    },
  );

  test('URI-shaped stored data alone does not promote an offline source', () {
    const unlinked = 'https://zotero.org/users/42/items/ABCD1234';
    const otherHost = 'https://example.test/users/42/items/ABCD1234';
    final fields = _fields(
      _item(
        {
          'uri': unlinked,
          'uris': [otherHost],
        },
        uris: ['opaque:unrecognized'],
      ),
    );

    expect(fields['Source linkage'], 'Embedded source only');
    expect(fields.containsKey('Zotero links'), isFalse);
    expect(
      fields['Stored URI metadata'],
      'opaque:unrecognized\n$unlinked\n$otherHost',
    );
  });

  test(
    'copy is readable source metadata and leaves citation state untouched',
    () {
      final item = ZoteroCitationItem.fromJson({
        'id': 7,
        'itemData': {
          'id': 7,
          'title': '<script>not a title</script><i>Stored title</i>',
          'type': 'book',
          'author': [
            {'literal': 'Name <with literal text>'},
          ],
          'abstract': 'A < B and C > D\n<script>inert stored text</script>',
          'custom': {'unknown': true},
        },
        'locator': '19–23',
        'label': 'page',
        'prefix': 'see also',
        'suffix': 'and following',
        'suppress-author': true,
        'citation-custom': [1, 2, 3],
      });
      final before = jsonEncode(item.toJson());

      final text = zoteroStoredReferenceDetailsText(item);

      expect(text, contains('Title: Stored title'));
      expect(text, contains('Authors: Name <with literal text>'));
      expect(text, contains('Reference ID: 7'));
      expect(
        text,
        contains(
          'Abstract: A < B and C > D\n<script>inert stored text</script>',
        ),
      );
      for (final excluded in [
        'not a title',
        '19–23',
        'see also',
        'and following',
        'suppress-author',
        'citation-custom',
        'unknown',
      ]) {
        expect(text, isNot(contains(excluded)), reason: excluded);
      }
      expect(jsonEncode(item.toJson()), before);
      final fields = zoteroStoredReferenceDetailFields(item);
      expect(() => fields.add(('Edited', 'No')), throwsUnsupportedError);
    },
  );
}
