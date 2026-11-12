import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_content_controls.dart';
import '../model/word_notes.dart';

/// Native SDT wrappers around editable blocks/runs, with export preflight.
abstract final class WordContentControlIo {
  /// Derived section slices must not cut an otherwise valid block wrapper.
  static void validateBlockSequence(List<WmlBlock> blocks, String context) =>
      _blocks(blocks, <String>{}, context);

  static ({WmlSdtInfo control, String? contentXml}) read(XmlPullReader reader) {
    final XmlElement source = XmlDocument.readElement(reader);
    final List<XmlElement> contents = source.childrenNamed(
      'sdtContent',
      namespaceUri: OfficeNamespaces.w,
    );
    if (contents.length > 1) {
      throw const FormatException(
        'Content control has multiple sdtContent slots',
      );
    }
    final XmlElement? content = contents.firstOrNull;
    final XmlElement? properties = source.firstChild(
      'sdtPr',
      namespaceUri: OfficeNamespaces.w,
    );
    String? property(String name) => properties
        ?.firstChild(name, namespaceUri: OfficeNamespaces.w)
        ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
    String? contentXml;
    if (content != null) {
      final XmlElement independent = content.copy();
      for (final XmlAttribute attribute in source.attributes) {
        if (attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns') {
          if (!independent.attributes.any(
            (XmlAttribute a) => a.qualifiedName == attribute.qualifiedName,
          )) {
            independent.attributes.add(attribute.copy());
          }
        }
      }
      contentXml = XmlDocument(
        root: independent,
      ).toXmlString(declaration: false);
      content.children.clear();
    }
    final WmlSdtInfo control = WmlSdtInfo(
      templateXml: XmlDocument(root: source).toXmlString(declaration: false),
      hasContent: content != null,
      id: property('id'),
      tag: property('tag'),
    );
    _template(control);
    return (control: control, contentXml: contentXml);
  }

  static XmlElement _template(WmlSdtInfo control) {
    final XmlElement? root = XmlDocument.parse(control.templateXml).root;
    if (root == null ||
        root.localName != 'sdt' ||
        root.namespaceUri != OfficeNamespaces.w) {
      throw const FormatException('Invalid content-control template');
    }
    bool sawContent = false;
    final Set<String> seen = <String>{};
    for (final XmlElement child in root.childElements) {
      if (child.namespaceUri != OfficeNamespaces.w ||
          !const <String>{
            'sdtPr',
            'sdtEndPr',
            'sdtContent',
          }.contains(child.localName) ||
          !seen.add(child.localName) ||
          sawContent) {
        throw const FormatException(
          'Unsupported content-control property structure',
        );
      }
      if (child.localName == 'sdtContent') {
        sawContent = true;
        if (child.childElements.isNotEmpty || child.text.trim().isNotEmpty) {
          throw const FormatException(
            'Content-control template contains hidden content',
          );
        }
        for (final XmlAttribute attribute in child.attributes) {
          if (attribute.prefix == 'w' &&
              attribute.namespaceUri != OfficeNamespaces.w) {
            throw UnsupportedError(
              'A content-slot attribute shadows the generated Word prefix',
            );
          }
        }
      }
    }
    if (sawContent != control.hasContent) {
      throw const FormatException(
        'Content-control content slot disagrees with metadata',
      );
    }
    return root;
  }

