import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ftp_security_mode.dart';

/// Captured FTP read evidence, not an immutable object revision. FTP's SIZE
/// and MDTM can remain unchanged when bytes change; resumed publication must
/// also compare the complete staged file with the original source SHA-256.
class FtpDownloadSnapshot {
  FtpDownloadSnapshot({
    required this.connectionIdentity,
    required this.path,
    required this.size,
    required String modified,
  }) : modified = canonicalModified(modified) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(connectionIdentity) ||
        !path.startsWith('/') ||
        RegExp(r'[\r\n\x00]').hasMatch(path) ||
        size < 0) {
      throw const FormatException('Invalid FTP download snapshot.');
    }
  }

  final String connectionIdentity;
  final String path;
  final int size;
  final String modified;

  static String identity({
    required String host,
    required int port,
    required String username,
    required FtpSecurityMode securityMode,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'ftp',
            host.toLowerCase(),
            port,
            username,
            securityMode.name,
            '/',
          ]),
        ),
      )
      .toString();

  /// MLSD times are UTC calendar fields. The metadata library represents those
  /// fields in a DateTime without marking its timezone; do not reinterpret
  /// them through the machine's local timezone before comparing with MDTM.
  static String listingModified(DateTime value) {
    String part(int value, int width) => value.toString().padLeft(width, '0');
    final fraction = value.millisecond * 1000 + value.microsecond;
    return canonicalModified(
      '${part(value.year, 4)}${part(value.month, 2)}${part(value.day, 2)}'
      '${part(value.hour, 2)}${part(value.minute, 2)}${part(value.second, 2)}'
      '${fraction == 0 ? '' : '.${part(fraction, 6)}'}',
    );
  }

  /// RFC 3659 time-val, retaining all supplied fractional precision. Reject
  /// impossible calendar dates instead of DateTime's overflow normalization.
  static String canonicalModified(String value) {
    final match = RegExp(r'^(\d{14})(?:\.(\d+))?$').firstMatch(value);
    if (match == null || value.length > 80) {
      throw const FormatException('FTP returned an invalid modification time.');
    }
    final base = match.group(1)!;
    final fields = [
      int.parse(base.substring(0, 4)),
      for (var index = 4; index < 14; index += 2)
        int.parse(base.substring(index, index + 2)),
    ];
    final date = DateTime.utc(
      fields[0],
      fields[1],
      fields[2],
      fields[3],
      fields[4],
      fields[5],
    );
    if (fields[0] < 1 ||
        date.year != fields[0] ||
        date.month != fields[1] ||
        date.day != fields[2] ||
        date.hour != fields[3] ||
        date.minute != fields[4] ||
        date.second != fields[5]) {
      throw const FormatException('FTP returned an invalid modification time.');
    }
    final fraction = (match.group(2) ?? '').replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? base : '$base.$fraction';
  }

  String encode() =>
      'ftp-range-v1:${base64Url.encode(utf8.encode(jsonEncode([connectionIdentity, path, size, modified]))).replaceAll('=', '')}';

  factory FtpDownloadSnapshot.decode(String encoded) {
    const prefix = 'ftp-range-v1:';
    if (!encoded.startsWith(prefix) || encoded.length > 16 * 1024) {
      throw const FormatException('Invalid FTP download snapshot.');
    }
    final value = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(encoded.substring(prefix.length))),
      ),
    );
    if (value is! List ||
        value.length != 4 ||
        value[0] is! String ||
        value[1] is! String ||
        value[2] is! int ||
        value[3] is! String) {
      throw const FormatException('Invalid FTP download snapshot.');
    }
    return FtpDownloadSnapshot(
      connectionIdentity: value[0] as String,
      path: value[1] as String,
      size: value[2] as int,
      modified: value[3] as String,
    );
  }

  bool matches(FtpDownloadSnapshot other) =>
      connectionIdentity == other.connectionIdentity &&
      path == other.path &&
      size == other.size &&
      modified == other.modified;
}
