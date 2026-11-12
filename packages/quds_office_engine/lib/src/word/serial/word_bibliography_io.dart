import 'dart:convert';

import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../model/wml_document.dart';

/// Native bibliography source ownership and conservative scalar updates.
///
/// Word's current source list is a bibliography XML part owned by the main
/// document through an internal customXml relationship. Arbitrary custom XML
/// parts, and unmodeled metadata inside native sources, remain untouched.
abstract final class WordBibliographyIo {
  static const _namespace = OfficeNamespaces.bibliography;

  static void read(
    WmlDocument document,
    OpcPackage package,
    String mainPartUri,
  ) {
    final found = _find(package, mainPartUri);
    if (found == null) return;
    for (final source in found.root.childrenNamed(
      'Source',
      namespaceUri: _namespace,
    )) {
      final values = _values(source);
      if (values['tag']!.isEmpty) continue;
      document.citations.add(
        WmlCitation(
          tag: values['tag']!,
          author: values['author']!,
          title: values['title']!,
          year: values['year']!,
          pages: values['pages']!,
          sourceXml: _standalone(source, found.root),
          importedValues: values,
        ),
      );
    }
  }

  static void write(
    WmlDocument document,
    OpcPackage package,
    String mainPartUri,
  ) {
    final found = _find(package, mainPartUri);
    if (found == null && document.citations.isEmpty) return;
    final root =
        found?.root ??
        (XmlElement(localName: 'Sources', prefix: 'b', namespaceUri: _namespace)
          ..setAttribute('b', _namespace, prefix: 'xmlns'));
    final originals = <String, XmlElement>{
      for (final source in root.childrenNamed(
        'Source',
        namespaceUri: _namespace,
      ))
        _text(source, 'Tag'): source,
    };
    final sources = <XmlElement>[
      for (final citation in document.citations)
        _writeSource(citation, originals[citation.tag], root),
    ];
    // Keep unknown nodes and unmodeled sources without a tag in their original
    // order. Tagged sources correspond to the editable collection, including
    // deliberate removals; an empty collection must not resurrect them.
    final children = <XmlNode>[];
    var inserted = false;
    for (final child in root.children) {
      if (child is XmlElement &&
          child.localName == 'Source' &&
          child.namespaceUri == _namespace &&
          _text(child, 'Tag').isNotEmpty) {
        if (!inserted) {
          children.addAll(sources);
          inserted = true;
        }
      } else {
        children.add(child);
      }
    }
    if (!inserted) children.addAll(sources);
    root.children.clear();
    for (final child in children) {
      root.addChild(child);
    }
    final uri = found?.part.uri ?? _allocateUri(package);
    final xml = XmlDocument(root: root).toXmlString();
    final part = package.getPart(uri);
    if (part == null) {
      package.createPart(uri, 'application/xml', utf8.encode(xml));
    } else {
      part
        ..contentType = 'application/xml'
        ..writeText(xml);
      package.contentTypes.setOverride(uri, 'application/xml');
    }
    final relationships = package.relationshipsFor(mainPartUri);
    if (!relationships.items.any(
      (rel) =>
          rel.type == RelationshipTypes.customXml &&
          rel.targetMode == RelationshipTargetMode.internal &&
          relationships.resolve(rel) == uri,
    )) {
      relationships.add(
        type: RelationshipTypes.customXml,
        target: OpcUris.relativize(mainPartUri, uri),
      );
    }
  }

  static ({PackagePart part, XmlElement root})? _find(
    OpcPackage package,
    String mainPartUri,
  ) {
    final relationships = package.relationshipsFor(mainPartUri);
    final candidates = <String>[
      for (final rel in relationships.items)
        if (rel.type == RelationshipTypes.customXml &&
            rel.targetMode == RelationshipTargetMode.internal)
          relationships.resolve(rel),
      // Compatibility with older suite files that wrote these unowned parts.
      // A filename alone never establishes that arbitrary XML is bibliography.
      '/customXml/sources.xml',
      '/customXml/item1.xml',
    ];
    for (final uri in candidates.toSet()) {
      final part = package.getPart(uri);
      if (part == null) continue;
      final root = _parse(part.readText());
      if (root?.localName == 'Sources' && root?.namespaceUri == _namespace) {
        return (part: part, root: root!);
      }
    }
    return null;
  }

  static XmlElement? _parse(String xml) {
    try {
      return XmlDocument.parse(xml).root;
    } on XmlParseException {
      return null;
    }
  }

  static String _allocateUri(OpcPackage package) {
    var index = 1;
    while (true) {
      final uri = '/customXml/bibliography${index == 1 ? '' : index}.xml';
      if (package.getPart(uri) == null) return uri;
      index++;
    }
  }

