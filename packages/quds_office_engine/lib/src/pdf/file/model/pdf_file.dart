import 'dart:convert';
import 'dart:typed_data';

import '../../../fonts/sfnt_parser.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_cos_reader.dart';
import '../cos/pdf_open_error.dart';
import '../cos/pdf_store.dart';
import '../cos/pdf_xref.dart';
import '../crypto/pdf_security.dart';
import '../decode/pdf_cms.dart';
import '../interp/pdf_display_list.dart';
import '../interp/pdf_interpreter.dart';
import '../text/pdf_stream_redact.dart';
import '../tools/pdf_page_graft.dart';
import 'pdf_annot.dart';
import 'pdf_extra.dart';
import 'pdf_form.dart';
import 'pdf_page_info.dart';

/// Opened PDF file (ISO 32000). Parallel to OOXML models — not the writer.
class PdfFile {
  /// PdfFile API.
  PdfFile._({
    required this.originalBytes,
    required this.version,
    required this.store,
    required this.info,
    required this._pages,
    required this.outline,
    required this.form,
    required this.permissions,
    required this.encrypted,
    required this.catalogObjectId,
    required this.pagesObjectId,
    required this.infoObjectId,
    required this.layers,
    required this.embeddedFiles,
    this.structTree,
    this.viewerPrefs = const PdfViewerPrefs(),
  });

  /// Original file bytes (for incremental save).
  Uint8List originalBytes;

  /// Header version, e.g. `1.7`.
  String version;

  /// store API.
  PdfCosStore store;

  /// info API.
  PdfDocInfo info;

  /// outline API.
  PdfOutlineNode? outline;

  /// form API.
  PdfAcroForm form;

  /// permissions API.
  PdfSecurity? permissions;

  /// encrypted API.
  bool encrypted;

  /// Catalog object number (`trailer /Root`).
  int catalogObjectId;

  /// `/Pages` tree object number.
  int pagesObjectId;

  /// Trailer `/Info` object number when present.
  int? infoObjectId;

  /// Optional content groups.
  List<PdfLayer> layers;

  /// Embedded files (not loaded until listed).
  List<PdfEmbeddedFile> embeddedFiles;

  /// Tagged structure when `/StructTreeRoot` is present (PDF/UA read).
  PdfStructNode? structTree;

  /// Catalog `/ViewerPreferences`.
  PdfViewerPrefs viewerPrefs;

  /// Face used when generating FreeText / Tx `/AP` streams.
  SfntFont? appearanceFont;

  /// Page-tree mutations need a `/Kids` rewrite.
  var treeDirty = false;

  /// Info dictionary was edited.
  var infoDirty = false;

  /// Content-removal redaction rectangles (extract filter).
  final List<PdfRedactRect> redactions = <PdfRedactRect>[];

  final List<PdfPageRec> _pages;
  var _nextAnnotId = 1;

  /// open API.
  static PdfFile open(Uint8List bytes, {String? password}) {
    if (bytes.length > 256 * 1024 * 1024) {
      throw const PdfOpenException(PdfOpenError.limit, 'File too large');
    }
    final PdfCosReader reader = PdfCosReader(bytes);
    final String version = reader.readHeaderVersion();
    final PdfXrefTable xref = PdfXref.parse(bytes, reader);
    PdfSecurity? security;
    final PdfCos? encryptRef = xref.trailer['Encrypt'];
    if (encryptRef != null) {
      final PdfCosStore probe = PdfCosStore(
        bytes: bytes,
        xref: xref,
        reader: reader,
      );
      final PdfCosDict? enc = probe.asDict(encryptRef);
      if (enc != null) {
        final PdfCos? idArr = xref.trailer['ID'];
        final PdfCos? id0 = idArr is PdfCosArray && idArr.items.isNotEmpty
            ? idArr.items.first
            : null;
        security = PdfSecurity.open(enc, id0, password: password);
      }
    }
    final PdfCosStore store = PdfCosStore(
      bytes: bytes,
      xref: xref,
      reader: reader,
      security: security,
    );
    PdfCosDict? catalog = store.asDict(xref.trailer['Root']);
    if (catalog == null) {
      for (final PdfXrefEntry entry in xref.entries.values) {
        if (!entry.inUse) {
          continue;
        }
        final PdfCosDict? dict = store.asDict(PdfCosRef(entry.id, entry.gen));
        if (pdfCosName(dict?['Type']) == 'Catalog') {
          catalog = dict;
          break;
        }
      }
    }
    if (catalog == null) {
      throw const PdfOpenException(PdfOpenError.badXref, 'Missing catalog');
    }
    final List<PdfPageRec> pages = <PdfPageRec>[];
    _walkPages(store, catalog['Pages'], pages, _Inherit.empty, 0);
    if (pages.length > 10000) {
      throw const PdfOpenException(PdfOpenError.limit, 'Too many pages');
    }
    _applyLabels(store, catalog, pages);
    final PdfDocInfo info = _readInfo(store, xref.trailer);
    final PdfOutlineNode? outline = _readOutline(
      store,
      catalog,
      catalog['Outlines'],
      pages,
    );
    final PdfAcroForm form = _readForm(store, catalog['AcroForm'], pages);
    final PdfCos? rootRef = xref.trailer['Root'];
    final PdfCos? pagesRef = catalog['Pages'];
    final PdfCos? infoRef = xref.trailer['Info'];
    final PdfFile file = PdfFile._(
      originalBytes: bytes,
      version: version,
      store: store,
      info: info,
      pages: pages,
      outline: outline,
      form: form,
      permissions: security,
      encrypted: security != null,
      catalogObjectId: rootRef is PdfCosRef ? rootRef.id : 1,
      pagesObjectId: pagesRef is PdfCosRef ? pagesRef.id : 0,
      infoObjectId: infoRef is PdfCosRef ? infoRef.id : null,
      layers: _readLayers(store, catalog),
      embeddedFiles: _readEmbedded(store, catalog),
      structTree: _readStruct(store, catalog, pages),
      viewerPrefs: _readViewerPrefs(store, catalog),
    );
    for (final PdfPageRec rec in pages) {
      rec.annots = _readAnnots(
        store,
        rec.dict,
        pages,
        file,
        rec.info.cropBox,
        catalog,
      );
    }
    return file;
  }

