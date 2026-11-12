part of 'kdbx_database.dart';

/// Lossless editing surface over the authenticated KDBX envelope.
///
/// The complete XML tree is retained, including unknown elements, attributes,
/// custom data and entry history. Protected XML values remain separately
/// obscured in memory and are re-encrypted in document order for every save.
/// This bypasses the model serializer, which cannot retain unknown XML fields.
class KdbxRawDocument {
  final KdbxHeader header;
  final XmlDocument xml;
  final Map<XmlElement, ProtectedData> _protected = {};
  bool _disposed = false;

  KdbxRawDocument._(this.header, this.xml);

  static Future<KdbxRawDocument> open({
    required List<int> data,
    required KdbxCredentials credentials,
    required void Function(KdbxHeader header) validateHeader,
    int maxDecodedBytes = 32 * 1024 * 1024,
  }) async {
    final reader = BytesReader(data);
    final header = KdbxHeader.fromBytes(
      credentials: credentials,
      reader: reader,
    );
    // Caller policy runs before the first password KDF, allocation or decryption.
    validateHeader(header);
    final XmlDocument xml;
    if (header.version.$1 == 3) {
      xml = _parseBoundedKdbxXml(await KdbxDatabase._decryptXmlV3(
        bytes: reader.readBytesToEnd(),
        header: header,
        maxDecodedBytes: maxDecodedBytes,
      ));
      final stored =
          xml.rootElement.getElement('Meta')?.getElement('HeaderHash');
      if (stored != null &&
          Digest(base64.decode(stored.innerText)) != Digest(header.hash)) {
        throw const FileCorruptedError('header hash mismatch');
      }
    } else {
      xml = await KdbxDatabase._readXmlV4(
        reader: reader,
        header: header,
        maxDecodedBytes: maxDecodedBytes,
      );
    }
    final result = KdbxRawDocument._(header, xml);
    try {
      for (final element in xml.descendants.whereType<XmlElement>()) {
        final protection = element.getAttribute('Protected')?.toLowerCase();
        if (protection != null &&
            protection != 'true' &&
            protection != 'false') {
          throw const UnsupportedValueError('protected attribute');
        }
        if (protection == 'true') {
          if (element.children
              .any((child) => child is! XmlText && child is! XmlCDATA)) {
            throw const UnsupportedValueError('structured protected value');
          }
          final bytes = base64.decode(element.innerText);
          result._protected[element] = ProtectedData.fromProtectedBytes(
            bytes: bytes,
            salt: header.saltGenerator.getSalt(bytes.length),
          );
          element.innerText = '';
          element.setAttribute('Protected', 'True');
        }
      }
      return result;
    } catch (_) {
      result.dispose();
      rethrow;
    }
  }

  bool isProtected(XmlElement element) => _protected.containsKey(element);

  /// Conservative storage estimate used before growing the editing tree.
  int get estimatedBytes {
    _checkOpen();
    var result = _estimateNode(xml) + 1024;
    for (final binary in header.binaries.all) {
      result += binary is ProtectedBinary
          ? binary.protectedData.length
          : binary.data.length;
    }
    return result;
  }

  int estimateHistorySnapshot(XmlElement entry) {
    _checkOpen();
    var result = 1024;
    for (final child in entry.children) {
      if (child is XmlElement && child.name.qualified == 'History') continue;
      result += _estimateNode(child);
    }
    return result;
  }

  int _estimateNode(XmlNode node) {
    var result = utf8.encode(node.toXmlString()).length;
    final elements = [
      if (node is XmlElement) node,
      ...node.descendants.whereType<XmlElement>(),
    ];
    for (final element in elements) {
      final value = _protected[element];
      if (value != null) result += ((value.length + 2) ~/ 3) * 4;
    }
    return result;
  }

  String textOf(XmlElement element) {
    _checkOpen();
    return _protected[element]?.text ?? element.innerText;
  }

  void setText(XmlElement element, String text, {bool? protected}) {
    _checkOpen();
    final shouldProtect = protected ?? isProtected(element);
    _protected.remove(element)?.dispose();
    if (shouldProtect) {
      _protected[element] = ProtectedData.fromString(text);
      element.setAttribute('Protected', 'True');
      element.innerText = '';
    } else {
      element.removeAttribute('Protected');
      element.innerText = text;
    }
  }

