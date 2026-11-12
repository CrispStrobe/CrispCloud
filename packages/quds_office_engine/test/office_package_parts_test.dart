import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _strict = 'http://purl.oclc.org/ooxml/officeDocument/relationships';

String _root(String body) =>
    '<Relationships xmlns="$_pr">$body</Relationships>';
String _rel(String id, String type, String target, {bool external = false}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

OfficePackageParts _parts(Map<String, String> parts) =>
    OfficePackageParts((name) => parts[name]);

void main() {
  test(
    'native owners resolve package-root and nested relationship members',
    () {
      expect(OfficePackageParts.relationshipPath(''), '_rels/.rels');
      expect(OfficePackageParts.relationshipPath('/'), '_rels/.rels');
      expect(
        OfficePackageParts.relationshipPath('main.xml'),
        '_rels/main.xml.rels',
      );
      expect(
        OfficePackageParts.relationshipPath('/office/text/main.xml'),
        'office/text/_rels/main.xml.rels',
      );
      for (final owner in [
        '../main.xml',
        r'office\main.xml',
        'a/../main.xml',
      ]) {
        expect(
          () => OfficePackageParts.relationshipPath(owner),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'relative, absolute and encoded targets retain exact native OPC keys',
    () async {
      final reads = <String>[];
      final navigator = OfficePackageParts((name) {
        reads.add(name);
        return name == 'office/text/_rels/main.xml.rels'
            ? _root(
                _rel('h', '$_r/header', '../stories/header.xml') +
                    _rel('n', '$_strict/footnotes', '/notes.xml') +
                    _rel('s', '$_r/footer', '../stories/footer%20draft.xml'),
              )
            : null;
      });
      final relationships = await navigator.relationships(
        'office/text/main.xml',
      );
      expect(relationships.map((relation) => relation.path), [
        'office/stories/header.xml',
        'notes.xml',
        'office/stories/footer%20draft.xml',
      ]);
      expect(relationships[0].isType('header'), isTrue);
      expect(relationships[1].isType('footnotes'), isTrue);
      expect(relationships[1].isType('header'), isFalse);
      // Resolving a relationship never fetches its target, external or otherwise.
      expect(reads, ['office/text/_rels/main.xml.rels']);
    },
  );

  test(
    'external, escaping and URI suffix targets cannot resolve inside package',
    () async {
      final targets = [
        '../../outside.xml',
        '%2e%2e/%2e%2e/outside.xml',
        r'..\outside.xml',
        '%5coutside.xml',
        'https://example.invalid/story.xml',
        '//example.invalid/story.xml',
        '%2f%2fexample.invalid/story.xml',
        'header.xml?variant=1',
        'header.xml#fragment',
        '%00story.xml',
      ];
      final navigator = _parts({
        'word/_rels/document.xml.rels': _root(
          _rel('external', '$_r/header', 'local.xml', external: true) +
              [
                for (var i = 0; i < targets.length; i++)
                  _rel('$i', '$_r/header', targets[i]),
              ].join(),
        ),
      });
      expect(await navigator.relationships('word/document.xml'), isEmpty);
    },
  );

  test('foreign relationship roots reject without canonical fallback', () async {
    final navigator = _parts({
      '_rels/.rels':
          '<Relationships xmlns="urn:foreign">'
          '${_rel('main', '$_r/officeDocument', 'other.xml')}</Relationships>',
    });
    await expectLater(
      navigator.mainPart('word/document.xml'),
      throwsFormatException,
    );
    await expectLater(
      navigator.mainPartOrNull(fallback: 'word/document.xml'),
      throwsFormatException,
    );
  });

  test(
    'foreign, nested and namespaced-attribute decoys do not select parts',
    () async {
      final navigator = _parts({
        '_rels/.rels': _root(
          '<x:Relationship xmlns:x="urn:foreign" Id="foreign" '
          'Type="$_r/officeDocument" Target="foreign.xml"/>'
          '<Extension>${_rel('nested', '$_r/officeDocument', 'nested.xml')}</Extension>'
          '<Relationship xmlns:x="urn:foreign" x:Id="attribute" '
          'x:Type="$_r/officeDocument" x:Target="attribute.xml"/>',
        ),
      });
      expect(await navigator.relationships(''), isEmpty);
      expect(
        await navigator.mainPartOrNull(fallback: 'word/document.xml'),
        isNull,
      );
      await expectLater(
        navigator.mainPart('word/document.xml'),
        throwsFormatException,
      );
    },
  );

  test(
    'duplicate relationship IDs reject before a target can be selected',
    () async {
      final navigator = _parts({
        '_rels/.rels': _root(
          _rel('same', '$_r/officeDocument', 'first.xml') +
              _rel('same', '$_r/officeDocument', 'second.xml'),
        ),
      });
      await expectLater(navigator.relationships(''), throwsFormatException);
      await expectLater(
        navigator.mainPart('word/document.xml'),
        throwsFormatException,
      );
    },
  );

  for (final external in [false, true]) {
    test(
      'multiple declared main owners reject with external=$external',
      () async {
        final navigator = _parts({
          '_rels/.rels': _root(
            _rel('one', '$_r/officeDocument', 'first.xml') +
                _rel(
                  'two',
                  '$_strict/officeDocument',
                  'second.xml',
                  external: external,
                ),
          ),
        });
        await expectLater(
          navigator.mainPart('word/document.xml'),
          throwsFormatException,
        );
        await expectLater(navigator.mainPartOrNull(), throwsFormatException);
      },
    );
  }

  test(
    'canonical fallback is available only when package metadata is absent',
    () async {
      expect(
        await _parts({}).mainPart('word/document.xml'),
        'word/document.xml',
      );
      for (final body in [
        '',
        _rel('main', '$_r/officeDocument', '../../outside.xml'),
        _rel('main', '$_r/officeDocument', 'external.xml', external: true),
      ]) {
        final navigator = _parts({'_rels/.rels': _root(body)});
        expect(
          await navigator.mainPartOrNull(fallback: 'word/document.xml'),
          isNull,
        );
        await expectLater(
          navigator.mainPart('word/document.xml'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'a declared relocated Strict main part wins over canonical names',
    () async {
      final navigator = _parts({
        '_rels/.rels': _root(
          _rel('main', '$_strict/officeDocument', 'content/main.xml'),
        ),
      });
      expect(await navigator.mainPart('word/document.xml'), 'content/main.xml');
    },
  );

  final malformed = <String, String>{
    'unclosed root': '<root>',
    'mismatched tags': '<root><child></root></child>',
    'multiple roots': '<first/><second/>',
    'dangling attribute': '<root value=',
    'document type':
        '<!DOCTYPE root [<!ENTITY text "hidden">]><root>&text;</root>',
    'outside text': 'unowned<root/>',
  };
  for (final entry in malformed.entries) {
    test('selected XML rejects ${entry.key}', () async {
      await expectLater(
        _parts({'part.xml': entry.value}).xml('part.xml'),
        throwsFormatException,
      );
    });
  }

  test(
    'selected XML retains whitespace runs and enforces a nesting limit',
    () async {
      final navigator = OfficePackageParts(
        (_) => '<root><run> </run><run><![CDATA[Visible]]></run></root>',
        maxXmlDepth: 2,
      );
      final document = (await navigator.xml('part.xml'))!;
      expect(document.root!.childrenNamed('run').map((node) => node.text), [
        ' ',
        'Visible',
      ]);
      await expectLater(
        OfficePackageParts(
          (_) => '<a><b><c/></b></a>',
          maxXmlDepth: 2,
        ).xml('part.xml'),
        throwsFormatException,
      );
      expect(
        () => OfficePackageParts((_) => null, maxXmlDepth: 0),
        throwsArgumentError,
      );
    },
  );
}
