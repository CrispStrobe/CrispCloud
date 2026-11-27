import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_bookmarks.dart';
import 'word_property_io.dart';

/// Native endpoints use the same validated model as editing and range lookup.
abstract final class WordBookmarkIo {
  static bool isMarker(XmlPullReader reader) =>
      reader.namespaceUri == OfficeNamespaces.w &&
      (reader.localName == 'bookmarkStart' ||
          reader.localName == 'bookmarkEnd');

  static final _nonPlainNameCharacter = RegExp(r'[^A-Za-z0-9_]');

  static WmlBookmarkBoundary read(XmlPullReader reader) {
    final empty = reader.isEmptyElement;
    final attributeCount = reader.attributeCount;
    final source = XmlDocument.readElement(reader);
    final isStart = source.localName == 'bookmarkStart';
    final name = source.getAttribute('name', namespaceUri: OfficeNamespaces.w);
    final plain = empty && _hasPlainSource(source, attributeCount, isStart, name);
    if (plain) WordPropertyIo.compactScalarWordFragment(source);
    final marker = WmlBookmarkBoundary(
      id: source.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
      isStart: isStart,
      name: name,
      sourceXml: XmlDocument(root: source).toXmlString(declaration: false),
    );
    if (plain) {
      // The captured element already owns these attributes and the native
      // namespace. Plain decimal IDs and ASCII names survive XML serialization.
      WordBookmarks.canonicalId(marker.id);
    } else {
      WordBookmarks.validateSource(marker);
    }
    return marker;
  }

  static bool _hasPlainSource(
    XmlElement source,
    int attributeCount,
    bool isStart,
    String? name,
  ) {
    if (source.prefix != 'w' ||
        source.namespaceUri != OfficeNamespaces.w ||
        source.localName != (isStart ? 'bookmarkStart' : 'bookmarkEnd') ||
        attributeCount != (isStart ? 2 : 1)) {
      return false;
    }
    for (var i = 0; i < attributeCount; i++) {
      final attribute = source.attributes[i];
      if (attribute.prefix != 'w' ||
          (attribute.localName != 'id' && attribute.localName != 'name')) {
        return false;
      }
    }
    return !isStart ||
        name != null &&
            name.isNotEmpty &&
            !_nonPlainNameCharacter.hasMatch(name);
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