  /// pageCount API.
  int get pageCount => _pages.length;

  /// pageAt API.
  PdfPageInfo pageAt(int index) =>
      _pages[index.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1)].info;

  /// pageRec API.
  PdfPageRec pageRec(int index) =>
      _pages[index.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1)];

  /// pageRecs API.
  List<PdfPageRec> get pageRecs => _pages;

  /// pageDict API.
  PdfCosDict pageDict(int index) => _pages[index].dict;

  /// isDirty API.
  bool get isDirty =>
      treeDirty || infoDirty || _pages.any((PdfPageRec p) => p.dirty);

  /// annotsOn API.
  List<PdfAnnot> annotsOn(int index) => _pages[index].annots;

  /// displayList API.
  PdfDisplayList displayList(int pageIndex) {
    final PdfPageRec rec = _pages[pageIndex.clamp(0, _pages.length - 1)];
    final List<PdfHotspot> spots = <PdfHotspot>[
      for (final PdfAnnot annot in rec.annots)
        if (annot.uri != null || annot.goToPage != null)
          PdfHotspot(
            rect: annot.rect,
            action: PdfLinkAction(
              uri: annot.uri,
              pageIndex: annot.goToPage,
              destY: annot.goToY,
              kind: annot.uri != null ? PdfLinkKind.uri : PdfLinkKind.goTo,
            ),
            annotId: annot.id,
          ),
    ];
    try {
      return PdfInterpreter(store, layers: layers).interpret(
        page: rec.info,
        pageDict: rec.dict,
        hotspots: spots,
      );
    } catch (_) {
      return PdfDisplayList(
        page: rec.info,
        ops: const <PdfPaintOp>[],
        runs: const <PdfTextRun>[],
        hotspots: spots,
      );
    }
  }

  /// displayLists API.
  List<PdfDisplayList> displayLists() => <PdfDisplayList>[
    for (int i = 0; i < _pages.length; i++) displayList(i),
  ];

  /// addAnnot API.
  PdfAnnot addAnnot(int pageIndex, PdfAnnot annot) {
    final PdfPageRec rec = _pages[pageIndex.clamp(0, _pages.length - 1)];
    final PdfAnnot next = PdfAnnot(
      id: _nextAnnotId++,
      subtype: annot.subtype,
      rect: annot.rect,
      quads: annot.quads,
      contents: annot.contents,
      color: annot.color,
      uri: annot.uri,
      goToPage: annot.goToPage,
      goToY: annot.goToY,
      ink: annot.ink,
      fieldName: annot.fieldName,
    );
    rec.annots.add(next);
    rec.dirty = true;
    return next;
  }

  /// removeAnnot API.
  bool removeAnnot(int pageIndex, int annotId) {
    final PdfPageRec rec = _pages[pageIndex.clamp(0, _pages.length - 1)];
    final int before = rec.annots.length;
    rec.annots.removeWhere((PdfAnnot a) => a.id == annotId);
    rec.dirty = rec.annots.length != before;
    return rec.dirty;
  }

  /// markDirty API.
  void markDirty(int pageIndex) {
    _pages[pageIndex.clamp(0, _pages.length - 1)].dirty = true;
  }

  /// dirtyPages API.
  List<PdfPageRec> get dirtyPages =>
      _pages.where((PdfPageRec p) => p.dirty).toList();

  /// nextObjectId API.
  int get nextObjectId {
    var max = 0;
    for (final int id in store.xref.entries.keys) {
      if (id > max) {
        max = id;
      }
    }
    return max + 1;
  }

  /// insertPage API.
  void insertBlankPage(int index, {double width = 595.28, double height = 841.89}) {
    final int at = index.clamp(0, _pages.length);
    final PdfPageInfo info = PdfPageInfo(
      index: at,
      mediaBox: PdfBox(llx: 0, lly: 0, urx: width, ury: height),
      cropBox: PdfBox(llx: 0, lly: 0, urx: width, ury: height),
    );
    _pages.insert(
      at,
      PdfPageRec(
        info: info,
        dict: PdfCosDict(),
        annots: <PdfAnnot>[],
        dirty: true,
        pendingContent: Uint8List(0),
      ),
    );
    treeDirty = true;
    _reindex();
  }

  /// deletePage API.
  void deletePage(int index) {
    if (_pages.length <= 1) {
      return;
    }
    _pages.removeAt(index.clamp(0, _pages.length - 1));
    treeDirty = true;
    _reindex();
    if (_pages.isNotEmpty) {
      _pages.first.dirty = true;
    }
  }

  /// rotatePage API.
  void rotatePage(int index, int degrees) {
    final PdfPageRec rec = _pages[index.clamp(0, _pages.length - 1)];
    rec.info = PdfPageInfo(
      index: rec.info.index,
      mediaBox: rec.info.mediaBox,
      cropBox: rec.info.cropBox,
      bleedBox: rec.info.bleedBox,
      trimBox: rec.info.trimBox,
      artBox: rec.info.artBox,
      rotate: ((rec.info.rotate + degrees) % 360 + 360) % 360,
      label: rec.info.label,
    );
    rec.dirty = true;
  }

  /// setInfo API.
  void setInfo({String? title, String? author, String? subject}) {
    info = PdfDocInfo(
      title: title ?? info.title,
      author: author ?? info.author,
      subject: subject ?? info.subject,
      keywords: info.keywords,
      creator: info.creator,
      producer: info.producer,
      xmp: info.xmp,
      pdfAPart: info.pdfAPart,
      pdfAConformance: info.pdfAConformance,
    );
    infoDirty = true;
  }

  /// appendPages API. Grafts both files so fonts and images survive.
  void appendPages(PdfFile other) {
    if (other.pageCount == 0) {
      return;
    }
    final Uint8List bytes = PdfPageGraft.write(<PdfGraftSlot>[
      for (int i = 0; i < pageCount; i++) PdfGraftSlot.page(this, i),
      for (int i = 0; i < other.pageCount; i++) PdfGraftSlot.page(other, i),
    ]);
    _adopt(PdfFile.open(bytes));
  }

  /// mergeFrom API. Same graft as [appendPages].
  void mergeFrom(PdfFile other) => appendPages(other);

  void _adopt(PdfFile src) {
    final SfntFont? keepFont = appearanceFont;
    originalBytes = src.originalBytes;
    version = src.version;
    store = src.store;
    info = src.info;
    outline = src.outline;
    form = src.form;
    permissions = src.permissions;
    encrypted = src.encrypted;
    catalogObjectId = src.catalogObjectId;
    pagesObjectId = src.pagesObjectId;
    infoObjectId = src.infoObjectId;
    layers = src.layers;
    embeddedFiles = src.embeddedFiles;
    structTree = src.structTree;
    viewerPrefs = src.viewerPrefs;
    appearanceFont = keepFont ?? src.appearanceFont;
    _pages
      ..clear()
      ..addAll(src._pages);
    treeDirty = false;
    infoDirty = false;
    redactions
      ..clear()
      ..addAll(src.redactions);
    _nextAnnotId = src._nextAnnotId;
  }

  /// extractPages API. Copies page resources; indices may repeat a page.
  Uint8List extractPages(List<int> indices) {
    final List<PdfGraftSlot> slots = <PdfGraftSlot>[
      for (final int i in indices)
        if (i >= 0 && i < _pages.length) PdfGraftSlot.page(this, i),
    ];
    return PdfPageGraft.write(slots);
  }

  /// setLayerVisible API.
  void setLayerVisible(int objectId, bool visible) {
    for (final PdfLayer layer in layers) {
      if (layer.objectId == objectId) {
        layer.visible = visible;
      }
    }
  }

  /// Toggle a layer by list index. Re-interpret via [displayList].
  void setLayerVisibleAt(int index, bool visible) {
    if (index < 0 || index >= layers.length) {
      return;
    }
    layers[index].visible = visible;
  }

  /// redactRect API.
  void redactRect(
    int pageIndex,
    PdfRect rect, {
    PdfRedactMode mode = PdfRedactMode.visual,
  }) {
    addAnnot(
      pageIndex,
      PdfAnnot(
        id: 0,
        subtype: 'Redact',
        rect: rect,
        color: 0xFF000000,
        contents: mode == PdfRedactMode.removeContent ? 'remove' : '',
      ),
    );
    if (mode == PdfRedactMode.removeContent) {
      redactions.add(PdfRedactRect(pageIndex: pageIndex, rect: rect));
      final PdfPageRec rec = pageRec(pageIndex);
      final String overlay =
          'q 0 0 0 rg ${rect.x} ${rect.y} ${rect.width} ${rect.height} re f Q\n';
      final String stripped = PdfStreamRedactor.strip(
        utf8.decode(_pageStream(rec.dict), allowMalformed: true),
        rect,
      );
      rec.pendingContent = Uint8List.fromList(utf8.encode('$stripped\n$overlay'));
      rec.dirty = true;
    }
  }

  Uint8List _pageStream(PdfCosDict dict) {
    final PdfCos? contents = dict['Contents'];
    if (contents is PdfCosArray) {
      final BytesBuilder out = BytesBuilder(copy: false);
      for (final PdfCos item in contents.items) {
        final Uint8List? part = store.streamBytes(item);
        if (part != null) {
          out.add(part);
          out.addByte(0x0A);
        }
      }
      return out.takeBytes();
    }
    return store.streamBytes(contents) ?? Uint8List(0);
  }

  /// signatures API — ByteRange coverage plus CMS `messageDigest` when present.
  List<PdfSignatureInfo> get signatures {
    final List<PdfSignatureInfo> out = <PdfSignatureInfo>[];
    for (final PdfFormField field in form.fields) {
      if (field.type != 'Sig') {
        continue;
      }
      final PdfCosDict? widget = field.objectId == null
          ? null
          : store.asDict(PdfCosRef(field.objectId!));
      final PdfCosDict? value = widget == null
          ? null
          : store.asDict(widget['V']);
      out.add(
        PdfSignatureInfo(
          fieldName: field.name,
          status: _signatureStatus(value),
          byteRangeLength: _byteRangeCovered(value),
        ),
      );
    }
    return out;
  }

  PdfSignatureStatus _signatureStatus(PdfCosDict? value) {
    if (value == null) {
      return PdfSignatureStatus.broken;
    }
    final String filter = pdfCosName(value['Filter']) ?? '';
    if (filter.isNotEmpty && !_knownSigFilters.contains(filter)) {
      return PdfSignatureStatus.unsupported;
    }
    final PdfCosArray? range = store.asArray(value['ByteRange']);
    if (range == null || range.items.length < 4) {
      return PdfSignatureStatus.broken;
    }
    final int a = pdfCosInt(range.items[0]) ?? -1;
    final int b = pdfCosInt(range.items[1]) ?? -1;
    final int c = pdfCosInt(range.items[2]) ?? -1;
    final int d = pdfCosInt(range.items[3]) ?? -1;
    final int len = originalBytes.length;
    if (a != 0 || b < 0 || c < a + b || d < 0 || c + d > len) {
      return PdfSignatureStatus.broken;
    }
    if (c + d != len) {
      return PdfSignatureStatus.broken;
    }
    final PdfCos? contents = value['Contents'];
    final Uint8List cms = contents is PdfCosString
        ? contents.bytes
        : Uint8List(0);
    final Uint8List signed = Uint8List(b + d);
    signed.setAll(0, originalBytes.sublist(a, a + b));
    signed.setAll(b, originalBytes.sublist(c, c + d));
    return PdfCms.verify(contents: cms, signedBytes: signed);
  }

  static int _byteRangeCovered(PdfCosDict? value) {
    final PdfCos? raw = value?['ByteRange'];
    if (raw is! PdfCosArray || raw.items.length < 4) {
      return 0;
    }
    return (pdfCosInt(raw.items[1]) ?? 0) + (pdfCosInt(raw.items[3]) ?? 0);
  }

  static const Set<String> _knownSigFilters = <String>{
    'Adobe.PPKLite',
    'Adobe.PPKMS',
    'ETSI.CAdES.detached',
  };

  /// pdfAProfile API — detection only; never a certification claim.
  String? get pdfAProfile {
    if (info.pdfAPart == null) {
      return null;
    }
    return 'PDF/A-${info.pdfAPart}${info.pdfAConformance ?? ''}';
  }

  /// incrementalSaveWarnsPdfA API.
  bool get incrementalSaveWarnsPdfA => info.pdfAPart != null;

  void _reindex() {
    for (int i = 0; i < _pages.length; i++) {
      final PdfPageRec rec = _pages[i];
      rec.info = PdfPageInfo(
        index: i,
        mediaBox: rec.info.mediaBox,
        cropBox: rec.info.cropBox,
        bleedBox: rec.info.bleedBox,
        trimBox: rec.info.trimBox,
        artBox: rec.info.artBox,
        rotate: rec.info.rotate,
        label: rec.info.label,
      );
    }
  }

  static void _walkPages(
    PdfCosStore store,
    PdfCos? node,
    List<PdfPageRec> out,
    _Inherit inherit,
    int depth,
  ) {
    if (depth > 64 || out.length > 10000) {
      throw const PdfOpenException(PdfOpenError.limit);
    }
    final PdfCosDict? dict = store.asDict(node);
    if (dict == null) {
      return;
    }
    final _Inherit next = inherit.child(dict);
    final String type = pdfCosName(dict['Type']) ?? '';
    if (type == 'Page' || (type.isEmpty && dict['Kids'] == null && dict['MediaBox'] != null)) {
      final PdfBox media = next.media ?? const PdfBox(llx: 0, lly: 0, urx: 595.28, ury: 841.89);
      final PdfBox crop = next.crop ?? media;
      out.add(
        PdfPageRec(
          info: PdfPageInfo(
            index: out.length,
            mediaBox: media,
            cropBox: crop,
            bleedBox: next.bleed,
            trimBox: next.trim,
            artBox: next.art,
            rotate: next.rotate,
          ),
          dict: dict,
          annots: <PdfAnnot>[],
          objectId: node is PdfCosRef ? node.id : null,
        ),
      );
      return;
    }
    final PdfCosArray? kids = store.asArray(dict['Kids']);
    if (kids == null) {
      return;
    }
    for (final PdfCos kid in kids.items) {
      _walkPages(store, kid, out, next, depth + 1);
    }
  }

  static void _applyLabels(
    PdfCosStore store,
    PdfCosDict catalog,
    List<PdfPageRec> pages,
  ) {
    final PdfCosDict? nums = store.asDict(catalog['PageLabels']);
    final PdfCosArray? arr = nums == null ? null : store.asArray(nums['Nums']);
    if (arr == null) {
      return;
    }
    var style = 'D';
    var prefix = '';
    var start = 1;
    var from = 0;
    for (int i = 0; i + 1 < arr.items.length; i += 2) {
      from = pdfCosInt(arr.items[i]) ?? 0;
      final PdfCosDict? spec = store.asDict(arr.items[i + 1]);
      if (spec != null) {
        style = pdfCosName(spec['S']) ?? style;
        prefix = pdfCosText(spec['P']) ?? prefix;
        start = pdfCosInt(spec['St']) ?? 1;
      }
      for (int p = from; p < pages.length; p++) {
        final int n = start + (p - from);
        pages[p].info = PdfPageInfo(
          index: pages[p].info.index,
          mediaBox: pages[p].info.mediaBox,
          cropBox: pages[p].info.cropBox,
          bleedBox: pages[p].info.bleedBox,
          trimBox: pages[p].info.trimBox,
          artBox: pages[p].info.artBox,
          rotate: pages[p].info.rotate,
          label: '$prefix$n',
        );
      }
    }
  }

  static PdfDocInfo _readInfo(PdfCosStore store, PdfCosDict trailer) {
    final PdfCosDict? info = store.asDict(trailer['Info']);
    String xmp = '';
    String? part;
    String? conf;
    final PdfCosDict? catalog = store.asDict(trailer['Root']);
    final Uint8List? meta = catalog == null
        ? null
        : store.streamBytes(catalog['Metadata']);
    if (meta != null) {
      xmp = utf8.decode(meta, allowMalformed: true);
      final RegExpMatch? p = RegExp(
        r'pdfaid:part[>\"]+\s*(\d+)',
      ).firstMatch(xmp);
      final RegExpMatch? c = RegExp(
        r'pdfaid:conformance[>\"]+\s*([A-Z])',
      ).firstMatch(xmp);
      part = p?.group(1);
      conf = c?.group(1);
    }
    return PdfDocInfo(
      title: pdfCosText(info?['Title']) ?? '',
      author: pdfCosText(info?['Author']) ?? '',
      subject: pdfCosText(info?['Subject']) ?? '',
      keywords: pdfCosText(info?['Keywords']) ?? '',
      creator: pdfCosText(info?['Creator']) ?? '',
      producer: pdfCosText(info?['Producer']) ?? '',
      xmp: xmp,
      pdfAPart: part,
      pdfAConformance: conf,
    );
  }

  static PdfOutlineNode? _readOutline(
    PdfCosStore store,
    PdfCosDict catalog,
    PdfCos? outlines,
    List<PdfPageRec> pages,
  ) {
    final PdfCosDict? dict = store.asDict(outlines);
    if (dict == null) {
      return null;
    }
    final PdfOutlineNode root = PdfOutlineNode(title: '');
    _walkOutline(store, catalog, dict['First'], root, pages, 0);
    return root.children.isEmpty ? null : root;
  }

  static void _walkOutline(
    PdfCosStore store,
    PdfCosDict catalog,
    PdfCos? node,
    PdfOutlineNode parent,
    List<PdfPageRec> pages,
    int depth,
  ) {
    if (depth > 64) {
      return;
    }
    PdfCos? current = node;
    var hops = 0;
    while (current != null && hops < 4096) {
      hops++;
      final PdfCosDict? dict = store.asDict(current);
      if (dict == null) {
        break;
      }
      final String title = pdfCosText(dict['Title']) ?? '';
      final PdfLinkAction dest = _dest(
        store,
        catalog,
        dict['Dest'] ?? dict['A'],
        pages,
      );
      final PdfOutlineNode item = PdfOutlineNode(
        title: title,
        pageIndex: dest.pageIndex,
        destY: dest.destY,
        uri: dest.uri,
      );
      parent.children.add(item);
      _walkOutline(store, catalog, dict['First'], item, pages, depth + 1);
      current = dict['Next'];
    }
  }

  static PdfLinkAction _dest(
    PdfCosStore store,
    PdfCosDict catalog,
    PdfCos? dest,
    List<PdfPageRec> pages, {
    int depth = 0,
  }) {
    if (depth > 8) {
      return const PdfLinkAction(kind: PdfLinkKind.ignored);
    }
    PdfCos? value = store.deref(dest);
    if (value is PdfCosDict) {
      final String s = pdfCosName(value['S']) ?? '';
      if (s == 'URI') {
        return PdfLinkAction(uri: pdfCosText(value['URI']), kind: PdfLinkKind.uri);
      }
      if (s == 'GoTo') {
        value = store.deref(value['D']);
      } else if (s == 'GoToR') {
        return PdfLinkAction(
          remoteFile: pdfCosText(value['F']),
          kind: PdfLinkKind.goToR,
        );
      } else if (s == 'Launch' || s == 'JavaScript' || s == 'SubmitForm') {
        return const PdfLinkAction(kind: PdfLinkKind.ignored);
      } else if (value['D'] != null && s.isEmpty) {
        // Destination dictionary (ISO 32000-1 §12.3.2.3).
        value = store.deref(value['D']);
      }
    }
    if (value is PdfCosName || value is PdfCosString) {
      final String key =
          value is PdfCosName ? value.value : (value as PdfCosString).asText;
      final PdfCos? named = _lookupNamedDest(store, catalog, key);
      if (named != null) {
        return _dest(store, catalog, named, pages, depth: depth + 1);
      }
      return const PdfLinkAction(kind: PdfLinkKind.named);
    }
    if (value is PdfCosArray && value.items.isNotEmpty) {
      final int? page = _pageIndex(store, value.items.first, pages);
      final double? y = value.items.length > 3
          ? pdfCosNumber(value.items[3])
          : null;
      return PdfLinkAction(pageIndex: page, destY: y, kind: PdfLinkKind.goTo);
    }
    return const PdfLinkAction(kind: PdfLinkKind.ignored);
  }

  /// Resolves a named destination from `Catalog/Dests` or `Names/Dests`.
  static PdfCos? _lookupNamedDest(
    PdfCosStore store,
    PdfCosDict catalog,
    String name,
  ) {
    if (name.isEmpty) {
      return null;
    }
    final PdfCosDict? legacy = store.asDict(catalog['Dests']);
    if (legacy != null) {
      final PdfCos? hit = legacy[name] ?? legacy['/$name'];
      if (hit != null) {
        return store.deref(hit);
      }
    }
    final PdfCosDict? names = store.asDict(catalog['Names']);
    final PdfCosDict? tree =
        names == null ? null : store.asDict(names['Dests']);
    if (tree == null) {
      return null;
    }
    return _nameTreeLookup(store, tree, name, 0);
  }

  static PdfCos? _nameTreeLookup(
    PdfCosStore store,
    PdfCosDict node,
    String name,
    int depth,
  ) {
    if (depth > 32) {
      return null;
    }
    final PdfCosArray? entries = store.asArray(node['Names']);
    if (entries != null) {
      for (int i = 0; i + 1 < entries.items.length; i += 2) {
        final String key = pdfCosText(entries.items[i]) ??
            pdfCosName(entries.items[i]) ??
            '';
        if (key == name) {
          return store.deref(entries.items[i + 1]);
        }
      }
    }
    final PdfCosArray? kids = store.asArray(node['Kids']);
    if (kids == null) {
      return null;
    }
    for (final PdfCos kid in kids.items) {
      final PdfCosDict? child = store.asDict(kid);
      if (child == null) {
        continue;
      }
      final PdfCosArray? limits = store.asArray(child['Limits']);
      if (limits != null && limits.items.length >= 2) {
        final String lo =
            pdfCosText(limits.items[0]) ?? pdfCosName(limits.items[0]) ?? '';
        final String hi =
            pdfCosText(limits.items[1]) ?? pdfCosName(limits.items[1]) ?? '';
        if (lo.isNotEmpty && name.compareTo(lo) < 0) {
          continue;
        }
        if (hi.isNotEmpty && name.compareTo(hi) > 0) {
          continue;
        }
      }
      final PdfCos? hit = _nameTreeLookup(store, child, name, depth + 1);
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  static int? _pageIndex(PdfCosStore store, PdfCos ref, List<PdfPageRec> pages) {
    if (ref is PdfCosNull) {
      return null;
    }
    final PdfCos? dict = store.deref(ref);
    for (int i = 0; i < pages.length; i++) {
      if (identical(pages[i].dict, dict)) {
        return i;
      }
      if (ref is PdfCosRef && pages[i].objectId == ref.id) {
        return i;
      }
    }
    if (ref is PdfCosInt) {
      final int v = ref.value;
      if (v >= 0 && v < pages.length) {
        return v;
      }
    }
    return null;
  }

  static List<PdfAnnot> _readAnnots(
    PdfCosStore store,
    PdfCosDict page,
    List<PdfPageRec> pages,
    PdfFile file,
    PdfBox crop,
    PdfCosDict catalog,
  ) {
    final PdfCosArray? arr = store.asArray(page['Annots']);
    if (arr == null) {
      return <PdfAnnot>[];
    }
    final List<PdfAnnot> out = <PdfAnnot>[];
    for (final PdfCos item in arr.items) {
      final PdfCosDict? dict = store.asDict(item);
      if (dict == null) {
        continue;
      }
      final ({double llx, double lly, double urx, double ury})? r = pdfCosRect(
        dict['Rect'],
      );
      if (r == null) {
        continue;
      }
      final PdfLinkAction action = _dest(
        store,
        catalog,
        dict['A'] ?? dict['Dest'],
        pages,
      );
      final String subtype = pdfCosName(dict['Subtype']) ?? 'Unknown';
      final double llx = r.llx < r.urx ? r.llx : r.urx;
      final double urx = r.llx < r.urx ? r.urx : r.llx;
      final double lly = r.lly < r.ury ? r.lly : r.ury;
      final double ury = r.lly < r.ury ? r.ury : r.lly;
      out.add(
        PdfAnnot(
          id: file._nextAnnotId++,
          subtype: subtype,
          rect: PdfRect(
            x: llx - crop.llx,
            y: crop.ury - ury,
            width: urx - llx,
            height: ury - lly,
          ),
          contents: pdfCosText(dict['Contents']) ?? '',
          color: _annotRgb(store, dict) ?? 0xFFFFE066,
          uri: action.uri,
          goToPage: action.pageIndex,
          goToY: action.destY,
          objectId: item is PdfCosRef ? item.id : null,
        ),
      );
    }
    return out;
  }

  /// `/C` RGB annotation color (ISO 32000-1 §12.5.3), else null.
  static int? _annotRgb(PdfCosStore store, PdfCosDict dict) {
    final PdfCosArray? arr = store.asArray(dict['C']);
    if (arr == null || arr.items.length < 3) {
      return null;
    }
    final double r = (pdfCosNumber(arr.items[0]) ?? 0).clamp(0, 1);
    final double g = (pdfCosNumber(arr.items[1]) ?? 0).clamp(0, 1);
    final double b = (pdfCosNumber(arr.items[2]) ?? 0).clamp(0, 1);
    return (0xFF << 24) |
        ((r * 255).round() << 16) |
        ((g * 255).round() << 8) |
        (b * 255).round();
  }

  static PdfAcroForm _readForm(
    PdfCosStore store,
    PdfCos? acro,
    List<PdfPageRec> pages,
  ) {
    final PdfCosDict? dict = store.asDict(acro);
    if (dict == null) {
      return PdfAcroForm();
    }
    final PdfAcroForm form = PdfAcroForm(
      needAppearances: dict['NeedAppearances'] is PdfCosBool
          ? (dict['NeedAppearances'] as PdfCosBool).value
          : false,
      hasXfa: dict['XFA'] != null,
    );
    _walkFields(store, store.asArray(dict['Fields']), form, '', pages);
    return form;
  }

  static void _walkFields(
    PdfCosStore store,
    PdfCosArray? fields,
    PdfAcroForm form,
    String prefix,
    List<PdfPageRec> pages,
  ) {
    if (fields == null) {
      return;
    }
    for (final PdfCos item in fields.items) {
      final PdfCosDict? dict = store.asDict(item);
      if (dict == null) {
        continue;
      }
      final String name = <String>[
        if (prefix.isNotEmpty) prefix,
        if (pdfCosText(dict['T']) != null) pdfCosText(dict['T'])!,
      ].join('.');
      final PdfCosArray? kids = store.asArray(dict['Kids']);
      if (kids != null && dict['FT'] == null) {
        _walkFields(store, kids, form, name, pages);
        continue;
      }
      form.fields.add(
        PdfFormField(
          name: name,
          type: pdfCosName(dict['FT']) ?? 'Tx',
          value: pdfCosText(dict['V']) ?? pdfCosName(dict['V']) ?? '',
          options: _opts(store.asArray(dict['Opt'])),
          multiline: (pdfCosInt(dict['Ff']) ?? 0) & 4096 != 0,
          readOnly: (pdfCosInt(dict['Ff']) ?? 0) & 1 != 0,
          objectId: item is PdfCosRef ? item.id : null,
        ),
      );
    }
  }

  static List<String> _opts(PdfCosArray? arr) {
    if (arr == null) {
      return const <String>[];
    }
    return <String>[
      for (final PdfCos item in arr.items)
        if (item is PdfCosString) item.asText,
    ];
  }

  static bool _flag(PdfCos? value) =>
      value is PdfCosBool && value.value;

  static PdfViewerPrefs _readViewerPrefs(
    PdfCosStore store,
    PdfCosDict catalog,
  ) {
    final PdfCosDict? dict = store.asDict(catalog['ViewerPreferences']);
    if (dict == null) {
      return const PdfViewerPrefs();
    }
    return PdfViewerPrefs(
      direction: pdfCosName(dict['Direction']) ?? 'L2R',
      fitWindow: _flag(dict['FitWindow']),
      centerWindow: _flag(dict['CenterWindow']),
      hideToolbar: _flag(dict['HideToolbar']),
      hideMenubar: _flag(dict['HideMenubar']),
      hideWindowUI: _flag(dict['HideWindowUI']),
      displayDocTitle: _flag(dict['DisplayDocTitle']),
    );
  }

  static List<PdfLayer> _readLayers(PdfCosStore store, PdfCosDict catalog) {
    final PdfCosDict? oc = store.asDict(catalog['OCProperties']);
    if (oc == null) {
      return <PdfLayer>[];
    }
    final PdfCosArray? occds = store.asArray(oc['OCGs']);
    final PdfCosDict? config = store.asDict(oc['D']);
    final Set<int> off = <int>{};
    final PdfCosArray? offArr = config == null ? null : store.asArray(config['OFF']);
    if (offArr != null) {
      for (final PdfCos item in offArr.items) {
        if (item is PdfCosRef) {
          off.add(item.id);
        }
      }
    }
    final List<PdfLayer> out = <PdfLayer>[];
    if (occds == null) {
      return out;
    }
    for (final PdfCos item in occds.items) {
      final PdfCosDict? dict = store.asDict(item);
      if (dict == null) {
        continue;
      }
      final int? id = item is PdfCosRef ? item.id : null;
      out.add(
        PdfLayer(
          name: pdfCosText(dict['Name']) ?? 'Layer',
          visible: id == null || !off.contains(id),
          objectId: id,
        ),
      );
    }
    return out;
  }

  static List<PdfEmbeddedFile> _readEmbedded(PdfCosStore store, PdfCosDict catalog) {
    final PdfCosDict? names = store.asDict(catalog['Names']);
    final PdfCosDict? tree = names == null ? null : store.asDict(names['EmbeddedFiles']);
    final PdfCosArray? arr = tree == null ? null : store.asArray(tree['Names']);
    if (arr == null) {
      return <PdfEmbeddedFile>[];
    }
    final List<PdfEmbeddedFile> out = <PdfEmbeddedFile>[];
    for (int i = 0; i + 1 < arr.items.length; i += 2) {
      final String name = pdfCosText(arr.items[i]) ?? 'file';
      final PdfCosDict? spec = store.asDict(arr.items[i + 1]);
      final PdfCosDict? ef = spec == null ? null : store.asDict(spec['EF']);
      final Uint8List? bytes = ef == null ? null : store.streamBytes(ef['F']);
      if (bytes != null) {
        out.add(PdfEmbeddedFile(name: name, bytes: bytes));
      }
    }
    return out;
  }

  static PdfStructNode? _readStruct(
    PdfCosStore store,
    PdfCosDict catalog,
    List<PdfPageRec> pages,
  ) {
    final PdfCosDict? root = store.asDict(catalog['StructTreeRoot']);
    if (root == null) {
      return null;
    }
    return _structNode(store, root, pages, 0);
  }

  static PdfStructNode _structNode(
    PdfCosStore store,
    PdfCosDict dict,
    List<PdfPageRec> pages,
    int depth,
  ) {
    final String role = pdfCosName(dict['S']) ??
        (pdfCosName(dict['Type']) == 'StructTreeRoot'
            ? 'StructTreeRoot'
            : 'NonStruct');
    if (depth > 32) {
      return PdfStructNode(role: role);
    }
    final List<PdfStructNode> kids = <PdfStructNode>[];
    final PdfCos? raw = store.deref(dict['K']);
    if (raw is PdfCosArray) {
      for (final PdfCos item in raw.items) {
        _addStructKid(store, item, kids, pages, depth);
      }
    } else if (raw != null) {
      _addStructKid(store, raw, kids, pages, depth);
    }
    return PdfStructNode(
      role: role,
      alt: pdfCosText(dict['Alt']) ?? '',
      actualText: pdfCosText(dict['ActualText']) ?? '',
      kids: kids,
      pageIndex: _structPage(store, dict['Pg'], pages),
      mcid: pdfCosInt(dict['MCID']),
    );
  }

  static void _addStructKid(
    PdfCosStore store,
    PdfCos item,
    List<PdfStructNode> kids,
    List<PdfPageRec> pages,
    int depth,
  ) {
    if (item is PdfCosInt) {
      kids.add(PdfStructNode(role: 'MCR', mcid: item.value));
      return;
    }
    final PdfCosDict? dict = store.asDict(item);
    if (dict == null) {
      return;
    }
    if (pdfCosName(dict['Type']) == 'MCR') {
      kids.add(
        PdfStructNode(
          role: 'MCR',
          mcid: pdfCosInt(dict['MCID']),
          pageIndex: _structPage(store, dict['Pg'], pages),
        ),
      );
      return;
    }
    kids.add(_structNode(store, dict, pages, depth + 1));
  }

  static int? _structPage(
    PdfCosStore store,
    PdfCos? pg,
    List<PdfPageRec> pages,
  ) {
    final PdfCos? ref = store.deref(pg);
    if (ref == null) {
      return null;
    }
    for (int i = 0; i < pages.length; i++) {
      if (identical(pages[i].dict, ref) ||
          (pg is PdfCosRef && pages[i].objectId == pg.id)) {
        return i;
      }
    }
    return null;
  }
}

/// Internal page record.
class PdfPageRec {
  /// PdfPageRec API.
  PdfPageRec({
    required this.info,
    required this.dict,
    required this.annots,
    this.dirty = false,
    this.objectId,
    this.pendingContent,
  });

  /// info API.
  PdfPageInfo info;

  /// dict API.
  final PdfCosDict dict;

  /// annots API.
  List<PdfAnnot> annots;

  /// dirty API.
  bool dirty;

  /// COS object number when the page already exists in the file.
  int? objectId;

  /// Decoded content to write for inserted / merged pages.
  Uint8List? pendingContent;
}

class _Inherit {
  const _Inherit({
    this.media,
    this.crop,
    this.bleed,
    this.trim,
    this.art,
    this.rotate = 0,
  });

  static const _Inherit empty = _Inherit();

  final PdfBox? media;
  final PdfBox? crop;
  final PdfBox? bleed;
  final PdfBox? trim;
  final PdfBox? art;
  final int rotate;

  _Inherit child(PdfCosDict dict) {
    return _Inherit(
      media: _box(dict['MediaBox']) ?? media,
      crop: _box(dict['CropBox']) ?? crop,
      bleed: _box(dict['BleedBox']) ?? bleed,
      trim: _box(dict['TrimBox']) ?? trim,
      art: _box(dict['ArtBox']) ?? art,
      rotate: pdfCosInt(dict['Rotate']) ?? rotate,
    );
  }

  static PdfBox? _box(PdfCos? value) {
    final ({double llx, double lly, double urx, double ury})? r = pdfCosRect(
      value,
    );
    if (r == null) {
      return null;
    }
    return PdfBox(llx: r.llx, lly: r.lly, urx: r.urx, ury: r.ury);
  }
}
