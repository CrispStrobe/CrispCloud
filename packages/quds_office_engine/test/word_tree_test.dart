import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/model/word_tree.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

void main() {
  test(
    'structural edits use the real owner through frames and nested tables',
    () {
      final target = _paragraph('Nested text');
      final cell = WmlTableCell(blocks: <WmlBlock>[target]);
      final inner = WmlTable(
        rows: <WmlTableRow>[
          WmlTableRow(cells: <WmlTableCell>[cell]),
        ],
      );
      final frame = WmlFrame(blocks: <WmlBlock>[inner]);
      final outerCell = WmlTableCell(blocks: <WmlBlock>[frame]);
      final outer = WmlTable(
        rows: <WmlTableRow>[
          WmlTableRow(cells: <WmlTableCell>[outerCell]),
        ],
      );
      final document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[
              _paragraph('Before'),
              outer,
              _paragraph('After'),
            ],
          ),
        ],
      );
      final location = WordTree.locate(document, target)!;
      expect(location.parent, same(cell.blocks));
      final host = WordTree.flowHost(document, target)!;
      expect(host.parent, same(document.sections.single.blocks));
      expect(host.parent[host.index], same(outer));
      expect(
        WordTree.flowHostIn(frame.blocks, target)!.parent,
        same(frame.blocks),
      );
      final inserted = _paragraph('Inserted in owner');
      location.parent.insert(location.index + 1, inserted);
      expect(
        WordTree.paragraphs(document.sections.single.blocks).map((p) => p.text),
        <String>['Before', 'Nested text', 'Inserted in owner', 'After'],
      );
      expect(document.sections.single.blocks, hasLength(3));
      expect(WordTree.locate(document, inserted)!.parent, same(cell.blocks));
      location.parent.remove(target);
      expect(WordTree.locate(document, target), isNull);
    },
  );

  test('note block ownership never falls back to a body paragraph', () {
    final document = WmlDocument.empty(text: 'Body');
    final target = _paragraph('Note');
    final frame = WmlFrame(blocks: <WmlBlock>[target]);
    final note = WmlNote(id: 1, endnote: false, blocks: <WmlBlock>[frame]);
    document.footnotes.add(note);
    final location = WordTree.locate(document, target)!;
    expect(location.parent, same(frame.blocks));
    location.parent.insert(location.index + 1, _paragraph('Continuation'));
    expect(note.allParagraphs.map((p) => p.text), <String>[
      'Note',
      'Continuation',
    ]);
    expect(document.paragraphs.single.text, 'Body');
    document.footnotes.clear();
    expect(WordTree.locate(document, target), isNull);
  });

  test('flow traversal keeps frame and table layout boundaries intact', () {
    final frame = WmlFrame(blocks: <WmlBlock>[_paragraph('Frame')]);
    final table = WmlTable(
      rows: <WmlTableRow>[
        WmlTableRow(
          cells: <WmlTableCell>[
            WmlTableCell(blocks: <WmlBlock>[_paragraph('Table')]),
          ],
        ),
      ],
    );
    final blocks = <WmlBlock>[_paragraph('Body'), frame, table];
    expect(WordTree.visibleBlocks(blocks), orderedEquals(blocks));
    expect(WordTree.paragraphs(blocks).map((p) => p.text), <String>[
      'Body',
      'Frame',
      'Table',
    ]);
  });
}
