import 'dart:convert';

import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import 'wml_document.dart';

/// Zotero's document-wide CSL preferences, retained in native Word custom
/// properties. Only the package-owned custom-properties part is authoritative.
abstract final class WordZoteroDocumentData {
  static const _propertyPrefix = 'ZOTERO_PREF_';
  static const _propertyNamespace = OfficeNamespaces.customProperties;
  static const _valueNamespace = OfficeNamespaces.docPropsVt;
  static const _contentType =
      'application/vnd.openxmlformats-officedocument.custom-properties+xml';
  static const _formatId = '{D5CDD505-2E9C-101B-9397-08002B2CF9AE}';

  /// Bounded independently of the document and the remote command stream.
  static const maxDataLength = 256 * 1024;
  static const _maxPartLength = 2 * 1024 * 1024;
  static const _chunkLength = 255;

  /// Returns native document data, or an empty string when none is present.
  /// Ambiguous or damaged preference sequences are never silently discarded.
  static String read(WmlDocument document) {
    final override = document.zoteroDocumentData;
    if (override != null) return toNative(override);
    final package = document.package;
    if (package == null) return '';
    final found = _find(package);
    return found == null ? '' : toNative(_readProperties(found.root));
  }

  /// Adapts the storage preference for Zotero's HTTP integration. Other XML or
  /// JSON keys, including extensions unknown to this editor, remain intact.
  static String toHttp(String data) => _convert(data, 'Http');

  /// Adapts the storage preference back to Word fields before DOCX storage.
  static String toNative(String data) => _convert(data, 'Field');

  /// Requests a fresh native bibliography layout without changing the chosen
  /// style or any unrelated preference. Earlier simplified results must not
  /// permanently advertise that their paragraph layout was already applied.
  static String requestBibliographyStyle(String data) {
    final native = toNative(data);
    if (native.isEmpty) return native;
    if (native.trim().startsWith('{')) {
      final json = jsonDecode(native) as Map<String, dynamic>;
      final style = json['style'];
      if (style is! Map<String, dynamic>) return native;
      if (style['bibliographyStyleHasBeenSet'] != true) return native;
      style['bibliographyStyleHasBeenSet'] = false;
      return _bounded(jsonEncode(json));
    }
    final root = _parseXml(native);
    final styles = root.childrenNamed('style', namespaceUri: '');
    if (styles.length > 1) {
      throw const FormatException('Duplicate Zotero document styles');
    }
    if (styles.length != 1 ||
        styles.single.getAttribute('bibliographyStyleHasBeenSet') != '1') {
      return native;
    }
    styles.single.setAttribute('bibliographyStyleHasBeenSet', '0');
    return _bounded(XmlDocument(root: root).toXmlString(declaration: false));
  }

  /// Note placement for a catalog selection seeded into the native picker.
  /// Zotero treats that seed as an existing field, so its document style must
  /// already be chosen before the seed is created.
  static int citationNoteType(String data) {
    final preferences = stylePreferences(data);
    if (preferences == null) {
      throw const FormatException(
        'Choose Document → Document style… in Zotero before inserting selected catalog sources.',
      );
    }
    return preferences.noteType;
  }

