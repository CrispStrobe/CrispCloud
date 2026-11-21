import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../model/wml_document.dart';
import '../properties/wml_properties.dart';

/// Allocates distinct revision IDs when a section's source history is cloned.
///
/// Reserving all source IDs first keeps a clone from taking an ID that belongs
/// to a later section. A new allocator per save makes repeated exports stable
/// without mutating the immutable source fragments used by undo/redo.
final class WordSectionRevisionIds {
  WordSectionRevisionIds(Iterable<WmlSection> sections) {
    for (final WmlSection section in sections) {
      final WmlSectionSource? source = section.sourceProperties;
      if (source == null) continue;
      final XmlElement root = XmlDocument.parse(source.xml).root!;
      for (final XmlElement change in _changes(root)) {
        final int? id = int.tryParse(
          change.getAttribute('id', namespaceUri: OfficeNamespaces.w) ?? '',
        );
        if (id != null) _reserved.add(id);
      }
    }
  }

  final Set<int> _reserved = <int>{};
  final Set<int> _used = <int>{};
  int _next = 1;

  void ensureUnique(XmlElement section) {
    for (final XmlElement change in _changes(section)) {
      final XmlAttribute? attribute = change.attributes
          .where(
            (XmlAttribute a) =>
                a.localName == 'id' && a.namespaceUri == OfficeNamespaces.w,
          )
          .firstOrNull;
      final int? id = int.tryParse(attribute?.value ?? '');
      if (id != null && _used.add(id)) continue;
      while (_reserved.contains(_next) || _used.contains(_next)) {
        _next++;
      }
      final int replacement = _next++;
      _used.add(replacement);
      if (attribute != null) {
        attribute.value = '$replacement';
      } else {
        final String prefix = change.prefix.isEmpty ? 'w' : change.prefix;
        WordSectionIo.setNamespaceDeclaration(
          change,
          prefix,
          OfficeNamespaces.w,
        );
        change.setAttribute(
          'id',
          '$replacement',
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
      }
    }
  }

  static Iterable<XmlElement> _changes(XmlElement node) sync* {
    if (node.namespaceUri == OfficeNamespaces.w &&
        node.localName == 'sectPrChange') {
      yield node;
    }
    for (final XmlElement child in node.childElements) {
      yield* _changes(child);
    }
  }
}

/// Merges deliberate section edits into an imported section-property fragment.
abstract final class WordSectionIo {
  /// Updates a declaration without taking an ordinary same-name attribute.
  ///
  /// Parsed declarations have an empty namespace URI in the lightweight XML
  /// model. Match their qualified names so repeated source edits neither add
  /// duplicate declarations nor overwrite attributes such as `w:w`.
  static void setNamespaceDeclaration(
    XmlElement element,
    String prefix,
    String uri,
  ) {
    final qualifiedName = prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix';
    final existing = element.attributes
        .where((attribute) => attribute.qualifiedName == qualifiedName)
        .firstOrNull;
    if (existing != null) {
      existing.value = uri;
      return;
    }
    element.attributes.add(
      XmlAttribute(
        localName: prefix.isEmpty ? 'xmlns' : prefix,
        prefix: prefix.isEmpty ? '' : 'xmlns',
        namespaceUri: 'http://www.w3.org/2000/xmlns/',
        value: uri,
      ),
    );
  }

  static Map<String, String> values(WmlSection section) => <String, String>{
    'type': section.breakKind.name,
    'pgSz':
        '${pointsToTwips(section.pageSize.width)}|'
        '${pointsToTwips(section.pageSize.height)}',
    'pgMar':
        '${pointsToTwips(section.margins.top)}|'
        '${pointsToTwips(section.margins.bottom)}|'
        '${pointsToTwips(section.margins.left)}|'
        '${pointsToTwips(section.margins.right)}|'
        '${pointsToTwips(section.margins.header)}|'
        '${pointsToTwips(section.margins.footer)}',
    'cols':
        '${section.resolvedColumnCount}|'
        '${pointsToTwips(section.columnSpace)}|${section.columnSep}',
    'lnNumType': '${section.lineNumbers}',
    'titlePg': '${section.differentFirstPage}',
  };

