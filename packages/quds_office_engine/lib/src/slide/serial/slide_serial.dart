import 'dart:convert';
import 'dart:typed_data';

import '../../builders/drawingml_charts.dart';
import '../../builders/office_markup.dart';
import '../../builders/pptx_builder.dart';
import '../../office/office_document_properties.dart';
import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../sheet/serial/sheet_drawing_io.dart';
import '../../visual/drawingml_visual_io.dart';
import '../../visual/office_visual.dart';
import '../../visual/png_bytes.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../anim/pml_motion_io.dart';
import '../model/pml_arrange.dart';
import '../model/pml_presentation.dart';
import '../shapes/drawingml.dart';
import 'slide_section_io.dart';

/// Class SlideDeserializer.
class SlideDeserializer {
  /// read API.
  PmlPresentation read(OpcPackage package) {
    package.assertUnsignedForEditing();
    final PmlPresentation pres = PmlPresentation(
      package: package,
      slides: <PmlSlide>[],
      properties: OfficeDocumentProperties.fromPackage(package),
    );
    final part = package.getPart(_presentationUri);
    if (part == null) {
      return pres;
    }
    final RelationshipCollection presentationRels = package.relationshipsFor(
      _presentationUri,
    );
    final List<String> slideUris = <String>[];
    String? slideRelationshipIssue;
    final XmlPullReader reader = XmlPullReader(part.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'sldId' &&
          reader.namespaceUri == OfficeNamespaces.p) {
        var id = 256;
        String? relId;
        for (int a = 0; a < reader.attributeCount; a++) {
          if (reader.attributeQualifiedName(a) == 'id') {
            id = int.tryParse(reader.attributeValue(a)) ?? id;
          } else if (reader.attributeLocalName(a) == 'id' &&
              reader.attributeNamespace(a) == OfficeNamespaces.r) {
            relId = reader.attributeValue(a);
          }
        }
        pres.slides.add(PmlSlide(id: id, backgroundShapesResolved: true));
        final PackageRelationship? rel = relId == null
            ? null
            : presentationRels.byId(relId);
        if (rel == null ||
            rel.type != RelationshipTypes.slide ||
            rel.targetMode == RelationshipTargetMode.external ||
            package.getPart(presentationRels.resolve(rel))?.contentType !=
                OfficeContentTypes.slide) {
          slideRelationshipIssue =
              'Section membership requires modeled internal slide relationships.';
        }
        slideUris.add(
          rel != null && rel.type == RelationshipTypes.slide
              ? presentationRels.resolve(rel)
              : '/ppt/slides/slide${pres.slides.length}.xml',
        );
      } else if (reader.localName == 'sldSz') {
        pres.slideWidth = int.parse(
          reader.getAttribute('cx') ?? '${pres.slideWidth}',
        );
        pres.slideHeight = int.parse(
          reader.getAttribute('cy') ?? '${pres.slideHeight}',
        );
      }
    }
    final XmlDocument source = XmlDocument.parse(part.readText());
    SlideSectionXml.read(
      pres,
      source.root!,
      slideRelationshipIssue: slideRelationshipIssue,
    );
    final _SlideTemplates templates = _SlideTemplates(
      package,
      slideWidth: pres.slideWidth,
      slideHeight: pres.slideHeight,
    );
    final String? masterBg = _masterBackground(
      package,
      templates.defaultColors,
    );
    pres.master.setImportedBackground(
      masterBg == null || masterBg.isEmpty ? pres.master.background : masterBg,
    );
    for (int i = 0; i < pres.slides.length; i++) {
      final String uri = slideUris[i];
      pres.slides[i].sourcePartUri = uri;
      final slidePart = package.getPart(uri);
      if (slidePart != null) {
        final String slideXml = slidePart.readText();
        pres.slides[i].showMasterShapes = _showsMasterShapes(slideXml);
        final _SlideTemplate? layout = templates.layoutOf(uri);
        final RelationshipCollection slideRels = package.relationshipsFor(uri);
        final PackageRelationship? layoutRel = slideRels.firstByType(
          RelationshipTypes.slideLayout,
        );
        if (layout != null &&
            layoutRel != null &&
            layoutRel.targetMode == RelationshipTargetMode.internal) {
          pres.slides[i].sourceLayoutPartUri = slideRels.resolve(layoutRel);
        }
        final Set<PmlShape> positioned = Set<PmlShape>.identity();
        final List<PmlShape> shapes = parseSlideShapes(
          slideXml,
          colors: layout?.colors ?? templates.defaultColors,
          positioned: positioned,
        );
        final String? slideBackground = _backgroundOf(
          slideXml,
          layout?.colors ?? templates.defaultColors,
        );
        final XmlElement? sourceBackground = _sourceBackgroundOf(slideXml);
        final bool ownsBackground = sourceBackground != null;
        final String resolvedBackground =
            (ownsBackground
                ? slideBackground ?? 'FFFFFF'
                : layout?.background) ??
            pres.master.background;
        if (!ownsBackground && (layout?.inheritsMasterBackground ?? true)) {
          pres.slides[i].setInheritedBackground(
            resolvedBackground,
            masterBackground: pres.master.background,
          );
        } else {
          pres.slides[i].background = resolvedBackground;
        }
        final PmlShape? backgroundImage = ownsBackground
            ? _backgroundImageShape(
                slideXml,
                package,
                package.relationshipsFor(uri),
                pres.slideWidth,
                pres.slideHeight,
              )
            : layout?.backgroundImage?.copy();
        final PmlShape? backgroundGradient = backgroundImage != null
            ? null
            : ownsBackground
            ? _backgroundGradientShape(
                slideXml,
                pres.slideWidth,
                pres.slideHeight,
                layout?.colors ?? templates.defaultColors,
              )
            : layout?.backgroundGradient?.copy();
        pres.slides[i].retainSourceBackground(
          sourceBackground,
          picture: backgroundImage,
          gradient: backgroundGradient,
        );
        if (layout != null) {
          pres.slides[i].layoutName = layout.name;
          _inheritPlaceholders(shapes, positioned, <List<PmlShape>>[
            layout.placeholders,
            layout.master?.placeholders ?? const <PmlShape>[],
          ]);
          pres.slides[i].backgroundShapes.addAll(<PmlShape>[
            if (pres.slides[i].showMasterShapes && layout.showsMasterShapes)
              for (final PmlShape shape
                  in layout.master?.decorations ?? const <PmlShape>[])
                shape.copy(),
            for (final PmlShape shape in layout.decorations) shape.copy(),
          ]);
        }
        pres.slides[i].shapes.addAll(shapes);
        parseSlideMotion(slideXml, pres.slides[i]);
        pres.slides[i].hidden = _slideIsHidden(slideXml);
        final RelationshipCollection rels = package.relationshipsFor(uri);
        _bindSlideMedia(pres.slides[i], package, rels);
        final PackageRelationship? notesRel = rels.firstByType(
          RelationshipTypes.notesSlide,
        );
        if (notesRel != null) {
          final notesPart = package.getPart(rels.resolve(notesRel));
          if (notesPart != null) {
            pres.slides[i].notes = parseSlideShapes(notesPart.readText())
                .map((PmlShape s) => s.text.trim())
                .where((String t) => t.isNotEmpty)
                .join('\n');
          }
        }
      }
    }
    final List<PmlLayout> layouts = templates.allLayouts();
    if (layouts.isNotEmpty) {
      pres.layouts = layouts;
    }
    return pres;
  }

  /// Gives slide placeholders without their own `xfrm` the geometry of the
  /// matching layout placeholder, falling back to the master.
  static void _inheritPlaceholders(
    List<PmlShape> shapes,
    Set<PmlShape> positioned,
    List<List<PmlShape>> sources,
  ) {
    for (final PmlShape shape in shapes) {
      if (!shape.placeholder || positioned.contains(shape)) {
        continue;
      }
      for (final List<PmlShape> source in sources) {
        final PmlShape? match = _matchPlaceholder(shape, source);
        if (match != null) {
          shape.transform = match.transform;
          positioned.add(shape);
          break;
        }
      }
    }
  }

  /// PowerPoint's rule: same `idx` first, then the same type family.
  static PmlShape? _matchPlaceholder(PmlShape shape, List<PmlShape> source) {
    final int? idx = shape.placeholderIndex;
    if (idx != null) {
      for (final PmlShape candidate in source) {
        if (candidate.placeholderIndex == idx) {
          return candidate;
        }
      }
    }
    final String family = _placeholderFamily(shape.placeholderType);
    for (final PmlShape candidate in source) {
      if (_placeholderFamily(candidate.placeholderType) == family) {
        return candidate;
      }
    }
    return null;
  }

  static String _placeholderFamily(String type) => switch (type) {
    'title' || 'ctrTitle' => 'title',
    '' || 'obj' || 'body' || 'subTitle' => 'body',
    _ => type,
  };

  /// readBytes API.
  PmlPresentation readBytes(Uint8List bytes, {String? password}) =>
      read(OpcPackage.openBytes(bytes, password: password));

  /// `showMasterSp` hides master decorations without hiding layout shapes or
  /// the editable slide content. XML Schema booleans default to true here.
  static bool _showsMasterShapes(String xml) {
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.namespaceUri == OfficeNamespaces.p &&
          (reader.localName == 'sld' || reader.localName == 'sldLayout')) {
        final String? value = reader.getAttribute('showMasterSp')?.trim();
        return value != '0' && value != 'false';
      }
    }
    return true;
  }

  static bool _slideIsHidden(String xml) {
    final int start = xml.indexOf('<p:sld');
    if (start < 0) {
      return false;
    }
    final int end = xml.indexOf('>', start);
    if (end < 0) {
      return false;
    }
    final String attrs = xml.substring(start, end);
    return RegExp(r'''\bshow\s*=\s*["'](?:0|false)["']''').hasMatch(attrs);
  }

  /// Whether this part owns a background, even if its fill is unsupported.
  static bool _hasBackground(String xml) {
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'bg' &&
          reader.namespaceUri == OfficeNamespaces.p) {
        return true;
      }
    }
    return false;
  }

  /// Retains the complete authored fill with its inherited namespace bindings.
  static XmlElement? _sourceBackgroundOf(String xml) {
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.namespaceUri == OfficeNamespaces.p &&
          reader.localName == 'bg') {
        return XmlDocument.readElement(reader);
      }
    }
    return null;
  }

  /// Converts an internal `p:bg/a:blipFill` into a full-slide picture.
  static PmlShape? _backgroundImageShape(
    String xml,
    OpcPackage package,
    RelationshipCollection rels,
    int width,
    int height,
  ) {
    final XmlPullReader reader = XmlPullReader(xml);
    final PictureAdjust picture = PictureAdjust();
    var inBg = false;
    var inFill = false;
    PackagePart? image;
    String? imageRelId;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'bg' &&
            reader.namespaceUri == OfficeNamespaces.p) {
          break;
        } else if (reader.localName == 'blipFill') {
          inFill = false;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.localName == 'bg' &&
          reader.namespaceUri == OfficeNamespaces.p) {
        inBg = true;
      } else if (inBg &&
          reader.localName == 'blipFill' &&
          reader.namespaceUri == OfficeNamespaces.a) {
        inFill = true;
      } else if (inFill && reader.namespaceUri == OfficeNamespaces.a) {
        if (reader.localName == 'blip') {
          final String? rid = reader.getAttribute(
            'embed',
            namespaceUri: OfficeNamespaces.r,
          );
          final PackageRelationship? rel = rid == null ? null : rels.byId(rid);
          if (rel != null &&
              rel.type == RelationshipTypes.image &&
              rel.targetMode != RelationshipTargetMode.external) {
            image = package.getPart(rels.resolve(rel));
            if (image != null) imageRelId = rid;
          }
        } else if (reader.localName == 'srcRect') {
          DrawingmlVisualIo.applySrcRect(picture, reader);
        } else if (reader.localName == 'lum') {
          DrawingmlVisualIo.applyLum(picture, reader);
        } else if (reader.localName == 'alphaModFix') {
          picture.transparency = DrawingmlVisualIo.alphaToTransparency(
            reader.getAttribute('amt'),
          );
        }
      }
    }
    if (image == null) return null;
    return PmlShape(
      id: 1,
      name: 'Background',
      fillColor: '',
      isBackgroundPicture: true,
      embedRelId: imageRelId,
      transform: PmlTransform(x: 0, y: 0, cx: width, cy: height),
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: 'Background',
        imageBytes: image.readBytes(),
        width: width / 12700,
        height: height / 12700,
        picture: picture,
      ),
    );
  }

  /// Converts the selected native gradient fill into a background snapshot.
  /// Keep fill ownership separate from ordinary master/layout decorations.
  static PmlShape? _backgroundGradientShape(
    String xml,
    int width,
    int height,
    Map<String, String> colors,
  ) {
    final XmlPullReader reader = XmlPullReader(xml);
    int? backgroundDepth;
    int? propertiesDepth;
    int? gradientDepth;
    int? stopDepth;
    double? position;
    double angle = 0;
    var radial = false;
    final List<PmlGradientStop> stops = <PmlGradientStop>[];
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        // The pull reader reports end events after popping the element.
        if (gradientDepth != null &&
            reader.depth == gradientDepth - 1 &&
            reader.localName == 'gradFill') {
          if (stops.length < 2) return null;
          stops.sort((a, b) => a.position.compareTo(b.position));
          return PmlShape(
            id: 1,
            name: 'Background',
            isBackgroundGradient: true,
            fillColor: stops.first.color,
            gradient: PmlGradientFill(
              stops: stops,
              angleDegrees: angle,
              radial: radial,
            ),
            transform: PmlTransform(x: 0, y: 0, cx: width, cy: height),
          );
        }
        if (backgroundDepth != null &&
            reader.depth == backgroundDepth - 1 &&
            reader.localName == 'bg') {
          return null;
        }
        if (stopDepth != null &&
            reader.depth == stopDepth - 1 &&
            reader.localName == 'gs') {
          stopDepth = null;
          position = null;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.localName == 'bg' &&
          reader.namespaceUri == OfficeNamespaces.p) {
        backgroundDepth = reader.depth;
      } else if (backgroundDepth != null &&
          reader.depth == backgroundDepth + 1 &&
          reader.namespaceUri == OfficeNamespaces.p &&
          reader.localName == 'bgPr') {
        propertiesDepth = reader.depth;
      } else if (propertiesDepth != null &&
          reader.depth == propertiesDepth + 1 &&
          reader.namespaceUri == OfficeNamespaces.a &&
          reader.localName == 'gradFill') {
        gradientDepth = reader.depth;
      } else if (gradientDepth != null &&
          reader.namespaceUri == OfficeNamespaces.a) {
        if (reader.localName == 'gs' && reader.depth == gradientDepth + 2) {
          stopDepth = reader.depth;
          position =
              ((int.tryParse(reader.getAttribute('pos') ?? '') ?? 0) / 100000)
                  .clamp(0.0, 1.0);
        } else if (reader.localName == 'lin' &&
            reader.depth == gradientDepth + 1) {
          angle = (int.tryParse(reader.getAttribute('ang') ?? '') ?? 0) / 60000;
        } else if (reader.localName == 'path' &&
            reader.depth == gradientDepth + 1) {
          radial = true;
        } else if (position != null &&
            stopDepth != null &&
            reader.depth == stopDepth + 1 &&
            const <String>{
              'srgbClr',
              'schemeClr',
              'sysClr',
              'prstClr',
            }.contains(reader.localName)) {
          final String? color = resolveDrawingmlColor(reader, colors);
          if (color != null && color.isNotEmpty) {
            stops.add(PmlGradientStop(position: position, color: color));
          }
          position = null;
        }
      }
    }
    return null;
  }

  /// Resolve a solid fill or the first gradient stop, never an effect color.
  static String? _backgroundOf(String xml, Map<String, String> colors) {
    final XmlPullReader reader = XmlPullReader(xml);
    var inBg = false;
    int? fillDepth;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'bg' &&
            reader.namespaceUri == OfficeNamespaces.p) {
          break;
        }
        if (fillDepth != null && reader.depth <= fillDepth) fillDepth = null;
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.localName == 'bg' &&
          reader.namespaceUri == OfficeNamespaces.p) {
        inBg = true;
      } else if (inBg &&
          reader.namespaceUri == OfficeNamespaces.a &&
          (reader.localName == 'solidFill' || reader.localName == 'gradFill')) {
        fillDepth = reader.depth;
      } else if (fillDepth != null &&
          reader.namespaceUri == OfficeNamespaces.a &&
          const <String>{
            'srgbClr',
            'schemeClr',
            'sysClr',
            'prstClr',
          }.contains(reader.localName)) {
        final String? value = resolveDrawingmlColor(reader, colors);
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _masterBackground(
    OpcPackage package,
    Map<String, String> colors,
  ) {
    final RelationshipCollection rels = package.relationshipsFor(
      _presentationUri,
    );
    for (final String uri in <String>{
      for (final rel in rels.byType(RelationshipTypes.slideMaster))
        if (rel.targetMode == RelationshipTargetMode.internal)
          rels.resolve(rel),
      '/ppt/slideMasters/slideMaster1.xml',
      '/ppt/slideMasters/slideMaster2.xml',
    }) {
      final String? xml = package.getPart(uri)?.readText();
      if (xml != null && _hasBackground(xml)) {
        return _backgroundOf(xml, colors) ?? 'FFFFFF';
      }
    }
    return null;
  }

  static void _bindSlideMedia(
    PmlSlide slide,
    OpcPackage package,
    RelationshipCollection rels,
  ) {
    _bindShapeMedia(slide.shapes, package, rels);
  }

  static void _bindShapeMedia(
    List<PmlShape> shapes,
    OpcPackage package,
    RelationshipCollection rels,
  ) {
    for (final PmlShape shape in shapes) {
      final String? rid = shape.embedRelId;
      if (rid == null || rid.isEmpty) {
        continue;
      }
      final PackageRelationship? rel = rels.byId(rid);
      if (rel == null) {
        continue;
      }
      final part = package.getPart(rels.resolve(rel));
      if (part == null) {
        continue;
      }
      if (rel.type == RelationshipTypes.image) {
        final PictureAdjust picture =
            shape.visual?.picture.copy() ?? PictureAdjust();
        shape.visual = OfficeVisual(
          kind: shape.visual?.kind ?? OfficeVisualKind.picture,
          title: shape.visual?.title ?? shape.name,
          imageBytes: part.readBytes(),
          width: shape.transform.widthPoints,
          height: shape.transform.heightPoints,
          picture: picture,
        );
      } else if (rel.type == RelationshipTypes.chart) {
        shape.visual = parseChartVisual(
          part.readText(),
          width: shape.transform.widthPoints,
          height: shape.transform.heightPoints,
        );
      }
    }
  }
}

