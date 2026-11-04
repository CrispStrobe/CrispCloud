import 'dart:convert';
import 'dart:typed_data';

import 'opc_archive.dart';
import 'relationships.dart';

/// Stream-based OPC part. Bytes stay in the owning [OpcPackage] until
/// [readBytes] or [openStream] is called.
class PackagePart {
  /// PackagePart API.
  PackagePart({
    required this.package,
    required this.uri,
    required this.contentType,
    Uint8List? bytes,
    bool loaded = false,
  }) : _bytes = bytes ?? Uint8List(0),
       _loaded = loaded || bytes != null;

  /// package API.
  final OpcPackage package;

  /// uri API.
  final String uri;

  /// contentType API.
  String contentType;
  Uint8List _bytes;
  bool _loaded;
  RelationshipCollection? _relationships;

  /// isLoaded API.
  bool get isLoaded => _loaded;

  /// Absolute OPC URI of this part's `*.rels` file.
  String get relationshipsUri => OpcUris.relationshipsUriFor(uri);

  /// readBytes API.
  Uint8List readBytes() => Uint8List.fromList(_bytes);

  /// Returns a view of the current payload. Callers must not mutate it.
  Uint8List get bytesView => _bytes;

  /// length API.
  int get length => _bytes.length;

  /// openStream API.
  Stream<List<int>> openStream() =>
      Stream<List<int>>.fromIterable(<List<int>>[_bytes]);

  /// readText API.
  String readText({Encoding encoding = utf8}) => encoding.decode(_bytes);

  /// writeBytes API.
  void writeBytes(Uint8List data) {
    _bytes = Uint8List.fromList(data);
    _loaded = true;
    package.markDirty(this);
  }

  /// writeText API.
  void writeText(String text, {Encoding encoding = utf8}) {
    writeBytes(Uint8List.fromList(encoding.encode(text)));
  }

  /// relationships API.
  RelationshipCollection get relationships {
    return _relationships ??= package.relationshipsFor(uri);
  }

  /// relationships API.
  set relationships(RelationshipCollection value) {
    _relationships = value;
    package.attachRelationships(uri, value);
  }

  /// hasRelationships API.
  bool get hasRelationships =>
      _relationships != null && _relationships!.isNotEmpty;
}

/// OPC URI helpers (ECMA-376 Part 2).
abstract final class OpcUris {
  /// normalize API.
  static String normalize(String uri) {
    String value = uri.replaceAll('\\', '/');
    if (value.isEmpty || value == '/') {
      return '/';
    }
    if (!value.startsWith('/')) {
      value = '/$value';
    }
    final List<String> out = <String>[];
    for (final String segment in value.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (out.isNotEmpty) {
          out.removeLast();
        }
        continue;
      }
      out.add(segment);
    }
    return '/${out.join('/')}';
  }

  /// toZipName API.
  static String toZipName(String opcUri) {
    final String n = normalize(opcUri);
    return n.startsWith('/') ? n.substring(1) : n;
  }

  /// fromZipName API.
  static String fromZipName(String zipName) => normalize(zipName);

  /// relationshipsUriFor API.
  static String relationshipsUriFor(String partUri) {
    final String n = normalize(partUri);
    if (n == '/') {
      return '/_rels/.rels';
    }
    final int slash = n.lastIndexOf('/');
    final String dir = n.substring(0, slash + 1);
    final String name = n.substring(slash + 1);
    return '${dir}_rels/$name.rels';
  }

  /// sourcePartForRelationships API.
  static String? sourcePartForRelationships(String relsUri) {
    final String n = normalize(relsUri);
    if (n == '/_rels/.rels') {
      return '/';
    }
    if (!n.contains('/_rels/') || !n.endsWith('.rels')) {
      return null;
    }
    final int relsDir = n.lastIndexOf('/_rels/');
    final String dir = n.substring(0, relsDir + 1);
    final String file = n.substring(relsDir + 7, n.length - 5);
    return normalize('$dir$file');
  }

  /// resolve API.
  static String resolve(String sourcePartUri, String target) {
    if (target.startsWith('/')) {
      return normalize(target);
    }
    final String source = normalize(sourcePartUri);
    if (source == '/') {
      return normalize('/$target');
    }
    final int slash = source.lastIndexOf('/');
    final String dir = source.substring(0, slash + 1);
    return normalize('$dir$target');
  }

  /// relativize API.
  static String relativize(String sourcePartUri, String targetPartUri) {
    final String source = normalize(sourcePartUri);
    final String target = normalize(targetPartUri);
    if (source == '/') {
      return target.startsWith('/') ? target.substring(1) : target;
    }
    final List<String> src = source.split('/')..removeLast();
    final List<String> dst = target.split('/');
    int i = 0;
    while (i < src.length && i < dst.length && src[i] == dst[i]) {
      i++;
    }
    final StringBuffer buffer = StringBuffer();
    for (int up = i; up < src.length; up++) {
      if (src[up].isEmpty) {
        continue;
      }
      buffer.write('../');
    }
    buffer.write(dst.skip(i).where((String s) => s.isNotEmpty).join('/'));
    return buffer.toString();
  }

  /// isRelationshipsPart API.
  static bool isRelationshipsPart(String uri) {
    final String n = normalize(uri);
    return n == '/_rels/.rels' ||
        (n.contains('/_rels/') && n.endsWith('.rels'));
  }

  /// isContentTypes API.
  static bool isContentTypes(String uri) =>
      normalize(uri) == '/[Content_Types].xml';
}