  static XmlElement preserve(XmlElement generated, WmlSection section) {
    final WmlSectionSource? source = section.sourceProperties;
    if (source == null) return generated;
    final XmlElement result = XmlDocument.parse(source.xml).root!;
    final Map<String, String> current = values(section);
    for (final String key in current.keys) {
      if (source.values[key] == current[key]) continue;
      final XmlElement? replacement = generated.firstChild(key);
      final XmlElement? original = result.firstChild(
        key,
        namespaceUri: OfficeNamespaces.w,
      );
      if (replacement == null) {
        result.children.remove(original);
      } else if (original == null) {
        result.addChild(_selfContained(replacement));
      } else {
        _mergeModeledAttributes(original, replacement, key);
      }
    }
    // A saved story can receive a new relationship ID. The references must
    // always come from the current package, even when page settings are intact.
    for (final String key in <String>['headerReference', 'footerReference']) {
      result.children.removeWhere(
        (XmlNode node) =>
            node is XmlElement &&
            node.namespaceUri == OfficeNamespaces.w &&
            node.localName == key,
      );
      for (final XmlElement child in generated.childrenNamed(key)) {
        result.addChild(_selfContained(child));
      }
    }
    final List<XmlNode> ordered = List<XmlNode>.of(result.children);
    final Map<XmlNode, int> originalOrder = <XmlNode, int>{
      for (int i = 0; i < ordered.length; i++) ordered[i]: i,
    };
    ordered.sort((XmlNode a, XmlNode b) {
      final int comparison = _rank(a).compareTo(_rank(b));
      return comparison == 0
          ? originalOrder[a]!.compareTo(originalOrder[b]!)
          : comparison;
    });
    result.children
      ..clear()
      ..addAll(ordered);
    return result;
  }

  static XmlElement _selfContained(XmlElement element) {
    final result = element.copy();
    setNamespaceDeclaration(result, 'w', OfficeNamespaces.w);
    setNamespaceDeclaration(result, 'r', OfficeNamespaces.r);
    return result;
  }

  static void _mergeModeledAttributes(
    XmlElement original,
    XmlElement replacement,
    String key,
  ) {
    final Set<String> attributes = switch (key) {
      'pgSz' => <String>{'w', 'h', 'orient'},
      'pgMar' => <String>{'top', 'bottom', 'left', 'right', 'header', 'footer'},
      'cols' => <String>{'num', 'space', 'sep'},
      'lnNumType' => <String>{'countBy'},
      _ => <String>{'val'},
    };
    // Keep a source Word namespace alias instead of shadowing a prefix that
    // an imported extension attribute may already use on this element.
    String prefix = original.prefix;
    if (prefix.isEmpty) {
      prefix =
          original.attributes
              .where((XmlAttribute a) => a.namespaceUri == OfficeNamespaces.w)
              .map((XmlAttribute a) => a.prefix)
              .where((String p) => p.isNotEmpty)
              .firstOrNull ??
          '';
      if (prefix.isEmpty) {
        // A default-namespace native group may already use w for an extension.
        // Reserve a fresh prefix across the subtree before adding declarations,
        // so untouched extension attributes and children keep their identity.
        final used = <String>{};
        void collect(XmlElement node) {
          used.add(node.prefix);
          for (final attribute in node.attributes) {
            used.add(attribute.prefix);
            if (attribute.prefix == 'xmlns') used.add(attribute.localName);
          }
          for (final child in node.childElements) {
            collect(child);
          }
        }

        collect(original);
        var index = 0;
        do {
          prefix = 'qudsWord${index++}';
        } while (used.contains(prefix));
      }
    }
    setNamespaceDeclaration(original, prefix, OfficeNamespaces.w);
    for (final String attribute in attributes) {
      original.removeAttribute(attribute, namespaceUri: OfficeNamespaces.w);
      final String? value = replacement.getAttribute(attribute);
      if (value != null) {
        original.setAttribute(
          attribute,
          value,
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
      }
    }
    if (key == 'cols') {
      // Editing the model's uniform columns replaces imported custom widths;
      // untouched custom columns remain byte-for-value in the source fragment.
      original.children.removeWhere(
        (XmlNode node) =>
            node is XmlElement &&
            node.namespaceUri == OfficeNamespaces.w &&
            node.localName == 'col',
      );
      if (original.getAttribute('equalWidth') != null) {
        original.setAttribute(
          'equalWidth',
          '1',
          prefix: prefix,
          namespaceUri: OfficeNamespaces.w,
        );
      }
    }
  }

  static int _rank(XmlNode node) {
    if (node is! XmlElement || node.namespaceUri != OfficeNamespaces.w) {
      return _order.length;
    }
    final int index = _order.indexOf(node.localName);
    return index < 0 ? _order.length : index;
  }

  static const List<String> _order = <String>[
    'headerReference',
    'footerReference',
    'footnotePr',
    'endnotePr',
    'type',
    'pgSz',
    'pgMar',
    'paperSrc',
    'pgBorders',
    'lnNumType',
    'pgNumType',
    'cols',
    'formProt',
    'vAlign',
    'noEndnote',
    'titlePg',
    'textDirection',
    'bidi',
    'rtlGutter',
    'docGrid',
    'printerSettings',
    'sectPrChange',
  ];
}
