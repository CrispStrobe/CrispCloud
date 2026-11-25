import 'namespaces.dart';
import 'xml_reader.dart';
import 'xml_writer.dart';

/// Lightweight mutable XML node.
sealed class XmlNode {
  /// XmlNode API.
  XmlNode({this.parent});

  /// parent API.
  XmlElement? parent;

  /// copy API.
  XmlNode copy();

  /// writeTo API.
  void writeTo(XmlWriter writer);
}

/// Attribute on an [XmlElement].
class XmlAttribute {
  /// XmlAttribute API.
  XmlAttribute({
    required this.localName,
    required this.value,
    this.prefix = '',
    this.namespaceUri = '',
  });

  /// localName API.
  String localName;

  /// value API.
  String value;

  /// prefix API.
  String prefix;

  /// namespaceUri API.
  String namespaceUri;

  /// qualifiedName API.
  String get qualifiedName => prefix.isEmpty ? localName : '$prefix:$localName';

  /// copy API.
  XmlAttribute copy() => XmlAttribute(
    localName: localName,
    value: value,
    prefix: prefix,
    namespaceUri: namespaceUri,
  );
}

/// Element node with attributes and ordered children.
class XmlElement extends XmlNode {
  /// XmlElement API.
  XmlElement({
    required this.localName,
    this.prefix = '',
    this.namespaceUri = '',
    List<XmlAttribute>? attributes,
    List<XmlNode>? children,
    super.parent,
  }) : attributes = attributes ?? <XmlAttribute>[],
       children = children ?? <XmlNode>[];

  /// localName API.
  String localName;

  /// prefix API.
  String prefix;

  /// namespaceUri API.
  String namespaceUri;

  /// attributes API.
  final List<XmlAttribute> attributes;

  /// children API.
  final List<XmlNode> children;

  /// qualifiedName API.
  String get qualifiedName => prefix.isEmpty ? localName : '$prefix:$localName';

  /// getAttribute API.
  String? getAttribute(String localName, {String? namespaceUri}) {
    for (final XmlAttribute attr in attributes) {
      if (attr.localName != localName) {
        continue;
      }
      if (namespaceUri == null || attr.namespaceUri == namespaceUri) {
        return attr.value;
      }
    }
    return null;
  }

  /// setAttribute API.
  void setAttribute(
    String localName,
    String value, {
    String prefix = '',
    String namespaceUri = '',
  }) {
    for (final XmlAttribute attr in attributes) {
      if (attr.localName == localName &&
          (namespaceUri.isEmpty || attr.namespaceUri == namespaceUri)) {
        attr.value = value;
        if (prefix.isNotEmpty) {
          attr.prefix = prefix;
        }
        if (namespaceUri.isNotEmpty) {
          attr.namespaceUri = namespaceUri;
        }
        return;
      }
    }
    attributes.add(
      XmlAttribute(
        localName: localName,
        value: value,
        prefix: prefix,
        namespaceUri: namespaceUri,
      ),
    );
  }

  /// removeAttribute API.
  void removeAttribute(String localName, {String? namespaceUri}) {
    attributes.removeWhere((XmlAttribute attr) {
      if (attr.localName != localName) {
        return false;
      }
      return namespaceUri == null || attr.namespaceUri == namespaceUri;
    });
  }

  /// addChild API.
  void addChild(XmlNode node) {
    node.parent = this;
    children.add(node);
  }

  /// addText API.
  void addText(String text) {
    if (text.isEmpty) {
      return;
    }
    addChild(XmlText(text));
  }

  /// childElements API.
  Iterable<XmlElement> get childElements sync* {
    for (final XmlNode child in children) {
      if (child is XmlElement) {
        yield child;
      }
    }
  }

  /// firstChild API.
  XmlElement? firstChild(String localName, {String? namespaceUri}) {
    for (final XmlElement child in childElements) {
      if (child.localName != localName) {
        continue;
      }
      if (namespaceUri == null || child.namespaceUri == namespaceUri) {
        return child;
      }
    }
    return null;
  }

  /// childrenNamed API.
  List<XmlElement> childrenNamed(String localName, {String? namespaceUri}) {
    return childElements
        .where((XmlElement e) {
          if (e.localName != localName) {
            return false;
          }
          return namespaceUri == null || e.namespaceUri == namespaceUri;
        })
        .toList(growable: false);
  }

