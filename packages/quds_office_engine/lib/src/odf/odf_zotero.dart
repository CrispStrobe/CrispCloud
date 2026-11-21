import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../opc/office_package_parts.dart';
import '../opc/zip/zip_reader.dart';
import '../word/model/word_zotero.dart';
import '../xml/xml_node.dart';
import '../xml/xml_reader.dart';
import 'odf_text.dart';
import 'odf_zotero_models.dart';
import 'odf_zotero_preferences.dart';

export 'odf_zotero_models.dart';
export 'odf_zotero_preferences.dart';

const _styleNamespace = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _xlinkNamespace = 'http://www.w3.org/1999/xlink';

/// Bounded, read-only inventory of native LibreOffice Zotero data in an ODT.
///
/// This is deliberately separate from rich-document loading and the HTTP
/// adapter. It never creates active fields, rewrites a ZIP member, accesses the
/// network, resolves external objects or normalizes document preferences.
abstract final class OdfZotero {
  static Future<OdfZoteroInventory> inspect(
    Uint8List bytes, {
    OdfZoteroLimits limits = const OdfZoteroLimits(),
  }) async {
    limits.validate();
    if (bytes.length > limits.maxArchiveBytes) {
      throw const OdfZoteroLimitException('archive bytes');
    }
    final zip = ZipReader.fromBytes(
      bytes,
      maxEntries: limits.maxZipEntries,
      rejectDuplicateNames: true,
    );
    if (!zip.contains('mimetype') ||
        utf8.decode(zip.read('mimetype', maxBytes: 128)) !=
            'application/vnd.oasis.opendocument.text') {
      throw const FormatException(
        'Expected a native OpenDocument text package.',
      );
    }
    var xmlBytes = 0;
    var xmlElements = 0;
    final parts = OfficePackageParts((name) {
      final entry = zip[name];
      if (entry == null) return null;
      if ((entry.generalPurposeFlag & 1) != 0) {
        throw FormatException('Encrypted ODT part is unsupported: $name');
      }
      final remaining = limits.maxTotalXmlBytes - xmlBytes;
      final maximum = math.min(limits.maxPartBytes, remaining);
      if (maximum < 0 || entry.uncompressedSize > maximum) {
        throw const OdfZoteroLimitException('XML bytes');
      }
      final data = zip.read(name, maxBytes: maximum);
      xmlBytes += data.length;
      final text = utf8.decode(data);
      // Check breadth and ambiguous attributes before a DOM is allocated.
      // OfficePackageParts separately validates roots, nesting and tag closure.
      final scanner = XmlPullReader(text);
      try {
        while (scanner.next()) {
          if (scanner.eventType != XmlEventType.startElement) continue;
          if (++xmlElements > limits.maxXmlElements) {
            throw const OdfZoteroLimitException('XML elements');
          }
          if (scanner.depth > limits.maxXmlDepth) {
            throw const OdfZoteroLimitException('XML depth');
          }
          final attributes = <String>{};
          for (var index = 0; index < scanner.attributeCount; index++) {
            final prefix = scanner.attributePrefix(index);
            final namespace =
                prefix == 'xmlns' ||
                    scanner.attributeQualifiedName(index) == 'xmlns'
                ? 'http://www.w3.org/2000/xmlns/'
                : scanner.attributeNamespace(index);
            final key = '$namespace\u0000${scanner.attributeLocalName(index)}';
            if (!attributes.add(key)) {
              throw FormatException('Duplicate XML attribute in $name.');
            }
          }
        }
      } on XmlParseException catch (error) {
        throw FormatException('Invalid ODT XML in $name: ${error.message}');
      }
      return text;
    }, maxXmlDepth: limits.maxXmlDepth);
    final content = await parts.xml('content.xml');
    if (content?.root == null ||
        content!.root!.namespaceUri != odfOfficeNamespace ||
        content.root!.localName != 'document-content') {
      throw const FormatException('Missing or invalid ODT content.xml root.');
    }
    final bodies = content.root!.childrenNamed(
      'body',
      namespaceUri: odfOfficeNamespace,
    );
    if (bodies.length != 1 ||
        bodies.single
                .childrenNamed('text', namespaceUri: odfOfficeNamespace)
                .length !=
            1) {
      throw const FormatException('Ambiguous or missing ODT text body.');
    }
    final styles = await parts.xml('styles.xml');
    if (styles != null &&
        (styles.root?.namespaceUri != odfOfficeNamespace ||
            styles.root?.localName != 'document-styles')) {
      throw const FormatException('Invalid ODT styles.xml root.');
    }
    final metadata = await parts.xml('meta.xml');
    final preferences = OdfZoteroPreferences.read(metadata?.root);
    final reader = _InventoryReader(limits);
    reader.read('content.xml', content.root!);
    if (styles?.root != null) reader.read('styles.xml', styles!.root!);
    return reader.finish(preferences);
  }
}

