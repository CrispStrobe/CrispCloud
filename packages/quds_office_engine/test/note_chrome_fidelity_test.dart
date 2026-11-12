import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _chromeTypes = {
  'separator',
  'continuationSeparator',
  'continuationNotice',
};

List<XmlElement> _chrome(XmlElement root) => root.childElements
    .where(
      (node) =>
          node.namespaceUri == OfficeNamespaces.w &&
          _chromeTypes.contains(
            node.getAttribute('type', namespaceUri: OfficeNamespaces.w),
          ),
    )
    .toList();

Object _semantic(XmlElement node, {bool fragmentRoot = true}) => {
  'name': [node.namespaceUri, node.localName],
  'attributes': {
    for (final attr in node.attributes)
      if (attr.prefix != 'xmlns' &&
          attr.qualifiedName != 'xmlns' &&
          !(fragmentRoot &&
              (attr.namespaceUri == OfficeNamespaces.xml ||
                  attr.namespaceUri == OfficeNamespaces.mc)))
        '{${attr.namespaceUri}}${attr.localName}': attr.value,
  },
  'children': [
    for (final child in node.children)
      if (child is XmlElement)
        _semantic(child, fragmentRoot: false)
      else if (child is XmlText)
        child.text,
  ],
};

String _authoredNotes(
  String kind, {
  required bool chrome,
  String prefix = 'w',
}) {
  String tag(String name) => prefix.isEmpty ? name : '$prefix:$name';
  final attributePrefix = prefix == 'w' ? 'w' : 'q';
  final namespace = prefix == 'w'
      ? 'xmlns:w="${OfficeNamespaces.w}"'
      : 'xmlns:q="${OfficeNamespaces.w}" xmlns:w="urn:foreign:word-prefix"'
            '${prefix.isEmpty ? ' xmlns="${OfficeNamespaces.w}"' : ''}';
  String attr(String name, String value) => '$attributePrefix:$name="$value"';
  final definitions = StringBuffer();
  if (chrome) {
    for (final entry in [
      ('separator', '-1', 'separator'),
      ('continuationSeparator', '0', 'continuationSeparator'),
      ('continuationNotice', '-2', null),
    ]) {
      definitions.write(
        '<${tag(kind)} ${attr('type', entry.$1)} ${attr('id', entry.$2)} '
        'ext:identity="${entry.$1}"'
        '${entry.$1 == 'continuationNotice' ? ' xml:lang="en-US"' : ''}>'
        '<${tag('p')}><${tag('pPr')}><${tag('spacing')} '
        '${attr('before', '0')} ${attr('after', '40')}/></${tag('pPr')}>'
        '<${tag('r')}><${tag('rPr')}><${tag('color')} '
        '${attr('val', '123456')}/></${tag('rPr')}>'
        '${entry.$3 == null ? '<${tag('t')}>Continued on next page</${tag('t')}>' : '<${tag(entry.$3!)}/>'}'
        '</${tag('r')}></${tag('p')}></${tag(kind)}>',
      );
    }
  }
  return '<${tag('${kind}s')} $namespace '
      'xmlns:mc="${OfficeNamespaces.mc}" xmlns:ext="urn:note-chrome-extension" '
      'xml:space="preserve" xml:lang="de-DE" mc:Ignorable="ext">'
      '$definitions'
      '<${tag(kind)} ${attr('id', '7')}><${tag('p')}>'
      '<${tag('r')}><${tag('${kind}Ref')}/></${tag('r')}>'
      '<${tag('r')}><${tag('t')}>Original note</${tag('t')}></${tag('r')}>'
      '</${tag('p')}></${tag(kind)}></${tag('${kind}s')}>';
}

OpcPackage _source(bool endnote, String notesXml, {bool relocated = false}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final package = OpcPackage.create(OpcPackageKind.word);
  final target = relocated ? 'notes/native-${kind}s.xml' : '${kind}s.xml';
  package.createPart(
    '/word/$target',
    endnote
        ? OfficeContentTypes.wordEndnotes
        : OfficeContentTypes.wordFootnotes,
    utf8.encode(notesXml),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type: endnote
            ? RelationshipTypes.endnotes
            : RelationshipTypes.footnotes,
        target: target,
      );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
        '<w:r><w:t>Body</w:t></w:r><w:r><w:${kind}Reference w:id="7"/></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  return package;
}