  /// text API.
  String get text {
    final StringBuffer buffer = StringBuffer();
    _collectText(this, buffer);
    return buffer.toString();
  }

  /// text API.
  set text(String value) {
    children
      ..clear()
      ..add(XmlText(value)..parent = this);
  }

  @override
  /// copy API.
  XmlElement copy() {
    final XmlElement clone = XmlElement(
      localName: localName,
      prefix: prefix,
      namespaceUri: namespaceUri,
      attributes: attributes
          .map((XmlAttribute a) => a.copy())
          .toList(growable: true),
    );
    for (final XmlNode child in children) {
      clone.addChild(child.copy());
    }
    return clone;
  }

  @override
  /// writeTo API.
  void writeTo(XmlWriter writer) {
    writer.writeStartElement(localName, prefix: prefix.isEmpty ? null : prefix);
    for (final XmlAttribute attr in attributes) {
      writer.writeAttribute(attr.qualifiedName, attr.value);
    }
    if (children.isEmpty) {
      writer.writeEndElement();
      return;
    }
    for (final XmlNode child in children) {
      child.writeTo(writer);
    }
    writer.writeEndElement();
  }

  static void _collectText(XmlNode node, StringBuffer buffer) {
    switch (node) {
      case XmlText(:final String text):
        buffer.write(text);
      case XmlCdata(:final String text):
        buffer.write(text);
      case XmlElement(:final List<XmlNode> children):
        for (final XmlNode child in children) {
          _collectText(child, buffer);
        }
      case XmlComment():
        break;
    }
  }
}

/// Character data node.
class XmlText extends XmlNode {
  /// XmlText API.
  XmlText(this.text, {super.parent});

  /// text API.
  String text;

  @override
  /// copy API.
  XmlText copy() => XmlText(text);

  @override
  /// writeTo API.
  void writeTo(XmlWriter writer) => writer.writeText(text);
}

/// CDATA node.
class XmlCdata extends XmlNode {
  /// XmlCdata API.
  XmlCdata(this.text, {super.parent});

  /// text API.
  String text;

  @override
  /// copy API.
  XmlCdata copy() => XmlCdata(text);

  @override
  /// writeTo API.
  void writeTo(XmlWriter writer) => writer.writeCdata(text);
}

/// Comment node.
class XmlComment extends XmlNode {
  /// XmlComment API.
  XmlComment(this.text, {super.parent});

  /// text API.
  String text;

  @override
  /// copy API.
  XmlComment copy() => XmlComment(text);

  @override
  /// writeTo API.
  void writeTo(XmlWriter writer) => writer.writeComment(text);
}

/// Document wrapper holding an optional XML declaration and a root element.
class XmlDocument {
  /// XmlDocument API.
  XmlDocument({this.root, this.standalone = true});

  /// root API.
  XmlElement? root;

  /// standalone API.
  bool standalone;

  /// Parses XML into a tree. [keepRootChild] can reject direct children of the
  /// root before they are materialized. Rejected subtrees are still validated.
  factory XmlDocument.parse(
    String xml, {
    bool Function(XmlElement root, XmlPullReader child)? keepRootChild,
  }) {
    final XmlPullReader reader = XmlPullReader(xml);
    final XmlDocument doc = XmlDocument();
    final List<XmlElement> stack = <XmlElement>[];
    while (reader.next()) {
      switch (reader.eventType) {
        case XmlEventType.xmlDeclaration:
          if (reader.text.contains('standalone="no"')) {
            doc.standalone = false;
          }
        case XmlEventType.startElement:
          if (keepRootChild != null &&
              stack.length == 1 &&
              !keepRootChild(stack.single, reader)) {
            reader.skip(validateTextEntities: true);
            break;
          }
          final XmlElement element = XmlElement(
            localName: reader.localName,
            prefix: reader.prefix,
            namespaceUri: reader.namespaceUri,
          );
          for (int i = 0; i < reader.attributeCount; i++) {
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
            doc.root = element;
          } else {
            stack.last.addChild(element);
          }
          stack.add(element);
        case XmlEventType.endElement:
          if (stack.isNotEmpty) {
            stack.removeLast();
          }
        case XmlEventType.characters:
          if (stack.isEmpty) {
            break;
          }
          if (reader.isWhitespace &&
              stack.last.children.isEmpty &&
              !_preservesSpace(stack)) {
            break;
          }
          stack.last.addText(reader.text);
        case XmlEventType.cdata:
          if (stack.isNotEmpty) {
            stack.last.addChild(XmlCdata(reader.text));
          }
        case XmlEventType.comment:
          if (stack.isNotEmpty) {
            stack.last.addChild(XmlComment(reader.text));
          }
        case XmlEventType.endDocument:
        case XmlEventType.none:
        case XmlEventType.processingInstruction:
        case XmlEventType.dtd:
          break;
      }
    }
    return doc;
  }