final class _Context {
  const _Context({
    required this.part,
    this.story = OdfZoteroStory.unknown,
    this.storyPath = '/0',
    this.owners = const [],
    this.guards = const {},
  });

  final String part;
  final OdfZoteroStory story;
  final String storyPath;
  final List<OdfZoteroOwner> owners;
  final Set<OdfZoteroIssueCode> guards;

  _Context child(
    XmlElement element,
    String path, {
    OdfZoteroStory? story,
    bool owner = false,
    Set<OdfZoteroIssueCode> guards = const {},
  }) => _Context(
    part: part,
    story: story ?? this.story,
    storyPath: story == null ? storyPath : path,
    owners: owner || story != null
        ? [
            ...owners,
            OdfZoteroOwner(
              path: path,
              namespaceUri: element.namespaceUri,
              localName: element.localName,
            ),
          ]
        : owners,
    guards: {
      ...this.guards,
      ...guards,
      if (story != null &&
          story != OdfZoteroStory.body &&
          !_supportedStory(this.story))
        OdfZoteroIssueCode.unsupportedStory,
      if ((story == OdfZoteroStory.footnote ||
              story == OdfZoteroStory.endnote) &&
          (this.story == OdfZoteroStory.footnote ||
              this.story == OdfZoteroStory.endnote))
        OdfZoteroIssueCode.unsupportedContent,
    },
  );

  OdfZoteroLocation location(
    String path, {
    _Paragraph? paragraph,
    int? offset,
  }) => OdfZoteroLocation(
    part: part,
    path: path,
    story: story,
    storyPath: storyPath,
    owners: owners,
    paragraphPath: paragraph?.path,
    paragraphIndex: paragraph?.index,
    offset: offset,
  );
}

final class _Endpoint {
  _Endpoint(this.context, this.path, this.order, this.paragraph, this.offset);

  final _Context context;
  final String path;
  final int order;
  final _Paragraph? paragraph;
  int? offset;

  OdfZoteroLocation get location =>
      context.location(path, paragraph: paragraph, offset: offset);
}

final class _Paragraph {
  _Paragraph(this.context, this.path, this.index, OdfTextBudget budget)
    : decoder = _PositionedText(budget),
      guards = {...context.guards};

  final _Context context;
  final String path;
  final int index;
  final _PositionedText decoder;
  final Set<OdfZoteroIssueCode> guards;
  String text = '';
}

final class _Field {
  _Field(this.name, this.storage, this.order);

  final String name;
  final OdfZoteroStorage storage;
  final int order;
  final starts = <_Endpoint>[];
  final ends = <_Endpoint>[];
  final guards = <OdfZoteroIssueCode>{};
  final ranges = <OdfZoteroTextRange>[];
  String? code;
  String? suffix;
  ZoteroFieldKind? kind;
  Map<String, Object?>? metadata;
  bool valid = false;
  int paragraphStart = 0;
  int paragraphEnd = 0;

  OdfZoteroLocation? get location =>
      starts.firstOrNull?.location ?? ends.firstOrNull?.location;
}

final class _InventoryReader {
  _InventoryReader(this.limits)
    : textBudget = OdfTextBudget(limits.maxTextBytes),
      cacheBudget = OdfTextBudget(limits.maxTextBytes);

  final OdfZoteroLimits limits;
  final OdfTextBudget textBudget;
  final OdfTextBudget cacheBudget;
  final _fields = <_Field>[];
  final _marks = <String, _Field>{};
  final _paragraphs = <_Paragraph>[];
  final _issues = <OdfZoteroIssue>[];
  final _sectionStack = <_Field>[];
  var _order = 0;
  var _endpointCount = 0;
  var _rangeWork = 0;
  var _rangeCount = 0;

  void read(String part, XmlElement root) {
    _visit(root, '/0', _Context(part: part), null);
  }

  _Endpoint _endpoint(_Context context, String path, _Paragraph? paragraph) {
    // Duplicate endpoints are also bounded; they do not evade the field cap.
    if (++_endpointCount > limits.maxFields * 2) {
      throw const OdfZoteroLimitException('field endpoints');
    }
    final endpoint = _Endpoint(
      context,
      path,
      _order++,
      paragraph,
      paragraph?.decoder.length,
    );
    paragraph?.decoder.anchor(endpoint);
    return endpoint;
  }

