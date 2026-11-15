import 'dart:convert';
import 'dart:typed_data';

/// What a file named `.doc` actually contains. Word itself writes several
/// non-binary formats under that extension ("Web Page", "Word 2003 XML",
/// RTF), and mail and download tools rename others.
enum LegacyWordFileKind {
  /// OLE compound document: Word 97 and later (and Word 6/95).
  compound('Word 97–2003 document'),

  /// Rich Text Format.
  rtf('RTF document'),

  /// PDF.
  pdf('PDF document'),

  /// ZIP container: a .docx/.odt (or another ZIP) with the wrong extension.
  zip('ZIP package (.docx or .odt)'),

  /// Word "Single File Web Page" (MHTML).
  mhtml('Word web archive (MHTML)'),

  /// HTML, including Word's "Web Page" format.
  html('HTML document'),

  /// Word 2003 XML (WordprocessingML 2003, flat OPC or `w:wordDocument`).
  wordXml('Word XML document'),

  /// Word for DOS / Word for Windows 1.x and 2.x binary.
  wordForDos('Word for DOS / Word 1–2 document'),

  /// WordPerfect.
  wordPerfect('WordPerfect document'),

  /// Plain text.
  text('plain text'),

  /// Office owner/lock file (`~$name.doc`, 162 bytes): the name of the user
  /// who has the real document open, not a document.
  lockFile('Office lock file (~\$…), not a document'),

  /// Zero bytes.
  empty('empty file'),

  /// Only zero bytes (an interrupted copy or download).
  zeroFilled('file containing only zero bytes'),

  /// Unrecognised content.
  unknown('unrecognised file');

  const LegacyWordFileKind(this.label);

  /// Human-readable name for messages.
  final String label;
}

/// Thrown instead of a bare [FormatException] when the bytes are not a
/// compound document; [kind] lets callers route the file to the right reader.
class LegacyWordNotCompoundException extends FormatException {
  LegacyWordNotCompoundException(this.kind)
    : super(
        kind == LegacyWordFileKind.compound
            ? 'Not a compound document: the compound header is truncated'
            : 'Not a compound document: the file is a ${kind.label}',
      );

  /// The detected format.
  final LegacyWordFileKind kind;
}

/// Identifies the format of [bytes] from its signature (no parsing).
LegacyWordFileKind sniffLegacyWordFile(Uint8List bytes) {
  if (bytes.isEmpty) return LegacyWordFileKind.empty;
  bool startsWith(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    return LegacyWordFileKind.compound;
  }
  if (startsWith(const [0x50, 0x4B, 0x03, 0x04])) return LegacyWordFileKind.zip;
  if (startsWith(const [0xFF, 0x57, 0x50, 0x43])) {
    return LegacyWordFileKind.wordPerfect;
  }
  // Word for Windows 1.x/DOS (0xBE31) and Word 2.x (0xA5DB) FIB magic.
  if (startsWith(const [0x31, 0xBE, 0x00, 0x00]) ||
      startsWith(const [0xDB, 0xA5, 0x2D, 0x00])) {
    return LegacyWordFileKind.wordForDos;
  }
  // Owner file: one length byte, the user name (ANSI), padding; 162 bytes.
  if (bytes.length == 162 && bytes[0] > 0 && bytes[0] <= 54) {
    var printable = true;
    for (var i = 1; i <= bytes[0]; i++) {
      if (bytes[i] < 0x20) printable = false;
    }
    if (printable) return LegacyWordFileKind.lockFile;
  }
  if (bytes.every((b) => b == 0)) return LegacyWordFileKind.zeroFilled;
  final head = _textHead(bytes);
  if (head.startsWith('{\\rtf')) return LegacyWordFileKind.rtf;
  // PDF readers accept the header anywhere in the first kilobyte.
  if (head.contains('%PDF-')) return LegacyWordFileKind.pdf;
  final lower = head.toLowerCase();
  if (lower.startsWith('mime-version:') ||
      (lower.contains('mime-version:') &&
          lower.contains('multipart/related'))) {
    return LegacyWordFileKind.mhtml;
  }
  if (lower.contains('<w:worddocument') ||
      lower.contains('<pkg:package') ||
      lower.contains('progid="word.document"')) {
    return LegacyWordFileKind.wordXml;
  }
  if (lower.startsWith('<!doctype html') ||
      lower.startsWith('<html') ||
      (lower.startsWith('<') && lower.contains('<html'))) {
    return LegacyWordFileKind.html;
  }
  if (bytes.isNotEmpty && _looksLikeText(bytes)) return LegacyWordFileKind.text;
  return LegacyWordFileKind.unknown;
}

String _textHead(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final end = bytes.length < start + 1024 ? bytes.length : start + 1024;
  // UTF-16 BOMs (Word's "Unicode text"/HTML exports).
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    final little = bytes[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < end; i += 2) {
      units.add(
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units).trimLeft();
  }
  return latin1.decode(bytes.sublist(start, end)).trimLeft();
}

bool _looksLikeText(Uint8List bytes) {
  final end = bytes.length < 4096 ? bytes.length : 4096;
  var control = 0;
  for (var i = 0; i < end; i++) {
    final b = bytes[i];
    if (b == 0) return false;
    if (b < 0x09 || (b > 0x0D && b < 0x20)) control++;
  }
  return control * 100 <= end;
}
