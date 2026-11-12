import '../../opc/opc_archive.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/wml_document.dart';
import '../model/word_content_controls.dart';
import 'word_opaque_io.dart';

/// Preserves native SDT metadata while its content remains editable model data.
abstract final class WordContentControlIo {
  static WmlContentControlData capture(
    XmlElement source,
    OpcPackage package,
    String owner,
  ) {
    final shell = source.copy();
    shell
        .firstChild('sdtContent', namespaceUri: OfficeNamespaces.w)
        ?.children
        .clear();
    final reader = XmlPullReader(
      XmlDocument(root: shell).toXmlString(declaration: false),
    )..next();
    final metadata = WordOpaqueIo.read(reader, package, owner);
    final properties = source.firstChild(
      'sdtPr',
      namespaceUri: OfficeNamespaces.w,
    );
    String? value(String name) => properties
        ?.firstChild(name, namespaceUri: OfficeNamespaces.w)
        ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
    final control = WmlContentControlData(
      xml: metadata.xml,
      sourcePartUri: metadata.sourcePartUri,
      relationships: metadata.relationships,
      alias: value('alias'),
      tag: value('tag'),
      id: value('id'),
    );
    WordContentControls.template(control);
    return control;
  }

  /// Writes the wrapper and metadata up to the start of editable content.
  /// Returns the prepared shell used by [end] after writing the live children.
  static XmlElement start(
    XmlWriter writer,
    WmlContentControlData control,
    OpcPackage package,
    String owner,
  ) {
    final prepared = XmlWriter();
    WordOpaqueIo.write(
      prepared,
      WmlOpaqueBlock(
        xml: control.xml,
        sourcePartUri: control.sourcePartUri,
        relationships: control.relationships,
      ),
      package,
      owner,
    );
    final shell = XmlDocument.parse(prepared.toXml()).root!;
    final content = shell.firstChild(
      'sdtContent',
      namespaceUri: OfficeNamespaces.w,
    );
    _open(writer, shell);
    for (final child in shell.children) {
      if (identical(child, content)) break;
      child.writeTo(writer);
    }
    if (content != null) {
      writer.writeStartElement(
        content.localName,
        prefix: content.prefix.isEmpty ? null : content.prefix,
      );
      for (final attribute in content.attributes) {
        if (attribute.qualifiedName != 'xmlns:w') {
          writer.writeAttribute(attribute.qualifiedName, attribute.value);
        }
      }
      // Generated live children use w even if their native wrapper used an
      // alias or inherited a foreign binding. Keep the binding local.
      writer.writeNamespace('w', OfficeNamespaces.w);
    }
    return shell;
  }

  static void end(XmlWriter writer, XmlElement shell) {
    if (shell.firstChild('sdtContent', namespaceUri: OfficeNamespaces.w) ==
        null) {
      writer.writeEndElement();
      return;
    }
    writer.writeEndElement();
    var afterContent = false;
    for (final child in shell.children) {
      if (afterContent) child.writeTo(writer);
      if (child is XmlElement &&
          child.localName == 'sdtContent' &&
          child.namespaceUri == OfficeNamespaces.w) {
        afterContent = true;
      }
    }
    writer.writeEndElement();
  }

  static void _open(XmlWriter writer, XmlElement element) {
    writer.writeStartElement(
      element.localName,
      prefix: element.prefix.isEmpty ? null : element.prefix,
    );
    for (final attribute in element.attributes) {
      writer.writeAttribute(attribute.qualifiedName, attribute.value);
    }
  }
}
