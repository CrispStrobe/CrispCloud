import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import 'omml_document.dart';

/// Reads and writes Office Math (`m:oMath` / `m:oMathPara`).
abstract final class OmmlIo {
  /// writeEquation API.
  static void writeEquation(XmlWriter w, OmmlEquation equation) {
    w.writeStartElement('oMathPara', prefix: 'm');
    if (equation.display == OmmlDisplay.display) {
      w.writeStartElement('oMathParaPr', prefix: 'm');
      w.writeEmptyElement(
        'jc',
        prefix: 'm',
        attributes: <String, String>{'m:val': 'center'},
      );
      w.writeEndElement();
    }
    writeMath(w, equation);
    w.writeEndElement();
  }

  /// writeMath API.
  static void writeMath(XmlWriter w, OmmlEquation equation) {
    w.writeStartElement('oMath', prefix: 'm');
    writeSeq(w, equation.root);
    w.writeEndElement();
  }

  /// writeSeq API.
  static void writeSeq(XmlWriter w, OmmlSeq seq) {
    for (final OmmlNode child in seq.children) {
      writeNode(w, child);
    }
  }

  /// writeNode API.
  static void writeNode(XmlWriter w, OmmlNode node) {
    switch (node) {
      case OmmlSeq():
        writeSeq(w, node);
      case OmmlText():
        w.writeStartElement('r', prefix: 'm');
        if (node.normal || !node.italic) {
          w.writeStartElement('rPr', prefix: 'm');
          w.writeEmptyElement(
            'sty',
            prefix: 'm',
            attributes: <String, String>{'m:val': node.normal ? 'p' : 'p'},
          );
          w.writeEndElement();
        }
        w.writeStartElement('t', prefix: 'm');
        w.writeAttribute('xml:space', 'preserve');
        w.writeText(node.text);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlFrac():
        w.writeStartElement('f', prefix: 'm');
        w.writeStartElement('fPr', prefix: 'm');
        w.writeEmptyElement(
          'type',
          prefix: 'm',
          attributes: <String, String>{
            'm:val': switch (node.type) {
              OmmlFracType.bar => 'bar',
              OmmlFracType.noBar => 'noBar',
              OmmlFracType.skewed => 'skw',
              OmmlFracType.linear => 'lin',
            },
          },
        );
        w.writeEndElement();
        w.writeStartElement('num', prefix: 'm');
        writeSeq(w, node.num);
        w.writeEndElement();
        w.writeStartElement('den', prefix: 'm');
        writeSeq(w, node.den);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlScript():
        final String tag = switch (node.kind) {
          OmmlScriptKind.sub => 'sSub',
          OmmlScriptKind.sup => 'sSup',
          OmmlScriptKind.subSup => 'sSubSup',
          OmmlScriptKind.preSubSup => 'sPre',
        };
        w.writeStartElement(tag, prefix: 'm');
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.base);
        w.writeEndElement();
        if (node.sub != null) {
          w.writeStartElement('sub', prefix: 'm');
          writeSeq(w, node.sub!);
          w.writeEndElement();
        }
        if (node.sup != null) {
          w.writeStartElement('sup', prefix: 'm');
          writeSeq(w, node.sup!);
          w.writeEndElement();
        }
        w.writeEndElement();
      case OmmlRad():
        w.writeStartElement('rad', prefix: 'm');
        if (node.deg != null) {
          w.writeStartElement('deg', prefix: 'm');
          writeSeq(w, node.deg!);
          w.writeEndElement();
        }
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlNary():
        w.writeStartElement('nary', prefix: 'm');
        w.writeStartElement('naryPr', prefix: 'm');
        w.writeEmptyElement(
          'chr',
          prefix: 'm',
          attributes: <String, String>{'m:val': node.chr},
        );
        w.writeEndElement();
        if (node.sub != null) {
          w.writeStartElement('sub', prefix: 'm');
          writeSeq(w, node.sub!);
          w.writeEndElement();
        }
        if (node.sup != null) {
          w.writeStartElement('sup', prefix: 'm');
          writeSeq(w, node.sup!);
          w.writeEndElement();
        }
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlDelim():
        w.writeStartElement('d', prefix: 'm');
        w.writeStartElement('dPr', prefix: 'm');
        if (node.begChr.isNotEmpty) {
          w.writeEmptyElement(
            'begChr',
            prefix: 'm',
            attributes: <String, String>{'m:val': node.begChr},
          );
        }
        if (node.endChr.isNotEmpty) {
          w.writeEmptyElement(
            'endChr',
            prefix: 'm',
            attributes: <String, String>{'m:val': node.endChr},
          );
        }
        w.writeEndElement();
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlMatrix():
        w.writeStartElement('m', prefix: 'm');
        for (final List<OmmlSeq> row in node.rows) {
          w.writeStartElement('mr', prefix: 'm');
          for (final OmmlSeq cell in row) {
            w.writeStartElement('e', prefix: 'm');
            writeSeq(w, cell);
            w.writeEndElement();
          }
          w.writeEndElement();
        }
        w.writeEndElement();
      case OmmlAcc():
        w.writeStartElement('acc', prefix: 'm');
        w.writeStartElement('accPr', prefix: 'm');
        w.writeEmptyElement(
          'chr',
          prefix: 'm',
          attributes: <String, String>{'m:val': node.chr},
        );
        w.writeEndElement();
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlFunc():
        w.writeStartElement('func', prefix: 'm');
        w.writeStartElement('fName', prefix: 'm');
        writeNode(w, OmmlText(text: node.name, italic: false, normal: true));
        w.writeEndElement();
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlLimLow():
        w.writeStartElement('limLow', prefix: 'm');
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeStartElement('lim', prefix: 'm');
        writeSeq(w, node.lim);
        w.writeEndElement();
        w.writeEndElement();
      case OmmlBar():
        w.writeStartElement('bar', prefix: 'm');
        w.writeStartElement('e', prefix: 'm');
        writeSeq(w, node.e);
        w.writeEndElement();
        w.writeEndElement();
    }
  }

  /// readFrom API.
  static OmmlEquation? readFrom(XmlPullReader reader) {
    if (reader.localName == 'oMathPara') {
      return _readMathPara(reader);
    }
    if (reader.localName == 'oMath') {
      return OmmlEquation(root: _readSeq(reader), display: OmmlDisplay.inline);
    }
    return null;
  }

  static OmmlEquation _readMathPara(XmlPullReader reader) {
    OmmlSeq root = OmmlSeq();
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (reader.localName == 'oMath') {
          root = _readSeq(reader);
        }
      }
    }
    return OmmlEquation(root: root, display: OmmlDisplay.display);
  }

  static OmmlSeq _readSeq(XmlPullReader reader) {
    final OmmlSeq seq = OmmlSeq();
    if (reader.isEmptyElement) {
      return seq;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.namespaceUri != OfficeNamespaces.m && reader.prefix != 'm') {
        continue;
      }
      final OmmlNode? node = _readNode(reader);
      if (node != null) {
        seq.children.add(node);
      }
    }
    return seq;
  }

  static OmmlNode? _readNode(XmlPullReader reader) {
    switch (reader.localName) {
      case 'r':
        return _readRun(reader);
      case 't':
        return OmmlText(text: _elementText(reader));
      case 'f':
        return _readFrac(reader);
      case 'sSub':
        return _readScript(reader, OmmlScriptKind.sub);
      case 'sSup':
        return _readScript(reader, OmmlScriptKind.sup);
      case 'sSubSup':
        return _readScript(reader, OmmlScriptKind.subSup);
      case 'sPre':
        return _readScript(reader, OmmlScriptKind.preSubSup);
      case 'rad':
        return _readRad(reader);
      case 'nary':
        return _readNary(reader);
      case 'd':
        return _readDelim(reader);
      case 'm':
        return _readMatrix(reader);
      case 'acc':
        return _readAcc(reader);
      case 'func':
        return _readFunc(reader);
      case 'limLow':
        return _readLimLow(reader);
      case 'bar':
        return OmmlBar(e: _readNamedSeq(reader, 'e') ?? OmmlSeq());
      case 'e':
      case 'num':
      case 'den':
      case 'sub':
      case 'sup':
      case 'deg':
      case 'lim':
        return _readSeq(reader);
      default:
        reader.skip();
        return null;
    }
  }

  static OmmlText _readRun(XmlPullReader reader) {
    var text = '';
    var normal = false;
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (reader.localName == 't') {
          text += _elementText(reader);
        } else if (reader.localName == 'sty') {
          final String? val =
              reader.getAttribute('val') ??
              reader.getAttribute('val', namespaceUri: OfficeNamespaces.m);
          normal = val == 'p';
        }
      }
    }
    return OmmlText(text: text, italic: !normal, normal: normal);
  }

  static OmmlFrac _readFrac(XmlPullReader reader) {
    OmmlSeq num = OmmlSeq();
    OmmlSeq den = OmmlSeq();
    var type = OmmlFracType.bar;
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'num':
          num = _readSeq(r);
        case 'den':
          den = _readSeq(r);
        case 'type':
          type = switch (r.getAttribute('val') ??
              r.getAttribute('val', namespaceUri: OfficeNamespaces.m)) {
            'noBar' => OmmlFracType.noBar,
            'skw' => OmmlFracType.skewed,
            'lin' => OmmlFracType.linear,
            _ => OmmlFracType.bar,
          };
      }
    });
    return OmmlFrac(num: num, den: den, type: type);
  }

  static OmmlScript _readScript(XmlPullReader reader, OmmlScriptKind kind) {
    OmmlSeq base = OmmlSeq();
    OmmlSeq? sub;
    OmmlSeq? sup;
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'e':
          base = _readSeq(r);
        case 'sub':
          sub = _readSeq(r);
        case 'sup':
          sup = _readSeq(r);
      }
    });
    return OmmlScript(base: base, sub: sub, sup: sup, kind: kind);
  }

  static OmmlRad _readRad(XmlPullReader reader) {
    OmmlSeq? deg;
    OmmlSeq e = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'deg':
          deg = _readSeq(r);
        case 'e':
          e = _readSeq(r);
      }
    });
    return OmmlRad(deg: deg, e: e);
  }

  static OmmlNary _readNary(XmlPullReader reader) {
    var chr = '∫';
    OmmlSeq? sub;
    OmmlSeq? sup;
    OmmlSeq e = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'chr':
          chr =
              r.getAttribute('val') ??
              r.getAttribute('val', namespaceUri: OfficeNamespaces.m) ??
              chr;
        case 'sub':
          sub = _readSeq(r);
        case 'sup':
          sup = _readSeq(r);
        case 'e':
          e = _readSeq(r);
      }
    });
    return OmmlNary(chr: chr, sub: sub, sup: sup, e: e);
  }

  static OmmlDelim _readDelim(XmlPullReader reader) {
    var beg = '(';
    var end = ')';
    OmmlSeq e = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'begChr':
          beg =
              r.getAttribute('val') ??
              r.getAttribute('val', namespaceUri: OfficeNamespaces.m) ??
              beg;
        case 'endChr':
          end =
              r.getAttribute('val') ??
              r.getAttribute('val', namespaceUri: OfficeNamespaces.m) ??
              end;
        case 'e':
          e = _readSeq(r);
      }
    });
    return OmmlDelim(begChr: beg, endChr: end, e: e);
  }

  static OmmlMatrix _readMatrix(XmlPullReader reader) {
    final List<List<OmmlSeq>> rows = <List<OmmlSeq>>[];
    _walkChildren(reader, (XmlPullReader r) {
      if (r.localName != 'mr') {
        return;
      }
      final List<OmmlSeq> row = <OmmlSeq>[];
      _walkChildren(r, (XmlPullReader cell) {
        if (cell.localName == 'e') {
          row.add(_readSeq(cell));
        }
      });
      rows.add(row);
    });
    return OmmlMatrix(rows: rows.isEmpty ? null : rows);
  }

  static OmmlAcc _readAcc(XmlPullReader reader) {
    var chr = 'ˆ';
    OmmlSeq e = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'chr':
          chr =
              r.getAttribute('val') ??
              r.getAttribute('val', namespaceUri: OfficeNamespaces.m) ??
              chr;
        case 'e':
          e = _readSeq(r);
      }
    });
    return OmmlAcc(chr: chr, e: e);
  }

  static OmmlFunc _readFunc(XmlPullReader reader) {
    var name = 'sin';
    OmmlSeq e = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'fName':
          name = OmmlLinearPlain.collect(_readSeq(r));
        case 'e':
          e = _readSeq(r);
      }
    });
    return OmmlFunc(name: name, e: e);
  }

  static OmmlLimLow _readLimLow(XmlPullReader reader) {
    OmmlSeq e = OmmlSeq();
    OmmlSeq lim = OmmlSeq();
    _walkChildren(reader, (XmlPullReader r) {
      switch (r.localName) {
        case 'e':
          e = _readSeq(r);
        case 'lim':
          lim = _readSeq(r);
      }
    });
    return OmmlLimLow(e: e, lim: lim);
  }

  static OmmlSeq? _readNamedSeq(XmlPullReader reader, String name) {
    OmmlSeq? found;
    _walkChildren(reader, (XmlPullReader r) {
      if (r.localName == name) {
        found = _readSeq(r);
      }
    });
    return found;
  }

  static void _walkChildren(
    XmlPullReader reader,
    void Function(XmlPullReader reader) onStart,
  ) {
    if (reader.isEmptyElement) {
      return;
    }
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.startElement) {
        onStart(reader);
      }
    }
  }

  static String _elementText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final int depth = reader.depth;
    final StringBuffer buffer = StringBuffer();
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }
}

/// Class OmmlLinearPlain.
abstract final class OmmlLinearPlain {
  /// collect API.
  static String collect(OmmlSeq seq) {
    final StringBuffer buf = StringBuffer();
    void walk(OmmlNode node) {
      switch (node) {
        case OmmlText():
          buf.write(node.text);
        case OmmlSeq():
          for (final OmmlNode child in node.children) {
            walk(child);
          }
        default:
          break;
      }
    }

    walk(seq);
    return buf.toString();
  }
}
