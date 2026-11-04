import 'dart:convert';
import 'dart:typed_data';

import '../cos/pdf_cos.dart';
import '../cos/pdf_cos_write.dart';
import '../cos/pdf_store.dart';
import '../model/pdf_file.dart';

/// Builds a new 1.7 file from selected pages (extract / blank).
abstract final class PdfPageIo {
  /// Writes a standalone PDF from [pages] (decoded content streams).
  static Uint8List writePages(List<PdfExtractedPage> pages) {
    if (pages.isEmpty) {
      throw ArgumentError('extract requires at least one page');
    }
    final BytesBuilder out = BytesBuilder();
    out.add(utf8.encode('%PDF-1.7\n%\xE2\xE3\xCF\xD3\n'));
    final List<(int, int)> xref = <(int, int)>[(0, 0)];

    void obj(int id, List<int> body) {
      xref.add((id, out.length));
      out.add(utf8.encode('$id 0 obj\n'));
      out.add(body);
      out.add(utf8.encode('\nendobj\n'));
    }

    const int catalogId = 1;
    const int pagesId = 2;
    var next = 3;
    final List<int> kids = <int>[];
    for (final PdfExtractedPage page in pages) {
      final int contentId = next++;
      final Uint8List content = page.content;
      obj(
        contentId,
        PdfCosWrite.encode(
          PdfCosStream(
            PdfCosDict(<String, PdfCos>{'Length': PdfCosInt(content.length)}),
            content,
          ),
        ),
      );
      final int pageId = next++;
      kids.add(pageId);
      obj(
        pageId,
        utf8.encode(
          PdfCosWrite.encodeDict(
            PdfCosDict(<String, PdfCos>{
              'Type': const PdfCosName('Page'),
              'Parent': const PdfCosRef(pagesId),
              'MediaBox': PdfCosArray(<PdfCos>[
                const PdfCosReal(0),
                const PdfCosReal(0),
                PdfCosReal(page.width),
                PdfCosReal(page.height),
              ]),
              'Rotate': PdfCosInt(page.rotate),
              'Resources': PdfCosDict(),
              'Contents': PdfCosRef(contentId),
            }),
          ),
        ),
      );
    }
    obj(
      pagesId,
      utf8.encode(
        PdfCosWrite.encodeDict(
          PdfCosDict(<String, PdfCos>{
            'Type': const PdfCosName('Pages'),
            'Kids': PdfCosArray(<PdfCos>[
              for (final int id in kids) PdfCosRef(id),
            ]),
            'Count': PdfCosInt(kids.length),
          }),
        ),
      ),
    );
    obj(
      catalogId,
      utf8.encode(
        PdfCosWrite.encodeDict(
          PdfCosDict(<String, PdfCos>{
            'Type': const PdfCosName('Catalog'),
            'Pages': const PdfCosRef(pagesId),
          }),
        ),
      ),
    );
    final int xrefAt = out.length;
    final StringBuffer table = StringBuffer('xref\n0 $next\n');
    table.write('0000000000 65535 f \n');
    for (int id = 1; id < next; id++) {
      final (int, int) row = xref.firstWhere((e) => e.$1 == id);
      table.write('${row.$2.toString().padLeft(10, '0')} 00000 n \n');
    }
    table.write(
      'trailer\n<</Size $next/Root 1 0 R>>\nstartxref\n$xrefAt\n%%EOF\n',
    );
    out.add(utf8.encode(table.toString()));
    return out.takeBytes();
  }

  /// Decoded content for one page (Contents stream or array).
  static Uint8List pageContent(PdfCosStore store, PdfCosDict dict) {
    final PdfCos? value = store.deref(dict['Contents']);
    if (value is PdfCosStream) {
      return store.streamBytes(dict['Contents']) ?? Uint8List(0);
    }
    if (value is PdfCosArray) {
      final BytesBuilder buf = BytesBuilder();
      for (final PdfCos item in value.items) {
        final Uint8List? part = store.streamBytes(item);
        if (part != null && part.isNotEmpty) {
          if (buf.length > 0) {
            buf.add(const <int>[10]);
          }
          buf.add(part);
        }
      }
      return buf.takeBytes();
    }
    return Uint8List(0);
  }

  /// Snapshot used by extract / merge.
  static PdfExtractedPage snapshot(PdfFile file, int index) {
    final PdfPageRec rec = file.pageRec(index);
    return PdfExtractedPage(
      width: rec.info.mediaBox.width,
      height: rec.info.mediaBox.height,
      rotate: rec.info.rotate,
      content: rec.pendingContent ?? pageContent(file.store, rec.dict),
    );
  }
}

/// One page ready to be written as a new file.
class PdfExtractedPage {
  /// PdfExtractedPage API.
  const PdfExtractedPage({
    required this.width,
    required this.height,
    required this.content,
    this.rotate = 0,
  });

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// rotate API.
  final int rotate;

  /// Decoded content operators.
  final Uint8List content;
}