const String _presentationUri = '/ppt/presentation.xml';

/// A parsed slide layout or master: its name, theme colors, and the
/// placeholders that ended up with a position.
class _SlideTemplate {
  _SlideTemplate({
    required this.name,
    required this.colors,
    required this.placeholders,
    required this.decorations,
    this.background,
    this.backgroundImage,
    this.backgroundGradient,
    this.inheritsMasterBackground = false,
    this.showsMasterShapes = true,
    this.master,
  });

  final String name;
  final Map<String, String> colors;
  final List<PmlShape> placeholders;
  final List<PmlShape> decorations;
  final String? background;
  final PmlShape? backgroundImage;
  final PmlShape? backgroundGradient;
  final bool inheritsMasterBackground;
  final bool showsMasterShapes;
  final _SlideTemplate? master;
}

/// Follows slide → `slideLayout` → `slideMaster` → `theme` relationships,
/// parsing each part once.
class _SlideTemplates {
  _SlideTemplates(
    this.package, {
    this.slideWidth = 12192000,
    this.slideHeight = 6858000,
  }) : defaultColors = _colorMap(
         package.getPart('/ppt/theme/theme1.xml')?.readText(),
         null,
       );

  final OpcPackage package;
  final int slideWidth;
  final int slideHeight;
  final Map<String, String> defaultColors;
  final Map<String, _SlideTemplate?> _layouts = <String, _SlideTemplate?>{};
  final Map<String, _SlideTemplate?> _masters = <String, _SlideTemplate?>{};