  _Field _newField(String name, OdfZoteroStorage storage) {
    if (_fields.length >= limits.maxFields) {
      throw const OdfZoteroLimitException('fields');
    }
    if (name.length > limits.maxNameLength) {
      throw const OdfZoteroLimitException('field name');
    }
    final field = _Field(name, storage, _order++);
    _parseName(field);
    _fields.add(field);
    return field;
  }

  void _visit(
    XmlElement element,
    String path,
    _Context incoming,
    _Paragraph? activeParagraph,
  ) {
    var context = incoming;
    var paragraph = activeParagraph;
    final namespace = element.namespaceUri;
    final local = element.localName;
    final textElement = namespace == odfTextNamespace;

    OdfZoteroStory? story;
    if (namespace == odfOfficeNamespace && local == 'text') {
      // Only the direct office:body/office:text owner is the document body.
      if (element.parent?.localName == 'body' &&
          element.parent?.namespaceUri == odfOfficeNamespace &&
          element.parent?.parent?.localName == 'document-content' &&
          element.parent?.parent?.namespaceUri == odfOfficeNamespace) {
        story = OdfZoteroStory.body;
      }
    } else if (textElement && local == 'note') {
      story = switch (element.getAttribute(
        'note-class',
        namespaceUri: odfTextNamespace,
      )) {
        'footnote' => OdfZoteroStory.footnote,
        'endnote' => OdfZoteroStory.endnote,
        _ => OdfZoteroStory.unknown,
      };
    } else if (isOdfAnnotation(element)) {
      story = OdfZoteroStory.annotation;
    } else if (isOdfTrackedChanges(element)) {
      story = OdfZoteroStory.revision;
    } else if (namespace == odfDrawingNamespace && local == 'text-box') {
      story = OdfZoteroStory.textBox;
    } else if (namespace == _styleNamespace && local.startsWith('header')) {
      story = OdfZoteroStory.header;
    } else if (namespace == _styleNamespace && local.startsWith('footer')) {
      story = OdfZoteroStory.footer;
    }
    if (story != null) {
      for (final section in _sectionStack) {
        section.guards.add(OdfZoteroIssueCode.unsupportedSectionStructure);
      }
      if (paragraph != null) {
        paragraph.guards.add(OdfZoteroIssueCode.unsupportedContent);
      }
      context = context.child(element, path, story: story);
      paragraph = null;
    }

    final isSection = textElement && local == 'section';
    final isTableOwner =
        namespace == odfTableNamespace &&
        {
          'table',
          'table-row',
          'table-cell',
          'covered-table-cell',
          'table-header-rows',
          'table-rows',
          'table-row-group',
        }.contains(local);
    final isTextOwner =
        textElement &&
        {
          'section',
          'list',
          'list-item',
          'list-header',
          'note-body',
        }.contains(local);
    final guards = <OdfZoteroIssueCode>{};
    // Descendants retain the guard even when a foreign/drawing wrapper is
    // outside a paragraph. A real text:p inside it must not regain body status.
    final unknownTextOwner =
        textElement &&
        !{
          'p',
          'h',
          'section',
          'list',
          'list-item',
          'list-header',
          'note',
          'note-body',
          'note-citation',
          'span',
          'a',
          's',
          'tab',
          'line-break',
          'reference-mark',
          'reference-mark-start',
          'reference-mark-end',
          'bookmark',
          'bookmark-start',
          'bookmark-end',
          'soft-page-break',
          'ruby',
          'ruby-base',
          'ruby-text',
        }.contains(local);
    final unknownOfficeOwner =
        namespace == odfOfficeNamespace &&
        context.story != OdfZoteroStory.unknown &&
        !{'text', 'annotation', 'annotation-end'}.contains(local);
    final unknownTableOwner =
        namespace == odfTableNamespace &&
        !{
          'table',
          'table-row',
          'table-cell',
          'covered-table-cell',
          'table-header-rows',
          'table-rows',
          'table-row-group',
          'table-column',
          'table-columns',
          'table-header-columns',
          'table-column-group',
        }.contains(local);
    final unknownStyleOwner =
        namespace == _styleNamespace &&
        context.story != OdfZoteroStory.unknown &&
        !{
          'header',
          'header-left',
          'header-first',
          'footer',
          'footer-left',
          'footer-first',
        }.contains(local);
    final unsupportedOwner =
        unknownTextOwner ||
        unknownOfficeOwner ||
        unknownTableOwner ||
        unknownStyleOwner ||
        (context.story != OdfZoteroStory.unknown &&
            !{
              odfOfficeNamespace,
              odfTextNamespace,
              odfTableNamespace,
              odfDrawingNamespace,
              _styleNamespace,
            }.contains(namespace)) ||
        (namespace == odfDrawingNamespace && local != 'text-box');
    if (unsupportedOwner) {
      guards.add(OdfZoteroIssueCode.unsupportedContent);
    }
    if (isOdfCoveredCell(element)) {
      guards.add(OdfZoteroIssueCode.unsupportedContent);
    }
    if (namespace == odfTableNamespace) {
      for (final name in ['number-columns-repeated', 'number-rows-repeated']) {
        final repeat = element.getAttribute(name, namespaceUri: namespace);
        if (repeat != null && repeat != '1') {
          guards.add(OdfZoteroIssueCode.repeatedContent);
        }
      }
    }
    if (isSection) {
      final protected = element.getAttribute(
        'protected',
        namespaceUri: odfTextNamespace,
      );
      final hidden = element.getAttribute(
        'is-hidden',
        namespaceUri: odfTextNamespace,
      );
      // ODF defines boolean as true/false. Invalid lexical values must not
      // turn a protected or hidden owner into an eligible ordinary section.
      if ((protected != null && protected != 'true' && protected != 'false') ||
          (hidden != null && hidden != 'true' && hidden != 'false')) {
        guards.add(OdfZoteroIssueCode.unsupportedContent);
      }
      if (protected == 'true') {
        guards.add(OdfZoteroIssueCode.protectedSection);
      }
      if (element.getAttribute('display', namespaceUri: odfTextNamespace) ==
              'none' ||
          element.getAttribute('condition', namespaceUri: odfTextNamespace) !=
              null ||
          hidden == 'true') {
        guards.add(OdfZoteroIssueCode.unsupportedContent);
      }
      if (element.childElements.any(
            (child) =>
                (child.namespaceUri == odfTextNamespace &&
                    child.localName == 'section-source') ||
                (child.namespaceUri == odfOfficeNamespace &&
                    child.localName == 'dde-source'),
          ) ||
          element.getAttribute('href', namespaceUri: _xlinkNamespace) != null) {
        guards.add(OdfZoteroIssueCode.linkedSection);
      }
    }
    for (final section in _sectionStack) {
      section.guards.addAll(guards);
      if (isTableOwner || isTextOwner || unsupportedOwner) {
        section.guards.add(OdfZoteroIssueCode.unsupportedSectionStructure);
      }
    }
    if (isTableOwner || isTextOwner || guards.isNotEmpty) {
      context = context.child(
        element,
        path,
        owner: isTableOwner || isTextOwner || unsupportedOwner,
        guards: guards,
      );
    }

    if (isOdfParagraph(element)) {
      if (_paragraphs.length >= limits.maxParagraphs) {
        throw const OdfZoteroLimitException('paragraphs');
      }
      // Invalid nested paragraph markup is still inventoried, but never ready
      // for import; the parent's decoder must not absorb the child text.
      if (paragraph != null) {
        paragraph.guards.add(OdfZoteroIssueCode.unsupportedContent);
        context = context.child(
          element,
          path,
          guards: {OdfZoteroIssueCode.unsupportedContent},
        );
      }
      paragraph = _Paragraph(context, path, _paragraphs.length, textBudget);
      _paragraphs.add(paragraph);
    }

    final markElement =
        textElement &&
        {
          'reference-mark-start',
          'reference-mark-end',
          'reference-mark',
        }.contains(local);
    final name = (markElement || isSection)
        ? element.getAttribute('name', namespaceUri: odfTextNamespace)
        : null;
    _Field? section;
    if (name != null && _recognizedName(name)) {
      if (name.length > limits.maxNameLength) {
        throw const OdfZoteroLimitException('field name');
      }
      final count = element.attributes
          .where(
            (attribute) =>
                attribute.namespaceUri == odfTextNamespace &&
                attribute.localName == 'name',
          )
          .length;
      if (isSection) {
        section = _newField(name, OdfZoteroStorage.section);
        section.paragraphStart = _paragraphs.length;
        section.starts.add(_endpoint(context, path, null));
        section.guards.addAll(context.guards);
        if (incoming.owners.any(
          (owner) =>
              owner.namespaceUri == odfTextNamespace &&
              owner.localName == 'section',
        )) {
          section.guards.add(OdfZoteroIssueCode.nestedSection);
        }
        if (section.kind != ZoteroFieldKind.bibliography) {
          section.guards.add(OdfZoteroIssueCode.sectionKind);
        }
        if (count != 1) section.guards.add(OdfZoteroIssueCode.malformedName);
      } else if (local == 'reference-mark') {
        final field = _newField(name, OdfZoteroStorage.pointMark);
        field.starts.add(_endpoint(context, path, paragraph));
        field.guards
          ..add(OdfZoteroIssueCode.pointMark)
          ..addAll(context.guards);
        if (count != 1) field.guards.add(OdfZoteroIssueCode.malformedName);
      } else {
        final key = '${context.part}\u0000$name';
        final field = _marks.putIfAbsent(
          key,
          () => _newField(name, OdfZoteroStorage.referenceMark),
        );
        final endpoint = _endpoint(context, path, paragraph);
        (local == 'reference-mark-start' ? field.starts : field.ends).add(
          endpoint,
        );
        field.guards.addAll(context.guards);
        if (count != 1) field.guards.add(OdfZoteroIssueCode.malformedName);
      }
    }

    if (namespace == odfDrawingNamespace &&
        {'object', 'object-ole', 'image', 'frame'}.contains(local)) {
      paragraph?.guards.add(OdfZoteroIssueCode.unsupportedContent);
      if (_issues.length >= limits.maxFields) {
        throw const OdfZoteroLimitException('unsupported objects');
      }
      _issues.add(
        OdfZoteroIssue(
          OdfZoteroIssueCode.unsupportedContent,
          'Drawing or embedded object requires a rich ODT reader.',
          location: context.location(
            path,
            paragraph: paragraph,
            offset: paragraph?.decoder.length,
          ),
        ),
      );
    }

    var consumeChildren = paragraph != null;
    if (paragraph != null && !isOdfParagraph(element)) {
      if (textElement && local == 's') {
        final raw = element.getAttribute('c', namespaceUri: odfTextNamespace);
        final value = raw?.trim() ?? '1';
        if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) {
          throw const FormatException('Invalid ODF text:s count.');
        }
        final count = int.tryParse(value);
        if (count == null || count > textBudget.remaining) {
          throw const OdfZoteroLimitException('decoded text');
        }
        if (count < 0) throw const FormatException('Invalid ODF text:s count.');
        paragraph.decoder.spaces(count);
        consumeChildren = false;
      } else if (textElement && (local == 'tab' || local == 'line-break')) {
        paragraph.decoder.explicit(local == 'tab' ? '\t' : '\n');
        consumeChildren = false;
      } else if (markElement || (textElement && local == 'soft-page-break')) {
        consumeChildren = false;
      } else if (textElement && local == 'ruby-text') {
        paragraph.guards.add(OdfZoteroIssueCode.unsupportedContent);
        consumeChildren = false;
      } else if (!(textElement &&
          {
            'span',
            'a',
            'ruby',
            'ruby-base',
            'bookmark',
            'bookmark-start',
            'bookmark-end',
          }.contains(local))) {
        paragraph.guards.add(OdfZoteroIssueCode.unsupportedContent);
        if (namespace != odfTextNamespace) consumeChildren = false;
      }
    }

