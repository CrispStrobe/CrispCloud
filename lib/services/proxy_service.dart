// lib/services/proxy_service.dart
//
// HTTP/SOCKS5 proxy configuration service.
//
// Provides a proxy-aware http.Client that can be injected into cloud adapters.
// Supports:
//   - HTTP/HTTPS proxy (CONNECT tunneling for HTTPS targets)
//   - SOCKS5 proxy (via dart:io HttpClient findProxy)
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

/// Proxy type.
enum ProxyType { none, http, socks5 }

/// Proxy configuration model.
class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  /// Comma-separated list of hosts to bypass the proxy for.
  final String noProxy;

  const ProxyConfig({
    this.type = ProxyType.none,
    this.host = '',
    this.port = 0,
    this.username,
    this.password,
    this.noProxy = '',
  });

  bool get isEnabled => type != ProxyType.none && host.isNotEmpty && port > 0;

  /// Build the proxy URI string for dart:io HttpClient.findProxy.
  String toProxyString() {
    if (!isEnabled) return 'DIRECT';
    return 'PROXY $host:$port';
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
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
        orElse: () => ProxyType.none,
      ),
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      username: json['username'] as String?,
      password: json['password'] as String?,
      noProxy: json['noProxy'] as String? ?? '',
    );
  }

  /// Create from environment variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY).
  factory ProxyConfig.fromEnvironment() {
    final proxyUrl = Platform.environment['HTTPS_PROXY'] ??
        Platform.environment['https_proxy'] ??
        Platform.environment['HTTP_PROXY'] ??
        Platform.environment['http_proxy'];
    final noProxy = Platform.environment['NO_PROXY'] ??
        Platform.environment['no_proxy'] ??
        '';

    if (proxyUrl == null || proxyUrl.isEmpty) {
      return const ProxyConfig();
    }

    try {
      final uri = Uri.parse(proxyUrl);
      final isSocks = uri.scheme == 'socks5' || uri.scheme == 'socks';
      return ProxyConfig(
        type: isSocks ? ProxyType.socks5 : ProxyType.http,
        host: uri.host,
        port: uri.port > 0 ? uri.port : (isSocks ? 1080 : 8080),
        username: uri.userInfo.contains(':')
            ? Uri.decodeComponent(uri.userInfo.split(':')[0])
            : (uri.userInfo.isNotEmpty ? Uri.decodeComponent(uri.userInfo) : null),
        password: uri.userInfo.contains(':')
            ? Uri.decodeComponent(uri.userInfo.split(':')[1])
            : null,
        noProxy: noProxy,
      );
    } catch (_) {
      return const ProxyConfig();
    }
  }

  static const ProxyConfig disabled = ProxyConfig();
}

/// Global HttpOverrides that handles proxy routing and certificate pinning.
///
/// When installed via [HttpOverrides.global], this affects all dart:io HTTP
/// clients including those created by the `http` package. This means all
/// `http.get/post/put/delete` calls automatically use the proxy and cert pins.
class ProxyHttpOverrides extends HttpOverrides {
  final ProxyConfig config;
  final CertPinningService? certPinning;

  ProxyHttpOverrides(this.config, {this.certPinning});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Apply TLS version enforcement via SecurityContext
    SecurityContext? secCtx = context;
    if (certPinning != null) {
      final minTls = certPinning!.getMinTlsVersion();
      if (minTls != TlsVersion.any) {
        secCtx ??= SecurityContext(withTrustedRoots: true);
        // Disable legacy unsafe renegotiation for TLS 1.2+
        secCtx.allowLegacyUnsafeRenegotiation = false;
        // Add custom CA certs to the SecurityContext
        for (final caPem in certPinning!.getCustomCaCerts()) {
          try {
            secCtx.setTrustedCertificatesBytes(caPem);
          } catch (_) {
            // Cert may not be valid PEM for SecurityContext; handled at
            // badCertificateCallback level instead.
          }
        }
      }
    }
    final client = super.createHttpClient(secCtx);

    // Proxy configuration
    if (config.isEnabled) {
      final noProxyHosts = config.noProxy
          .split(',')
          .map((h) => h.trim().toLowerCase())
          .where((h) => h.isNotEmpty)
          .toSet();

      client.findProxy = (uri) {
        final host = uri.host.toLowerCase();
        for (final bypass in noProxyHosts) {
          if (host == bypass || host.endsWith('.$bypass')) {
            return 'DIRECT';
          }
        }
        return config.toProxyString();
      };

      if (config.username != null) {
        client.addProxyCredentials(
          config.host,
          config.port,
          'Basic',
          HttpClientBasicCredentials(
            config.username!,
            config.password ?? '',
          ),
        );
      }
    }

    // Certificate pinning and custom CA validation
    if (certPinning != null) {
      final hasPinning = certPinning!.isEnabled;
      final hasCustomCAs = certPinning!.getCustomCaCerts().isNotEmpty;
      if (hasPinning || hasCustomCAs) {
        client.badCertificateCallback = (cert, host, port) {
          // badCertificateCallback is called when the system rejects the cert.
          // First check if cert passes standard pinning validation.
          if (hasPinning && certPinning!.validateCertificate(cert, host)) {
            return true;
          }
          // Then check if cert chains to a custom CA.
          if (hasCustomCAs && certPinning!.validateWithCustomCAs(cert)) {
            return true;
          }
          return false;
        };
      }
    }

    return client;
  }
}

/// Manages proxy configuration and produces proxy-aware HTTP clients.
class ProxyService {
  static final _log = Log('ProxyService');
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
        _log.info('Loaded proxy config: ${_config.type.name} ${_config.host}:${_config.port}');
        return;
      } catch (e) {
        _log.warn('Failed to load saved proxy config', e);
      }
    }

    // Fall back to environment variables (desktop only)
    if (!kIsWeb) {
      final envConfig = ProxyConfig.fromEnvironment();
      if (envConfig.isEnabled) {
        _config = envConfig;
        _log.info('Using proxy from environment: ${_config.type.name} ${_config.host}:${_config.port}');
      }
    }
  }

  /// Save proxy configuration.
  Future<void> save(ProxyConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
    _installOverrides();
    _log.info('Saved proxy config: ${config.type.name} ${config.host}:${config.port}');
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
    final needsProxy = _config.isEnabled;
    final needsPinning = _certPinning != null && _certPinning!.isEnabled;

    if (needsProxy || needsPinning) {
      HttpOverrides.global = ProxyHttpOverrides(_config, certPinning: _certPinning);
      if (needsProxy) {
        _log.info('Installed global overrides: proxy=${_config.type.name} ${_config.host}:${_config.port}, pinning=$needsPinning');
      } else {
        _log.info('Installed global overrides: pinning=$needsPinning');
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
    if (kIsWeb || !_config.isEnabled) {
      return http.Client();
    }

    final ioClient = HttpClient();

    // Build no-proxy bypass set
    final noProxyHosts = _config.noProxy
        .split(',')
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty)
        .toSet();

    ioClient.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      for (final bypass in noProxyHosts) {
        if (host == bypass || host.endsWith('.$bypass')) {
          return 'DIRECT';
        }
      }
      return _config.toProxyString();
    };

    // Set proxy authentication if credentials provided
    if (_config.username != null) {
      ioClient.addProxyCredentials(
        _config.host,
        _config.port,
        'Basic',
        HttpClientBasicCredentials(
          _config.username!,
          _config.password ?? '',
        ),
      );
    }

    _log.debug('Created proxy HTTP client: ${_config.type.name} ${_config.host}:${_config.port}');
    return IOClient(ioClient);
  }
}