  _SlideTemplate? layoutOf(String slideUri) {
    final String? uri = _target(slideUri, RelationshipTypes.slideLayout);
    return uri == null ? null : _layout(uri);
  }

  /// Every layout of every master seen so far, prompts removed: layout
  /// placeholder text is a UI hint, not slide content.
  List<PmlLayout> allLayouts() {
    for (final String masterUri in _masters.keys.toList()) {
      final RelationshipCollection rels = package.relationshipsFor(masterUri);
      for (final PackageRelationship rel in rels.items) {
        if (rel.type == RelationshipTypes.slideLayout) {
          _layout(rels.resolve(rel));
        }
      }
    }
    return <PmlLayout>[
      for (final _SlideTemplate? layout in _layouts.values)
        if (layout != null)
          PmlLayout(
            name: layout.name,
            placeholders: <PmlShape>[
              for (final PmlShape shape in layout.placeholders)
                shape.copy()..text = '',
            ],
          ),
    ];
  }

  _SlideTemplate? _layout(String uri) {
    if (_layouts.containsKey(uri)) {
      return _layouts[uri];
    }
    _layouts[uri] = null;
    final String? xml = package.getPart(uri)?.readText();
    if (xml == null) {
      return null;
    }
    final String? masterUri = _target(uri, RelationshipTypes.slideMaster);
    final _SlideTemplate? master = masterUri == null
        ? null
        : _master(masterUri);
    final Map<String, String> colors = master?.colors ?? defaultColors;
    final Set<PmlShape> positioned = Set<PmlShape>.identity();
    final List<PmlShape> shapes = parseSlideShapes(
      xml,
      colors: colors,
      positioned: positioned,
    );
    if (master != null) {
      SlideDeserializer._inheritPlaceholders(
        shapes,
        positioned,
        <List<PmlShape>>[master.placeholders],
      );
    }
    final String? background = SlideDeserializer._backgroundOf(xml, colors);
    final bool ownsBackground = SlideDeserializer._hasBackground(xml);
    return _layouts[uri] = _SlideTemplate(
      name: _cSldName(xml) ?? 'Layout',
      colors: colors,
      placeholders: <PmlShape>[
        for (final PmlShape shape in shapes)
          if (shape.placeholder && positioned.contains(shape)) shape,
      ],
      decorations: _decorations(shapes, package, uri),
      background: ownsBackground ? background ?? 'FFFFFF' : master?.background,
      backgroundImage: ownsBackground
          ? SlideDeserializer._backgroundImageShape(
              xml,
              package,
              package.relationshipsFor(uri),
              slideWidth,
              slideHeight,
            )
          : master?.backgroundImage,
      backgroundGradient: ownsBackground
          ? SlideDeserializer._backgroundGradientShape(
              xml,
              slideWidth,
              slideHeight,
              colors,
            )
          : master?.backgroundGradient,
      inheritsMasterBackground: !ownsBackground,
      showsMasterShapes: SlideDeserializer._showsMasterShapes(xml),
      master: master,
    );
  }

