import 'dart:convert';
import 'dart:typed_data';

import '../fonts/font_subsetter.dart';
import '../fonts/office_font_set.dart';
import '../fonts/sfnt_parser.dart';
import '../opc/zip/crc32.dart';
import '../sheet/model/sml_workbook.dart';
import '../slide/model/pml_presentation.dart';
import '../word/model/wml_document.dart';
import 'file/io/pdf_appearance.dart';
import 'office_pdf_export.dart';
import 'pdf_font.dart';
import 'pdf_save_options.dart';
import 'pdf_stream.dart';

/// One embedded CID face written as `/FontFile2`.
class PdfEmbeddedFace {
  /// PdfEmbeddedFace API.
  const PdfEmbeddedFace({
    required this.subset,
    required this.source,
    required this.resourceName,
  });

  /// subset API.
  final FontSubset subset;

  /// source API.
  final SfntFont source;

  /// PDF resource name such as `F1` or `F3`.
  final String resourceName;
}

/// Interactive AcroForm field written by `pdf_widgets` when `acroForm: true`.
class PdfAcroField {
  /// PdfAcroField API.
  const PdfAcroField({
    required this.name,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pageIndex,
    this.value = '',
    this.options = const <String>[],
    this.checked = false,
    this.exportOn = 'Yes',
    this.multiline = false,
    this.radio = false,
  });

  /// Fully qualified field name.
  final String name;

  /// `Tx`, `Btn`, or `Ch`.
  final String type;

  /// Top-left X in page space (same as [PdfLinkAnnot]).
  final double x;

  /// Top-left Y in page space.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// Zero-based page index.
  final int pageIndex;

  /// value API.
  final String value;

  /// Combo / list options.
  final List<String> options;

  /// Checkbox / radio on.
  final bool checked;

  /// Export value when [checked] is true.
  final String exportOn;

  /// multiline API.
  final bool multiline;

  /// Radio button (circle) vs checkbox.
  final bool radio;
}

/// Native PDF 1.7 compiler.
class PdfDocument {
  /// PdfDocument API.
  PdfDocument({this.title = 'Quds Office', this.author = ''});

  /// title API.
  final String title;

  /// author API.
  final String author;

  /// pages API.
  final List<PdfPage> pages = <PdfPage>[];

  /// Document outline bookmarks (PDF `/Outlines`).
  final List<PdfOutlineItem> outlines = <PdfOutlineItem>[];

  /// addPage API.
  void addPage(PdfPage page) => pages.add(page);

  /// addOutline API.
  void addOutline(PdfOutlineItem item) => outlines.add(item);