    var childIndex = 0;
    if (section != null) _sectionStack.add(section);
    for (final child in element.children) {
      if (child is XmlElement) {
        _visit(
          child,
          '$path/${childIndex++}',
          context,
          consumeChildren ? paragraph : null,
        );
      } else if (consumeChildren && paragraph != null) {
        if (child is XmlText) paragraph.decoder.literal(child.text);
        if (child is XmlCdata) paragraph.decoder.literal(child.text);
      }
    }
    if (isOdfParagraph(element) && paragraph != null) {
      paragraph.text = paragraph.decoder.finish();
    }
    if (section != null) {
      _sectionStack.removeLast();
      section.paragraphEnd = _paragraphs.length;
      section.ends.add(_endpoint(context, path, null));
    }
  }

  OdfZoteroInventory finish(OdfZoteroPreferences preferences) {
    final names = <String, List<_Field>>{};
    for (final field in _fields) {
      names.putIfAbsent(field.name, () => []).add(field);
      if (field.storage == OdfZoteroStorage.referenceMark) {
        if (field.starts.isEmpty) {
          field.guards.add(OdfZoteroIssueCode.missingStart);
        }
        if (field.ends.isEmpty) field.guards.add(OdfZoteroIssueCode.missingEnd);
        if (field.starts.length > 1) {
          field.guards.addAll({
            OdfZoteroIssueCode.duplicateStart,
            OdfZoteroIssueCode.duplicateName,
          });
        }
        if (field.ends.length > 1) {
          field.guards.addAll({
            OdfZoteroIssueCode.duplicateEnd,
            OdfZoteroIssueCode.duplicateName,
          });
        }
      }
      for (final endpoint in [...field.starts, ...field.ends]) {
        if (!_supportedStory(endpoint.context.story)) {
          field.guards.add(OdfZoteroIssueCode.unsupportedStory);
        }
        field.guards.addAll(endpoint.paragraph?.guards ?? {});
      }
      if (field.storage == OdfZoteroStorage.section) {
        _sectionRanges(field);
      } else if (field.storage == OdfZoteroStorage.referenceMark &&
          field.starts.length == 1 &&
          field.ends.length == 1) {
        _markRanges(field);
      }
    }
    for (final sameName in names.values) {
      if (sameName.length > 1) {
        for (final field in sameName) {
          field.guards.add(OdfZoteroIssueCode.duplicateName);
        }
      }
    }
    _overlaps();
    _fields.sort((a, b) => a.order.compareTo(b.order));
    return OdfZoteroInventory(
      fields: [
        for (final field in _fields)
          OdfZoteroField(
            name: field.name,
            storage: field.storage,
            logicalCode: field.code,
            randomSuffix: field.suffix,
            kind: field.kind,
            metadata: field.metadata,
            isValid:
                field.valid &&
                !field.guards.contains(OdfZoteroIssueCode.malformedName),
            starts: [for (final endpoint in field.starts) endpoint.location],
            ends: [for (final endpoint in field.ends) endpoint.location],
            ranges: field.ranges,
            issues: [
              for (final code in field.guards)
                OdfZoteroIssue(code, _message(code), location: field.location),
            ],
          ),
      ],
      preferences: preferences,
      issues: _issues,
      paragraphCount: _paragraphs.length,
    );
  }

  void _markRanges(_Field field) {
    final start = field.starts.single;
    final end = field.ends.single;
    if (start.order >= end.order) {
      field.guards.add(OdfZoteroIssueCode.reversedRange);
      return;
    }
    if (!_sameStory(start.context, end.context)) {
      field.guards.add(OdfZoteroIssueCode.crossStory);
      return;
    }
    if (!_sameOwners(start.context, end.context)) {
      field.guards.add(OdfZoteroIssueCode.crossOwner);
      return;
    }
    final first = start.paragraph;
    final last = end.paragraph;
    if (first == null || last == null) {
      field.guards.add(OdfZoteroIssueCode.outsideParagraph);
      return;
    }
    if (last.index < first.index) {
      field.guards.add(OdfZoteroIssueCode.crossOwner);
      return;
    }
    final selected = _paragraphs.getRange(first.index, last.index + 1).where((
      paragraph,
    ) {
      _consumeRangeWork();
      return _sameStory(paragraph.context, start.context);
    }).toList();
    if (selected.any(
      (paragraph) => !_sameOwners(paragraph.context, start.context),
    )) {
      field.guards.add(OdfZoteroIssueCode.crossOwner);
      return;
    }
    if (selected.length > 1 && field.kind == ZoteroFieldKind.citation) {
      field.guards.add(OdfZoteroIssueCode.citationAcrossParagraphs);
    }
    for (final paragraph in selected) {
      field.guards.addAll(paragraph.guards);
      _addRange(
        field,
        paragraph,
        identical(paragraph, first) ? start.offset! : 0,
        identical(paragraph, last) ? end.offset! : paragraph.text.length,
      );
    }
  }

  void _sectionRanges(_Field field) {
    final start = field.starts.single;
    // The traversal owns this interval. Empty sections do no paragraph work,
    // and nested sections cannot multiply range allocations without a bound.
    for (
      var index = field.paragraphStart;
      index < field.paragraphEnd;
      index++
    ) {
      _consumeRangeWork();
      final paragraph = _paragraphs[index];
      if (!_sameStory(paragraph.context, start.context)) continue;
      field.guards.addAll(paragraph.guards);
      if (!_sameOwners(paragraph.context, start.context)) {
        field.guards.add(OdfZoteroIssueCode.unsupportedSectionStructure);
      }
      _addRange(field, paragraph, 0, paragraph.text.length);
    }
    if (field.ranges.isEmpty) field.guards.add(OdfZoteroIssueCode.emptySection);
  }

  void _consumeRangeWork() {
    if (++_rangeWork > limits.maxRangeWork) {
      throw const OdfZoteroLimitException('range work');
    }
  }

  void _addRange(_Field field, _Paragraph paragraph, int start, int end) {
    if (++_rangeCount > limits.maxFieldRanges) {
      throw const OdfZoteroLimitException('field ranges');
    }
    if (start < 0 || end < start || end > paragraph.text.length) {
      throw const FormatException('Invalid ODT Zotero endpoint offsets.');
    }
    if (end - start > cacheBudget.remaining) {
      throw const OdfZoteroLimitException('cached field text');
    }
    final text = paragraph.text.substring(start, end);
    cacheBudget.consume(
      utf8.encode(text).length + (field.ranges.isEmpty ? 0 : 1),
    );
    field.ranges.add(
      OdfZoteroTextRange(
        location: paragraph.context.location(
          paragraph.path,
          paragraph: paragraph,
          offset: start,
        ),
        start: start,
        end: end,
        text: text,
      ),
    );
  }

  void _overlaps() {
    // Sweep contiguous interval components instead of comparing every pair.
    // A nested/crossed component is wholly guarded even for malformed metadata.
    int endOrder(_Field field) => field.ends.isEmpty
        ? field.starts.single.order
        : field.ends.single.order;
    final ranges =
        _fields
            .where(
              (field) =>
                  field.starts.length == 1 &&
                  ((field.ends.length == 1 &&
                          field.starts.single.order <
                              field.ends.single.order) ||
                      field.storage == OdfZoteroStorage.pointMark),
            )
            .toList()
          ..sort(
            (a, b) => a.starts.single.order.compareTo(b.starts.single.order),
          );
    var component = <_Field>[];
    _Field? furthest;
    void close() {
      if (component.length > 1) {
        for (final field in component) {
          field.guards.add(OdfZoteroIssueCode.overlappingFields);
        }
      }
      component = [];
    }

    for (final field in ranges) {
      final previous = furthest;
      if (previous == null || field.starts.single.order >= endOrder(previous)) {
        close();
        furthest = field;
      } else {
        final code = endOrder(field) <= endOrder(previous)
            ? OdfZoteroIssueCode.nestedRange
            : OdfZoteroIssueCode.crossedRange;
        field.guards.add(code);
        previous.guards.add(code);
        if (endOrder(field) > endOrder(previous)) {
          furthest = field;
        }
      }
      component.add(field);
    }
    close();
  }
}