  static String _standalone(XmlElement source, XmlElement root) {
    final copy = source.copy();
    for (final attribute in root.attributes) {
      if ((attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') &&
          !copy.attributes.any(
            (own) => own.qualifiedName == attribute.qualifiedName,
          )) {
        copy.attributes.add(attribute.copy());
      }
    }
    return XmlDocument(root: copy).toXmlString(declaration: false);
  }

  static XmlElement _writeSource(
    WmlCitation citation,
    XmlElement? original,
    XmlElement root,
  ) {
    XmlElement? source = citation.sourceXml == null
        ? null
        : _parse(citation.sourceXml!);
    if (source?.localName != 'Source' || source?.namespaceUri != _namespace) {
      source = original == null ? null : _parse(_standalone(original, root));
    }
    final baseline =
        citation.importedValues ?? (source == null ? null : _values(source));
    source ??= XmlElement(
      localName: 'Source',
      prefix: root.prefix,
      namespaceUri: _namespace,
    );
    final values = <String, String>{
      'Tag': citation.tag,
      'Title': citation.title,
      'Year': citation.year,
      'Pages': citation.pages,
    };
    for (final entry in values.entries) {
      if (baseline == null ||
          baseline[entry.key.toLowerCase()] != entry.value) {
        _setText(source, entry.key, entry.value);
      }
    }
    if (source.firstChild('SourceType', namespaceUri: _namespace) == null) {
      _setText(source, 'SourceType', 'Misc');
    }
    final author = source.firstChild('Author', namespaceUri: _namespace);
    final legacyScalar =
        author != null &&
        author.childElements.isEmpty &&
        author.text.isNotEmpty;
    if (baseline == null ||
        baseline['author'] != citation.author ||
        legacyScalar) {
      _setAuthor(source, citation.author);
    }
    return source;
  }

  static XmlElement _element(XmlElement parent, String name) => XmlElement(
    localName: name,
    prefix: parent.prefix,
    namespaceUri: _namespace,
  );

  static void _setText(XmlElement source, String name, String value) {
    final existing = source.firstChild(name, namespaceUri: _namespace);
    if (value.isEmpty) {
      if (existing != null) source.children.remove(existing);
      return;
    }
    final element = existing ?? _element(source, name);
    element.children.clear();
    element.addText(value);
    if (existing == null) source.addChild(element);
  }

  static void _setAuthor(XmlElement source, String value) {
    var container = source.firstChild('Author', namespaceUri: _namespace);
    if (container == null) {
      if (value.isEmpty) return;
      container = _element(source, 'Author');
      source.addChild(container);
    }
    container.children.removeWhere(
      (node) =>
          node is XmlText ||
          node is XmlCdata ||
          (node is XmlElement &&
              node.localName == 'Author' &&
              node.namespaceUri == _namespace),
    );
    if (value.isEmpty) {
      if (container.children.isEmpty) source.children.remove(container);
      return;
    }
    // The compact model has one free-text author. Keep it literal instead of
    // guessing personal-name components; imported NameList trees stay intact
    // until that scalar author is deliberately edited.
    final author = _element(container, 'Author');
    author.addChild(_element(author, 'Corporate')..addText(value));
    container.addChild(author);
  }

  static String _text(XmlElement parent, String name) =>
      parent.firstChild(name, namespaceUri: _namespace)?.text ?? '';

  static Map<String, String> _values(XmlElement source) => <String, String>{
    'tag': _text(source, 'Tag'),
    'author': _author(source),
    'title': _text(source, 'Title'),
    'year': _text(source, 'Year'),
    'pages': _text(source, 'Pages'),
  };

  static String _author(XmlElement source) {
    final container = source.firstChild('Author', namespaceUri: _namespace);
    if (container == null) return '';
    final author = container.firstChild('Author', namespaceUri: _namespace);
    if (author == null) {
      return container.childElements.isEmpty ? container.text : '';
    }
    final corporate = author.firstChild('Corporate', namespaceUri: _namespace);
    if (corporate != null) return corporate.text;
    final list = author.firstChild('NameList', namespaceUri: _namespace);
    if (list == null) return '';
    return <String>[
      for (final person in list.childrenNamed(
        'Person',
        namespaceUri: _namespace,
      ))
        <String>[
          _text(person, 'First'),
          _text(person, 'Middle'),
          _text(person, 'Last'),
        ].where((part) => part.isNotEmpty).join(' '),
    ].where((person) => person.isNotEmpty).join('; ');
  }
}