  /// The saved native style, language and placement, without changing data.
  /// Returns null until Zotero has supplied a complete document style.
  /// Malformed or ambiguous data still throws instead of being replaced.
  static ({String id, String? locale, int noteType})? stylePreferences(
    String data,
  ) {
    final native = toNative(data);
    Object? styleId;
    Object? locale;
    Object? noteType;
    if (native.trim().startsWith('{')) {
      final json = jsonDecode(native) as Map<String, dynamic>;
      final style = json['style'];
      if (style != null && style is! Map<String, dynamic>) {
        throw const FormatException('Malformed Zotero document style');
      }
      if (style is Map<String, dynamic>) {
        styleId = style['styleID'];
        locale = style['locale'];
      }
      noteType = (json['prefs'] as Map<String, dynamic>)['noteType'];
      // JSON numbers describe the enum's value. Integral doubles and exponent
      // forms must have the same meaning on the VM and JavaScript, whose
      // number representation does not distinguish 1 from 1.0.
      if (noteType is num &&
          noteType.isFinite &&
          noteType >= 0 &&
          noteType <= 2 &&
          noteType == noteType.truncateToDouble()) {
        noteType = noteType.toInt();
      }
    } else if (native.isNotEmpty) {
      final root = _parseXml(native);
      final styles = root.childrenNamed('style', namespaceUri: '');
      if (styles.length > 1) {
        throw const FormatException('Duplicate Zotero document styles');
      }
      if (styles.length == 1) {
        styleId = styles.single.getAttribute('id');
        locale = styles.single.getAttribute('locale');
      }
      final prefs = root.childrenNamed('prefs', namespaceUri: '').single;
      final notes = prefs
          .childrenNamed('pref', namespaceUri: '')
          .where((pref) => pref.getAttribute('name') == 'noteType');
      // Zotero's native XML writer omits falsy preferences; its reader treats
      // absent noteType as inline (0).
      if (notes.isEmpty) {
        noteType = 0;
      } else if (notes.length == 1) {
        final value = notes.single.getAttribute('value');
        if (value == '0' || value == '1' || value == '2') {
          noteType = int.parse(value!);
        } else {
          throw const FormatException('Invalid Zotero citation placement');
        }
      }
    }
    if ((styleId != null && styleId is! String) ||
        (locale != null && locale is! String)) {
      throw const FormatException('Malformed Zotero document style');
    }
    if (noteType != null &&
        (noteType is! int || noteType < 0 || noteType > 2)) {
      throw const FormatException('Invalid Zotero citation placement');
    }
    if (styleId is! String ||
        styleId.trim().isEmpty ||
        noteType is! int ||
        noteType < 0 ||
        noteType > 2) {
      return null;
    }
    return (
      id: styleId,
      locale: locale is String && locale.trim().isNotEmpty ? locale : null,
      noteType: noteType,
    );
  }

  /// Validates and prepares preference changes without mutating the package.
  /// The serializer invokes the returned closure only after its other writes.
  static void Function() prepareWrite(
    WmlDocument document,
    OpcPackage package,
  ) {
    final override = document.zoteroDocumentData;
    if (override == null) return () {};
    final data = toNative(override);
    final found = _find(package);
    final previous = found == null ? '' : _readProperties(found.root);
    if (data == previous) return () {};
    final root =
        found?.root ??
        (XmlElement(localName: 'Properties', namespaceUri: _propertyNamespace)
          ..setAttribute('xmlns', _propertyNamespace)
          ..setAttribute('vt', _valueNamespace, prefix: 'xmlns'));
    root.children.removeWhere(
      (node) =>
          node is XmlElement &&
          node.namespaceUri == _propertyNamespace &&
          node.localName == 'property' &&
          (node.getAttribute('name') ?? '').startsWith(_propertyPrefix),
    );
    final usedIds = <int>{};
    for (final property in root.childrenNamed(
      'property',
      namespaceUri: _propertyNamespace,
    )) {
      final id = int.tryParse(property.getAttribute('pid') ?? '');
      if (id != null) usedIds.add(id);
    }
    var id = 2;
    var index = 1;
    for (final chunk in _chunks(data)) {
      while (usedIds.contains(id)) {
        id++;
      }
      final property =
          XmlElement(
              localName: 'property',
              prefix: root.prefix,
              namespaceUri: _propertyNamespace,
            )
            ..setAttribute('fmtid', _formatId)
            ..setAttribute('pid', '${id++}')
            ..setAttribute('name', '$_propertyPrefix${index++}');
      // A local declaration avoids taking over an unrelated source prefix.
      property.addChild(
        XmlElement(
            localName: 'lpwstr',
            prefix: 'vt',
            namespaceUri: _valueNamespace,
          )
          ..setAttribute('vt', _valueNamespace, prefix: 'xmlns')
          ..setAttribute(
            'space',
            'preserve',
            prefix: 'xml',
            namespaceUri: OfficeNamespaces.xml,
          )
          ..text = chunk,
      );
      root.addChild(property);
    }
    final uri = found?.part.uri ?? _allocateUri(package);
    final xml = XmlDocument(root: root).toXmlString();
    final payload = utf8.encode(xml);
    if (payload.length > _maxPartLength) {
      throw const FormatException('Zotero custom properties exceed the limit');
    }
    return () {
      final part = package.getPart(uri);
      if (part == null) {
        package.createPart(uri, _contentType, payload);
      } else {
        part
          ..contentType = _contentType
          ..writeText(xml);
        package.contentTypes.setOverride(uri, _contentType);
      }
      if (found == null) {
        package.packageRelationships.add(
          type: RelationshipTypes.customProperties,
          target: uri.substring(1),
        );
      }
    };
  }