  /// Lays out [document] and emits a PDF with an optional embedded [font].
  static Uint8List fromWord(
    WmlDocument document, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
  }) => OfficePdfExport.word(
    document,
    font: font,
    fonts: fonts,
    saveOptions: saveOptions,
    title: title,
  );

  /// Landscape page per slide from a PPTX archive.
  static Uint8List fromPptx(
    Uint8List bytes, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
    String? password,
  }) => OfficePdfExport.fromBytes(
    bytes,
    font: font,
    fonts: fonts,
    saveOptions: saveOptions,
    title: title,
    password: password,
  );

  /// Print-layout PDF for every worksheet in [book].
  static Uint8List fromWorkbook(
    SmlWorkbook book, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
  }) => OfficePdfExport.workbook(
    book,
    font: font,
    fonts: fonts,
    saveOptions: saveOptions,
    title: title,
  );

  /// One PDF page per slide from an in-memory deck.
  static Uint8List fromPresentation(
    PmlPresentation deck, {
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSaveOptions saveOptions = const PdfSaveOptions(),
    String title = 'Quds Office',
  }) => OfficePdfExport.presentation(
    deck,
    font: font,
    fonts: fonts,
    saveOptions: saveOptions,
    title: title,
  );

  /// save API.
  Uint8List save({
    FontSubset? subset,
    SfntFont? font,
    List<PdfEmbeddedFace> faces = const <PdfEmbeddedFace>[],
    PdfSaveOptions options = const PdfSaveOptions(),
  }) {
    final List<PdfEmbeddedFace> embed = faces.isNotEmpty
        ? faces
        : (subset != null && font != null
              ? <PdfEmbeddedFace>[
                  PdfEmbeddedFace(
                    subset: subset,
                    source: font,
                    resourceName: 'F1',
                  ),
                ]
              : const <PdfEmbeddedFace>[]);
    final List<_PdfObj> objects = <_PdfObj>[];
    int nextId = 1;
    int alloc() => nextId++;

    final int infoId = alloc();
    final int catalogId = alloc();
    final int pagesId = alloc();
    final List<int> pageIds = <int>[for (final _ in pages) alloc()];
    final List<int> contentIds = <int>[for (final _ in pages) alloc()];
    final int helveticaId = alloc();
    final List<({int fontId, int cidId, int descId, int fileId, int toUnicodeId})>
        faceIds = <({int fontId, int cidId, int descId, int fileId, int toUnicodeId})>[
      for (final _ in embed)
        (
          fontId: alloc(),
          cidId: alloc(),
          descId: alloc(),
          fileId: alloc(),
          toUnicodeId: alloc(),
        ),
    ];
    int? metadataId;
    int? outputIntentId;
    int? outputProfileId;
    int? structTreeId;
    int? markInfoId;
    if (options.pdfA) {
      metadataId = alloc();
      outputIntentId = alloc();
      outputProfileId = alloc();
    }
    if (options.tagged || options.pdfA) {
      markInfoId = alloc();
    }
    if (options.tagged && outlines.isNotEmpty) {
      structTreeId = alloc();
    }
    final List<List<int>> pageImageIds = <List<int>>[
      for (final PdfPage page in pages)
        <int>[for (final PdfEmbeddedImage _ in page.images) alloc()],
    ];
    final List<List<int?>> pageMaskIds = <List<int?>>[
      for (final PdfPage page in pages)
        <int?>[
          for (final PdfEmbeddedImage img in page.images)
            img.maskBytes == null ? null : alloc(),
        ],
    ];
    final List<List<int>> pageAnnotIds = <List<int>>[
      for (final PdfPage page in pages)
        <int>[for (final PdfLinkAnnot _ in page.links) alloc()],
    ];

    objects.add(
      _PdfObj(
        infoId,
        '<</Title ${_pdfString(title)}/Author ${_pdfString(author)}'
        '/Producer ${_pdfString('Quds Office Engine')}'
        '${options.pdfA ? '/GTS_PDFXVersion ${_pdfString('PDF/A')}' : ''}>>',
      ),
    );

    final String kids = pageIds.map((int id) => '$id 0 R').join(' ');
    objects.add(
      _PdfObj(pagesId, '<</Type /Pages/Count ${pages.length}/Kids [$kids]>>'),
    );

    int? outlinesId;
    final List<int> outlineItemIds = <int>[];
    if (outlines.isNotEmpty && pageIds.isNotEmpty) {
      outlinesId = alloc();
      for (final _ in outlines) {
        outlineItemIds.add(alloc());
      }
    }

    for (int i = 0; i < embed.length; i++) {
      final PdfEmbeddedFace face = embed[i];
      final ids = faceIds[i];
      final PdfCidFont cid = PdfCidFont.build(face.subset, face.source);
      objects.add(_PdfObj(ids.fontId, cid.type0Dict(ids.cidId, ids.toUnicodeId)));
      objects.add(_PdfObj(ids.cidId, cid.cidFontDict(ids.descId)));
      objects.add(_PdfObj(ids.descId, cid.descriptorDict(ids.fileId)));
      objects.add(
        _PdfObj.stream(
          ids.fileId,
          cid.fontFile,
          extra: '/Length1 ${cid.fontFile.length}',
        ),
      );
      objects.add(
        _PdfObj.stream(ids.toUnicodeId, utf8.encode(cid.toUnicodeCmap)),
      );
    }
    objects.add(
      _PdfObj(
        helveticaId,
        '<</Type /Font/Subtype /Type1/BaseFont /Helvetica>>',
      ),
    );
    for (int i = 0; i < pages.length; i++) {
      final PdfPage page = pages[i];
      for (int j = 0; j < page.links.length; j++) {
        objects.add(
          _PdfObj(pageAnnotIds[i][j], _linkDict(page.links[j], page, pageIds)),
        );
      }
    }
    for (int i = 0; i < pages.length; i++) {
      final PdfPage page = pages[i];
      for (int j = 0; j < page.images.length; j++) {
        final PdfEmbeddedImage img = page.images[j];
        final int id = pageImageIds[i][j];
        final int? maskId = pageMaskIds[i][j];
        if (maskId != null && img.maskBytes != null) {
          objects.add(
            _PdfObj.stream(
              maskId,
              img.maskBytes!,
              extra:
                  '/Type /XObject/Subtype /Image/Width ${img.width}'
                  '/Height ${img.height}/ColorSpace /DeviceGray'
                  '/BitsPerComponent 8',
            ),
          );
        }
        final String smask = maskId == null ? '' : '/SMask $maskId 0 R';
        if (img.jpeg) {
          objects.add(
            _PdfObj.rawStream(
              id,
              img.bytes,
              extra:
                  '/Type /XObject/Subtype /Image/Width ${img.width}'
                  '/Height ${img.height}/ColorSpace /DeviceRGB'
                  '/BitsPerComponent 8/Filter /DCTDecode$smask',
            ),
          );
        } else {
          objects.add(
            _PdfObj.stream(
              id,
              img.bytes,
              extra:
                  '/Type /XObject/Subtype /Image/Width ${img.width}'
                  '/Height ${img.height}/ColorSpace /DeviceRGB'
                  '/BitsPerComponent 8$smask',
            ),
          );
        }
      }
    }

    final SfntFont? apFont =
        font ?? (embed.isNotEmpty ? embed.first.source : null);
    final List<List<int>> pageFieldIds = <List<int>>[
      for (final _ in pages) <int>[],
    ];
    final List<int> allFieldIds = <int>[];
    var needAppearances = false;
    for (int i = 0; i < pages.length; i++) {
      final PdfPage page = pages[i];
      for (final PdfAcroField field in page.acroFields) {
        if (field.name.isEmpty) {
          continue;
        }
        final PdfAppearanceBundle ap = field.type == 'Btn'
            ? PdfAppearance.button(
                startId: nextId,
                width: field.width,
                height: field.height,
                on: field.checked,
                radio: field.radio,
              )
            : PdfAppearance.text(
                startId: nextId,
                width: field.width,
                height: field.height,
                text: field.value,
                colorArgb: 0xFFFFFFFF,
                font: apFont,
                rtl: _acroRtl(field.value),
              );
        nextId = ap.nextId;
        for (final PdfAppearanceObj obj in ap.objects) {
          objects.add(_PdfObj.encoded(obj.id, obj.body));
        }
        if (ap.needAppearances) {
          needAppearances = true;
        }
        final int widgetId = alloc();
        pageFieldIds[i].add(widgetId);
        allFieldIds.add(widgetId);
        objects.add(
          _PdfObj(
            widgetId,
            _acroWidgetDict(field, page, pageIds[i], ap.formId),
          ),
        );
      }
    }
    int? acroFormId;
    if (allFieldIds.isNotEmpty) {
      acroFormId = alloc();
      final String kids = allFieldIds.map((int id) => '$id 0 R').join(' ');
      objects.add(
        _PdfObj(
          acroFormId,
          '<</Fields [$kids]/NeedAppearances ${needAppearances ? 'true' : 'false'}'
          '/DA (/Helv 11 Tf 0 g)>>',
        ),
      );
    }

    for (int i = 0; i < pages.length; i++) {
      final PdfPage page = pages[i];
      final StringBuffer fonts = StringBuffer('/F2 $helveticaId 0 R');
      for (int f = 0; f < embed.length; f++) {
        fonts.write('/${embed[f].resourceName} ${faceIds[f].fontId} 0 R');
      }
      final StringBuffer xos = StringBuffer();
      for (int j = 0; j < page.images.length; j++) {
        xos.write('/${page.images[j].name} ${pageImageIds[i][j]} 0 R');
      }
      final String xoRes = xos.isEmpty ? '' : '/XObject <<$xos>>';
      final List<int> annotIds = <int>[
        ...pageAnnotIds[i],
        ...pageFieldIds[i],
      ];
      final String annots = annotIds.isEmpty
          ? ''
          : '/Annots [${annotIds.map((int id) => '$id 0 R').join(' ')}]';
      objects.add(
        _PdfObj(
          pageIds[i],
          '<</Type /Page/Parent $pagesId 0 R/MediaBox [0 0 ${_n(page.width)} ${_n(page.height)}]'
          '/Contents ${contentIds[i]} 0 R/Resources <</Font <<$fonts>>$xoRes'
          '/ProcSet [/PDF /Text /ImageC]>>$annots>>',
        ),
      );
      objects.add(_PdfObj.stream(contentIds[i], page.content));
    }

    if (outlinesId != null && outlineItemIds.isNotEmpty) {
      for (int i = 0; i < outlines.length; i++) {
        final PdfOutlineItem item = outlines[i];
        final int pageIdx = item.pageIndex.clamp(0, pageIds.length - 1);
        final double destTop =
            pages[pageIdx].height - item.destY.clamp(0, pages[pageIdx].height);
        final StringBuffer dict = StringBuffer(
          '<</Title ${_pdfString(item.title)}/Parent $outlinesId 0 R'
          '/Dest [${pageIds[pageIdx]} 0 R /XYZ 0 ${_n(destTop)} 0]',
        );
        if (i > 0) {
          dict.write('/Prev ${outlineItemIds[i - 1]} 0 R');
        }
        if (i + 1 < outlineItemIds.length) {
          dict.write('/Next ${outlineItemIds[i + 1]} 0 R');
        }
        dict.write('>>');
        objects.add(_PdfObj(outlineItemIds[i], dict.toString()));
      }
      objects.add(
        _PdfObj(
          outlinesId,
          '<</Type /Outlines/First ${outlineItemIds.first} 0 R'
          '/Last ${outlineItemIds.last} 0 R/Count ${outlineItemIds.length}>>',
        ),
      );
    }

    if (markInfoId != null) {
      objects.add(_PdfObj(markInfoId, '<</Marked true>>'));
    }
    final List<int> structKids = <int>[];
    if (structTreeId != null && outlinesId != null) {
      for (final _ in outlines) {
        structKids.add(alloc());
      }
      for (int i = 0; i < outlines.length; i++) {
        final PdfOutlineItem item = outlines[i];
        final int pageIdx = item.pageIndex.clamp(0, pageIds.length - 1);
        objects.add(
          _PdfObj(
            structKids[i],
            '<</Type /StructElem/S /H1/P $structTreeId 0 R'
            '/Pg ${pageIds[pageIdx]} 0 R'
            '/Alt ${_pdfString(item.title)}>>',
          ),
        );
      }
      final String kidsRef = structKids.map((int id) => '$id 0 R').join(' ');
      objects.add(
        _PdfObj(
          structTreeId,
          '<</Type /StructTreeRoot/K <</Type /StructElem/S /Document'
          '/K [$kidsRef]>>>>',
        ),
      );
    }
    if (metadataId != null) {
      objects.add(
        _PdfObj.stream(
          metadataId,
          utf8.encode(_pdfaXmp(title: title, author: author)),
          extra: '/Type /Metadata/Subtype /XML',
          filter: false,
        ),
      );
    }
    if (outputProfileId != null && outputIntentId != null) {
      // Minimal sRGB ICC stub referenced by OutputIntent (PDF/A-oriented).
      objects.add(
        _PdfObj.stream(
          outputProfileId,
          utf8.encode('sRGB'),
          extra: '/N 3',
        ),
      );
      objects.add(
        _PdfObj(
          outputIntentId,
          '<</Type /OutputIntent/S /GTS_PDFA1'
          '/OutputConditionIdentifier ${_pdfString('sRGB')}'
          '/Info ${_pdfString('sRGB IEC61966-2.1')}'
          '/DestOutputProfile $outputProfileId 0 R>>',
        ),
      );
    }

    final StringBuffer catalog = StringBuffer(
      '<</Type /Catalog/Pages $pagesId 0 R',
    );
    if (outlinesId != null) {
      catalog.write('/Outlines $outlinesId 0 R');
    }
    if (markInfoId != null) {
      catalog.write('/MarkInfo $markInfoId 0 R');
    }
    if (structTreeId != null) {
      catalog.write('/StructTreeRoot $structTreeId 0 R');
    }
    if (metadataId != null) {
      catalog.write('/Metadata $metadataId 0 R');
    }
    if (outputIntentId != null) {
      catalog.write('/OutputIntents [$outputIntentId 0 R]');
    }
    if (options.pdfA) {
      catalog.write('/Lang ${_pdfString('en-US')}');
    }
    if (acroFormId != null) {
      catalog.write('/AcroForm $acroFormId 0 R');
    }
    catalog.write('>>');
    objects.add(_PdfObj(catalogId, catalog.toString()));

    objects.sort((a, b) => a.id - b.id);
    final BytesBuilder body = BytesBuilder(copy: false);
    body.add(utf8.encode('%PDF-1.7\n%\xE2\xE3\xCF\xD3\n'));
    final List<int> offsets = List<int>.filled(nextId, 0);
    for (final _PdfObj obj in objects) {
      offsets[obj.id] = body.length;
      body.add(obj.serialize());
    }
    final int xrefAt = body.length;
    final StringBuffer xref = StringBuffer('xref\n0 $nextId\n');
    xref.write('0000000000 65535 f \n');
    for (int i = 1; i < nextId; i++) {
      xref.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    body.add(utf8.encode(xref.toString()));
    final int id1 = Crc32.compute(utf8.encode(title));
    final int id2 = Crc32.compute(body.toBytes());
    body.add(
      utf8.encode(
        'trailer\n<</Size $nextId/Root $catalogId 0 R/Info $infoId 0 R'
        '/ID [<${id1.toRadixString(16).padLeft(8, '0')}>'
        '<${id2.toRadixString(16).padLeft(8, '0')}>]>>\n'
        'startxref\n$xrefAt\n%%EOF\n',
      ),
    );
    return body.takeBytes();
  }

  static String _pdfaXmp({required String title, required String author}) {
    final String safeTitle = _xmlEscape(title);
    final String safeAuthor = _xmlEscape(author);
    return '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">'
        '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">$safeTitle'
        '</rdf:li></rdf:Alt></dc:title>'
        '<dc:creator><rdf:Seq><rdf:li>$safeAuthor</rdf:li></rdf:Seq></dc:creator>'
        '<pdfaid:part>2</pdfaid:part><pdfaid:conformance>B</pdfaid:conformance>'
        '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _n(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3);

  String _linkDict(PdfLinkAnnot link, PdfPage page, List<int> pageIds) {
    final double llx = link.x;
    final double lly = page.height - (link.y + link.height);
    final double urx = link.x + link.width;
    final double ury = page.height - link.y;
    final String rect = '${_n(llx)} ${_n(lly)} ${_n(urx)} ${_n(ury)}';
    final String action;
    final String? uri = link.uri;
    final int? destPage = link.destPage;
    final String? file = link.file;
    if (uri != null && uri.isNotEmpty) {
      action = '/A <</S /URI/URI ${_pdfUri(uri)}>>';
    } else if (destPage != null && destPage >= 0 && destPage < pageIds.length) {
      final double destTop = pages[destPage].height - (link.destY ?? 0);
      action =
          '/A <</S /GoTo/D [${pageIds[destPage]} 0 R /XYZ 0 ${_n(destTop)} 0]>>';
    } else if (file != null && file.isNotEmpty) {
      action = '/A <</S /Launch/F ${_pdfString(file)}>>';
    } else {
      action = '';
    }
    return '<</Type /Annot/Subtype /Link/Rect [$rect]/Border [0 0 0]/H /I$action>>';
  }

  static bool _acroRtl(String text) {
    for (final int cp in text.runes) {
      if ((cp >= 0x0590 && cp <= 0x08FF) ||
          (cp >= 0xFB1D && cp <= 0xFDFF) ||
          (cp >= 0xFE70 && cp <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }

  String _acroWidgetDict(
    PdfAcroField field,
    PdfPage page,
    int pageId,
    int apId,
  ) {
    final double llx = field.x;
    final double lly = page.height - (field.y + field.height);
    final double urx = field.x + field.width;
    final double ury = page.height - field.y;
    final String rect = '${_n(llx)} ${_n(lly)} ${_n(urx)} ${_n(ury)}';
    final StringBuffer buf = StringBuffer(
      '<</Type /Annot/Subtype /Widget/FT /${field.type}'
      '/T ${_pdfString(field.name)}/Rect [$rect]/P $pageId 0 R/F 4'
      '/AP <</N $apId 0 R>>',
    );
    if (field.type == 'Btn') {
      final String on = _sanitizeName(field.exportOn);
      buf.write(field.checked ? '/V /$on/AS /$on' : '/V /Off/AS /Off');
      if (field.radio) {
        buf.write('/Ff 32768');
      } else {
        buf.write('/Ff 0');
      }
    } else if (field.type == 'Ch') {
      buf.write('/V ${_pdfString(field.value)}');
      if (field.options.isNotEmpty) {
        buf.write('/Opt [');
        for (final String opt in field.options) {
          buf.write(_pdfString(opt));
        }
        buf.write(']');
      }
    } else {
      buf.write('/V ${_pdfString(field.value)}');
      if (field.multiline) {
        buf.write('/Ff 4096');
      }
    }
    buf.write('>>');
    return buf.toString();
  }

  static String _sanitizeName(String name) {
    final String cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return cleaned.isEmpty ? 'Yes' : cleaned;
  }

  static String _pdfString(String value) {
    var ascii = true;
    for (final int unit in value.codeUnits) {
      if (unit > 127) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      final String escaped = value
          .replaceAll('\\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      return '($escaped)';
    }
    // PDF Unicode string: UTF-16BE with BOM.
    final StringBuffer hex = StringBuffer('feff');
    for (final int unit in value.codeUnits) {
      hex.write((unit >> 8).toRadixString(16).padLeft(2, '0'));
      hex.write((unit & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return '<$hex>';
  }

  static String _pdfUri(String value) {
    var ascii = true;
    for (final int unit in value.codeUnits) {
      if (unit < 32 || unit > 126) {
        ascii = false;
        break;
      }
    }
    if (ascii) {
      return _pdfString(value);
    }
    final String hex = utf8.encode(value).map((int b) {
      return b.toRadixString(16).padLeft(2, '0');
    }).join();
    return '<$hex>';
  }
}

/// Class PdfEmbeddedImage.
class PdfEmbeddedImage {
  /// PdfEmbeddedImage API.
  const PdfEmbeddedImage({
    required this.name,
    required this.width,
    required this.height,
    required this.bytes,
    this.jpeg = false,
    this.maskBytes,
  });

  /// name API.
  final String name;

  /// width API.
  final int width;

  /// height API.
  final int height;

  /// bytes API.
  final Uint8List bytes;

  /// jpeg API.
  final bool jpeg;

  /// Soft-mask bytes (`DeviceGray`, same size as [bytes] pixels).
  final Uint8List? maskBytes;
}

/// Bookmark entry for the PDF document outline tree.
class PdfOutlineItem {
  /// PdfOutlineItem API.
  const PdfOutlineItem({
    required this.title,
    required this.pageIndex,
    this.destY = 0,
  });

  /// Visible outline title.
  final String title;

  /// Zero-based index into [PdfDocument.pages].
  final int pageIndex;

  /// Destination Y in top-left page space.
  final double destY;
}

/// Class PdfLinkAnnot.
class PdfLinkAnnot {
  /// PdfLinkAnnot API.
  const PdfLinkAnnot({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.uri,
    this.destPage,
    this.destY,
    this.file,
  });

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// uri API.
  final String? uri;

  /// destPage API.
  final int? destPage;

  /// destY API.
  final double? destY;

  /// file API.
  final String? file;
}

/// Class PdfPage.
class PdfPage {
  /// PdfPage API.
  PdfPage({
    required this.width,
    required this.height,
    required this.content,
    this.images = const <PdfEmbeddedImage>[],
    this.links = const <PdfLinkAnnot>[],
    this.acroFields = const <PdfAcroField>[],
  });

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// content API.
  final Uint8List content;

  /// images API.
  final List<PdfEmbeddedImage> images;

  /// links API.
  final List<PdfLinkAnnot> links;

  /// Real AcroForm widgets on this page (optional).
  final List<PdfAcroField> acroFields;
}

class _PdfObj {
  /// stream API.
  _PdfObj(this.id, this.dict)
    : stream = null,
      extra = '',
      applyFlateFilter = true,
      encoded = null;

  /// Already-encoded object body (dict or stream, no `obj` wrapper).
  _PdfObj.encoded(this.id, Uint8List this.encoded)
    : dict = '',
      stream = null,
      extra = '',
      applyFlateFilter = false;

  /// stream API.
  _PdfObj.stream(
    this.id,
    List<int> data, {
    this.extra = '',
    bool filter = true,
  }) : dict = '',
       stream = filter
           ? PdfFlate.compress(data)
           : (data is Uint8List ? data : Uint8List.fromList(data)),
       applyFlateFilter = filter,
       encoded = null;

  /// rawStream API.
  _PdfObj.rawStream(this.id, List<int> data, {this.extra = ''})
    : dict = '',
      stream = data is Uint8List ? data : Uint8List.fromList(data),
      applyFlateFilter = false,
      encoded = null;

  /// id API.
  final int id;

  /// dict API.
  final String dict;

  /// stream API.
  final Uint8List? stream;

  /// extra API.
  final String extra;

  /// When false, omit `/Filter /FlateDecode` (e.g. XMP metadata).
  final bool applyFlateFilter;

  /// Prebuilt object body.
  final Uint8List? encoded;

  /// serialize API.
  Uint8List serialize() {
    if (encoded != null) {
      final BytesBuilder b = BytesBuilder(copy: false);
      b.add(utf8.encode('$id 0 obj\n'));
      b.add(encoded!);
      b.add(utf8.encode('\nendobj\n'));
      return b.takeBytes();
    }
    if (stream == null) {
      return utf8.encode('$id 0 obj\n$dict\nendobj\n');
    }
    final String filter = !applyFlateFilter || extra.contains('/Filter')
        ? ''
        : '/Filter /FlateDecode ';
    final String header =
        '$id 0 obj\n<</Length ${stream!.length}$filter$extra>>\nstream\n';
    final BytesBuilder b = BytesBuilder(copy: false);
    b.add(utf8.encode(header));
    b.add(stream!);
    b.add(utf8.encode('\nendstream\nendobj\n'));
    return b.takeBytes();
  }
}
