import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _namespaces =
    'xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}" '
    'xmlns:w14="${OfficeNamespaces.w14}" xmlns:m="${OfficeNamespaces.m}"';
const _stories = [
  'header_default',
  'header_first',
  'header_even',
  'footer_default',
  'footer_first',
  'footer_even',
  'comments',
];
const _pageField =
    '<w:p><w:pPr><w:spacing w:before="0" '
    'w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>'
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> PAGE \\* MERGEFORMAT </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>2</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>';

String _control(String story, int id, String content) =>
    '<w:sdt><w:sdtPr><w:alias w:val="Auxiliary $id"/>'
    '<w:tag w:val="$story-$id"/><w:id w:val="$id"/>'
    '<w:lock w:val="unlocked"/><w:richText/></w:sdtPr>'
    '<w:sdtEndPr><w:rPr><w:color w:val="123456"/></w:rPr></w:sdtEndPr>'
    '<w:sdtContent>$content</w:sdtContent></w:sdt>';

String _textParagraph(String story) =>
    '<w:p${story == 'comments' ? ' w14:paraId="00000077"' : ''}>'
    '<w:pPr><w:spacing w:before="0" w:after="0" w:line="240" '
    'w:lineRule="auto"/></w:pPr>'
    '<w:r><w:rPr><w:sz w:val="22"/></w:rPr><w:t>Original $story</w:t></w:r>'
    '<w:hyperlink r:id="nativeLink"><w:r><w:rPr><w:sz w:val="22"/>'
    '<w:u w:val="single"/></w:rPr><w:t xml:space="preserve"> link</w:t>'
    '</w:r></w:hyperlink></w:p>';