  static String _convert(String data, String fieldType) {
    if (data.isEmpty) return '';
    if (data.length > maxDataLength) {
      throw const FormatException(
        'Zotero document preferences exceed the limit',
      );
    }
    final trimmed = data.trim();
    if (trimmed.startsWith('{')) {
      final Object? decoded;
      try {
        _ZoteroJsonShape(data).validate();
        decoded = jsonDecode(data);
      } on FormatException {
        throw const FormatException('Malformed Zotero document preferences');
      }
      if (decoded is! Map<String, dynamic> ||
          decoded['prefs'] is! Map<String, dynamic>) {
        throw const FormatException('Missing Zotero document preferences');
      }
      final prefs = decoded['prefs'] as Map<String, dynamic>;
      _checkFieldType(prefs['fieldType']);
      if (prefs['fieldType'] == fieldType) return data;
      prefs['fieldType'] = fieldType;
      return _bounded(jsonEncode(decoded));
    }
    final root = _parseXml(data);
    if (root.localName != 'data' || root.namespaceUri.isNotEmpty) {
      throw const FormatException('Unsupported Zotero document preferences');
    }
    final preferences = root.childrenNamed('prefs', namespaceUri: '');
    if (preferences.length != 1) {
      throw const FormatException('Missing or duplicate Zotero preferences');
    }
    final names = <String>{};
    final fields = <XmlElement>[];
    for (final pref in preferences.single.childrenNamed(
      'pref',
      namespaceUri: '',
    )) {
      final name = pref.getAttribute('name');
      if (name == null || name.isEmpty || !names.add(name)) {
        throw const FormatException(
          'Missing or duplicate Zotero preference name',
        );
      }
      if (name == 'fieldType') fields.add(pref);
    }
    if (fields.length != 1) {
      throw const FormatException('Missing or duplicate Zotero field type');
    }
    final value = fields.single.getAttribute('value');
    _checkFieldType(value);
    if (value == fieldType) return data;
    fields.single.setAttribute('value', fieldType);
    return _bounded(XmlDocument(root: root).toXmlString(declaration: false));
  }

  static String _bounded(String data) {
    if (data.length > maxDataLength) {
      throw const FormatException(
        'Zotero document preferences exceed the limit',
      );
    }
    return data;
  }

  static void _checkFieldType(Object? fieldType) {
    if (fieldType != 'Field' && fieldType != 'Http') {
      throw const FormatException(
        'Only Zotero Word fields can use the desktop connection',
      );
    }
  }

  static ({PackagePart part, XmlElement root})? _find(OpcPackage package) {
    final relationships = package.packageRelationships
        .byType(RelationshipTypes.customProperties)
        .toList();
    if (relationships.isEmpty) return null;
    if (relationships.length != 1 ||
        relationships.single.targetMode == RelationshipTargetMode.external) {
      throw const FormatException('Ambiguous Word custom-properties ownership');
    }
    final relationship = relationships.single;
    final target = Uri.tryParse(relationship.target);
    if (target == null ||
        target.hasScheme ||
        target.hasAuthority ||
        target.hasQuery ||
        target.hasFragment) {
      throw const FormatException('Invalid Word custom-properties target');
    }
    final part = package.getPart(
      package.packageRelationships.resolve(relationship),
    );
    if (part == null || part.length > _maxPartLength) {
      throw const FormatException(
        'Missing or oversized Word custom properties',
      );
    }
    final root = _parseXml(_readXmlPart(part));
    if (root.localName != 'Properties' ||
        root.namespaceUri != _propertyNamespace) {
      throw const FormatException('Invalid Word custom-properties part');
    }
    return (part: part, root: root);
  }