  _SlideTemplate? _master(String uri) {
    if (_masters.containsKey(uri)) {
      return _masters[uri];
    }
    _masters[uri] = null;
    final String? xml = package.getPart(uri)?.readText();
    if (xml == null) {
      return null;
    }
    final String? themeUri = _target(uri, RelationshipTypes.theme);
    final Map<String, String> colors = _colorMap(
      themeUri == null ? null : package.getPart(themeUri)?.readText(),
      xml,
    );
    final Set<PmlShape> positioned = Set<PmlShape>.identity();
    final List<PmlShape> shapes = parseSlideShapes(
      xml,
      colors: colors,
      positioned: positioned,
    );
    return _masters[uri] = _SlideTemplate(
      name: _cSldName(xml) ?? 'Master',
      colors: colors,
      placeholders: <PmlShape>[
        for (final PmlShape shape in shapes)
          if (shape.placeholder && positioned.contains(shape)) shape,
      ],
      decorations: _decorations(shapes, package, uri),
      background: SlideDeserializer._backgroundOf(xml, colors),
      backgroundImage: SlideDeserializer._backgroundImageShape(
        xml,
        package,
        package.relationshipsFor(uri),
        slideWidth,
        slideHeight,
      ),
      backgroundGradient: SlideDeserializer._backgroundGradientShape(
        xml,
        slideWidth,
        slideHeight,
        colors,
      ),
    );
  }

