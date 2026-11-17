// Qualify the actual host menu/export path with authored values and source
// preservation checks. Storage and copy destinations are deterministic test
// boundaries; the dialog, controllers, menu, writers and preview parser are real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/services/office_editor_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pr = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _presentation = 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

// Independently authored DOCX, not output from the serializer under test.
Uint8List _wordSource() {
  final parts = <String, String>{
    '[Content_Types].xml': '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>
<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
</Types>''',
    '_rels/.rels':
        '<Relationships xmlns="$_pr"><Relationship Id="office" Type="$_r/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels':
        '''
<Relationships xmlns="$_pr">
<Relationship Id="comments" Type="$_r/comments" Target="comments.xml"/>
<Relationship Id="notes" Type="$_r/footnotes" Target="footnotes.xml"/>
<Relationship Id="header" Type="$_r/header" Target="header1.xml"/>
</Relationships>''',
    'word/document.xml':
        '''
<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>
<w:p><w:pPr><w:shd w:fill="AABBCC"/><w:pBdr><w:bottom w:val="single" w:sz="4" w:color="112233"/></w:pBdr><w:tabs><w:tab w:val="right" w:pos="1440" w:leader="dot"/></w:tabs></w:pPr><w:commentRangeStart w:id="1"/><w:r><w:t xml:space="preserve">Visible body </w:t></w:r><w:commentRangeEnd w:id="1"/><w:r><w:commentReference w:id="1"/></w:r><w:r><w:t>tail</w:t><w:tab/><w:t>Tabbed</w:t></w:r></w:p>
<w:p><w:pPr><w:shd w:fill="DDEEFF"/><w:pBdr><w:bottom w:val="single" w:sz="4" w:color="445566"/></w:pBdr><w:tabs><w:tab w:val="right" w:pos="1440" w:leader="dot"/></w:tabs></w:pPr><w:r><w:t>Independent colors</w:t></w:r></w:p>
<w:p><w:r><w:t>Base pagination</w:t></w:r></w:p>
<w:p><w:pPr><w:keepLines/></w:pPr><w:r><w:br w:type="column"/><w:t>Column kept</w:t></w:r></w:p>
<w:p><w:r><w:t>Base pagination again</w:t></w:r></w:p>
<w:tbl><w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Visible cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>Visible reference</w:t></w:r><w:r><w:footnoteReference w:id="7"/></w:r></w:p>
<w:sectPr><w:headerReference w:type="default" r:id="header"/><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/><w:cols w:num="2" w:space="360"/></w:sectPr>
</w:body></w:document>''',
    'word/comments.xml':
        '<w:comments xmlns:w="$_w"><w:comment w:id="1" w:author="HIDDEN AUTHOR"><w:p><w:r><w:t>HIDDEN COMMENT</w:t></w:r></w:p></w:comment></w:comments>',
    'word/footnotes.xml':
        '<w:footnotes xmlns:w="$_w"><w:footnote w:id="7"><w:p><w:r><w:footnoteRef/><w:t xml:space="preserve">Visible note</w:t></w:r></w:p></w:footnote></w:footnotes>',
    'word/header1.xml':
        '<w:hdr xmlns:w="$_w"><w:p><w:r><w:t>Visible header</w:t></w:r></w:p></w:hdr>',
  };
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _slideSource() =>
    File('test/fixtures/office_native_workflows/native-slide-source.pptx')
        .readAsBytesSync();

Uint8List _chartSource() {
  final original = ZipDecoder().decodeBytes(_slideSource());
  final parts = <String, List<int>>{
    for (final file in original.files) file.name: file.content,
  };
  void append(String name, String closing, String value) {
    parts[name] = utf8.encode(
      utf8.decode(parts[name]!).replaceFirst(closing, '$value$closing'),
    );
  }

  // Author a chart relationship and cached values directly in the OOXML package.
  append(
    '[Content_Types].xml',
    '</Types>',
    '''
<Override PartName="/ppt/charts/chartReview.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>''',
  );
  append(
    'ppt/slides/_rels/slide1.xml.rels',
    '</Relationships>',
    '''
<Relationship Id="chartReview" Type="$_r/chart" Target="../charts/chartReview.xml"/>''',
  );
  append(
    'ppt/slides/slide1.xml',
    '</p:spTree>',
    '''
<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="4" name="Authored chart"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>
<p:xfrm><a:off x="457200" y="2926080"/><a:ext cx="4572000" cy="1600200"/></p:xfrm>
<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="chartReview"/></a:graphicData></a:graphic></p:graphicFrame>''',
  );
  parts['ppt/charts/chartReview.xml'] = utf8.encode('''
<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:barChart><c:barDir val="col"/><c:ser><c:idx val="0"/><c:order val="0"/>
<c:cat><c:strLit><c:ptCount val="2"/><c:pt idx="0"><c:v>North &amp; East</c:v></c:pt><c:pt idx="1"><c:v>South &lt;West&gt;</c:v></c:pt></c:strLit></c:cat>
<c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="2"/><c:pt idx="0"><c:v>12.5</c:v></c:pt><c:pt idx="1"><c:v>-7.25</c:v></c:pt></c:numLit></c:val>
</c:ser></c:barChart></c:plotArea></c:chart></c:chartSpace>''');
  final output = Archive();
  for (final part in parts.entries) {
    output.addFile(ArchiveFile.bytes(part.key, part.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(output));
}

xml.XmlDocument _part(Uint8List bytes, String name) => xml.XmlDocument.parse(
  utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.content),
);

xml.XmlElement? _paragraphProperties(xml.XmlDocument content, String text) {
  final paragraph = content
      .findAllElements('p', namespace: _text)
      .singleWhere((node) => node.innerText == text);
  final styleName = paragraph.getAttribute('style-name', namespace: _text);
  return content
      .findAllElements('style', namespace: _style)
      .singleWhere(
        (node) => node.getAttribute('name', namespace: _style) == styleName,
      )
      .getElement('paragraph-properties', namespace: _style);
}

void _export(OfficeTestHarness host, bool word) => host.container
    .read(officeEditorMenuProvider)!
    .perform(
      word ? OfficeEditorAction.exportOdt : OfficeEditorAction.exportOdp,
    );

void _edit(OfficeController controller, String value) {
  if (controller is WordEditorController) {
    controller.insertText(value);
  } else if (controller is SlideEditorController) {
    controller.selectShape(controller.slide.shapes.first);
    controller.beginTextEdit(initial: value);
  }
  expect(controller.isDirty, isTrue);
}

void _expectOriginal(OfficeTestHarness host, Uint8List original) {
  expect(host.savedBytes, orderedEquals(original));
  expect(host.cloud.uploadAttempts, 0);
  expect(host.cloud.writes, isEmpty);
}

void main() {
  testWidgets(
    'ODT menu export retains authored content and annotation privacy',
    (tester) async {
      await tester.runAsync(() async {
        final original = _wordSource();
        Uint8List? exported;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'review.docx',
          initialBytes: original,
          copyExporter: (bytes, name, title, {initialDirectory}) async {
            expect(name, 'review.odt');
            expect(title, 'Export as ODT');
            exported = bytes;
            return OfficeCopyOutcome.savedCopy;
          },
        );
        try {
          _export(host, true);
          await officePumpUntil(
            tester,
            () => exported != null && !host.ribbon.saving,
          );
          final preview = await parseOfficeDocument(exported!, 'review.odt');
          expect(preview.fallback, isNull);
          for (final value in [
            'Visible body',
            'tail',
            'Tabbed',
            'Independent colors',
            'Visible cell',
            'Visible reference',
            'Visible note',
            'Visible header',
            'Base pagination',
            'Column kept',
            'Base pagination again',
          ]) {
            expect(preview.markdown, contains(value));
            expect(preview.plainText, contains(value));
          }
          expect(preview.markdown, isNot(contains('HIDDEN')));
          expect(preview.plainText, isNot(contains('HIDDEN')));
          expect(preview.rawXml, contains('HIDDEN COMMENT'));
          final content = _part(exported!, 'content.xml');
          expect(
            content.findAllElements('annotation', namespace: _office),
            hasLength(1),
          );
          final properties = content
              .findAllElements('paragraph-properties', namespace: _style)
              .where(
                (node) =>
                    node.getAttribute('background-color', namespace: _fo) !=
                    null,
              )
              .toList();
          expect(properties, hasLength(2));
          expect(
            properties.map(
              (node) => node.getAttribute('background-color', namespace: _fo),
            ),
            ['#aabbcc', '#ddeeff'],
          );
          expect(
            properties.map(
              (node) => node.getAttribute('border', namespace: _fo),
            ),
            ['0.5pt solid #112233', '0.5pt solid #445566'],
          );
          for (final properties in properties) {
            final tab = properties
                .findAllElements('tab-stop', namespace: _style)
                .single;
            expect(tab.getAttribute('position', namespace: _style), '72.00pt');
            expect(tab.getAttribute('type', namespace: _style), 'right');
            expect(
              tab.getAttribute('leader-style', namespace: _style),
              'dotted',
            );
          }
          expect(
            content.findAllElements('note', namespace: _text),
            hasLength(1),
          );
          final columns = content
              .findAllElements('columns', namespace: _style)
              .single;
          expect(columns.parentElement!.name.local, 'section-properties');
          expect(columns.parentElement!.name.namespaceUri, _style);
          expect(columns.getAttribute('column-count', namespace: _fo), '2');
          expect(columns.getAttribute('column-gap', namespace: _fo), '18.00pt');
          final kept = _paragraphProperties(content, 'Column kept')!;
          expect(kept.getAttribute('break-before', namespace: _fo), 'column');
          expect(kept.getAttribute('keep-together', namespace: _fo), 'always');
          for (final text in ['Base pagination', 'Base pagination again']) {
            final regular = _paragraphProperties(content, text);
            expect(
              regular?.getAttribute('break-before', namespace: _fo),
              isNull,
            );
            expect(
              regular?.getAttribute('keep-together', namespace: _fo),
              isNull,
            );
          }
          expect(host.controller.isDirty, isFalse);
          _expectOriginal(host, original);
        } finally {
          await host.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ODP menu export commits pending title and preserves notes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final original = _slideSource();
      Uint8List? exported;
      final host = await OfficeTestHarness.open(
        tester,
        name: 'review.pptx',
        initialBytes: original,
        copyExporter: (bytes, name, title, {initialDirectory}) async {
          expect(name, 'review.odp');
          expect(title, 'Export as ODP');
          exported = bytes;
          return OfficeCopyOutcome.savedCopy;
        },
      );
      try {
        final slides = host.controller as SlideEditorController;
        _edit(slides, 'Pending reviewed title');
        expect(slides.textEditor.editing, isTrue);
        _export(host, false);
        await officePumpUntil(
          tester,
          () => exported != null && !host.ribbon.saving,
        );
        expect(slides.textEditor.editing, isFalse);
        final content = _part(exported!, 'content.xml');
        expect(content.toXmlString(), contains('Pending reviewed title'));
        expect(
          content.toXmlString(),
          contains('Reference body remains unchanged.'),
        );
        expect(content.toXmlString(), isNot(contains('Native slide title')));
        final notes = content
            .findAllElements('notes', namespace: _presentation)
            .single;
        expect(notes.innerText, contains('Source notes'));
        expect(notes.innerText, contains('Reference retained.'));
        final preview = await parseOfficeDocument(exported!, 'review.odp');
        expect(preview.fallback, isNull);
        expect(preview.plainText, contains('Pending reviewed title'));
        expect(
          preview.plainText,
          contains('Reference body remains unchanged.'),
        );
        expect(slides.isDirty, isTrue);
        _expectOriginal(host, original);
      } finally {
        await host.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('ODP menu exports authored chart values as a readable table', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final original = _chartSource();
      Uint8List? exported;
      final host = await OfficeTestHarness.open(
        tester,
        name: 'chart.pptx',
        initialBytes: original,
        copyExporter: (bytes, name, title, {initialDirectory}) async {
          expect(name, 'chart.odp');
          exported = bytes;
          return OfficeCopyOutcome.savedCopy;
        },
      );
      try {
        final slides = host.controller as SlideEditorController;
        final chart = slides.slide.shapes
            .singleWhere((shape) => shape.name == 'Authored chart')
            .visual!;
        expect(chart.points.map((point) => point.label), [
          'North & East',
          'South <West>',
        ]);
        expect(chart.points.map((point) => point.value), [12.5, -7.25]);
        _export(host, false);
        await officePumpUntil(
          tester,
          () => exported != null && !host.ribbon.saving,
        );
        final content = _part(exported!, 'content.xml');
        final table = content
            .findAllElements('table', namespace: _table)
            .single;
        final rows = table
            .findAllElements('table-row', namespace: _table)
            .map(
              (row) => row
                  .findAllElements('table-cell', namespace: _table)
                  .map((cell) => cell.innerText)
                  .toList(),
            )
            .toList();
        expect(rows, [
          ['Label', 'Value'],
          ['North & East', '12.5'],
          ['South <West>', '-7.25'],
        ]);
        final preview = await parseOfficeDocument(exported!, 'chart.odp');
        expect(preview.fallback, isNull);
        for (final value in ['North & East', 'South <West>', '12.5', '-7.25']) {
          expect(preview.plainText, contains(value));
        }
        expect(slides.isDirty, isFalse);
        _expectOriginal(host, original);
      } finally {
        await host.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  for (final word in [true, false]) {
    final sourceExtension = word ? 'docx' : 'pptx';
    final outputExtension = word ? 'odt' : 'odp';
    for (final outcome in ['saved', 'downloaded', 'cancelled', 'failed']) {
      testWidgets(
        '$outputExtension $outcome export preserves newer edits and save target',
        (tester) async {
          await tester.runAsync(() async {
            final original = word ? _wordSource() : _slideSource();
            final destination = Completer<OfficeCopyOutcome?>();
            Uint8List? exported;
            var exports = 0;
            final host = await OfficeTestHarness.open(
              tester,
              name: 'review.$sourceExtension',
              initialBytes: original,
              copyExporter: (bytes, name, title, {initialDirectory}) {
                exports++;
                expect(name, 'review.$outputExtension');
                exported = bytes;
                return destination.future;
              },
            );
            try {
              _edit(host.controller, 'Captured revision ');
              _export(host, word);
              await officePumpUntil(tester, () => exported != null);
              expect(() => exported![0] = 0, throwsUnsupportedError);
              final snapshot = Uint8List.fromList(exported!);
              final preview = await parseOfficeDocument(
                snapshot,
                'review.$outputExtension',
              );
              expect(preview.plainText, contains('Captured revision'));
              expect(preview.plainText, isNot(contains('Later revision')));
              _edit(host.controller, 'Later revision ');
              _export(host, word);
              expect(
                exports,
                1,
                reason:
                    'An active destination must not launch a second export.',
              );
              switch (outcome) {
                case 'saved':
                  destination.complete(OfficeCopyOutcome.savedCopy);
                case 'downloaded':
                  destination.complete(OfficeCopyOutcome.downloadedCopy);
                case 'cancelled':
                  destination.complete(null);
                case 'failed':
                  destination.completeError(
                    StateError('Test destination failed'),
                  );
              }
              await officePumpUntil(tester, () => !host.ribbon.saving);
              expect(exported, orderedEquals(snapshot));
              expect(host.controller.isDirty, isTrue);
              expect(host.ribbon.title, 'review.$sourceExtension');
              _expectOriginal(host, original);
              // Ordinary Save still owns the original OOXML target and serializes
              // the newer edit, even after a cancelled or failed ODF destination.
              await host.save();
              expect(exports, 1);
              expect(host.cloud.uploadAttempts, 1);
              expect(host.controller.isDirty, isFalse);
              final saved = await parseOfficeDocument(
                host.savedBytes,
                'review.$sourceExtension',
              );
              expect(saved.plainText, contains('Later revision'));
            } finally {
              if (!destination.isCompleted) destination.complete(null);
              await host.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