  static bool _preservesSpace(List<XmlElement> stack) {
    for (final XmlElement element in stack.reversed) {
      for (final XmlAttribute attribute in element.attributes) {
        if (attribute.namespaceUri != OfficeNamespaces.xml ||
            attribute.localName != 'space') {
          continue;
        }
        if (attribute.value == 'preserve') {
          return true;
        }
        if (attribute.value == 'default') {
          return false;
        }
      }
    }
    return false;
  }

  /// Consume the element at the reader's current start event, retaining namespaces.
  static XmlElement readElement(XmlPullReader reader) {
    if (reader.eventType != XmlEventType.startElement) {
      throw StateError('Expected an XML start element');
    }
    final List<XmlElement> stack = [];
    final List<Map<String, String>> namespaceScopes = [];
    XmlElement? root;
    do {
      switch (reader.eventType) {
        case XmlEventType.startElement:
          final node = XmlElement(
            localName: reader.localName,
            prefix: reader.prefix,
            namespaceUri: reader.namespaceUri,
          );
          for (int i = 0; i < reader.attributeCount; i++) {
            node.attributes.add(
              XmlAttribute(
                localName: reader.attributeLocalName(i),
                value: reader.attributeValue(i),
                prefix: reader.attributePrefix(i),
                namespaceUri: reader.attributeNamespace(i),
              ),
            );
          }
          // Materialize only bindings missing from the captured parent scope.
          // Projected readers can hide wrappers carrying local declarations
          // (for example mc:Choice), so retain the actual scope at each visible
          // node, including prefixes used only in QName-valued attributes.
          final namespaces = reader.inScopeNamespaces;
          final parentNamespaces = namespaceScopes.isEmpty
              ? const <String, String>{}
              : namespaceScopes.last;
          if (!identical(namespaces, parentNamespaces)) {
            final declared = <String>{
              for (final attribute in node.attributes)
                if (attribute.prefix == 'xmlns')
                  attribute.localName
                else if (attribute.prefix.isEmpty &&
                    attribute.localName == 'xmlns')
                  '',
            };
            for (final ns in namespaces.entries) {
              if (parentNamespaces[ns.key] == ns.value ||
                  declared.contains(ns.key)) {
                continue;
              }
              node.attributes.add(
                XmlAttribute(
                  localName: ns.key.isEmpty ? 'xmlns' : ns.key,
                  prefix: ns.key.isEmpty ? '' : 'xmlns',
                  value: ns.value,
                ),
              );
            }
          }
          if (stack.isEmpty) {
            root = node;
          } else {
            stack.last.addChild(node);
          }
          stack.add(node);
          namespaceScopes.add(namespaces);
        case XmlEventType.endElement:
          stack.removeLast();
          namespaceScopes.removeLast();
          if (stack.isEmpty) {
            return root!;
          }
        case XmlEventType.characters:
          if (stack.isNotEmpty) stack.last.addText(reader.text);
        case XmlEventType.cdata:
          if (stack.isNotEmpty) stack.last.addChild(XmlCdata(reader.text));
        case XmlEventType.comment:
          if (stack.isNotEmpty) stack.last.addChild(XmlComment(reader.text));
        default:
          break;
      }
    } while (reader.next());
    throw StateError('Unterminated XML element');
  }

  /// toXmlString API.
  String toXmlString({bool declaration = true}) {
    final XmlWriter writer = XmlWriter();
    if (declaration) {
      writer.writeStartDocument(standalone: standalone);
    }
    root?.writeTo(writer);
    return writer.toXml();
  }
}
