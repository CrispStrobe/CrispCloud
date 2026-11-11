import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';

/// Presents the selected branch of `mc:AlternateContent` as ordinary Word XML.
///
/// A Choice is eligible only when every namespace named by Requires is handled
/// by this importer. Selection is first-match; otherwise the Fallback is used.
/// The wrappers themselves are hidden so body, paragraph, drawing and note
/// readers all see the same stream, including nested alternatives.
final class WordMarkupCompatibilityReader extends XmlPullReader {
  WordMarkupCompatibilityReader(super.source);

  static const Set<String> _supported = <String>{
    OfficeNamespaces.w,
    OfficeNamespaces.m,
    OfficeNamespaces.a,
    OfficeNamespaces.wp,
    OfficeNamespaces.wps,
    OfficeNamespaces.pic,
    OfficeNamespaces.c,
  };

  final List<_AlternateContent> _alternatives = <_AlternateContent>[];

  @override
  bool next() {
    while (super.next()) {
      if (eventType == XmlEventType.startElement) {
        if (namespaceUri == OfficeNamespaces.mc &&
            localName == 'AlternateContent') {
          _alternatives.add(_AlternateContent(depth));
          continue;
        }
        if (_alternatives.isNotEmpty) {
          final _AlternateContent alternative = _alternatives.last;
          if (depth == alternative.depth + 1 &&
              namespaceUri == OfficeNamespaces.mc &&
              (localName == 'Choice' || localName == 'Fallback')) {
            if (alternative.selected ||
                localName == 'Choice' && !_supportsRequirements()) {
              _skipBranch();
            } else {
              alternative.selected = true;
              alternative.branchDepth = depth;
            }
            continue;
          }
        }
      } else if (eventType == XmlEventType.endElement &&
          _alternatives.isNotEmpty) {
        final _AlternateContent alternative = _alternatives.last;
        if (depth == alternative.depth - 1) {
          _alternatives.removeLast();
          continue;
        }
        if (alternative.branchDepth != null &&
            depth == alternative.branchDepth! - 1) {
          alternative.branchDepth = null;
          continue;
        }
      }
      return true;
    }
    return false;
  }

  bool _supportsRequirements() {
    final String requires = (getAttribute('Requires') ?? '').trim();
    return requires.isNotEmpty &&
        requires
            .split(RegExp(r'\s+'))
            .every(
              (String prefix) => _supported.contains(lookupNamespace(prefix)),
            );
  }

  void _skipBranch() {
    final int branchDepth = depth;
    while (super.next()) {
      if (eventType == XmlEventType.endElement && depth < branchDepth) return;
    }
  }
}

final class _AlternateContent {
  _AlternateContent(this.depth);

  final int depth;
  bool selected = false;
  int? branchDepth;
}
