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

  static WmlBookmarkBoundary read(XmlPullReader reader) {
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

  static void write(XmlWriter writer, WmlBookmarkBoundary marker) {
    WordBookmarks.validateSource(marker);
    if (marker.sourceXml != null) {
      XmlDocument.parse(marker.sourceXml!).root!.writeTo(writer);
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