OpcPackage _source({
  String? changedStory,
  String? changedContent,
  bool wrappedComment = true,
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final mainRels = package.relationshipsFor('/word/document.xml');
  final references = StringBuffer();
  for (var index = 0; index < _stories.length; index++) {
    final story = _stories[index];
    final id = 700 + index * 2;
    final content = changedStory == story
        ? changedContent!
        : story == 'footer_default'
        ? _pageField
        : _textParagraph(story);
    final isComment = story == 'comments';
    final wrapped = isComment && !wrappedComment
        ? content
        : _control(story, id, _control(story, id + 1, content));
    final isHeader = story.startsWith('header');
    final root = isComment
        ? 'comments'
        : isHeader
        ? 'hdr'
        : 'ftr';
    final uri = '/word/aux_$story.xml';
    package.createPart(
      uri,
      isComment
          ? OfficeContentTypes.wordComments
          : isHeader
          ? OfficeContentTypes.wordHeader
          : OfficeContentTypes.wordFooter,
      utf8.encode(
        '<w:$root $_namespaces>'
        '${isComment ? '<w:comment w:id="7" w:author="Native author">' : ''}'
        '$wrapped${isComment ? '</w:comment>' : ''}</w:$root>',
      ),
    );
    package
        .relationshipsFor(uri)
        .add(
          id: 'nativeLink',
          type: RelationshipTypes.hyperlink,
          target: 'https://example.test/$story',
          targetMode: RelationshipTargetMode.external,
        );
    final relation = mainRels.add(
      type: isComment
          ? RelationshipTypes.comments
          : isHeader
          ? RelationshipTypes.header
          : RelationshipTypes.footer,
      target: 'aux_$story.xml',
    );
    if (!isComment) {
      references.write(
        '<w:${isHeader ? 'header' : 'footer'}Reference '
        'w:type="${story.split('_').last}" r:id="${relation.id}"/>',
      );
    }
  }
  package.createPart(
    '/word/aux_commentsExtended.xml',
    OfficeContentTypes.wordCommentsExtended,
    utf8.encode(
      '<w15:commentsEx xmlns:w15="${OfficeNamespaces.w15}">'
      '<w15:commentEx w15:paraId="00000077" w15:done="1"/></w15:commentsEx>',
    ),
  );
  mainRels.add(
    type: RelationshipTypes.commentsExtended,
    target: 'aux_commentsExtended.xml',
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document $_namespaces><w:body><w:p><w:pPr>'
        '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
        '</w:pPr><w:commentRangeStart w:id="7"/><w:r><w:t>Body</w:t></w:r>'
        '<w:commentRangeEnd w:id="7"/><w:r><w:commentReference w:id="7"/></w:r>'
        '</w:p><w:sectPr>$references<w:pgSz w:w="7200" w:h="5600"/>'
        '<w:pgMar w:top="480" w:right="480" w:bottom="480" w:left="480" '
        'w:header="120" w:footer="120"/></w:sectPr></w:body></w:document>',
      );
  return package;
}

Map<String, List<WmlParagraph>> _paragraphs(WmlDocument document) {
  final section = document.sections.single;
  return {
    'header_default': section.header,
    'header_first': section.firstHeader,
    'header_even': section.evenHeader,
    'footer_default': section.footer,
    'footer_first': section.firstFooter,
    'footer_even': section.evenFooter,
    'comments': document.comments.single.paragraphs,
  };
}

void _expectModel(
  WmlDocument document, {
  required bool edited,
  bool wrappedComment = true,
}) {
  final stories = _paragraphs(document);
  for (var index = 0; index < _stories.length; index++) {
    final name = _stories[index];
    final paragraph = stories[name]!.single;
    expect(paragraph.contentControlWrappers.map((control) => control.id), [
      if (name != 'comments' || wrappedComment) ...[
        '${700 + index * 2}',
        '${701 + index * 2}',
      ],
    ]);
    expect(WordContentControls.hasInlineControls(paragraph), isFalse);
    expect(
      WordContentControls.hasStructuralControls(paragraph),
      name != 'comments' || wrappedComment,
    );
    if (name == 'footer_default') {
      expect(paragraph.properties.pageNumberField, isTrue);
      expect(paragraph.properties.fieldInstruction, contains('PAGE'));
      expect(paragraph.text, isNot(contains('PAGE')));
      continue;
    }
    expect(paragraph.text, '${edited ? 'Changed' : 'Original'} $name link');
    expect(
      paragraph.inlines.whereType<WmlRun>().last.hyperlink?.url,
      'https://example.test/$name',
    );
    if (edited) {
      expect(
        paragraph.inlines.whereType<WmlRun>().first.properties.bold,
        isTrue,
      );
    }
  }
  expect(document.comments.single.paragraphId, '00000077');
  expect(document.comments.single.resolved, isTrue);
  expect(document.paragraphs.single.text, edited ? 'Body edited' : 'Body');
  final laid = WordLayoutEngine(font: null).layout(document);
  expect(
    laid.pages.first.footer.any((line) => line.overlayText == '1'),
    isTrue,
  );
}

void main() {
  test('a native PAGE wrapper without sdtPr survives three saves', () {
    final source = _source();
    source
        .getPart('/word/aux_footer_default.xml')!
        .writeText(
          '<w:ftr $_namespaces><w:sdt><w:sdtContent>$_pageField'
          '</w:sdtContent></w:sdt></w:ftr>',
        );
    var document = WordDeserializer().read(source);
    for (var cycle = 0; cycle < 3; cycle++) {
      final paragraph = document.sections.single.footer.single;
      expect(paragraph.contentControlWrappers, hasLength(1));
      expect(paragraph.contentControlWrappers.single.id, isNull);
      expect(paragraph.properties.pageNumberField, isTrue);
      final package = WordSerializer().write(document);
      final body = XmlDocument.parse(
        package.getPart('/word/document.xml')!.readText(),
      ).root!.firstChild('body')!;
      final reference = body
          .firstChild('sectPr')!
          .childrenNamed('footerReference', namespaceUri: OfficeNamespaces.w)
          .singleWhere(
            (node) =>
                node.getAttribute('type', namespaceUri: OfficeNamespaces.w) ==
                'default',
          );
      final rels = package.relationshipsFor('/word/document.xml');
      final relation = rels.byId(
        reference.getAttribute('id', namespaceUri: OfficeNamespaces.r)!,
      )!;
      final root = XmlDocument.parse(
        package.getPart(rels.resolve(relation))!.readText(),
      ).root!;
      final wrapper = root.firstChild('sdt', namespaceUri: OfficeNamespaces.w)!;
      expect(
        wrapper.firstChild('sdtPr', namespaceUri: OfficeNamespaces.w),
        isNull,
      );
      final content = wrapper.firstChild(
        'sdtContent',
        namespaceUri: OfficeNamespaces.w,
      )!;
      expect(content.childElements.map((child) => child.localName), ['p']);
      final xml = XmlDocument(root: content).toXmlString(declaration: false);
      expect(xml, contains(r'PAGE \* MERGEFORMAT'));
      expect(
        RegExp('w:fldCharType="(begin|separate|end)"').allMatches(xml),
        hasLength(3),
      );
      document = WordDeserializer().read(package);
    }
  });

  for (final wrappedComment in [true, false]) {
    test(
      'single-paragraph auxiliary controls retain live fields and native shells '
      '(wrapped comment: $wrappedComment)',
      () async {
        final directory = Directory(
          wrappedComment
              ? 'build/fidelity-aux-controls'
              : 'build/fidelity-aux-header-footer',
        )..createSync(recursive: true);
        final native = _source(wrappedComment: wrappedComment);
        // Preserve the actual authored input before any engine import or export.
        File('${directory.path}/source.docx').writeAsBytesSync(native.save());
        for (final edited in [false, true]) {
          var document = WordDeserializer().read(
            _source(wrappedComment: wrappedComment),
          );
          if (edited) {
            WmlRunEdit.replaceRange(
              document.paragraphs.single,
              4,
              4,
              ' edited',
            );
            for (final entry in _paragraphs(document).entries) {
              if (entry.key == 'footer_default') continue;
              final original = entry.value.single;
              final clone = WmlClone.paragraph(original);
              expect(
                clone.contentControlWrappers,
                isNot(same(original.contentControlWrappers)),
              );
              if (original.contentControlWrappers.isNotEmpty) {
                expect(
                  clone.contentControlWrappers.first,
                  same(original.contentControlWrappers.first),
                );
              }
              entry.value[0] = clone;
              WmlRunEdit.replaceRange(clone, 0, 'Original'.length, 'Changed');
              WmlRunEdit.applyRange(
                clone,
                0,
                'Changed'.length,
                (props) => props.bold = true,
              );
              expect(original.text, startsWith('Original'));
            }
          }
          for (var cycle = 1; cycle <= 3; cycle++) {
            _expectModel(
              document,
              edited: edited,
              wrappedComment: wrappedComment,
            );
            final bytes = cycle.isEven
                ? await OfficeIsolateSave.word(document)
                : WordSerializer().writeBytes(document);
            File(
              '${directory.path}/${edited ? 'edited' : 'imported'}-$cycle.docx',
            ).writeAsBytesSync(bytes);
            document = WordDeserializer().readBytes(bytes);
          }
          _expectModel(
            document,
            edited: edited,
            wrappedComment: wrappedComment,
          );
        }
      },
    );
  }

  test(
    'auxiliary wrapper IDs participate in clone insertion and save guards',
    () {
      final document = WordDeserializer().read(_source());
      final paragraph = document.sections.single.header.single;
      final copy = WmlClone.paragraph(paragraph);
      expect(
        () => WordContentControls.assertCanInsert(document, [copy]),
        throwsUnsupportedError,
      );
      document.sections.single.header.add(copy);
      final before = {
        for (final part in document.package!.parts)
          part.uri: List.of(part.bytesView),
      };
      expect(() => WordSerializer().writeBytes(document), throwsStateError);
      expect({
        for (final part in document.package!.parts)
          part.uri: List.of(part.bytesView),
      }, before);
    },
  );

  test(
    'auxiliary wrapper split is guarded without blocking contained edits',
    () {
      final paragraph = WordDeserializer()
          .read(_source())
          .sections
          .single
          .header
          .single;
      final before = paragraph.text;
      for (final at in [0, 5, before.length]) {
        expect(
          () => WmlClone.splitInlines(paragraph, at),
          throwsUnsupportedError,
        );
        expect(paragraph.text, before);
        expect(paragraph.contentControlWrappers, hasLength(2));
      }
      WmlRunEdit.replaceRange(paragraph, 0, paragraph.text.length, 'New text');
      expect(paragraph.text, 'New text');
      expect(paragraph.contentControlWrappers, hasLength(2));
    },
  );

  for (final story in ['header_default', 'footer_default', 'comments']) {
    for (final content in {
      'drawing': '<w:p><w:r><w:drawing/></w:r></w:p>',
      'equation': '<w:p><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></w:p>',
      'table': '<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
    }.entries) {
      test('$story control retains explicit ${content.key} import guard', () {
        final source = _source(
          changedStory: story,
          changedContent: content.value,
        );
        final before = {
          for (final part in source.parts) part.uri: List.of(part.bytesView),
        };
        expect(
          () => WordDeserializer().read(source),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'source context',
              contains('/word/aux_$story.xml'),
            ),
          ),
        );
        expect({
          for (final part in source.parts) part.uri: List.of(part.bytesView),
        }, before);
      });
    }
  }
}
