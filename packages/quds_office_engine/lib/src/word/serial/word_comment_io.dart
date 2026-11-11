import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../model/wml_document.dart';

/// Joins native comment extensions through their last paragraph's w14:paraId.
///
/// CT_CommentEx paraId/paraIdParent identify paragraphs, not w:comment/@w:id:
/// https://learn.microsoft.com/dotnet/api/documentformat.openxml.office2013.word.commentex
abstract final class WordCommentIo {
  /// Canonicalize the fixed-width hexadecimal paragraph identifier.
  static String? normalizeParagraphId(String? value) {
    if (value == null || !RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value)) {
      return null;
    }
    return value.toUpperCase();
  }

  /// Preserve valid imported anchors, reserving them before allocating new ones.
  static Map<int, String> paragraphIds(List<WmlComment> comments) {
    final Set<String> reserved = <String>{
      for (final WmlComment comment in comments)
        if (normalizeParagraphId(comment.paragraphId) case final String id) id,
    };
    final Set<String> assigned = <String>{};
    final Map<int, String> result = <int, String>{};
    var next = 1;
    for (final WmlComment comment in comments) {
      if (result.containsKey(comment.id)) {
        throw FormatException('Duplicate comment ID: ${comment.id}');
      }
      String? id = normalizeParagraphId(comment.paragraphId);
      if (id == null || assigned.contains(id)) {
        do {
          id = next.toRadixString(16).toUpperCase().padLeft(8, '0');
          next++;
        } while (reserved.contains(id) || assigned.contains(id));
      }
      comment.paragraphId = id;
      assigned.add(id);
      result[comment.id] = id;
    }
    for (final WmlComment comment in comments) {
      if (comment.parentId != null && !result.containsKey(comment.parentId)) {
        throw FormatException(
          'Comment ${comment.id} has missing parent ${comment.parentId}',
        );
      }
    }
    return result;
  }

  /// Attach each anchor to the final serialized paragraph, including a final
  /// drawing paragraph. Keeping this local avoids changing body paragraph IDs.
  static String attachParagraphIds(String xml, Map<int, String> ids) {
    final XmlDocument document = XmlDocument.parse(xml);
    final XmlElement root = document.root!;
    root.setAttribute('w14', OfficeNamespaces.w14, prefix: 'xmlns');
    root.setAttribute('mc', OfficeNamespaces.mc, prefix: 'xmlns');
    root.setAttribute(
      'Ignorable',
      'w14',
      prefix: 'mc',
      namespaceUri: OfficeNamespaces.mc,
    );
    for (final XmlElement comment in root.childrenNamed(
      'comment',
      namespaceUri: OfficeNamespaces.w,
    )) {
      final int? id = int.tryParse(
        comment.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
      );
      final String? anchor = ids[id];
      if (anchor == null) {
        throw const FormatException(
          'Serialized comment has no paragraph anchor',
        );
      }
      XmlElement? last;
      void visit(XmlElement element) {
        if (element.localName == 'p' &&
            element.namespaceUri == OfficeNamespaces.w) {
          last = element;
        }
        for (final XmlElement child in element.childElements) {
          visit(child);
        }
      }

      visit(comment);
      if (last == null) {
        last = XmlElement(
          localName: 'p',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
        comment.addChild(last!);
      }
      last!.setAttribute(
        'paraId',
        anchor,
        prefix: 'w14',
        namespaceUri: OfficeNamespaces.w14,
      );
    }
    return document.toXmlString();
  }

  /// Read done/reply state independently of comment ordering and hex casing.
  static void readExtended(List<WmlComment> comments, XmlPullReader reader) {
    final Map<String, WmlComment> byParagraph = <String, WmlComment>{
      for (final WmlComment comment in comments)
        if (normalizeParagraphId(comment.paragraphId) case final String id)
          id: comment,
    };
    // Earlier Quds versions emitted numeric comment IDs here without w14
    // paragraph anchors. Recover those packages only when *no* native anchors
    // exist; genuine native paragraph IDs always take precedence.
    final bool legacy = byParagraph.isEmpty;
    WmlComment? lookup(String? value) {
      final String? id = normalizeParagraphId(value);
      if (id == null) return null;
      if (!legacy) return byParagraph[id];
      final int numeric = int.parse(id, radix: 16);
      for (final WmlComment comment in comments) {
        if (comment.id == numeric) return comment;
      }
      return null;
    }

    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.namespaceUri != OfficeNamespaces.w15 ||
          reader.localName != 'commentEx') {
        continue;
      }
      final WmlComment? comment = lookup(
        reader.getAttribute('paraId', namespaceUri: OfficeNamespaces.w15),
      );
      if (comment == null) continue;
      final String done =
          (reader.getAttribute('done', namespaceUri: OfficeNamespaces.w15) ??
                  '0')
              .toLowerCase();
      comment.resolved = const <String>{'1', 'true', 'on'}.contains(done);
      comment.parentId = lookup(
        reader.getAttribute('paraIdParent', namespaceUri: OfficeNamespaces.w15),
      )?.id;
    }
  }

  /// Keep the OPC MIME declaration synchronized even when clearing a part.
  static void writePart(
    OpcPackage package,
    String uri,
    String contentType,
    String xml, {
    bool create = true,
  }) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      if (create) package.createPart(uri, contentType).writeText(xml);
      return;
    }
    existing.contentType = contentType;
    package.contentTypes.setOverride(uri, contentType);
    existing.writeText(xml);
  }
}