  static String _readProperties(XmlElement root) {
    final values = <int, String>{};
    var length = 0;
    for (final property in root.childrenNamed(
      'property',
      namespaceUri: _propertyNamespace,
    )) {
      final name = property.getAttribute('name') ?? '';
      if (!name.startsWith(_propertyPrefix)) continue;
      final suffix = name.substring(_propertyPrefix.length);
      final index = int.tryParse(suffix);
      if (index == null ||
          index < 1 ||
          index > 2048 ||
          '$index' != suffix ||
          values.containsKey(index)) {
        throw const FormatException(
          'Invalid or duplicate Zotero preference chunk',
        );
      }
      final children = property.childElements.toList();
      if (children.length != 1 ||
          children.single.localName != 'lpwstr' ||
          children.single.namespaceUri != _valueNamespace ||
          children.single.childElements.isNotEmpty) {
        throw const FormatException('Invalid Zotero preference chunk type');
      }
      final text = children.single.text;
      if (text.isEmpty || text.length > _chunkLength) {
        throw const FormatException('Invalid Zotero preference chunk length');
      }
      length += text.length;
      if (length > maxDataLength) {
        throw const FormatException(
          'Zotero document preferences exceed the limit',
        );
      }
      values[index] = text;
    }
    if (values.isEmpty) return '';
    final result = StringBuffer();
    for (var index = 1; index <= values.length; index++) {
      final value = values[index];
      if (value == null) {
        throw const FormatException('Incomplete Zotero document preferences');
      }
      result.write(value);
    }
    final data = result.toString();
    toNative(data);
    return data;
  }

  static Iterable<String> _chunks(String data) sync* {
    for (var offset = 0; offset < data.length;) {
      var end = (offset + _chunkLength).clamp(0, data.length);
      if (end < data.length) {
        final last = data.codeUnitAt(end - 1);
        if (last >= 0xd800 && last <= 0xdbff) end--;
      }
      yield data.substring(offset, end);
      offset = end;
    }
  }

  static String _allocateUri(OpcPackage package) {
    var index = 1;
    while (true) {
      final uri = '/docProps/custom${index == 1 ? '' : index}.xml';
      if (package.getPart(uri) == null) return uri;
      index++;
    }
  }

  static XmlElement _parseXml(String data) {
    _checkXmlCharacters(data);
    final reader = XmlPullReader(data);
    var depth = 0;
    var roots = 0;
    var nodes = 0;
    final stack = <XmlElement>[];
    XmlElement? root;
    try {
      while (reader.next()) {
        switch (reader.eventType) {
          case XmlEventType.startElement:
            if (depth++ == 0) roots++;
            if (++nodes > 16384 || depth > 64 || roots > 1) {
              throw const FormatException(
                'Invalid or excessive preference XML',
              );
            }
            final attributes = <String>{};
            final element = XmlElement(
              localName: reader.localName,
              prefix: reader.prefix,
              namespaceUri: reader.namespaceUri,
            );
            for (var i = 0; i < reader.attributeCount; i++) {
              if (!attributes.add(reader.attributeQualifiedName(i))) {
                throw const FormatException(
                  'Duplicate preference XML attribute',
                );
              }
              _checkXmlCharacters(reader.attributeValue(i));
              element.attributes.add(
                XmlAttribute(
                  localName: reader.attributeLocalName(i),
                  value: reader.attributeValue(i),
                  prefix: reader.attributePrefix(i),
                  namespaceUri: reader.attributeNamespace(i),
                ),
              );
            }
            if (stack.isEmpty) {
              root = element;
            } else {
              stack.last.addChild(element);
            }
            stack.add(element);
          case XmlEventType.endElement:
            depth--;
            if (stack.isNotEmpty) stack.removeLast();
          case XmlEventType.dtd:
          case XmlEventType.processingInstruction:
            throw const FormatException(
              'Unsupported preference XML declaration',
            );
          case XmlEventType.characters:
          case XmlEventType.cdata:
            _checkXmlCharacters(reader.text);
            if (depth == 0 && reader.text.trim().isNotEmpty) {
              throw const FormatException(
                'Content outside preference XML root',
              );
            }
            if (stack.isNotEmpty) {
              stack.last.addChild(
                reader.eventType == XmlEventType.cdata
                    ? XmlCdata(reader.text)
                    : XmlText(reader.text),
              );
            }
          case XmlEventType.comment:
            if (stack.isNotEmpty) stack.last.addChild(XmlComment(reader.text));
          default:
            break;
        }
      }
      if (depth != 0 || roots != 1) {
        throw const FormatException('Incomplete Zotero preference XML');
      }
      if (root == null) {
        throw const FormatException('Missing Zotero preference XML root');
      }
      return root;
    } on XmlParseException {
      throw const FormatException('Malformed Zotero preference XML');
    } on RangeError {
      throw const FormatException('Invalid Zotero preference XML character');
    }
  }

