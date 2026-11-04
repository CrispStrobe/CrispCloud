import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';
import '../xml/xml_writer.dart';
import 'package_part.dart';

/// Parsed `[Content_Types].xml` (Defaults + Overrides).
class ContentTypes {
  /// ContentTypes API.
  ContentTypes({Map<String, String>? defaults, Map<String, String>? overrides})
    : defaults = defaults ?? <String, String>{},
      overrides = overrides ?? <String, String>{};

  /// File extension (without dot, lower-case) → MIME type.
  final Map<String, String> defaults;

  /// Absolute OPC part name → MIME type.
  final Map<String, String> overrides;

  /// standard API.
  factory ContentTypes.standard() {
    return ContentTypes(
      defaults: <String, String>{
        'rels': 'application/vnd.openxmlformats-package.relationships+xml',
        'xml': 'application/xml',
        'bin': 'application/vnd.openxmlformats-officedocument.oleObject',
        'png': 'image/png',
        'jpeg': 'image/jpeg',
        'jpg': 'image/jpeg',
        'gif': 'image/gif',
        'emf': 'image/x-emf',
        'wmf': 'image/x-wmf',
        'svg': 'image/svg+xml',
      },
    );
  }

  /// parse API.
  factory ContentTypes.parse(String xml) {
    final ContentTypes types = ContentTypes();
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'Default') {
        final String? ext = reader.getAttribute('Extension');
        final String? type = reader.getAttribute('ContentType');
        if (ext != null && type != null) {
          types.defaults[ext.toLowerCase()] = type;
        }
      } else if (reader.localName == 'Override') {
        final String? part = reader.getAttribute('PartName');
        final String? type = reader.getAttribute('ContentType');
        if (part != null && type != null) {
          types.overrides[OpcUris.normalize(part)] = type;
        }
      }
    }
    return types;
  }

  /// contentTypeFor API.
  String contentTypeFor(String partUri) {
    final String uri = OpcUris.normalize(partUri);
    final String? overrideType = overrides[uri];
    if (overrideType != null) {
      return overrideType;
    }
    final int dot = uri.lastIndexOf('.');
    if (dot < 0 || dot == uri.length - 1) {
      return 'application/octet-stream';
    }
    final String ext = uri.substring(dot + 1).toLowerCase();
    return defaults[ext] ?? 'application/octet-stream';
  }

  /// setOverride API.
  void setOverride(String partUri, String contentType) {
    overrides[OpcUris.normalize(partUri)] = contentType;
  }

  /// removeOverride API.
  void removeOverride(String partUri) {
    overrides.remove(OpcUris.normalize(partUri));
  }

  /// setDefault API.
  void setDefault(String extension, String contentType) {
    defaults[extension.toLowerCase()] = contentType;
  }

  /// toXml API.
  String toXml() {
    final XmlWriter writer = XmlWriter();
    writer.writeStartDocument();
    writer.writeStartElement(
      'Types',
      namespaceUri: OfficeNamespaces.contentTypes,
    );
    final List<String> extKeys = defaults.keys.toList()..sort();
    for (final String ext in extKeys) {
      writer.writeStartElement('Default');
      writer.writeAttribute('Extension', ext);
      writer.writeAttribute('ContentType', defaults[ext]!);
      writer.writeEndElement();
    }
    final List<String> partKeys = overrides.keys.toList()..sort();
    for (final String part in partKeys) {
      writer.writeStartElement('Override');
      writer.writeAttribute('PartName', part);
      writer.writeAttribute('ContentType', overrides[part]!);
      writer.writeEndElement();
    }
    writer.writeEndElement();
    return writer.toXml();
  }
}

/// Well-known OPC / Office content types.
abstract final class OfficeContentTypes {
  /// relationships API.
  static const String relationships =
      'application/vnd.openxmlformats-package.relationships+xml';

  /// coreProperties API.
  static const String coreProperties =
      'application/vnd.openxmlformats-package.core-properties+xml';

  /// wordMain API.
  static const String wordMain =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';

  /// wordTemplate API.
  static const String wordTemplate =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml';

  /// sheetMain API.
  static const String sheetMain =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

  /// sheetWorksheet API.
  static const String sheetWorksheet =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

  /// sheetSharedStrings API.
  static const String sheetSharedStrings =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml';

  /// sheetStyles API.
  static const String sheetStyles =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml';

  /// slideMain API.
  static const String slideMain =
      'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml';

  /// slide API.
  static const String slide =
      'application/vnd.openxmlformats-officedocument.presentationml.slide+xml';

  /// slideLayout API.
  static const String slideLayout =
      'application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml';

  /// slideMaster API.
  static const String slideMaster =
      'application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml';

  /// oleObject API.
  static const String oleObject =
      'application/vnd.openxmlformats-officedocument.oleObject';

  /// extendedProperties API.
  static const String extendedProperties =
      'application/vnd.openxmlformats-officedocument.extended-properties+xml';

  /// wordStyles API.
  static const String wordStyles =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml';

  /// wordSettings API.
  static const String wordSettings =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml';

  /// wordNumbering API.
  static const String wordNumbering =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml';

  /// wordComments API.
  static const String wordComments =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml';

  /// wordCommentsExtended API.
  static const String wordCommentsExtended =
      'application/vnd.ms-word.commentsExtended+xml';

  /// drawingChart API.
  static const String drawingChart =
      'application/vnd.openxmlformats-officedocument.drawingml.chart+xml';

  /// theme API.
  static const String theme =
      'application/vnd.openxmlformats-officedocument.theme+xml';

  /// slidePresProps API.
  static const String slidePresProps =
      'application/vnd.openxmlformats-officedocument.presentationml.presProps+xml';

  /// slideViewProps API.
  static const String slideViewProps =
      'application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml';

  /// slideTableStyles API.
  static const String slideTableStyles =
      'application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml';

  /// notesSlide API.
  static const String notesSlide =
      'application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml';

  /// notesMaster API.
  static const String notesMaster =
      'application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml';

  /// wordHeader API.
  static const String wordHeader =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml';

  /// wordFooter API.
  static const String wordFooter =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml';

  /// wordFootnotes API.
  static const String wordFootnotes =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml';

  /// wordEndnotes API.
  static const String wordEndnotes =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml';

  /// spreadsheetDrawing API.
  static const String spreadsheetDrawing =
      'application/vnd.openxmlformats-officedocument.drawing+xml';
}