  /// Copies a subtree with its protected values, optionally omitting the entry's
  /// direct History child when creating a new history snapshot.
  XmlElement cloneElement(XmlElement source, {bool omitHistory = false}) {
    _checkOpen();
    final copy = XmlElement(
      XmlName(source.name.local, source.name.prefix),
      source.attributes.map((attribute) => attribute.copy()),
    );
    _copyProtected(source, copy);
    for (final child in source.children) {
      if (omitHistory &&
          child is XmlElement &&
          child.name.qualified == 'History') {
        continue;
      }
      final cloned = child.copy();
      copy.children.add(cloned);
      if (child is XmlElement && cloned is XmlElement) {
        _copyProtected(child, cloned);
        final originals = child.descendants.whereType<XmlElement>().iterator;
        final copies = cloned.descendants.whereType<XmlElement>().iterator;
        while (originals.moveNext() && copies.moveNext()) {
          _copyProtected(originals.current, copies.current);
        }
      }
    }
    return copy;
  }

  void _copyProtected(XmlElement original, XmlElement copy) {
    final protected = _protected[original];
    if (protected == null) return;
    final bytes = protected.bytes;
    try {
      _protected[copy] = ProtectedData.fromBytes(bytes);
    } finally {
      CryptoUtils.wipeData(bytes);
    }
  }

  /// Discards protected values belonging to a subtree that is truly removed.
  void forgetElement(XmlElement element) {
    _protected.remove(element)?.dispose();
    for (final child in element.descendants.whereType<XmlElement>()) {
      _protected.remove(child)?.dispose();
    }
  }

  Future<Uint8List> save({int maxDecodedBytes = 32 * 1024 * 1024}) async {
    _checkOpen();
    header.generateSalts();
    final headerBytes = header.bytes;
    final copy = xml.copy();
    final originals = xml.descendants.whereType<XmlElement>().iterator;
    final copies = copy.descendants.whereType<XmlElement>().iterator;
    while (originals.moveNext() && copies.moveNext()) {
      final value = _protected[originals.current];
      if (value == null) continue;
      final bytes = value.bytes;
      final salt = header.saltGenerator.getSalt(bytes.length);
      final encrypted = CryptoUtils.transformXor(data: bytes, salt: salt);
      copies.current.innerText = base64.encode(encrypted);
      CryptoUtils.wipeData(bytes);
      CryptoUtils.wipeData(salt);
      CryptoUtils.wipeData(encrypted);
    }
    if (header.version.$1 == 3) {
      final meta = copy.rootElement.getElement('Meta');
      if (meta == null) throw const FileCorruptedError('missing meta');
      final hash =
          meta.getElement('HeaderHash') ?? XmlElement(XmlName('HeaderHash'));
      if (hash.parent == null) meta.children.add(hash);
      hash.innerText = base64.encode(header.hash);
    }
    // Editing must not produce a file that our bounded reader cannot reopen.
    _validateKdbxXmlEvents(copy.toXmlString());
    final codec = KdbxDatabase._(header: header, meta: KdbxMeta.create());
    final body = header.version.$1 == 3
        ? await codec._getXmlV3Bytes(copy, maxDecodedBytes: maxDecodedBytes)
        : await codec._getXmlV4Bytes(copy, maxDecodedBytes: maxDecodedBytes);
    return Uint8List.fromList([...headerBytes, ...body]);
  }

  void _checkOpen() {
    if (_disposed) throw const InvalidStateError('database is locked');
  }

  /// Best-effort cleanup of mutable buffers and references. Dart does not offer
  /// reliable erasure of immutable strings or garbage-collected copies.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final value in _protected.values) {
      value.dispose();
    }
    _protected.clear();
    header.credentials.dispose();
    header.binaries.dispose();
    CryptoUtils.wipeData(header.protectedStreamKey);
    CryptoUtils.wipeData(header.transformSeed);
    CryptoUtils.wipeData(header.masterSeed);
    CryptoUtils.wipeData(header.encryptionIV);
    CryptoUtils.wipeData(header.streamStartBytes);
    xml.children.clear();
  }
}

XmlDocument _parseBoundedKdbxXml(String text) {
  _validateKdbxXmlEvents(text);
  final xml = XmlDocument.parse(text);
  if (xml.rootElement.name.qualified != 'KeePassFile') {
    throw const FileCorruptedError('invalid database XML');
  }
  return xml;
}

void _validateKdbxXmlEvents(String text) {
  var depth = 0;
  var count = 0;
  for (final event in parseEvents(text)) {
    if (++count > 200000) {
      throw const ResourceLimitError('XML node count');
    }
    if (event is XmlDoctypeEvent) {
      throw const UnsupportedValueError('XML document type declarations');
    }
    if (event is XmlStartElementEvent && !event.isSelfClosing) {
      if (++depth > 64) throw const ResourceLimitError('XML nesting');
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
}