  static List<PmlShape> _decorations(
    List<PmlShape> shapes,
    OpcPackage package,
    String uri,
  ) {
    final List<PmlShape> decorations = <PmlShape>[
      for (final PmlShape shape in shapes)
        if (!shape.placeholder) shape,
    ];
    final RelationshipCollection rels = package.relationshipsFor(uri);
    SlideDeserializer._bindShapeMedia(decorations, package, rels);
    return decorations;
  }

  String? _target(String sourceUri, String type) {
    final RelationshipCollection rels = package.relationshipsFor(sourceUri);
    final PackageRelationship? rel = rels.firstByType(type);
    return rel == null ? null : rels.resolve(rel);
  }

  static String? _cSldName(String xml) {
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'cSld') {
        final String? name = reader.getAttribute('name');
        return name == null || name.isEmpty ? null : name;
      }
    }
    return null;
  }

  /// Theme `a:clrScheme` slots, plus the master's `p:clrMap` aliases
  /// (`tx1` → `dk1`, `bg1` → `lt1`, …).
  static Map<String, String> _colorMap(String? themeXml, String? masterXml) {
    final Map<String, String> scheme = <String, String>{};
    if (themeXml != null) {
      final XmlPullReader reader = XmlPullReader(themeXml);
      String? slot;
      var inScheme = false;
      while (reader.next()) {
        final String name = reader.localName;
        if (reader.eventType == XmlEventType.endElement) {
          if (name == 'clrScheme') {
            break;
          }
          if (name == slot) {
            slot = null;
          }
          continue;
        }
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (name == 'clrScheme') {
          inScheme = true;
        } else if (inScheme && _schemeSlots.contains(name)) {
          slot = name;
        } else if (slot != null && (name == 'srgbClr' || name == 'sysClr')) {
          final String? hex = name == 'srgbClr'
              ? reader.getAttribute('val')
              : reader.getAttribute('lastClr');
          if (hex != null && hex.length == 6) {
            scheme[slot] = hex.toUpperCase();
          }
        }
      }
    }
    final Map<String, String> aliases = <String, String>{
      'bg1': 'lt1',
      'tx1': 'dk1',
      'bg2': 'lt2',
      'tx2': 'dk2',
    };
    if (masterXml != null) {
      final XmlPullReader reader = XmlPullReader(masterXml);
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'clrMap') {
          for (int a = 0; a < reader.attributeCount; a++) {
            aliases[reader.attributeLocalName(a)] = reader.attributeValue(a);
          }
          break;
        }
      }
    }
    return <String, String>{
      ...scheme,
      for (final MapEntry<String, String> alias in aliases.entries)
        if (scheme[alias.value] != null) alias.key: scheme[alias.value]!,
    };
  }

  static const Set<String> _schemeSlots = <String>{
    'dk1',
    'lt1',
    'dk2',
    'lt2',
    'accent1',
    'accent2',
    'accent3',
    'accent4',
    'accent5',
    'accent6',
    'hlink',
    'folHlink',
  };
}

/// Class SlideSerializer.
class SlideSerializer {
  /// writeBytes API.
  Uint8List writeBytes(PmlPresentation pres, {String? password}) =>
      write(pres).save(password: password);

  /// write API.
  OpcPackage write(PmlPresentation pres) {
    pres.package?.assertUnsignedForEditing();
    SlideSectionXml.validateForWrite(pres);
    for (final slide in pres.slides) {
      PmlArrange.validateGrouping(slide.shapes);
    }
    final bool fresh = pres.package == null;
    final OpcPackage package =
        pres.package ?? OpcPackage.create(OpcPackageKind.slide);
    final RelationshipCollection presentationRels = package.relationshipsFor(
      _presentationUri,
    );
    final String layoutUri = _ensureTemplates(
      package,
      notes: pres.slides.any((s) => s.notes.trim().isNotEmpty),
    );
    _syncAuthoredMasterBackground(pres, package);
    final List<String> slideRelIds = <String>[];
    final Set<String> used = <String>{};
    for (int i = 0; i < pres.slides.length; i++) {
      String? uri =
          pres.slides[i].sourcePartUri ??
          (fresh ? '/ppt/slides/slide${i + 1}.xml' : null);
      if (uri == null || used.contains(uri)) {
        var n = 1;
        while (package.getPart('/ppt/slides/slide$n.xml') != null) {
          n++;
        }
        uri = '/ppt/slides/slide$n.xml';
      }
      used.add(uri);
      pres.slides[i].sourcePartUri = uri;
      final RelationshipCollection slideRels = package.relationshipsFor(uri);
      if (slideRels.firstByType(RelationshipTypes.slideLayout) == null) {
        final String? sourceLayout = fresh
            ? null
            : pres.slides[i].sourceLayoutPartUri;
        slideRels.add(
          type: RelationshipTypes.slideLayout,
          target: OpcUris.relativize(
            uri,
            sourceLayout != null &&
                    package.getPart(sourceLayout)?.contentType ==
                        OfficeContentTypes.slideLayout
                ? sourceLayout
                : layoutUri,
          ),
        );
      }
      final PackageRelationship? layoutRel = slideRels.firstByType(
        RelationshipTypes.slideLayout,
      );
      final bool preserveBackgroundInheritance =
          !fresh &&
          pres.slides[i].sourceBackground == null &&
          !pres.slides[i].writesSolidBackground &&
          pres.slides[i].sourceLayoutPartUri != null &&
          layoutRel != null &&
          layoutRel.targetMode == RelationshipTargetMode.internal &&
          slideRels.resolve(layoutRel) == pres.slides[i].sourceLayoutPartUri;
      if (package.getPart(uri) == null) {
        package.createPart(uri, OfficeContentTypes.slide, utf8.encode(''));
      }
      PackageRelationship? slideRel;
      for (final PackageRelationship rel in presentationRels.items) {
        if (rel.type == RelationshipTypes.slide &&
            presentationRels.resolve(rel) == uri) {
          slideRel = rel;
          break;
        }
      }
      slideRel ??= presentationRels.add(
        type: RelationshipTypes.slide,
        target: OpcUris.relativize(_presentationUri, uri),
      );
      slideRelIds.add(slideRel.id);
      final Map<PmlShape, String> embedIds = _syncSlideVisuals(
        pres.slides[i],
        package,
        uri,
        preserveBackgroundInheritance: preserveBackgroundInheritance,
      );
      package
          .getPart(uri)!
          .writeText(
            slideToXml(
              pres.slides[i],
              embedIds: embedIds,
              preserveBackgroundInheritance: preserveBackgroundInheritance,
            ),
          );
      _syncNotesSlide(pres.slides[i], package, uri, i + 1);
    }
    for (final PackageRelationship rel
        in presentationRels.byType(RelationshipTypes.slide).toList()) {
      if (!slideRelIds.contains(rel.id)) presentationRels.removeById(rel.id);
    }
    package
        .getPart(_presentationUri)!
        .writeText(_presentationXml(pres, slideRelIds, package));
    _normalizeChartAxisIds(package);
    pres.properties.writeToPackage(package);
    pres.package = package;
    pres.master.setImportedBackground(pres.master.background);
    return package;
  }

