// lib/services/proxy_service.dart
//
// HTTP/SOCKS5 proxy configuration service.
//
// Provides a proxy-aware http.Client that can be injected into cloud adapters.
// Supports:
//   - HTTP/HTTPS proxy (CONNECT tunneling for HTTPS targets)
//   - SOCKS5 CONNECT with optional password authentication and remote DNS
//   - No-proxy bypass list (comma-separated hostnames)
//   - Environment variable auto-detection (HTTP_PROXY, HTTPS_PROXY, NO_PROXY)
//   - Manual configuration via ProxyConfig model

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cert_pinning_service.dart';
import 'log_service.dart';
import 'socks5_connector.dart';

/// Proxy type.
enum ProxyType { none, http, socks5 }

/// Proxy configuration model.
class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  /// A selected configuration could not be restored safely. HTTP routing stays
  /// blocked until the user saves corrected settings or explicitly disables it.
  final bool isInvalid;

  /// Comma-separated list of hosts to bypass the proxy for.
  final String noProxy;

  const ProxyConfig({
    this.type = ProxyType.none,
    this.host = '',
    this.port = 0,
    this.username,
    this.password,
    this.noProxy = '',
  }) : isInvalid = false;

  const ProxyConfig.invalid()
    : type = ProxyType.none,
      host = '',
      port = 0,
      username = null,
      password = null,
      noProxy = '',
      isInvalid = true;

  bool get requiresRouting => isInvalid || type != ProxyType.none;

  bool get isEnabled =>
      type != ProxyType.none &&
      host.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535;

  void validate() {
    if (isInvalid) {
      throw const FormatException(
        'Saved proxy settings are invalid. Correct or disable them before connecting.',
      );
    }
    if (type == ProxyType.none) return;
    if (!isEnabled) {
      throw const FormatException(
        'A proxy host and port from 1 to 65535 are required.',
      );
    }
    if (type == ProxyType.socks5) {
      Socks5Connector(
        host: host,
        port: port,
        username: username,
        password: password,
      ).validate();
    }
  }

  /// A hostname entry matches itself and its subdomains. Leading dots follow
  /// the same convention; IP addresses only match exactly. No local DNS query
  /// is performed when deciding whether a destination bypasses the proxy.
  bool bypassesHost(String destination) {
    String normalize(String value) {
      var result = value.trim().toLowerCase();
      if (result.endsWith('.')) result = result.substring(0, result.length - 1);
      if (result.startsWith('[') && result.endsWith(']')) {
        result = result.substring(1, result.length - 1);
      }
      return result;
    }

    final target = normalize(destination);
    final targetAddress = InternetAddress.tryParse(target)?.rawAddress;
    for (final entry in noProxy.split(',')) {
      if (entry.trim() == '*') return true;
      var bypass = normalize(entry);
      if (bypass.startsWith('.')) bypass = bypass.substring(1);
      if (bypass.isEmpty) continue;
      final bypassAddress = InternetAddress.tryParse(bypass)?.rawAddress;
      if (targetAddress != null || bypassAddress != null) {
        if (targetAddress != null &&
            bypassAddress != null &&
            targetAddress.length == bypassAddress.length &&
            targetAddress.indexed.every(
              (byte) => byte.$2 == bypassAddress[byte.$1],
            )) {
          return true;
        }
        continue;
      }
      if (target == bypass || target.endsWith('.$bypass')) {
        return true;
      }
    }
    return false;
  }

  /// Build the proxy URI string for dart:io HttpClient.findProxy.
  String toProxyString() {
    validate();
    if (type == ProxyType.none) return 'DIRECT';
    if (type == ProxyType.socks5) {
      throw UnsupportedError(
        'SOCKS5 requires the socket connector, not an HTTP proxy directive.',
      );
    }
    return 'PROXY $host:$port';
  }

  Map<String, dynamic> toJson() => {
    'type': isInvalid ? 'invalid' : type.name,
    'host': host,
    'port': port,
    if (username != null) 'username': username,
    if (password != null) 'password': password,
    'noProxy': noProxy,
  };

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    return ProxyConfig(
      type: ProxyType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () {
          if (json['type'] == null) return ProxyType.none;
          throw const FormatException('Unknown proxy type.');
        },
      ),
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      username: json['username'] as String?,
      password: json['password'] as String?,
      noProxy: json['noProxy'] as String? ?? '',
    );
  }

  /// Create from environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY).
  factory ProxyConfig.fromEnvironment({Map<String, String>? environment}) {
    if (kIsWeb) return const ProxyConfig();
    final variables = environment ?? Platform.environment;
    final proxyUrl =
        variables['HTTPS_PROXY'] ??
        variables['https_proxy'] ??
        variables['HTTP_PROXY'] ??
        variables['http_proxy'];
    final noProxy = variables['NO_PROXY'] ?? variables['no_proxy'] ?? '';

    if (proxyUrl == null || proxyUrl.trim().isEmpty) {
      return const ProxyConfig();
    }

    try {
      final uri = Uri.parse(proxyUrl);
      final isSocks =
          uri.scheme == 'socks5' ||
          uri.scheme == 'socks5h' ||
          uri.scheme == 'socks';
      if (!isSocks && uri.scheme != 'http') {
        // Native PROXY directives connect to an HTTP proxy. A TLS connection
        // to the proxy itself and other SOCKS versions are not implemented.
        return const ProxyConfig.invalid();
      }
      final credentialsSeparator = uri.userInfo.indexOf(':');
      final config = ProxyConfig(
        type: isSocks ? ProxyType.socks5 : ProxyType.http,
        host: uri.host,
        port: uri.port > 0 ? uri.port : (isSocks ? 1080 : 8080),
        username: credentialsSeparator >= 0
            ? Uri.decodeComponent(
                uri.userInfo.substring(0, credentialsSeparator),
              )
            : (uri.userInfo.isNotEmpty
                  ? Uri.decodeComponent(uri.userInfo)
                  : null),
        password: credentialsSeparator >= 0
            ? Uri.decodeComponent(
                uri.userInfo.substring(credentialsSeparator + 1),
              )
            : null,
        noProxy: noProxy,
      );
      config.validate();
      return config;
    } catch (_) {
      return const ProxyConfig.invalid();
    }
  }

  static const ProxyConfig disabled = ProxyConfig();
}