bool _recognizedName(String name) =>
    name.contains('ZOTERO_') || name.contains(' CSL_');

void _parseName(_Field field) {
  final match = RegExp(r' RND([A-Za-z0-9]{10})$').firstMatch(field.name);
  if (!field.name.startsWith('ZOTERO_')) {
    field.guards.add(OdfZoteroIssueCode.legacyName);
    return;
  }
  if (match == null) {
    field.guards.add(OdfZoteroIssueCode.malformedName);
    return;
  }
  field.code = field.name.substring('ZOTERO_'.length, match.start);
  field.suffix = match.group(1);
  if (!(field.code!.startsWith('ITEM CSL_CITATION ') ||
      field.code!.startsWith('BIBL '))) {
    field.guards.add(OdfZoteroIssueCode.unsupportedCode);
    return;
  }
  final instruction = ' ADDIN ZOTERO_${field.code} ';
  field.kind = WordZotero.kindOfInstruction(instruction);
  field.metadata = WordZotero.metadataOf(instruction);
  if (field.metadata == null || field.kind == null) {
    field.guards.add(OdfZoteroIssueCode.invalidMetadata);
    return;
  }
  try {
    if (field.kind == ZoteroFieldKind.citation) {
      ZoteroCitation.fromJson(field.metadata!);
    }
    field.valid = true;
  } on FormatException {
    field.guards.add(OdfZoteroIssueCode.invalidMetadata);
  } on ArgumentError {
    field.guards.add(OdfZoteroIssueCode.invalidMetadata);
  }
}