  // SDK semantic constraints restrict axis IDs to signed-positive integers.
  // Allocate replacements for out-of-range producer IDs without colliding with
  // valid IDs, and apply the same mapping to every axis reference in the part.
  static Map<PmlShape, String> _syncSlideVisuals(
    PmlSlide slide,
    OpcPackage package,
    String slideUri, {
    required bool preserveBackgroundInheritance,
  }) {
    final Map<PmlShape, String> ids = <PmlShape, String>{};
    final RelationshipCollection rels = package.relationshipsFor(slideUri);
    var mediaIndex = 1;
    var chartIndex = 1;
    final String owner = slideUri.split('/').last.replaceAll('.xml', '');
    for (final PmlShape shape in <PmlShape>[
      for (final shape in slide.backgroundShapes)
        if (shape.isBackgroundPicture && !preserveBackgroundInheritance) shape,
      ...slide.shapes,
    ]) {
      final OfficeVisual? visual = shape.visual;
      if (visual == null) {
        continue;
      }
      if (visual.isChart) {
        final String uri = '/ppt/charts/${owner}_chart$chartIndex.xml';
        chartIndex++;
        final String xml = _chartXml(visual);
        final PackagePart? existing = package.getPart(uri);
        if (existing == null) {
          package.createPart(
            uri,
            OfficeContentTypes.drawingChart,
            utf8.encode(xml),
          );
        } else {
          existing.writeText(xml);
        }
        final String target = OpcUris.relativize(slideUri, uri);
        PackageRelationship? found;
        for (final PackageRelationship rel in rels.items) {
          if (rel.target == target && rel.type == RelationshipTypes.chart) {
            found = rel;
            break;
          }
        }
        found ??= rels.add(type: RelationshipTypes.chart, target: target);
        ids[shape] = found.id;
        shape.embedRelId = found.id;
        continue;
      }
      if (!visual.isPicture && !visual.isDiagram) {
        continue;
      }
      final Uint8List bytes = PngBytes.fromVisual(visual);
      final String mime = WordLikeMedia.mimeOf(bytes);
      late String uri;
      while (true) {
        uri =
            '/ppt/media/${owner}_image${mediaIndex++}'
            '${WordLikeMedia.extensionOf(mime)}';
        final PackagePart? existing = package.getPart(uri);
        if (existing == null) {
          package.createPart(uri, mime, bytes);
          break;
        }
        // Generated-looking names can belong to retained masters, layouts or
        // another picture. Only reuse identical content; never overwrite it.
        if (existing.contentType == mime && _sameMedia(existing, bytes)) break;
      }
      final String target = OpcUris.relativize(slideUri, uri);
      PackageRelationship? found;
      for (final PackageRelationship rel in rels.items) {
        if (rel.target == target &&
            rel.type == RelationshipTypes.image &&
            rel.targetMode == RelationshipTargetMode.internal) {
          found = rel;
          break;
        }
      }
      found ??= rels.add(type: RelationshipTypes.image, target: target);
      ids[shape] = found.id;
      shape.embedRelId = found.id;
    }
    return ids;
  }

  static bool _sameMedia(PackagePart part, Uint8List bytes) {
    if (part.length != bytes.length) return false;
    final Uint8List existing = part.bytesView;
    for (var i = 0; i < bytes.length; i++) {
      if (existing[i] != bytes[i]) return false;
    }
    return true;
  }

