import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _r = OfficeNamespaces.r;
const _stories = [
  'header',
  'footer',
  'firstHeader',
  'firstFooter',
  'evenHeader',
  'evenFooter',
];

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

List<WmlParagraph> _story(WmlSection section, String story) => switch (story) {
  'header' => section.header,
  'footer' => section.footer,
  'firstHeader' => section.firstHeader,
  'firstFooter' => section.firstFooter,
  'evenHeader' => section.evenHeader,
  'evenFooter' => section.evenFooter,
  _ => throw ArgumentError(story),
};

OpcPackage _package({int count = 2}) {
  final document = WmlDocument(
    sections: [
      for (var index = 0; index < count; index++)
        WmlSection(
          blocks: [_paragraph('Body $index')],
          header: [_paragraph('Header $index')],
          footer: [_paragraph('Footer $index')],
          firstHeader: [_paragraph('First header $index')],
          firstFooter: [_paragraph('First footer $index')],
          evenHeader: [_paragraph('Even header $index')],
          evenFooter: [_paragraph('Even footer $index')],
          // Dormant first/even stories are still explicit editable stories.
          differentFirstPage: false,
          differentOddEven: false,
          linkToPrevious: false,
        ),
    ],
  );
  final package = OpcPackage.openBytes(WordSerializer().writeBytes(document));
  const macroType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
  package.getPart('/word/document.xml')!.contentType = macroType;
  package.contentTypes.setOverride('/word/document.xml', macroType);
  package.createPart(
    '/word/vbaProject.bin',
    'application/vnd.ms-office.vbaProject',
    Uint8List.fromList([0, 1, 7, 255, 48, 66]),
  );
  package.createPart(
    '/custom/untouched.bin',
    'application/octet-stream',
    Uint8List.fromList([9, 0, 255, 16]),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        type:
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
        target: 'vbaProject.bin',
      );
  return package;
}

List<XmlElement> _sections(XmlElement root) {
  final body = root.firstChild('body', namespaceUri: _w)!;
  return [
    for (final child in body.childElements)
      if (child.localName == 'sectPr' && child.namespaceUri == _w)
        child
      else if (child.localName == 'p' && child.namespaceUri == _w) ...[
        for (final pPr in child.childrenNamed('pPr', namespaceUri: _w))
          ...pPr.childrenNamed('sectPr', namespaceUri: _w),
      ],
  ];
}

XmlElement _reference(XmlElement root, int section, String story) {
  final header = story.toLowerCase().endsWith('header');
  final type = story.startsWith('first')
      ? 'first'
      : story.startsWith('even')
      ? 'even'
      : 'default';
  return _sections(root)[section]
      .childrenNamed(
        header ? 'headerReference' : 'footerReference',
        namespaceUri: _w,
      )
      .singleWhere(
        (value) => value.getAttribute('type', namespaceUri: _w) == type,
      );
}

void _editDocument(OpcPackage package, void Function(XmlElement) edit) {
  final part = package.getPart('/word/document.xml')!;
  final root = XmlDocument.parse(part.readText()).root!;
  edit(root);
  part.writeText(XmlDocument(root: root).toXmlString());
}

PackagePart _storyPart(OpcPackage package, int section, String story) {
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final id = _reference(
    root,
    section,
    story,
  ).getAttribute('id', namespaceUri: _r)!;
  final rels = package.relationshipsFor('/word/document.xml');
  return package.getPart(rels.resolve(rels.byId(id)!))!;
}

void _removeReference(OpcPackage package, int section, String story) =>
    _editDocument(package, (root) {
      final reference = _reference(root, section, story);
      reference.parent!.children.remove(reference);
    });

Map<String, Object?> _step(String story, {int section = 0}) => {
  'op': 'replaceText',
  'section': section,
  'story': story,
  'paragraph': 0,
  'text': 'Changed $story',
};

List<Object?> _state(WmlDocument document) => [
  document.paragraphs.map((paragraph) => paragraph.text).toList(),
  for (final section in document.sections)
    [
      section.differentFirstPage,
      section.differentOddEven,
      for (final story in _stories)
        [
          for (final paragraph in _story(section, story))
            [
              paragraph.text,
              paragraph.properties.justification.name,
              for (final run in paragraph.inlines.whereType<WmlRun>())
                [run.text, run.properties.bold, run.properties.italic],
            ],
        ],
    ],
];