/// Global HttpOverrides for proxy routing and platform TLS verification.
///
/// When installed via [HttpOverrides.global], this affects all dart:io HTTP
/// clients including those created by the `http` package. Direct FTP, SFTP and
/// SMB sockets and browser networking are outside this HTTP proxy setting.
class ProxyHttpOverrides extends HttpOverrides {
  final ProxyConfig config;
  final CertPinningService? certPinning;

  ProxyHttpOverrides(this.config, {this.certPinning});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Reject an invalid selected proxy instead of connecting directly.
    config.validate();
    final secCtx = certPinning?.configureSecurityContext(context) ?? context;
    final client = super.createHttpClient(secCtx);

    // Proxy configuration
    if (config.type == ProxyType.socks5) {
      final connector = Socks5Connector(
        host: config.host,
        port: config.port,
        username: config.username,
        password: config.password,
      );
      // The custom factory performs SOCKS itself. DIRECT here prevents the
      // native HTTP proxy parser from adding a second proxy or a fallback.
      client.findProxy = (_) => 'DIRECT';
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        if (proxyHost != null || proxyPort != null) {
          throw const SocketException(
            'Cannot combine SOCKS5 with an HTTP proxy.',
          );
        }
        if (config.bypassesHost(uri.host)) {
          if (uri.scheme == 'https') {
            return SecureSocket.startConnect(
              uri.host,
              uri.port,
              context: secCtx,
            );
          }
          return Socket.startConnect(uri.host, uri.port);
        }
        return connector.connect(
          uri,
          securityContext: secCtx,
          timeout: client.connectionTimeout ?? const Duration(seconds: 30),
        );
      };
    } else if (config.type == ProxyType.http) {
      client.findProxy = (uri) =>
          config.bypassesHost(uri.host) ? 'DIRECT' : config.toProxyString();
      if (config.username != null) {
        client.addProxyCredentials(
          config.host,
          config.port,
          'Basic',
          HttpClientBasicCredentials(config.username!, config.password ?? ''),
        );
      }
    }

    // Deliberately leave badCertificateCallback unset: custom trust anchors
    // still require valid signatures, certificate dates and the correct host.
    return client;
  }
}