  static void _syncAuthoredMasterBackground(
    PmlPresentation pres,
    OpcPackage package,
  ) {
    if (!pres.master.hasAuthoredBackground) return;
    final String color = pres.master.background.isEmpty
        ? 'FFFFFF'
        : pres.master.background;
    final bool changesAllColors = pres.master.changesNativeBackgroundColor;
    final _SlideTemplates templates = _SlideTemplates(package);
    final Map<String, String> resolvedByMaster = {};
    final RelationshipCollection presRels = package.relationshipsFor(
      _presentationUri,
    );
    final Set<String> masterUris = {
      for (final rel in presRels.byType(RelationshipTypes.slideMaster))
        if (rel.targetMode == RelationshipTargetMode.internal)
          presRels.resolve(rel),
    };
    for (final slide in pres.slides) {
      final String resolved = changesAllColors
          ? color
          : slide.resolveBackground(color);
      final String? layoutUri = slide.sourceLayoutPartUri;
      if (layoutUri != null &&
          package.getPart(layoutUri)?.contentType ==
              OfficeContentTypes.slideLayout) {
        final rels = package.relationshipsFor(layoutUri);
        for (final rel in rels.byType(RelationshipTypes.slideMaster)) {
          if (rel.targetMode == RelationshipTargetMode.internal) {
            final String masterUri = rels.resolve(rel);
            masterUris.add(masterUri);
            if (slide.inheritsMasterBackground) {
              resolvedByMaster[masterUri] = resolved;
            }
          }
        }
      }
      if (slide.inheritsMasterBackground) {
        slide.setInheritedBackground(resolved, masterBackground: color);
        slide.backgroundShapes.removeWhere((shape) => shape.isBackgroundFill);
      }
    }
    for (final uri in masterUris) {
      final PackagePart? part = package.getPart(uri);
      if (part?.contentType != OfficeContentTypes.slideMaster) continue;
      final String? nativeColor = templates._master(uri)?.background;
      final String targetColor =
          resolvedByMaster[uri] ??
          (!changesAllColors && nativeColor != null ? nativeColor : color);
      if (!changesAllColors &&
          nativeColor != null &&
          nativeColor.toUpperCase() == targetColor.toUpperCase() &&
          targetColor.toUpperCase() != color.toUpperCase()) {
        continue;
      }
      final XmlDocument document = XmlDocument.parse(part!.readText());
      final XmlElement? root = document.root;
      final XmlElement? common = root?.firstChild(
        'cSld',
        namespaceUri: OfficeNamespaces.p,
      );
      if (root == null || common == null) continue;
      root.setAttribute('p', OfficeNamespaces.p, prefix: 'xmlns');
      root.setAttribute('a', OfficeNamespaces.a, prefix: 'xmlns');
      XmlElement element(String name, String prefix, String namespace) =>
          XmlElement(localName: name, prefix: prefix, namespaceUri: namespace);
      final XmlElement background = element('bg', 'p', OfficeNamespaces.p);
      final XmlElement properties = element('bgPr', 'p', OfficeNamespaces.p);
      final XmlElement fill = element('solidFill', 'a', OfficeNamespaces.a);
      final XmlElement rgb = element('srgbClr', 'a', OfficeNamespaces.a)
        ..setAttribute('val', targetColor);
      fill.addChild(rgb);
      properties.addChild(fill);
      background.addChild(properties);
      common.children.removeWhere(
        (node) =>
            node is XmlElement &&
            node.localName == 'bg' &&
            node.namespaceUri == OfficeNamespaces.p,
      );
      common.children.insert(0, background..parent = common);
      part.writeText(document.toXmlString());
    }
  }