bool _supportedStory(OdfZoteroStory story) =>
    story == OdfZoteroStory.body ||
    story == OdfZoteroStory.footnote ||
    story == OdfZoteroStory.endnote;

bool _sameStory(_Context a, _Context b) =>
    a.part == b.part && a.story == b.story && a.storyPath == b.storyPath;

bool _sameOwners(_Context a, _Context b) =>
    a.owners.length == b.owners.length &&
    Iterable<int>.generate(a.owners.length).every(
      (index) =>
          a.owners[index].path == b.owners[index].path &&
          a.owners[index].namespaceUri == b.owners[index].namespaceUri &&
          a.owners[index].localName == b.owners[index].localName,
    );

String _message(OdfZoteroIssueCode code) => switch (code) {
  OdfZoteroIssueCode.legacyName =>
    'Legacy or nonanchored Zotero name is not qualified.',
  OdfZoteroIssueCode.malformedName =>
    'Expected one canonical name and a terminal ten-character RND identity.',
  OdfZoteroIssueCode.unsupportedCode =>
    'Native field code is not a supported citation or bibliography.',
  OdfZoteroIssueCode.invalidMetadata =>
    'Zotero field metadata is malformed or exceeds the bounded codec.',
  OdfZoteroIssueCode.missingStart => 'Reference mark has no start endpoint.',
  OdfZoteroIssueCode.missingEnd => 'Reference mark has no end endpoint.',
  OdfZoteroIssueCode.duplicateStart =>
    'Reference mark has multiple start endpoints.',
  OdfZoteroIssueCode.duplicateEnd =>
    'Reference mark has multiple end endpoints.',
  OdfZoteroIssueCode.duplicateName =>
    'Native Zotero name is not unique in this document.',
  OdfZoteroIssueCode.pointMark =>
    'Point reference mark has no cached text range.',
  OdfZoteroIssueCode.reversedRange => 'End endpoint precedes its start.',
  OdfZoteroIssueCode.crossStory =>
    'Reference endpoints belong to different stories.',
  OdfZoteroIssueCode.crossOwner =>
    'Reference endpoints cross structural owners.',
  OdfZoteroIssueCode.outsideParagraph =>
    'Reference endpoint is outside a text paragraph.',
  OdfZoteroIssueCode.unsupportedStory =>
    'This story requires explicit rich-import support.',
  OdfZoteroIssueCode.unsupportedContent =>
    'The surrounding content needs additional rich-import handling.',
  OdfZoteroIssueCode.repeatedContent =>
    'Repeated table content has ambiguous physical identities.',
  OdfZoteroIssueCode.citationAcrossParagraphs =>
    'A citation spans multiple paragraphs.',
  OdfZoteroIssueCode.nestedRange => 'Native field ranges are nested.',
  OdfZoteroIssueCode.crossedRange => 'Native field endpoints cross.',
  OdfZoteroIssueCode.overlappingFields =>
    'Native field ownership overlaps another field.',
  OdfZoteroIssueCode.nestedSection =>
    'Nested bibliography section needs explicit rich-import handling.',
  OdfZoteroIssueCode.protectedSection =>
    'Field belongs to a protected section.',
  OdfZoteroIssueCode.linkedSection =>
    'Field belongs to an externally linked section.',
  OdfZoteroIssueCode.sectionKind =>
    'Only native bibliography codes are candidates in sections.',
  OdfZoteroIssueCode.emptySection =>
    'Bibliography section has no owned text paragraphs.',
  OdfZoteroIssueCode.unsupportedSectionStructure =>
    'Bibliography section contains additional structural owners.',
};