/// Manages proxy configuration and produces proxy-aware HTTP clients.
class ProxyService {
  static const _log = Log('ProxyService');
  static const _prefsKey = 'proxy_config';

  ProxyConfig _config;
  CertPinningService? _certPinning;

  ProxyConfig get config => _config;
  CertPinningService? get certPinning => _certPinning;

  ProxyService([ProxyConfig? initial, this._certPinning])
    : _config = initial ?? const ProxyConfig();

  /// Load proxy config from SharedPreferences, falling back to environment.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _config = ProxyConfig.fromJson(map);
        _config.validate();
        _log.info(
          'Loaded proxy config: ${_config.type.name} ${_config.host}:${_config.port}',
        );
        return;
      } catch (_) {
        // Decoding errors may contain serialized credentials; do not log them.
        _config = const ProxyConfig.invalid();
        _log.warn(
          'Saved proxy settings are invalid; HTTP routing remains blocked.',
        );
        return;
      }
    }

    // Fall back to environment variables (desktop only)
    if (!kIsWeb) {
      final envConfig = ProxyConfig.fromEnvironment();
      if (envConfig.requiresRouting) {
        _config = envConfig;
        _log.info(
          'Using proxy from environment: ${_config.type.name} ${_config.host}:${_config.port}',
        );
      }
    }
  }

  /// Save proxy configuration.
  Future<void> save(ProxyConfig config) async {
    config.validate();
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
    _installOverrides();
    _log.info(
      'Saved proxy config: ${config.type.name} ${config.host}:${config.port}',
    );
  }

  /// Clear saved proxy config and remove global overrides.
  Future<void> clear() async {
    _config = const ProxyConfig();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _installOverrides();
  }

  /// Install global HttpOverrides so all HTTP traffic uses the proxy.
  /// Call after load() or save().
  void applyGlobally() => _installOverrides();

  /// Set cert pinning service (called from main after both are loaded).
  void setCertPinning(CertPinningService service) {
    _certPinning = service;
  }

  void _installOverrides() {
    if (kIsWeb) return;
    final needsProxy = _config.requiresRouting;
    final needsTlsPolicy = _certPinning != null;

    if (needsProxy || needsTlsPolicy) {
      HttpOverrides.global = ProxyHttpOverrides(
        _config,
        certPinning: _certPinning,
      );
      if (needsProxy) {
        _log.info(
          'Installed global overrides: proxy=${_config.type.name} ${_config.host}:${_config.port}, TLS policy=$needsTlsPolicy',
        );
      } else {
        _log.info('Installed global overrides: platform TLS verification');
      }
    } else {
      HttpOverrides.global = null;
      _log.debug('Cleared global HTTP overrides');
    }
  }

  /// Create an [http.Client] that routes through the configured proxy.
  ///
  /// On web, always returns a plain client (browsers handle proxies natively).
  http.Client createHttpClient() {
    if (kIsWeb || (!_config.requiresRouting && _certPinning == null)) {
      return http.Client();
    }

    // Apply this service's TLS settings even when callers have not installed
    // the global override, and when no proxy is configured.
    final ioClient = ProxyHttpOverrides(
      _config,
      certPinning: _certPinning,
    ).createHttpClient(null);

    _log.debug(
      'Created proxy HTTP client: ${_config.type.name} ${_config.host}:${_config.port}',
    );
    return IOClient(ioClient);
  }
}