  // Some independent producers use signed or oversized chart axis IDs.
  // Both the schema and Office's semantic constraint require nonnegative
  // Int32 values. Allocate unused IDs and update declarations/references
  // together, including retained source charts, without changing their data.
  static void _normalizeChartAxisIds(OpcPackage package) {
    for (final PackagePart part in package.parts) {
      if (part.contentType != OfficeContentTypes.drawingChart) continue;
      final XmlPullReader reader = XmlPullReader(
        package.getPart(part.uri)!.readText(),
      );
      XmlElement? root;
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement) {
          root = XmlDocument.readElement(reader);
          break;
        }
      }
      if (root == null) continue;
      final XmlDocument xml = XmlDocument(root: root);
      final List<XmlElement> nodes =
          <XmlElement>[
                ..._descendants(root, 'axId'),
                ..._descendants(root, 'crossAx'),
              ]
              .where(
                (XmlElement node) => node.namespaceUri == OfficeNamespaces.c,
              )
              .toList();
      final Set<int> used = <int>{
        for (final XmlElement node in nodes)
          if (int.tryParse(node.getAttribute('val') ?? '') case final int value)
            if (value >= 0 && value <= 2147483647) value,
      };
      final Map<int, int> replacements = <int, int>{};
      int next = 1;
      for (final XmlElement node in nodes) {
        final int? value = int.tryParse(node.getAttribute('val') ?? '');
        if (value == null || (value >= 0 && value <= 2147483647)) continue;
        final int normalized = replacements.putIfAbsent(value, () {
          while (used.contains(next)) {
            next++;
          }
          used.add(next);
          return next++;
        });
        node.setAttribute('val', '$normalized');
      }
      if (replacements.isNotEmpty) part.writeText(xml.toXmlString());
    }
  }

  static String _chartXml(OfficeVisual visual) {
    final String title = visual.title.isEmpty ? 'Chart' : visual.title;
    final List<ChartPoint> points = visual.points.isEmpty
        ? OfficeVisual.sampleSeries()
        : visual.points;
    final bool rtl = visual.chart.rtl;
    return switch (visual.kind) {
      OfficeVisualKind.chartPie => DrawingmlCharts.pie(
        title: title,
        series: points,
        rtl: rtl,
        display: visual.chart,
      ),
      OfficeVisualKind.chartLine => DrawingmlCharts.line(
        title: title,
        series: <ChartSeries>[ChartSeries(name: title, points: points)],
        rtl: rtl,
        display: visual.chart,
      ),
      OfficeVisualKind.chartBar => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: rtl,
        display: visual.chart,
      ),
      _ => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: rtl,
        horizontal: false,
        display: visual.chart,
      ),
    };
  }

  String _presentationXml(
    PmlPresentation pres,
    List<String> slideRelIds,
    OpcPackage package,
  ) {
    final XmlDocument document = XmlDocument.parse(
      package.getPart(_presentationUri)!.readText(),
    );
    final XmlElement root = document.root!;
    XmlElement element(String name, [Map<String, String> attrs = const {}]) =>
        XmlElement(
          localName: name,
          prefix: 'p',
          namespaceUri: OfficeNamespaces.p,
          attributes: [
            for (final a in attrs.entries)
              XmlAttribute(localName: a.key, value: a.value),
          ],
        );
    final RelationshipCollection rels = package.relationshipsFor(
      _presentationUri,
    );
    final XmlElement masters = element('sldMasterIdLst');
    var masterId = 2147483648;
    for (final PackageRelationship rel in rels.byType(
      RelationshipTypes.slideMaster,
    )) {
      masters.addChild(
        element('sldMasterId', {'id': '${masterId++}', 'r:id': rel.id}),
      );
    }
    final XmlElement slides = element('sldIdLst');
    for (int i = 0; i < pres.slides.length; i++) {
      slides.addChild(
        element('sldId', {
          'id': '${pres.slides[i].id}',
          'r:id': slideRelIds[i],
        }),
      );
    }
    final XmlElement? oldNotesSize = root.firstChild('notesSz');
    final XmlElement? oldExtensions = root.firstChild(
      'extLst',
      namespaceUri: OfficeNamespaces.p,
    );
    root.children.removeWhere(
      (n) =>
          n is XmlElement &&
          n.namespaceUri == OfficeNamespaces.p &&
          {
            'sldMasterIdLst',
            'notesMasterIdLst',
            'sldIdLst',
            'sldSz',
            'notesSz',
            'extLst',
          }.contains(n.localName),
    );
    final List<XmlNode> tail = root.children.toList();
    root.children.clear();
    root.setAttribute('r', OfficeNamespaces.r, prefix: 'xmlns');
    root.addChild(masters);
    final XmlElement notesMasters = element('notesMasterIdLst');
    for (final PackageRelationship rel in rels.byType(
      RelationshipTypes.notesMaster,
    )) {
      notesMasters.addChild(element('notesMasterId', {'r:id': rel.id}));
    }
    if (notesMasters.children.isNotEmpty) root.addChild(notesMasters);
    // Handout master IDs precede the slide list in the presentation sequence.
    for (final n in tail.where(
      (n) => n is XmlElement && n.localName == 'handoutMasterIdLst',
    )) {
      root.addChild(n);
    }
    root.addChild(slides);
    root.addChild(
      element('sldSz', {
        'cx': '${pres.slideWidth}',
        'cy': '${pres.slideHeight}',
      }),
    );
    root.addChild(
      oldNotesSize ?? element('notesSz', {'cx': '6858000', 'cy': '9144000'}),
    );
    for (final n in tail.where(
      (n) => !(n is XmlElement && n.localName == 'handoutMasterIdLst'),
    )) {
      root.addChild(n);
    }
    final XmlElement extensions = oldExtensions ?? element('extLst');
    SlideSectionXml.write(pres, extensions);
    if (extensions.children.isNotEmpty) root.addChild(extensions);
    return document.toXmlString();
  }

  /// Fill missing template relationships without replacing imported templates.
  static String _ensureTemplates(OpcPackage package, {required bool notes}) {
    OpcPackage? seed;
    final Map<String, String> copied = {};
    String copyPart(String uri) {
      if (copied[uri] case final String existing) return existing;
      seed ??= OpcPackage.openBytes(
        (PptxDeckBuilder()..addTitleSlide(title: '', notes: 'Template'))
            .build(),
      );
      final PackagePart part = seed!.getPart(uri)!;
      final int slash = uri.lastIndexOf('/');
      final String stem =
          '${uri.substring(0, slash + 1)}quds_${uri.substring(slash + 1)}';
      String target = stem;
      var suffix = 1;
      while (package.getPart(target) != null) {
        target = stem.replaceFirst('.xml', '_${suffix++}.xml');
      }
      copied[uri] = target;
      package.createPart(target, part.contentType, part.readBytes());
      final RelationshipCollection dest = package.relationshipsFor(target);
      final RelationshipCollection source = seed!.relationshipsFor(uri);
      for (final rel in source.items) {
        dest.add(
          id: rel.id,
          type: rel.type,
          targetMode: rel.targetMode,
          target: rel.targetMode == RelationshipTargetMode.external
              ? rel.target
              : OpcUris.relativize(target, copyPart(source.resolve(rel))),
        );
      }
      return target;
    }

    final RelationshipCollection rels = package.relationshipsFor(
      _presentationUri,
    );
    PackageRelationship? master = rels.firstByType(
      RelationshipTypes.slideMaster,
    );
    master ??= rels.add(
      type: RelationshipTypes.slideMaster,
      target: OpcUris.relativize(
        _presentationUri,
        copyPart('/ppt/slideMasters/slideMaster1.xml'),
      ),
    );
    final RelationshipCollection masterRels = package.relationshipsFor(
      rels.resolve(master),
    );
    PackageRelationship? layout = masterRels.firstByType(
      RelationshipTypes.slideLayout,
    );
    if (layout == null) {
      final String uri = copyPart('/ppt/slideLayouts/slideLayout1.xml');
      layout = masterRels.add(
        type: RelationshipTypes.slideLayout,
        target: OpcUris.relativize(masterRels.sourcePartUri, uri),
      );
    }
    if (notes && rels.firstByType(RelationshipTypes.notesMaster) == null) {
      rels.add(
        type: RelationshipTypes.notesMaster,
        target: OpcUris.relativize(
          _presentationUri,
          copyPart('/ppt/notesMasters/notesMaster1.xml'),
        ),
      );
    }
    return masterRels.resolve(layout);
  }

  static void _syncNotesSlide(
    PmlSlide slide,
    OpcPackage package,
    String slideUri,
    int index,
  ) {
    final RelationshipCollection rels = package.relationshipsFor(slideUri);
    final PackageRelationship? oldNotes = rels.firstByType(
      RelationshipTypes.notesSlide,
    );
    if (slide.notes.trim().isEmpty) {
      if (oldNotes != null) rels.removeById(oldNotes.id);
      return;
    }
    final String uri = oldNotes == null
        ? '/ppt/notesSlides/${slideUri.split('/').last.replaceFirst('slide', 'notesSlide')}'
        : rels.resolve(oldNotes);
    final String escaped = slide.notes
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final String xml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:p="${OfficeNamespaces.p}">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes"/><p:cNvSpPr txBox="1"/>'
        '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>'
        '<a:p><a:r><a:t>$escaped</a:t></a:r></a:p>'
        '</p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:notes>';
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, OfficeContentTypes.notesSlide, utf8.encode(xml));
    } else {
      existing.writeText(xml);
    }
    if (oldNotes == null) {
      rels.add(
        type: RelationshipTypes.notesSlide,
        target: OpcUris.relativize(slideUri, uri),
      );
    }
    final RelationshipCollection noteRels = package.relationshipsFor(uri);
    for (final rel in noteRels.byType(RelationshipTypes.slide).toList()) {
      noteRels.removeById(rel.id);
    }
    noteRels.add(
      type: RelationshipTypes.slide,
      target: OpcUris.relativize(uri, slideUri),
    );
    final RelationshipCollection presRels = package.relationshipsFor(
      _presentationUri,
    );
    final PackageRelationship? notesMaster = presRels.firstByType(
      RelationshipTypes.notesMaster,
    );
    if (notesMaster != null &&
        noteRels.firstByType(RelationshipTypes.notesMaster) == null) {
      noteRels.add(
        type: RelationshipTypes.notesMaster,
        target: OpcUris.relativize(uri, presRels.resolve(notesMaster)),
      );
    }
  }
}

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final XmlElement child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}