Future<Uint8List> _save(WmlDocument document, bool isolate) => isolate
    ? OfficeIsolateSave.word(document)
    : Future.value(WordSerializer().writeBytes(document));

void main() {
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    for (final isolate in [false, true]) {
      final route = isolate ? 'isolate' : 'direct';
      test(
        '$kind absent separator definitions stay absent through $route saves',
        () async {
          var document = WordDeserializer().read(
            _source(endnote, _authoredNotes(kind, chrome: false)),
          );
          for (var cycle = 1; cycle <= 3; cycle++) {
            final bytes = await _save(document, isolate);
            final package = OpcPackage.openBytes(bytes);
            final root = XmlDocument.parse(
              package.getPart('/word/${kind}s.xml')!.readText(),
            ).root!;
            expect(_chrome(root), isEmpty);
            expect(root.childrenNamed(kind).length, 1);
            document = WordDeserializer().readBytes(bytes);
            final notes = endnote ? document.endnotes : document.footnotes;
            expect(notes.single.paragraphs.single.text, 'Original note');
          }
        },
      );

      for (final prefix in ['w', 'q', '']) {
        test(
          '$kind custom separators retain namespace context: $route/$prefix',
          () async {
            final source = _authoredNotes(kind, chrome: true, prefix: prefix);
            final expected = _chrome(
              XmlDocument.parse(source).root!,
            ).map(_semantic).toList();
            var document = WordDeserializer().read(
              _source(endnote, source, relocated: true),
            );
            for (var cycle = 1; cycle <= 3; cycle++) {
              final notes = endnote ? document.endnotes : document.footnotes;
              notes.single.paragraphs.single.inlines
                      .whereType<WmlRun>()
                      .single
                      .text =
                  'Edited note $cycle';
              final bytes = await _save(document, isolate);
              final package = OpcPackage.openBytes(bytes);
              final root = XmlDocument.parse(
                package.getPart('/word/notes/native-${kind}s.xml')!.readText(),
              ).root!;
              final retained = _chrome(root);
              expect(retained.map(_semantic).toList(), expected);
              for (final node in retained) {
                expect(
                  node.getAttribute(
                    'space',
                    namespaceUri: OfficeNamespaces.xml,
                  ),
                  'preserve',
                );
                expect(
                  node.getAttribute(
                    'Ignorable',
                    namespaceUri: OfficeNamespaces.mc,
                  ),
                  'ext',
                );
                expect(
                  node.getAttribute('lang', namespaceUri: OfficeNamespaces.xml),
                  node.getAttribute('type') == 'continuationNotice'
                      ? 'en-US'
                      : 'de-DE',
                );
              }
              // Source aliases and a foreign source `w` binding must stay local
              // to retained fragments; generated ordinary notes remain WordML.
              expect(root.namespaceUri, OfficeNamespaces.w);
              final ordinary = root.childElements.singleWhere(
                (node) =>
                    node.getAttribute('id', namespaceUri: OfficeNamespaces.w) ==
                    '7',
              );
              expect(ordinary.namespaceUri, OfficeNamespaces.w);
              expect(
                ordinary.firstChild('p')!.namespaceUri,
                OfficeNamespaces.w,
              );
              expect(ordinary.text, 'Edited note $cycle');
              document = WordDeserializer().readBytes(bytes);
            }
          },
        );
      }

      test(
        '$kind newly authored part gets one standard pair: $route',
        () async {
          var document = WmlDocument.empty(text: 'Body');
          WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: 'New note',
          );
          for (var cycle = 1; cycle <= 3; cycle++) {
            final bytes = await _save(document, isolate);
            final root = XmlDocument.parse(
              OpcPackage.openBytes(
                bytes,
              ).getPart('/word/${kind}s.xml')!.readText(),
            ).root!;
            final chrome = _chrome(root);
            expect(chrome.map((node) => node.getAttribute('type')), [
              'separator',
              'continuationSeparator',
            ]);
            expect(chrome.map((node) => node.getAttribute('id')), ['-1', '0']);
            expect(
              chrome[0]
                  .firstChild('p')!
                  .firstChild('r')!
                  .firstChild('separator'),
              isNotNull,
            );
            expect(
              chrome[1]
                  .firstChild('p')!
                  .firstChild('r')!
                  .firstChild('continuationSeparator'),
              isNotNull,
            );
            document = WordDeserializer().readBytes(bytes);
          }
        },
      );
    }
  }
}