  static void writeBoundary(
    XmlWriter writer,
    WmlSdtInfo control,
    bool isStart,
  ) {
    if (!isStart) {
      if (control.hasContent) writer.writeEndElement();
      writer.writeEndElement();
      return;
    }
    final XmlElement root = _template(control);
    writer.writeStartElement(root.localName, prefix: root.prefix);
    for (final XmlAttribute attribute in root.attributes) {
      writer.writeAttribute(attribute.qualifiedName, attribute.value);
    }
    for (final XmlNode child in root.children) {
      if (child is XmlElement &&
          child.localName == 'sdtContent' &&
          child.namespaceUri == OfficeNamespaces.w) {
        // Generated child paragraphs/runs use w even when the source used an
        // alias. Bind it locally without changing source metadata namespaces.
        writer.writeStartElement(
          'sdtContent',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
        for (final XmlAttribute attribute in child.attributes) {
          if (attribute.qualifiedName == 'xmlns:w') continue;
          if (attribute.prefix == 'w' &&
              attribute.namespaceUri != OfficeNamespaces.w) {
            throw UnsupportedError(
              'A content-slot attribute shadows the generated Word prefix',
            );
          }
          writer.writeAttribute(attribute.qualifiedName, attribute.value);
        }
      } else {
        child.writeTo(writer);
      }
    }
  }

  /// Validate before the serializer writes relationships or mutates any part.
  static void validate(WmlDocument document) {
    final Set<String> bodyIds = <String>{};
    for (final WmlSection section in document.sections) {
      _blocks(section.blocks, bodyIds, 'document section');
      for (final List<WmlParagraph> story in <List<WmlParagraph>>[
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        final Set<String> ids = <String>{};
        for (final WmlParagraph paragraph in story) {
          _inlines(paragraph, ids);
        }
      }
    }
    for (final List<WmlNote> story in <List<WmlNote>>[
      document.footnotes,
      document.endnotes,
    ]) {
      final Set<String> ids = <String>{};
      for (final WmlNote note in story) {
        _blocks(note.blocks, ids, 'note');
      }
    }
    final Set<String> commentIds = <String>{};
    for (final WmlComment comment in document.comments) {
      for (final WmlParagraph paragraph in comment.paragraphs) {
        _inlines(paragraph, commentIds);
      }
    }
  }

  static void _marker(
    WmlSdtInfo control,
    bool start,
    List<WmlSdtInfo> stack,
    Set<String> ids,
    String context,
  ) {
    if (start) {
      _template(control);
      if (stack.isNotEmpty && !stack.last.hasContent) {
        throw StateError(
          'Cannot save content inside an absent SDT content slot ($context)',
        );
      }
      if (control.id != null && !ids.add(control.id!)) {
        throw StateError(
          'Cannot save duplicate content-control ID ${control.id} ($context)',
        );
      }
      stack.add(control);
    } else {
      if (stack.isEmpty || !identical(stack.last, control)) {
        throw StateError(
          'Cannot save unmatched or crossing content-control boundaries ($context)',
        );
      }
      stack.removeLast();
    }
  }

  static void _blocks(List<WmlBlock> blocks, Set<String> ids, String context) {
    final List<WmlSdtInfo> stack = <WmlSdtInfo>[];
    for (final WmlBlock block in blocks) {
      if (block is WmlSdtBlockBoundary) {
        _marker(block.control, block.isStart, stack, ids, context);
        continue;
      }
      if (stack.isNotEmpty && !stack.last.hasContent) {
        throw StateError(
          'Cannot save content inside an absent SDT content slot ($context)',
        );
      }
      if (block is WmlParagraph) {
        _inlines(block, ids);
      } else if (block is WmlTable) {
        for (final WmlTableRow row in block.rows) {
          for (final WmlTableCell cell in row.cells) {
            _blocks(cell.blocks, ids, 'table cell');
          }
        }
      } else if (block is WmlFrame) {
        _blocks(block.blocks, ids, 'frame');
      }
    }
    if (stack.isNotEmpty) {
      throw StateError(
        'Cannot save an unclosed content control across $context boundaries',
      );
    }
  }

  static void _inlines(WmlParagraph paragraph, Set<String> ids) {
    final List<WmlSdtInfo> stack = <WmlSdtInfo>[];
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlSdtInlineBoundary) {
        _marker(inline.control, inline.isStart, stack, ids, 'paragraph');
      } else if (stack.isNotEmpty && !stack.last.hasContent) {
        throw StateError('Cannot save text inside an absent SDT content slot');
      }
    }
    if (stack.isNotEmpty) {
      throw StateError(
        'Cannot save an inline content control split across paragraphs',
      );
    }
  }
}