  static void _checkXmlCharacters(String text) {
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == 9 || unit == 10 || unit == 13) continue;
      if (unit < 0x20 || unit == 0xfffe || unit == 0xffff) {
        throw const FormatException('Invalid Zotero preference XML character');
      }
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index >= text.length) {
          throw const FormatException('Incomplete Zotero preference character');
        }
        final low = text.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) {
          throw const FormatException(
            'Invalid Zotero preference character pair',
          );
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid Zotero preference character pair');
      }
    }
  }

  static String _readXmlPart(PackagePart part) {
    final bytes = part.bytesView;
    final bomLittle = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
    final bomBig = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff;
    final little =
        bomLittle || (bytes.length >= 4 && bytes[0] == 0x3c && bytes[1] == 0);
    final big =
        bomBig || (bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0x3c);
    if (!little && !big) return part.readText();
    final start = bomLittle || bomBig ? 2 : 0;
    if ((bytes.length - start).isOdd) {
      throw const FormatException('Truncated UTF-16 Zotero custom properties');
    }
    return String.fromCharCodes([
      for (var index = start; index < bytes.length; index += 2)
        little
            ? bytes[index] | (bytes[index + 1] << 8)
            : (bytes[index] << 8) | bytes[index + 1],
    ]);
  }
}

/// Checks duplicate object keys and nesting before the ordinary JSON decoder
/// constructs data. Duplicate preferences cannot silently become last-wins.
final class _ZoteroJsonShape {
  _ZoteroJsonShape(this.source);

  final String source;
  var at = 0;

  void validate() {
    _value(0);
    _space();
    if (at != source.length) {
      throw const FormatException('Trailing Zotero preference JSON');
    }
  }

  void _value(int depth) {
    if (depth > 64) {
      throw const FormatException('Excessive Zotero preference nesting');
    }
    _space();
    if (at == source.length) {
      throw const FormatException('Incomplete Zotero preference JSON');
    }
    final unit = source.codeUnitAt(at);
    if (unit == 0x7b || unit == 0x5b) {
      final object = unit == 0x7b;
      final end = object ? 0x7d : 0x5d;
      final names = <String>{};
      at++;
      _space();
      if (_take(end)) return;
      while (true) {
        _space();
        if (object) {
          final name = _string();
          if (!names.add(name)) {
            throw const FormatException('Duplicate Zotero preference JSON key');
          }
          _space();
          if (!_take(0x3a)) {
            throw const FormatException('Missing Zotero preference JSON colon');
          }
        }
        _value(depth + 1);
        _space();
        if (_take(end)) return;
        if (!_take(0x2c)) {
          throw const FormatException(
            'Missing Zotero preference JSON delimiter',
          );
        }
      }
    }
    if (unit == 0x22) {
      _string();
      return;
    }
    final start = at;
    while (at < source.length &&
        ![0x20, 9, 10, 13, 0x2c, 0x5d, 0x7d].contains(source.codeUnitAt(at))) {
      at++;
    }
    if (at == start) {
      throw const FormatException('Invalid Zotero preference JSON value');
    }
    jsonDecode(source.substring(start, at));
  }

  String _string() {
    final start = at;
    if (!_take(0x22)) {
      throw const FormatException('Invalid Zotero preference JSON key');
    }
    while (at < source.length) {
      final unit = source.codeUnitAt(at++);
      if (unit == 0x22) {
        return jsonDecode(source.substring(start, at)) as String;
      }
      if (unit == 0x5c) at++;
    }
    throw const FormatException('Incomplete Zotero preference JSON string');
  }

  bool _take(int unit) {
    if (at >= source.length || source.codeUnitAt(at) != unit) return false;
    at++;
    return true;
  }

  void _space() {
    while (at < source.length &&
        [0x20, 9, 10, 13].contains(source.codeUnitAt(at))) {
      at++;
    }
  }
}
