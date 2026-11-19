import 'package:quds_office_engine/quds_office_engine.dart';

import 'table_selector.dart';
import 'word_structure_steps.dart';

Map<String, Object?> inspectWord(WmlDocument doc) {
  Map<String, Object?> p(WmlParagraph value) => <String, Object?>{
    'text': value.text,
    'style': value.properties.styleId,
    'heading': value.properties.headingLevel,
    'list': value.properties.listLabel,
    'bookmark': value.properties.bookmarkName,
    'field': value.properties.fieldInstruction,
    'paragraphFormat': <String, Object?>{
      'alignment': value.properties.justification.name,
      'before': value.properties.spacingBefore,
      'after': value.properties.spacingAfter,
      'lineSpacing': value.properties.lineSpacing,
      'lineSpacingRule': value.properties.lineSpacingRule.name,
      'left': value.properties.indent.left,
      'right': value.properties.indent.right,
      'firstLine': value.properties.indent.firstLine,
      'hanging': value.properties.indent.hanging,
      'tabs': [
        for (final tab in value.properties.tabs)
          {
            'position': tab.position,
            'alignment': tab.alignment.name,
            'leader': tab.leader.name,
          },
      ],
      'keepTogether': value.properties.keepTogether,
      'pageBreakBefore': value.properties.pageBreakBefore,
      'columnBreakBefore': value.properties.columnBreakBefore,
      'rtl': value.properties.rightToLeft,
    },
    'runs': <Object?>[
      for (final run in value.inlines.whereType<WmlRun>())
        <String, Object?>{
          'text': run.text,
          'style': run.properties.styleId,
          'note': run.noteRefId,
          'endnote': run.noteRefEndnote,
          'link': run.hyperlink?.displayTarget,
          'comments': run.commentIds,
        },
    ],
  };
  Map<String, Object?> image(WmlVisual value) => <String, Object?>{
    'title': value.visual.title,
    'width': value.visual.width,
    'height': value.visual.height,
    'picture': value.visual.isPicture,
    'wrap': value.visual.picture.wrap.name,
    'rotation': value.visual.picture.rotationDeg,
  };
  return <String, Object?>{
    'format': 'docx',
    'paragraphs': <Object?>[for (final value in doc.paragraphs) p(value)],
    'notes': <Object?>[
      for (final n in <WmlNote>[...doc.footnotes, ...doc.endnotes])
        <String, Object?>{
          'id': n.id,
          'endnote': n.endnote,
          'text': n.text,
          'paragraphs': <Object?>[
            for (final value in n.allParagraphs) p(value),
          ],
          'images': <Object?>[for (final value in n.visuals) image(value)],
        },
    ],
    'images': <Object?>[for (final v in doc.visuals) image(v)],
    'tables': [
      for (final (t, coordinates) in bodyBlocks(doc).whereType<WmlTable>().map(
        (table) => (table, tableGridCoordinates(table)),
      ))
        {
          'grid': t.grid,
          'style': t.properties.styleId,
          'gridAddressingSupported': WordTable.supportsGridAddressing(t),
          'rows': [
            for (final (rowIndex, row) in t.rows.indexed)
              {
                'row': rowIndex,
                'height': row.height,
                'cantSplit': row.cantSplit,
                'gridBefore': row.gridBefore,
                'gridAfter': row.gridAfter,
                'cells': [
                  for (final (column, cell) in row.cells.indexed)
                    {
                      ...coordinates[rowIndex][column],
                      'width': cell.width,
                      'span': cell.gridSpan,
                      'merge': cell.vMerge.name,
                      'fill': cell.fillColor,
                      'paragraphs': [
                        for (final para
                            in row.cells[column].blocks
                                .whereType<WmlParagraph>())
                          p(para),
                      ],
                    },
                ],
              },
          ],
        },
    ],
    'frames': [
      for (final frame in bodyBlocks(doc).whereType<WmlFrame>())
        {
          'x': frame.x,
          'y': frame.y,
          'width': frame.width,
          'height': frame.height,
          'anchor': frame.anchor.name,
          'wrap': frame.wrap.name,
          'fill': frame.fillColor,
          'stroke': frame.strokeColor,
        },
    ],
    'tocs': [
      for (final toc in WordToc.tocs(doc))
        {
          'title': toc.title,
          'minLevel': toc.minLevel,
          'maxLevel': toc.maxLevel,
          'showPageNumbers': toc.showPageNumbers,
          'entries': [
            for (final entry in toc.entries)
              {
                'text': entry.text,
                'level': entry.level,
                'page': entry.pageNumber,
              },
          ],
        },
    ],
    'comments': [
      for (final comment in doc.comments)
        {
          'id': comment.id,
          'parentId': comment.parentId,
          'author': comment.author,
          'initials': comment.initials,
          'date': comment.dateIso,
          'resolved': comment.resolved,
          'paragraphs': [for (final para in comment.paragraphs) p(para)],
          'images': [for (final visual in comment.visuals) image(visual)],
        },
    ],
    'sections': <Object?>[
      for (final s in doc.sections)
        <String, Object?>{
          'width': s.pageSize.width,
          'height': s.pageSize.height,
          'columns': s.columnCount,
          'blocks': <String>[
            for (final b in s.blocks) b.runtimeType.toString(),
          ],
          'header': <Object?>[for (final v in s.header) p(v)],
          'footer': <Object?>[for (final v in s.footer) p(v)],
          'firstHeader': <Object?>[for (final v in s.firstHeader) p(v)],
          'firstFooter': <Object?>[for (final v in s.firstFooter) p(v)],
          'evenHeader': <Object?>[for (final v in s.evenHeader) p(v)],
          'evenFooter': <Object?>[for (final v in s.evenFooter) p(v)],
          'headerImages': <Object?>[for (final v in s.headerVisuals) image(v)],
          'footerImages': <Object?>[for (final v in s.footerVisuals) image(v)],
          'firstHeaderImages': <Object?>[
            for (final v in s.firstHeaderVisuals) image(v),
          ],
          'firstFooterImages': <Object?>[
            for (final v in s.firstFooterVisuals) image(v),
          ],
          'evenHeaderImages': <Object?>[
            for (final v in s.evenHeaderVisuals) image(v),
          ],
          'evenFooterImages': <Object?>[
            for (final v in s.evenFooterVisuals) image(v),
          ],
        },
    ],
  };
}
