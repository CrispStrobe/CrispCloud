import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_bookmarks.dart';

/// Native endpoints use the same validated model as editing and range lookup.
abstract final class WordBookmarkIo {
  static bool isMarker(XmlPullReader reader) =>
      reader.namespaceUri == OfficeNamespaces.w &&
      (reader.localName == 'bookmarkStart' ||
          reader.localName == 'bookmarkEnd');

  static final _nonPlainNameCharacter = RegExp(r'[^A-Za-z0-9_]');

  static WmlBookmarkBoundary read(XmlPullReader reader) {
    final plain = _readPlainMarker(reader);
    if (plain != null) return plain;

    final source = XmlDocument.readElement(reader);
    final marker = WmlBookmarkBoundary(
      id: source.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
      isStart: source.localName == 'bookmarkStart',
      name: source.getAttribute('name', namespaceUri: OfficeNamespaces.w),
      sourceXml: XmlDocument(root: source).toXmlString(declaration: false),
    );
    WordBookmarks.validateSource(marker);
    return marker;
  }

  static WmlBookmarkBoundary? _readPlainMarker(XmlPullReader reader) {
    if (!reader.isEmptyElement ||
        reader.prefix != 'w' ||
        reader.namespaceUri != OfficeNamespaces.w) {
      return null;
    }
    final element = reader.localName;
    final isStart = element == 'bookmarkStart';
    if ((!isStart && element != 'bookmarkEnd') ||
        reader.attributeCount != (isStart ? 2 : 1)) {
      return null;
    }
    final firstAttribute = reader.attributeQualifiedName(0);
    final idFirst = firstAttribute == 'w:id';
    if (!idFirst && (!isStart || firstAttribute != 'w:name')) return null;
    final secondAttribute = idFirst ? 'w:name' : 'w:id';
    if (isStart && reader.attributeQualifiedName(1) != secondAttribute) {
      return null;
    }
    final id = reader.attributeValue(idFirst ? 0 : 1);
    final name = isStart ? reader.attributeValue(idFirst ? 1 : 0) : null;
    if (name != null &&
        (name.isEmpty || _nonPlainNameCharacter.hasMatch(name))) {
      return null;
    }
    WordBookmarks.canonicalId(id);

    // These scalar attributes only use the Word prefix. Also retain any
    // inherited default declaration, at its original position relative to w.
    final writer = XmlWriter()..writeStartElement(element, prefix: 'w');
    writer.writeAttribute(firstAttribute, idFirst ? id : name!);
    if (isStart) writer.writeAttribute(secondAttribute, idFirst ? name! : id);
    final namespaces = reader.inScopeNamespaces;
    if (namespaces.containsKey('')) {
      for (final entry in namespaces.entries) {
        if (entry.key.isEmpty || entry.key == 'w') {
          writer.writeNamespace(entry.key, entry.value);
        }
      }
    } else {
      writer.writeNamespace('w', OfficeNamespaces.w);
    }
    writer.writeEndElement();
    reader.next();
    return WmlBookmarkBoundary(
      id: id,
      isStart: isStart,
      name: name,
      sourceXml: writer.toXml(),
    );
  }

  static void write(XmlWriter writer, WmlBookmarkBoundary marker) {
    final source = WordBookmarks.validateSource(marker);
    if (source != null) {
      source.writeTo(writer);
      return;
    }
    writer.writeEmptyElement(
      marker.isStart ? 'bookmarkStart' : 'bookmarkEnd',
      prefix: 'w',
      attributes: {
        'w:id': marker.id,
        if (marker.isStart) 'w:name': marker.name!,
      },
    );
  }
}
