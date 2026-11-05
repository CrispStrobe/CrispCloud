import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// A field shared across selected/omitted pages, a second omitted-only field,
// indirect form/name-tree arrays, and a bookmark parent whose own target is
// omitted while its child survives. Built independently of the page importer.
Uint8List _selectionPdf() {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final leaves = [
    for (var i = 0; i < 3; i++)
      CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray(const [
          CosInteger(0),
          CosInteger(0),
          CosInteger(612),
          CosInteger(792)
        ]),
        'Resources': CosDictionary(),
        'Contents': builder.add(CosStream(
            CosDictionary(),
            Uint8List.fromList(
                latin1.encode('BT (source-page-${i + 1}) Tj ET')))),
      }),
  ];
  final pageRefs = [for (final page in leaves) builder.add(page)];
  pages['Kids'] = CosArray(pageRefs);
  pages['Count'] = const CosInteger(3);
  final root = CosDictionary({'T': CosString.fromText('customer')});
  final rootRef = builder.add(root);
  final field = CosDictionary({
    'Parent': rootRef,
    'T': CosString.fromText('name'),
    'FT': const CosName('Tx'),
    'V': CosString.fromText('Original'),
  });
  final fieldRef = builder.add(field);
  root['Kids'] = builder.add(CosArray([fieldRef]));
  CosArray rect(int y) => CosArray([
        const CosInteger(20),
        CosInteger(y),
        const CosInteger(200),
        CosInteger(y + 30)
      ]);
  final widgets = [
    for (final page in [0, 2])
      builder.add(CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Widget'),
        'Parent': fieldRef,
        'P': pageRefs[page],
        'Rect': rect(20),
      })),
  ];
  field['Kids'] = builder.add(CosArray(widgets));
  final omittedField = builder.add(CosDictionary({
    'Type': const CosName('Annot'),
    'Subtype': const CosName('Widget'),
    'FT': const CosName('Tx'),
    'T': CosString.fromText('omitted'),
    'V': CosString.fromText('only-on-page-three'),
    'P': pageRefs[2],
    'Rect': rect(100),
  }));
  CosReference link(String name) => builder.add(CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Link'),
        'Rect': rect(60),
        'A': builder.add(CosDictionary({
          'S': const CosName('GoTo'),
          'D': CosString.fromText(name),
        })),
      }));
  leaves[0]['Annots'] = builder.add(CosArray([
    widgets[0],
    link('keep'),
    link('drop'),
  ]));
  leaves[2]['Annots'] = builder.add(CosArray([widgets[1], omittedField]));
  final outlines = CosDictionary({'Type': const CosName('Outlines')});
  final outlinesRef = builder.add(outlines);
  final heading = CosDictionary({
    'Title': CosString.fromText('Keep as heading'),
    'Parent': outlinesRef,
    'Dest': const CosName('drop'),
    'Count': const CosInteger(1),
  });
  final headingRef = builder.add(heading);
  final child = builder.add(CosDictionary({
    'Title': CosString.fromText('Selected child'),
    'Parent': headingRef,
    'Dest': const CosName('keep'),
  }));
  heading['First'] = child;
  heading['Last'] = child;
  final omittedOutline = builder.add(CosDictionary({
    'Title': CosString.fromText('Drop leaf'),
    'Parent': outlinesRef,
    'Prev': headingRef,
    'Dest': const CosName('drop'),
  }));
  heading['Next'] = omittedOutline;
  outlines['First'] = headingRef;
  outlines['Last'] = omittedOutline;
  outlines['Count'] = const CosInteger(3);
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    'Outlines': outlinesRef,
    'PageMode': const CosName('UseOutlines'),
    'Names': builder.add(CosDictionary({
      'Dests': builder.add(CosDictionary({
        'Names': builder.add(CosArray([
          CosString.fromText('keep'),
          CosArray([pageRefs[1], const CosName('Fit')]),
          CosString.fromText('drop'),
          CosArray([pageRefs[2], const CosName('Fit')]),
        ])),
      })),
      'EmbeddedFiles': CosDictionary({'Names': CosArray([])}),
      'JavaScript': CosDictionary({'Names': CosArray([])}),
    })),
    'AcroForm': builder.add(CosDictionary({
      'Fields': builder.add(CosArray([rootRef, omittedField])),
      'CO': builder.add(CosArray([fieldRef, omittedField])),
      'DA': CosString.fromText('/F1 11 Tf 0 g'),
      'Q': const CosInteger(2),
      'DR': builder.add(CosDictionary({
        'Font': CosDictionary({
          'F1': builder.add(CosDictionary({
            'Type': const CosName('Font'),
            'Subtype': const CosName('Type1'),
            'BaseFont': const CosName('Courier'),
            'Encoding': const CosName('WinAnsiEncoding'),
          })),
        }),
      })),
    })),
  }));
  return builder.build(
      root: catalog,
      info: builder.add(
          CosDictionary({'Title': CosString.fromText('Selection fixture')})));
}