void _refuses(
  WmlDocument document, {
  String story = 'header',
  int section = 0,
  Map<String, Object?>? operation,
}) {
  final before = _state(document);
  final sources = document.sections
      .map((value) => value.sourceProperties)
      .toList();
  final package = document.package;
  final parts = {
    if (package != null)
      for (final name in package.partNames)
        name: package.getPart(name)!.readBytes(),
  };
  expect(
    () =>
        native.applyStep(document, operation ?? _step(story, section: section)),
    throwsUnsupportedError,
  );
  expect(_state(document), before);
  for (final (index, value) in document.sections.indexed) {
    expect(value.sourceProperties, same(sources[index]));
  }
  if (package != null) {
    expect({
      for (final name in package.partNames)
        name: package.getPart(name)!.readBytes(),
    }, parts);
  }
}

void main() {
  for (final story in _stories) {
    test('$story edits one independent dormant story through DOCM reopens', () {
      var document = WordDeserializer().read(_package());
      final original = _state(document);
      native.applyStep(document, _step(story));
      native.applyStep(document, {
        'op': 'runFormat',
        'section': 0,
        'story': story,
        'paragraph': 0,
        'bold': true,
      });
      final target = _story(document.sections[0], story).single;
      expect(target.text, 'Changed $story');
      expect(target.inlines.whereType<WmlRun>().single.properties.bold, isTrue);
      final changed = _state(document);
      expect(changed, isNot(original));
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final package = OpcPackage.openBytes(bytes);
        expect(package.getPart('/word/vbaProject.bin')!.readBytes(), [
          0,
          1,
          7,
          255,
          48,
          66,
        ]);
        expect(package.getPart('/custom/untouched.bin')!.readBytes(), [
          9,
          0,
          255,
          16,
        ]);
        expect(
          package.getPart('/word/document.xml')!.contentType,
          'application/vnd.ms-word.document.macroEnabled.main+xml',
        );
        document = WordDeserializer().read(package);
        expect(_state(document), changed);
      }
      expect(document.paragraphs.map((value) => value.text), [
        'Body 0',
        'Body 1',
      ]);
      for (var index = 0; index < document.sections.length; index++) {
        for (final other in _stories) {
          if (index == 0 && other == story) continue;
          expect(
            (_state(document)[index + 1] as List)[_stories.indexOf(other) + 2],
            (original[index + 1] as List)[_stories.indexOf(other) + 2],
          );
        }
      }
    });
  }

  test('native namespace aliases select the same independent story', () {
    final package = _package();
    for (final part in package.parts.toList()) {
      if (!part.contentType.endsWith('+xml')) continue;
      final text = package.getPart(part.uri)!.readText();
      part.writeText(
        text
            .replaceAll('xmlns:w=', 'xmlns:q=')
            .replaceAll('w:', 'q:')
            .replaceAll('xmlns:r=', 'xmlns:rel=')
            .replaceAll('r:', 'rel:'),
      );
    }
    final document = WordDeserializer().read(package);
    native.applyStep(document, _step('firstFooter', section: 1));
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(reopened.sections[1].firstFooter.single.text, 'Changed firstFooter');
    expect(reopened.sections[0].firstFooter.single.text, 'First footer 0');
  });

  test('new source-free native stories remain editable', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [_paragraph('Body')],
          header: [_paragraph('Authored')],
        ),
      ],
    );
    native.applyStep(document, _step('header'));
    expect(document.sections.single.header.single.text, 'Changed header');
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    expect(reopened.sections.single.header.single.text, 'Changed header');
  });

  test(
    'a new in-memory native story is independent when no source family exists',
    () {
      final document = WordDeserializer().readBytes(
        (DocxDocumentBuilder()..paragraph('Body')).build(),
      );
      document.sections.single.header.add(_paragraph('Authored'));
      native.applyStep(document, _step('header'));
      native.applyStep(document, {
        'op': 'lineSpacing',
        'story': 'header',
        'paragraph': 0,
        'section': 0,
        'rule': 'multiple',
        'points': 30,
      });
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(reopened.sections.single.header.single.text, 'Changed header');
      expect(
        reopened.sections.single.header.single.properties.lineSpacing,
        2.5,
      );
    },
  );

  for (final story in _stories) {
    test('$story refuses later implicit inheritance before mutation', () {
      final package = _package();
      _removeReference(package, 1, story);
      _refuses(WordDeserializer().read(package), story: story);
    });
    test('$story refuses a missing selected reference before mutation', () {
      final package = _package();
      _removeReference(package, 0, story);
      _refuses(WordDeserializer().read(package), story: story);
    });
  }

  for (final alias in [false, true]) {
    test(
      'shared part ownership refuses ${alias ? 'canonical target aliases' : 'duplicate direct targets'}',
      () {
        final package = _package();
        _editDocument(package, (root) {
          final source = _reference(root, 0, 'header');
          final rid = source.getAttribute('id', namespaceUri: _r)!;
          var targetId = rid;
          if (alias) {
            final rels = package.relationshipsFor('/word/document.xml');
            final existing = rels.byId(rid)!;
            targetId = rels
                .add(
                  type: RelationshipTypes.header,
                  target: './${existing.target}',
                )
                .id;
          }
          _reference(
            root,
            1,
            'header',
          ).setAttribute('id', targetId, prefix: 'r', namespaceUri: _r);
        });
        _refuses(WordDeserializer().read(package));
      },
    );
  }

  test('a direct part shared by two variants is refused', () {
    final package = _package();
    _editDocument(package, (root) {
      final id = _reference(
        root,
        0,
        'header',
      ).getAttribute('id', namespaceUri: _r)!;
      _reference(
        root,
        0,
        'firstHeader',
      ).setAttribute('id', id, prefix: 'r', namespaceUri: _r);
    });
    _refuses(WordDeserializer().read(package));
  });

  for (final mutation in [
    'duplicate reference',
    'duplicate type',
    'missing type',
    'foreign id',
    'unknown type',
  ]) {
    test('$mutation is refused without changing native content', () {
      final package = _package();
      _editDocument(package, (root) {
        final reference = _reference(root, 0, 'header');
        switch (mutation) {
          case 'duplicate reference':
            reference.parent!.addChild(reference.copy());
          case 'duplicate type':
            reference.attributes.add(
              XmlAttribute(
                localName: 'type',
                value: 'default',
                prefix: 'w',
                namespaceUri: _w,
              ),
            );
          case 'missing type':
            reference.removeAttribute('type', namespaceUri: _w);
          case 'foreign id':
            final id = reference.getAttribute('id', namespaceUri: _r)!;
            reference.removeAttribute('id', namespaceUri: _r);
            reference.setAttribute(
              'id',
              id,
              prefix: 'x',
              namespaceUri: 'urn:foreign',
            );
            reference.setAttribute('x', 'urn:foreign', prefix: 'xmlns');
          case 'unknown type':
            reference.setAttribute(
              'type',
              'odd',
              prefix: 'w',
              namespaceUri: _w,
            );
        }
      });
      _refuses(WordDeserializer().read(package));
    });
  }

  for (final mutation in [
    'missing',
    'wrong type',
    'external',
    'duplicate ID',
    'escaped target',
  ]) {
    test('$mutation relationship is refused before paragraph mutation', () {
      final package = _package();
      final part = _storyPart(package, 0, 'header');
      final rels = package.relationshipsFor('/word/document.xml');
      final original = rels.items.singleWhere(
        (value) => rels.resolve(value) == part.uri,
      );
      if (mutation == 'duplicate ID') {
        final extra =
            '<Relationship Id="${original.id}" Type="${original.type}" Target="${original.target}"/>';
        package.attachRelationships(
          '/word/document.xml',
          RelationshipCollection.parse(
            rels.toXml().replaceFirst(
              '</Relationships>',
              '$extra</Relationships>',
            ),
            '/word/document.xml',
          ),
        );
      } else {
        rels.removeById(original.id);
        if (mutation != 'missing') {
          rels.add(
            id: original.id,
            type: mutation == 'wrong type'
                ? RelationshipTypes.footer
                : original.type,
            target: mutation == 'escaped target'
                ? original.target.replaceFirst('header', '%68eader')
                : original.target,
            targetMode: mutation == 'external'
                ? RelationshipTargetMode.external
                : RelationshipTargetMode.internal,
          );
        }
      }
      _refuses(WordDeserializer().read(package));
    });
  }

  test('source/model section references must still agree', () {
    final document = WordDeserializer().read(_package());
    final source = document.sections[1].sourceProperties!;
    document.sections[0].sourceProperties = source;
    _refuses(document);
  });

  test(
    'shared paragraph model identities are refused even without a source package',
    () {
      final paragraph = _paragraph('Shared');
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [_paragraph('Body')],
            header: [paragraph],
            footer: [paragraph],
          ),
        ],
      );
      _refuses(document);
    },
  );

  for (final structure in [
    'table',
    'alternate',
    'processContent',
    'opaque control',
  ]) {
    test('$structure source story cannot masquerade as direct paragraphs', () {
      final package = _package();
      final part = _storyPart(package, 0, 'header');
      const paragraph = '<w:p><w:r><w:t>Header source</w:t></w:r></w:p>';
      final content = switch (structure) {
        'table' => '<w:tbl><w:tr><w:tc>$paragraph</w:tc></w:tr></w:tbl>',
        'alternate' =>
          '<mc:AlternateContent><mc:Choice Requires="w">$paragraph</mc:Choice>'
              '<mc:Fallback><w:p><w:r><w:t>Other source</w:t></w:r></w:p></mc:Fallback></mc:AlternateContent>',
        'opaque control' =>
          '<w:sdt><w:sdtPr><w:id w:val="441"/></w:sdtPr><w:sdtContent>'
              '<w:tbl><w:tr><w:tc>$paragraph</w:tc></w:tr></w:tbl></w:sdtContent></w:sdt>',
        _ => paragraph,
      };
      part.writeText(
        '<w:hdr xmlns:w="$_w" xmlns:x="urn:extension" xmlns:mc="${OfficeNamespaces.mc}" '
        '${structure == 'processContent' ? 'mc:ProcessContent="x:story"' : ''}>$content</w:hdr>',
      );
      _refuses(WordDeserializer().read(package));
    });
  }

  test(
    'unrelated opaque story content and payloads survive an independent edit',
    () {
      final package = _package();
      _storyPart(package, 1, 'firstFooter').writeText(
        '<w:ftr xmlns:w="$_w"><w:sdt><w:sdtPr><w:id w:val="991"/>'
        '<w:tag w:val="Untouched"/></w:sdtPr><w:sdtContent><w:tbl>'
        '<w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid><w:tr><w:tc>'
        '<w:p><w:r><w:t>Opaque footer table</w:t></w:r></w:p>'
        '</w:tc></w:tr></w:tbl></w:sdtContent></w:sdt></w:ftr>',
      );
      var document = WordDeserializer().read(package);
      expect(document.sections[1].preservedStories, contains('firstFooter'));
      native.applyStep(document, _step('header'));
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = OpcPackage.openBytes(
          WordSerializer().writeBytes(document),
        );
        final xml = _storyPart(saved, 1, 'firstFooter').readText();
        expect(xml, contains('Opaque footer table'));
        expect(xml, contains('w:val="Untouched"'));
        expect(xml, contains('<w:tbl>'));
        expect(saved.getPart('/custom/untouched.bin')!.readBytes(), [
          9,
          0,
          255,
          16,
        ]);
        document = WordDeserializer().read(saved);
        expect(document.sections[0].header.single.text, 'Changed header');
      }
    },
  );

  test('serializer collision with an unrelated package part is refused', () {
    final package = _package(count: 1);
    final original = _storyPart(package, 0, 'header');
    final moved = package.createPart(
      '/word/directHeader.xml',
      original.contentType,
      original.readBytes(),
    );
    final rels = package.relationshipsFor('/word/document.xml');
    final relation = rels.items.singleWhere(
      (value) => rels.resolve(value) == original.uri,
    );
    rels.removeById(relation.id);
    rels.add(id: relation.id, type: relation.type, target: 'directHeader.xml');
    expect(moved.readBytes(), original.readBytes());
    original.writeText('<unrelated>Must not be overwritten</unrelated>');
    original.contentType = 'application/octet-stream';
    _refuses(WordDeserializer().read(package));
  });

  test('story part referenced by opaque unrelated content is refused', () {
    final package = _package();
    package
        .relationshipsFor('/custom/untouched.bin')
        .add(type: 'urn:custom:header', target: '../word/header1.xml');
    _refuses(WordDeserializer().read(package));
  });

  test(
    'failing story step rolls back earlier body work and recording',
    () async {
      final package = _package();
      _removeReference(package, 1, 'header');
      final source = package.save();
      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Rollback unsafe story');
      final plan = OfficeMacro(
        name: 'Rollback unsafe story',
        format: OfficeMacroFormat.docx,
        steps: [
          OfficeMacroStep(
            tool: 'docx.replaceText',
            arguments: {'paragraph': 0, 'text': 'Never publish'},
          ),
          OfficeMacroStep(
            tool: 'docx.replaceText',
            arguments: {
              'paragraph': 0,
              'story': 'header',
              'section': 0,
              'text': 'Never publish header',
            },
          ),
        ],
      );
      for (final validate in [true, false]) {
        await expectLater(
          validate ? session.validate(plan) : session.run(plan),
          throwsA(
            isA<OfficeMacroException>()
                .having((value) => value.code, 'code', 'operation_failed')
                .having((value) => value.stepIndex, 'stepIndex', 1),
          ),
        );
        expect(session.bytes, source);
        expect(session.revision, 0);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final kind in ['shared', 'inherited']) {
    test(
      'unselected $kind story rolls back an independent header edit',
      () async {
        final package = _package(count: 3);
        if (kind == 'inherited') {
          _removeReference(package, 2, 'evenFooter');
        } else {
          _editDocument(package, (root) {
            final id = _reference(
              root,
              1,
              'evenFooter',
            ).getAttribute('id', namespaceUri: _r)!;
            _reference(
              root,
              2,
              'evenFooter',
            ).setAttribute('id', id, prefix: 'r', namespaceUri: _r);
          });
        }
        _refuses(WordDeserializer().read(package));
        final input = package.save();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        session.startRecording('Refuse unrelated linkage changes');
        final plan = OfficeMacro(
          name: 'Independent header with unsafe sibling',
          format: OfficeMacroFormat.docx,
          steps: [
            OfficeMacroStep(
              tool: 'docx.replaceText',
              arguments: {'paragraph': 0, 'text': 'Body checkpoint'},
            ),
            OfficeMacroStep(
              tool: 'docx.runFormat',
              arguments: {
                'paragraph': 0,
                'story': 'header',
                'section': 0,
                'bold': false,
              },
            ),
          ],
        );
        for (final validate in [true, false]) {
          await expectLater(
            validate ? session.validate(plan) : session.run(plan),
            throwsA(
              isA<OfficeMacroException>().having(
                (value) => value.stepIndex,
                'stepIndex',
                1,
              ),
            ),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  test('unselected inherited source-free story is also refused', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [_paragraph('Body 0')],
          header: [_paragraph('H0')],
          evenFooter: [_paragraph('Inherited')],
        ),
        WmlSection(blocks: [_paragraph('Body 1')], header: [_paragraph('H1')]),
      ],
    );
    _refuses(document);
  });

  for (final alias in [
    'inline list',
    'paragraph properties',
    'run',
    'run properties',
  ]) {
    test('shared $alias cannot propagate a header edit into the body', () {
      final body = _paragraph('Body');
      final header = _paragraph('Header');
      switch (alias) {
        case 'inline list':
          header.inlines = body.inlines;
        case 'paragraph properties':
          header.properties = body.properties;
        case 'run':
          header.inlines = [body.inlines.single];
        case 'run properties':
          (header.inlines.single as WmlRun).properties =
              (body.inlines.single as WmlRun).properties;
      }
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [body], header: [header]),
        ],
      );
      _refuses(
        document,
        operation: {
          'op': 'runFormat',
          'section': 0,
          'story': 'header',
          'paragraph': 0,
          'bold': true,
        },
      );
      expect((body.inlines.single as WmlRun).properties.bold, isFalse);
    });
  }

  for (final selected in [true, false]) {
    for (final kind in [
      'foreign payload',
      'foreign run',
      'foreign text',
      'paragraph attribute',
      'run attribute',
      'root attribute',
      'native unknown',
      'field',
      'hyperlink',
    ]) {
      test(
        '${selected ? 'selected' : 'unselected'} $kind refuses before same-value formatting loses data',
        () async {
          final package = _package();
          final part = _storyPart(
            package,
            selected ? 0 : 1,
            selected ? 'header' : 'footer',
          );
          final tag = selected ? 'hdr' : 'ftr';
          final content = switch (kind) {
            'foreign payload' =>
              '<w:p><w:r><w:t>Keep</w:t></w:r><x:payload x:token="retain"/></w:p>',
            'foreign run' => '<w:p><x:r><x:t>Foreign text</x:t></x:r></w:p>',
            'foreign text' => '<w:p><w:r><x:t>Foreign text</x:t></w:r></w:p>',
            'paragraph attribute' =>
              '<w:p x:token="retain"><w:r><w:t>Keep</w:t></w:r></w:p>',
            'run attribute' =>
              '<w:p><w:r x:token="retain"><w:t>Keep</w:t></w:r></w:p>',
            'native unknown' =>
              '<w:p><w:r><w:t>Keep</w:t><w:unknown w:val="retain"/></w:r></w:p>',
            'field' =>
              '<w:p><w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p>',
            'hyperlink' =>
              '<w:p><w:hyperlink w:anchor="Target"><w:r><w:t>Keep</w:t></w:r></w:hyperlink></w:p>',
            _ => '<w:p><w:r><w:t>Keep</w:t></w:r></w:p>',
          };
          part.writeText(
            '<w:$tag xmlns:w="$_w" xmlns:x="urn:extension" '
            '${kind == 'root attribute' ? 'x:token="retain"' : ''}>$content</w:$tag>',
          );
          final document = WordDeserializer().read(package);
          _refuses(
            document,
            operation: {
              'op': 'runFormat',
              'section': 0,
              'story': 'header',
              'paragraph': 0,
              'bold': false,
            },
          );
          final input = package.save();
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          await expectLater(
            session.callTool('docx.runFormat', {
              'section': 0,
              'story': 'header',
              'paragraph': 0,
              'bold': false,
            }),
            throwsA(
              isA<OfficeMacroException>().having(
                (value) => value.code,
                'code',
                'operation_failed',
              ),
            ),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
        },
      );
    }
  }

  test(
    'native text, tabs, breaks and sparse property metadata remain supported',
    () {
      final package = _package();
      _storyPart(package, 0, 'header').writeText(
        '<w:hdr xmlns:w="$_w" xmlns:x="urn:extension"><w:p><w:pPr>'
        '<w:keepNext x:token="paragraph"/><x:paragraphMetadata x:token="keep"/>'
        '</w:pPr><w:r><w:rPr><w:color w:val="223344" x:token="color"/>'
        '<x:runMetadata x:token="keep"/></w:rPr><w:t xml:space="preserve">Keep </w:t>'
        '<w:tab/><w:t>tab</w:t><w:br/><w:t>line</w:t></w:r></w:p></w:hdr>',
      );
      var document = WordDeserializer().read(package);
      final before = document.sections.first.header.single.text;
      native.applyStep(document, {
        'op': 'runFormat',
        'section': 0,
        'story': 'header',
        'paragraph': 0,
        'bold': true,
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = OpcPackage.openBytes(
          WordSerializer().writeBytes(document),
        );
        final xml = _storyPart(saved, 0, 'header').readText();
        expect(xml, contains('paragraphMetadata'));
        expect(xml, contains('runMetadata'));
        expect(xml, contains('x:token="color"'));
        document = WordDeserializer().read(saved);
        expect(document.sections.first.header.single.text, before);
        native.applyStep(document, {
          'op': 'runFormat',
          'section': 0,
          'story': 'header',
          'paragraph': 0,
          'bold': true,
        });
      }
    },
  );

  test(
    'Unicode soft and nonbreaking hyphens remain editable after save and reopen',
    () {
      var document = WordDeserializer().read(_package());
      const text = 'Soft\u00adhyphen non\u2011breaking العربية 👩‍💻';
      for (var cycle = 0; cycle < 3; cycle++) {
        native.applyStep(document, {..._step('header'), 'text': text});
        final package = OpcPackage.openBytes(
          WordSerializer().writeBytes(document),
        );
        final xml = _storyPart(package, 0, 'header').readText();
        expect(xml, contains('softHyphen'));
        expect(xml, contains('noBreakHyphen'));
        document = WordDeserializer().read(package);
        expect(document.sections.first.header.single.text, text);
        native.applyStep(document, {
          'op': 'runFormat',
          'section': 0,
          'story': 'header',
          'paragraph': 0,
          'bold': false,
        });
      }
    },
  );

  test(
    'body paragraph operation keeps its existing behavior on unsupported headers',
    () {
      final package = _package();
      _removeReference(package, 1, 'header');
      final document = WordDeserializer().read(package);
      native.applyStep(document, {
        'op': 'replaceText',
        'paragraph': 0,
        'text': 'Body edit',
      });
      expect(document.paragraphs.first.text, 'Body edit');
      expect(document.sections.first.header.single.text, 'Header 0');
    },
  );
}
