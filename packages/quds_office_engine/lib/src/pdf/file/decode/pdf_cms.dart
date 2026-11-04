import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/pdf_extra.dart';

/// CMS / PKCS#7 `SignedData` digest check against the ByteRange payload.
///
/// Compares `messageDigest` (OID 1.2.840.113549.1.9.4) to SHA-1/256/384/512
/// of the signed bytes. Does not verify RSA/ECDSA or a system trust list.
abstract final class PdfCms {
  /// Returns [PdfSignatureStatus.valid] when the encapsulated digest matches.
  static PdfSignatureStatus verify({
    required Uint8List contents,
    required Uint8List signedBytes,
  }) {
    if (contents.isEmpty || _allZero(contents)) {
      return PdfSignatureStatus.unverified;
    }
    final _Der? root = _Der.read(contents);
    if (root == null || !root.constructed) {
      return PdfSignatureStatus.unsupported;
    }
    final List<_Der> seq = root.children;
    if (seq.length < 2) {
      return PdfSignatureStatus.unsupported;
    }
    if (!_oidEq(_oid(seq[0]), _kSignedData)) {
      return PdfSignatureStatus.unsupported;
    }
    final _Der wrapped = seq[1];
    if (!wrapped.constructed || wrapped.children.isEmpty) {
      return PdfSignatureStatus.unsupported;
    }
    final _Der signedData = wrapped.children.first.constructed
        ? wrapped.children.first
        : wrapped;
    final List<_Der> sd = signedData.children;
    if (sd.length < 4) {
      return PdfSignatureStatus.unsupported;
    }
    _Der? signerInfos;
    for (int i = sd.length - 1; i >= 3; i--) {
      if (sd[i].constructed) {
        signerInfos = sd[i];
        break;
      }
    }
    if (signerInfos == null || signerInfos.children.isEmpty) {
      return PdfSignatureStatus.unsupported;
    }
    final _Der signer = signerInfos.children.first.constructed
        ? signerInfos.children.first
        : signerInfos;
    final List<_Der> si = signer.children;
    if (si.length < 3) {
      return PdfSignatureStatus.unsupported;
    }
    List<int>? digestOid;
    Uint8List? messageDigest;
    for (final _Der node in si) {
      if (!node.constructed) {
        continue;
      }
      final List<int>? oid = node.children.isEmpty
          ? null
          : _oid(node.children.first);
      if (oid != null && _digestOf(oid) != null && digestOid == null) {
        digestOid = oid;
      }
      if (node.tag == 0xA0) {
        for (final _Der attr in node.children) {
          if (!attr.constructed || attr.children.length < 2) {
            continue;
          }
          if (!_oidEq(_oid(attr.children[0]), _kMessageDigest)) {
            continue;
          }
          final _Der set = attr.children[1];
          if (set.children.isNotEmpty) {
            messageDigest = set.children.first.body;
          } else if (set.body.isNotEmpty) {
            messageDigest = set.body;
          }
        }
      }
    }
    digestOid ??= _digestOidIn(sd);
    if (digestOid == null) {
      return PdfSignatureStatus.unsupported;
    }
    if (messageDigest == null) {
      return PdfSignatureStatus.unverified;
    }
    final Hash? hash = _digestOf(digestOid);
    if (hash == null) {
      return PdfSignatureStatus.unsupported;
    }
    final List<int> actual = hash.convert(signedBytes).bytes;
    if (actual.length != messageDigest.length) {
      return PdfSignatureStatus.invalid;
    }
    var ok = true;
    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != messageDigest[i]) {
        ok = false;
        break;
      }
    }
    return ok ? PdfSignatureStatus.valid : PdfSignatureStatus.invalid;
  }

  static List<int>? _digestOidIn(List<_Der> signedData) {
    for (final _Der node in signedData) {
      if (!node.constructed) {
        continue;
      }
      for (final _Der child in node.children) {
        final _Der seq = child.constructed ? child : node;
        if (seq.children.isEmpty) {
          continue;
        }
        final List<int>? oid = _oid(seq.children.first);
        if (oid != null && _digestOf(oid) != null) {
          return oid;
        }
      }
    }
    return null;
  }

  static Hash? _digestOf(List<int> oid) {
    if (_oidEq(oid, _kSha1)) {
      return sha1;
    }
    if (_oidEq(oid, _kSha256)) {
      return sha256;
    }
    if (_oidEq(oid, _kSha384)) {
      return sha384;
    }
    if (_oidEq(oid, _kSha512)) {
      return sha512;
    }
    return null;
  }

  static List<int>? _oid(_Der node) {
    if (node.tag != 0x06 || node.body.isEmpty) {
      return null;
    }
    final List<int> out = <int>[node.body[0] ~/ 40, node.body[0] % 40];
    var acc = 0;
    for (int i = 1; i < node.body.length; i++) {
      acc = (acc << 7) | (node.body[i] & 0x7F);
      if ((node.body[i] & 0x80) == 0) {
        out.add(acc);
        acc = 0;
      }
    }
    return out;
  }

  static bool _oidEq(List<int>? a, List<int> b) {
    if (a == null || a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _allZero(Uint8List bytes) {
    for (final int b in bytes) {
      if (b != 0) {
        return false;
      }
    }
    return true;
  }

  static const List<int> _kSignedData = <int>[1, 2, 840, 113549, 1, 7, 2];
  static const List<int> _kMessageDigest = <int>[1, 2, 840, 113549, 1, 9, 4];
  static const List<int> _kSha1 = <int>[1, 3, 14, 3, 2, 26];
  static const List<int> _kSha256 = <int>[2, 16, 840, 1, 101, 3, 4, 2, 1];
  static const List<int> _kSha384 = <int>[2, 16, 840, 1, 101, 3, 4, 2, 2];
  static const List<int> _kSha512 = <int>[2, 16, 840, 1, 101, 3, 4, 2, 3];
}

class _Der {
  _Der(this.tag, this.body, this.children);

  final int tag;
  final Uint8List body;
  final List<_Der> children;

  bool get constructed => (tag & 0x20) != 0;

  static _Der? read(Uint8List bytes, [int offset = 0]) {
    final ({_Der node, int next})? parsed = _parse(bytes, offset);
    return parsed?.node;
  }

  static ({_Der node, int next})? _parse(Uint8List bytes, int i) {
    if (i >= bytes.length) {
      return null;
    }
    final int tag = bytes[i++];
    if (i >= bytes.length) {
      return null;
    }
    var len = bytes[i++];
    if (len == 0x80) {
      return null;
    }
    if (len > 127) {
      final int n = len & 0x7F;
      if (n <= 0 || n > 4 || i + n > bytes.length) {
        return null;
      }
      len = 0;
      for (int k = 0; k < n; k++) {
        len = (len << 8) | bytes[i++];
      }
    }
    if (len < 0 || i + len > bytes.length) {
      return null;
    }
    final Uint8List body = Uint8List.sublistView(bytes, i, i + len);
    final List<_Der> kids = <_Der>[];
    if ((tag & 0x20) != 0) {
      var p = 0;
      while (p < body.length) {
        final ({_Der node, int next})? child = _parse(body, p);
        if (child == null) {
          break;
        }
        kids.add(child.node);
        p = child.next;
      }
    }
    return (node: _Der(tag, body, kids), next: i + len);
  }
}