void main() {
  test('extraction retains selected form branches and their defaults', () {
    final original = _selectionPdf();
    final source = PdfDocument.open(original);
    final output = PdfDocument.open(source.extractPages([1, 0]));
    expect(output.pageCount, 2);
    expect(latin1.decode(output.page(0).contentBytes()),
        contains('source-page-2'));
    expect(latin1.decode(output.page(1).contentBytes()),
        contains('source-page-1'));
    final form = PdfAcroForm.of(output)!;
    expect(form.fields.map((field) => field.name), ['customer.name']);
    final field = form.fieldNamed('customer.name')!;
    expect(field.widgets, hasLength(1));
    expect(field.widgetPageIndex(0), 1);
    expect(field.defaultAppearance, contains('/F1 11 Tf'));
    expect(field.quadding, 2);
    final calculationOrder = output.cos.resolve(form.dict['CO']) as CosArray;
    expect(calculationOrder.items, hasLength(1));
    expect(output.cos.resolve(calculationOrder[0]), same(field.dict));
    final editor = PdfEditor(output)..setTextValue(field, 'Changed');
    final reopened = PdfDocument.open(editor.save());
    final filled = PdfAcroForm.of(reopened)!.fieldNamed('customer.name')!;
    expect(filled.value, 'Changed');
    expect(filled.widgets.single.containsKey('AP'), isTrue);
    expect(reopened.info['Title'], 'Selection fixture');

    // Import does not modify the source field tree or its input buffer.
    expect(PdfAcroForm.of(source)!.fieldNamed('customer.name')!.widgets,
        hasLength(2));
    expect(source.pageCount, 3);
    expect(original, _selectionPdf());
  });

  test('destinations remap, omitted links disappear, child headings survive',
      () {
    final output = PdfDocument.open(
        PdfDocument.open(_selectionPdf()).extractPages([1, 0]));
    final kept = PdfDestination.parse(output, const CosName('keep'))!;
    expect(kept.pageIndex, 0);
    expect(PdfDestination.parse(output, const CosName('drop')), isNull);
    final links =
        output.page(1).annotations.whereType<PdfLinkAnnotation>().toList();
    expect((links[0].action as PdfGoToAction).destination.pageIndex, 0);
    expect(links[1].action, isNull);
    expect(links[1].dict.containsKey('A'), isFalse);
    final outline = PdfOutline.of(output).items.single;
    expect(outline.title, 'Keep as heading');
    expect(outline.destination, isNull);
    expect(outline.children.single.title, 'Selected child');
    expect(outline.children.single.destination!.pageIndex, 0);
    expect(output.catalog['PageMode'], const CosName('UseOutlines'));
  });

  test('omitted page objects, fields and unrelated names are not copied', () {
    final bytes = PdfDocument.open(_selectionPdf()).extractPages([0]);
    final output = PdfDocument.open(bytes);
    final raw = latin1.decode(bytes);
    expect(raw, isNot(contains('source-page-2')));
    expect(raw, isNot(contains('source-page-3')));
    expect(raw, isNot(contains('only-on-page-three')));
    final names = output.cos.resolve(output.catalog['Names']);
    if (names is CosDictionary) {
      expect(names.containsKey('EmbeddedFiles'), isFalse);
      expect(names.containsKey('JavaScript'), isFalse);
    }
    expect(PdfOutline.of(output).items, isEmpty);
  });

  test('full reordered extraction retains every widget', () {
    final output = PdfDocument.open(
        PdfDocument.open(_selectionPdf()).extractPages([2, 1, 0]));
    final form = PdfAcroForm.of(output)!;
    expect(
        form.fields.map((field) => field.name), ['customer.name', 'omitted']);
    final shared = form.fieldNamed('customer.name')!;
    expect(
        [
          for (var i = 0; i < shared.widgets.length; i++)
            shared.widgetPageIndex(i)
        ].toSet(),
        {0, 2});
    expect(form.fieldNamed('omitted')!.widgetPageIndex(0), 0);
  });

  test('source incremental history is not the extracted file base', () {
    var source = PdfDocument.open(_selectionPdf());
    var edit = PdfEditor(source)
      ..setTextValue(PdfAcroForm.of(source)!.fieldNamed('customer.name')!,
          'obsolete-secret-marker');
    source = PdfDocument.open(edit.save());
    edit = PdfEditor(source)
      ..setTextValue(
          PdfAcroForm.of(source)!.fieldNamed('customer.name')!, 'Current');
    final withHistory = edit.save();
    expect(latin1.decode(withHistory), contains('obsolete-secret-marker'));
    final bytes = PdfDocument.open(withHistory).extractPages([0]);
    expect(latin1.decode(bytes), isNot(contains('obsolete-secret-marker')));
    expect(
        PdfAcroForm.of(PdfDocument.open(bytes))!
            .fieldNamed('customer.name')!
            .value,
        'Current');
  });

  test('encrypted input extracts into a fresh unencrypted document', () {
    final source = PdfDocument.open(
        buildEncryptedPdf(revision: 6, userPassword: 'test-password'),
        password: 'test-password');
    final output = PdfDocument.open(source.extractPages([0]));
    expect(output.cos.isEncrypted, isFalse);
    expect(latin1.decode(output.page(0).contentBytes()),
        contains('Hello, world!'));
  });
}
