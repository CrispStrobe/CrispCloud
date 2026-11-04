import '../xml/xml_reader.dart';
import '../xml/xml_writer.dart';

/// Streaming shared-string table with write-side deduplication.
class SharedStringTable {
  /// SharedStringTable API.
  SharedStringTable({List<String>? strings})
    : _strings = strings ?? <String>[],
      _index = <String, int>{
        for (int i = 0; i < (strings?.length ?? 0); i++) strings![i]: i,
      };

  final List<String> _strings;
  final Map<String, int> _index;

  /// values API.
  List<String> get values => List<String>.unmodifiable(_strings);

  /// length API.
  int get length => _strings.length;

  String operator [](int index) =>
      index >= 0 && index < _strings.length ? _strings[index] : '';

  /// intern API.
  int intern(String value) {
    final int? existing = _index[value];
    if (existing != null) {
      return existing;
    }
    final int id = _strings.length;
    _strings.add(value);
    _index[value] = id;
    return id;
  }

  /// parse API.
  factory SharedStringTable.parse(String xml) {
    final SharedStringTable table = SharedStringTable();
    final XmlPullReader reader = XmlPullReader(xml);
    final StringBuffer text = StringBuffer();
    var inSi = false;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'si') {
        inSi = true;
        text.clear();
      } else if (reader.eventType == XmlEventType.characters && inSi) {
        text.write(reader.text);
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'si') {
        table.intern(text.toString());
        inSi = false;
      }
    }
    return table;
  }

  /// toXml API.
  String toXml() {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('sst');
    w.writeAttribute(
      'xmlns',
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    );
    w.writeAttribute('count', '${_strings.length}');
    w.writeAttribute('uniqueCount', '${_strings.length}');
    for (final String s in _strings) {
      w.writeStartElement('si');
      w.writeStartElement('t');
      w.writeAttribute('xml:space', 'preserve');
      w.writeText(s);
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
    return w.toXml();
  }
}
