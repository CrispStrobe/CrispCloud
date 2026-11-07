// lib/services/cert_pinning_service.dart
//
// Saved TLS trust settings. The historical service name is retained for callers,
// but provider certificate pinning is not supported by the current transport.
// Trust is established only by the platform TLS verifier, with optional custom
// trust anchors. A rejected certificate is never accepted by a name comparison.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

/// Minimum TLS version preference.
enum TlsVersion {
  /// Use the platform default (TLS 1.2 or later).
  /// The historical name remains for existing saved preferences.
  any,

  /// Require TLS 1.2 or higher (default).
  tls12,

  /// Require TLS 1.3 or higher.
  tls13,
}

/// Information about an explicitly imported trust anchor.
class CustomCaCertInfo {
  /// Display identifier. Use a DER certificate fingerprint, never unverified
  /// Subject/Issuer text outside the certificate's signed ASN.1 structure.
  final String subjectDn;
  final String issuerDn;
  final Uint8List pemBytes;

  const CustomCaCertInfo({
    required this.subjectDn,
    required this.issuerDn,
    required this.pemBytes,
  });
}

class CertPinningService {
  static const _log = Log('CertPinning');
  static const _enabledKey = 'cert_pinning_enabled';
  static const _customCaCertsKey = 'custom_ca_certs';
  static const _minTlsVersionKey = 'min_tls_version';
  static final _pemCertificate = RegExp(
    r'-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)-----END CERTIFICATE-----',
  );

  /// The old bad-certificate callback did not implement pinning and weakened
  /// certificate validation. Do not claim protection until a transport can
  /// enforce real pins, together with normal TLS validation, before HTTP data.
  bool get isEnabled => false;

  final List<Uint8List> _customCaCerts = [];
  TlsVersion _minTlsVersion = TlsVersion.tls12;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) == true) {
      _log.warn(
        'Removed unsupported certificate-pinning preference; '
        'normal TLS certificate validation remains enabled.',
      );
    }
    await prefs.remove(_enabledKey);
    await loadCustomCaCerts();
    await _loadMinTlsVersion();
  }

  /// Kept for settings migration. Enabling unsupported pinning must not report
  /// success or install a permissive bad-certificate callback.
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      throw UnsupportedError(
        'Certificate pinning is unavailable. '
        'TLS certificates are still verified.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey);
  }

  /// Configure platform chain, hostname and validity verification. Custom CAs
  /// apply independently of proxy and TLS-version settings.
  ///
  /// Keep an explicitly stricter caller context; never mutate defaultContext.
  SecurityContext configureSecurityContext(SecurityContext? context) {
    final result = context ?? SecurityContext(withTrustedRoots: true);
    result.allowLegacyUnsafeRenegotiation = false;
    if (_minTlsVersion == TlsVersion.tls13) {
      result.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
    } else if (_minTlsVersion == TlsVersion.tls12 &&
        result.minimumTlsProtocolVersion != TlsProtocolVersion.tls1_3) {
      result.minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    }
    for (final pem in _customCaCerts) {
      for (final der in _decodeCertificates(pem)) {
        _addTrustAnchor(result, der);
      }
    }
    return result;
  }

  /// Import PEM (including bundles) or DER only after the native X.509 parser
  /// accepts every certificate. No user-provided label can establish trust.
  Future<void> addCustomCaCert(Uint8List bytes) async {
    final certificates = _validateAndNormalize(bytes);
    _customCaCerts.addAll(certificates);
    await saveCustomCaCerts();
    _log.info('Added ${certificates.length} custom CA certificate(s)');
  }

  Future<void> removeCustomCaCert(int index) async {
    if (index < 0 || index >= _customCaCerts.length) return;
    _customCaCerts.removeAt(index);
    await saveCustomCaCerts();
  }

  /// Defensive copies prevent callers from changing already validated anchors.
  List<Uint8List> getCustomCaCerts() =>
      List.unmodifiable(_customCaCerts.map((cert) => Uint8List.fromList(cert)));

  List<CustomCaCertInfo> getCustomCaCertInfos() {
    return _customCaCerts.map((pem) {
      final der = _decodeCertificates(pem).single;
      return CustomCaCertInfo(
        subjectDn: 'SHA-256: ${sha256.convert(der)}',
        issuerDn: '',
        pemBytes: Uint8List.fromList(pem),
      );
    }).toList();
  }

  Future<void> loadCustomCaCerts() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_customCaCertsKey) ?? const <String>[];
    _customCaCerts.clear();
    for (final encoded in stored) {
      try {
        _customCaCerts.addAll(_validateAndNormalize(base64Decode(encoded)));
      } catch (e) {
        // Invalid old entries are not trust anchors and must never fall back to
        // matching a Subject/CN string from PEM metadata.
        _log.warn('Skipping invalid custom CA certificate', e);
      }
    }
  }

  Future<void> saveCustomCaCerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _customCaCertsKey,
      _customCaCerts.map(base64Encode).toList(),
    );
  }

  static List<Uint8List> _validateAndNormalize(Uint8List bytes) {
    try {
      final certificates = _decodeCertificates(bytes);
      final verifier = SecurityContext();
      for (final der in certificates) {
        _addTrustAnchor(verifier, der);
      }
      return certificates.map(_encodePem).toList();
    } catch (_) {
      throw const FormatException('Import a valid PEM or DER certificate.');
    }
  }

  static List<Uint8List> _decodeCertificates(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('Empty certificate');
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('-----BEGIN')) {
      final matches = _pemCertificate.allMatches(text).toList();
      if (matches.isEmpty ||
          '-----BEGIN CERTIFICATE-----'.allMatches(text).length !=
              matches.length ||
          '-----END CERTIFICATE-----'.allMatches(text).length !=
              matches.length) {
        throw const FormatException('Malformed PEM certificate');
      }
      return matches
          .map(
            (match) =>
                base64Decode(match.group(1)!.replaceAll(RegExp(r'\s'), '')),
          )
          .toList();
    }
    // The native parser below checks that these bytes are an X.509 certificate.
    return [Uint8List.fromList(bytes)];
  }

  static Uint8List _encodePem(Uint8List der) {
    final encoded = base64Encode(der);
    final pem = StringBuffer('-----BEGIN CERTIFICATE-----\n');
    for (var start = 0; start < encoded.length; start += 64) {
      final end = start + 64 < encoded.length ? start + 64 : encoded.length;
      pem.writeln(encoded.substring(start, end));
    }
    pem.writeln('-----END CERTIFICATE-----');
    return Uint8List.fromList(utf8.encode(pem.toString()));
  }

  static void _addTrustAnchor(SecurityContext context, Uint8List der) {
    // dart:io requires one DER certificate at a time on iOS. Other supported
    // platforms accept PEM. Preserve normal platform certificate verification.
    context.setTrustedCertificatesBytes(Platform.isIOS ? der : _encodePem(der));
  }

  TlsVersion getMinTlsVersion() => _minTlsVersion;

  Future<void> setMinTlsVersion(TlsVersion version) async {
    _minTlsVersion = version;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_minTlsVersionKey, version.name);
  }

  Future<void> _loadMinTlsVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_minTlsVersionKey);
    _minTlsVersion = TlsVersion.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => TlsVersion.tls12,
    );
  }
}
