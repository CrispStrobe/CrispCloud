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
    return found == null ? '' : _readProperties(found.root);
  }

  /// Adapts the storage preference for Zotero's HTTP integration. Other XML or
  /// JSON keys, including extensions unknown to this editor, remain intact.
  static String toHttp(String data) => _convert(data, 'Http');

  /// Adapts the storage preference back to Word fields before DOCX storage.
  static String toNative(String data) => _convert(data, 'Field');

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
          ..text = chunk,
      );
      root.addChild(property);
    }
    final uri = found?.part.uri ?? _allocateUri(package);
    final xml = XmlDocument(root: root).toXmlString();
    if (xml.length > _maxPartLength) {
      throw const FormatException('Zotero custom properties exceed the limit');
    }
    return () {
      final part = package.getPart(uri);
      if (part == null) {
        package.createPart(uri, _contentType, utf8.encode(xml));
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
      return jsonEncode(decoded);
    }
    final root = _parseXml(data);
    if (root.localName != 'data' || root.namespaceUri.isNotEmpty) {
      throw const FormatException('Unsupported Zotero document preferences');
    }
    final preferences = root.childrenNamed('prefs', namespaceUri: '');
    if (preferences.length != 1) {
      throw const FormatException('Missing or duplicate Zotero preferences');
    }
    final fields = preferences.single
        .childrenNamed('pref', namespaceUri: '')
        .where((node) => node.getAttribute('name') == 'fieldType')
        .toList();
    if (fields.length != 1) {
      throw const FormatException('Missing or duplicate Zotero field type');
    }
    final value = fields.single.getAttribute('value');
    _checkFieldType(value);
    if (value == fieldType) return data;
    fields.single.setAttribute('value', fieldType);
    return XmlDocument(root: root).toXmlString(declaration: false);
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
    return toNative(result.toString());
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
    final reader = XmlPullReader(data);
    var depth = 0;
    var roots = 0;
    var nodes = 0;
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
            for (var i = 0; i < reader.attributeCount; i++) {
              if (!attributes.add(reader.attributeQualifiedName(i))) {
                throw const FormatException(
                  'Duplicate preference XML attribute',
                );
              }
            }
          case XmlEventType.endElement:
            depth--;
          case XmlEventType.dtd:
          case XmlEventType.processingInstruction:
            throw const FormatException(
              'Unsupported preference XML declaration',
            );
          case XmlEventType.characters:
          case XmlEventType.cdata:
            if (depth == 0 && reader.text.trim().isNotEmpty) {
              throw const FormatException(
                'Content outside preference XML root',
              );
            }
          default:
            break;
        }
      }
      if (depth != 0 || roots != 1) {
        throw const FormatException('Incomplete Zotero preference XML');
      }
      final root = XmlDocument.parse(data).root;
      if (root == null) {
        throw const FormatException('Missing Zotero preference XML root');
      }
      return root;
    } on XmlParseException {
      throw const FormatException('Malformed Zotero preference XML');
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