/// The ODF collapse rules plus deferred endpoints at pending literal spaces.
///
/// If a space before a mark eventually becomes visible, the mark moves after
/// that space. Paragraph-final collapsed whitespace contributes no offset.
final class _PositionedText {
  _PositionedText(this.budget);

  final OdfTextBudget budget;
  final _buffer = StringBuffer();
  final _pendingAnchors = <_Endpoint>[];
  bool _started = false;
  bool _pendingSpace = false;

  int get length => _buffer.length;

  void anchor(_Endpoint endpoint) {
    if (_pendingSpace) _pendingAnchors.add(endpoint);
  }

  void literal(String value) {
    var index = 0;
    while (index < value.length) {
      if (_whitespace(value.codeUnitAt(index))) {
        _pendingSpace = true;
        index++;
        continue;
      }
      final start = index;
      while (index < value.length && !_whitespace(value.codeUnitAt(index))) {
        index++;
      }
      _flush();
      _append(value.substring(start, index));
      _started = true;
    }
  }

  void explicit(String value) {
    _flush();
    _append(value);
    _started = true;
  }

  void spaces(int count) {
    _flush();
    budget.consume(count);
    _buffer.write(' ' * count);
    _started = true;
  }

  void _flush() {
    if (_pendingSpace && _started) _append(' ');
    for (final anchor in _pendingAnchors) {
      anchor.offset = length;
    }
    _pendingAnchors.clear();
    _pendingSpace = false;
  }

  void _append(String value) {
    budget.consume(utf8.encode(value).length);
    _buffer.write(value);
  }

  String finish() {
    // Trailing literal whitespace is discarded, so deferred offsets stay put.
    _pendingAnchors.clear();
    return _buffer.toString();
  }
}

bool _whitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;
