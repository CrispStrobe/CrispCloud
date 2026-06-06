// lib/services/azure_config_service.dart
//
// Configuration service for Azure Blob Storage.
// Supports three credential modes:
//   1. SAS token (Shared Access Signature) — simplest, no key needed
//   2. Account name + Account key — HMAC-SHA256 SharedKey auth
//   3. Connection string — parsed into name/key/endpoint

import 'log_service.dart';
import 'secure_storage_service.dart';

/// Parsed result from a connection string.
class AzureConnectionInfo {
  final String accountName;
  final String accountKey;
  final String endpointSuffix;
  final String defaultEndpointsProtocol;

  const AzureConnectionInfo({
    required this.accountName,
    required this.accountKey,
    required this.endpointSuffix,
    required this.defaultEndpointsProtocol,
  });

  String get blobEndpoint =>
      '$defaultEndpointsProtocol://$accountName.blob.$endpointSuffix';
}

class AzureConfigService {
  static const _log = Log('AzureConfig');
  static const _credKey = 'azure_credentials';

  final SecureStorage _secure;

  AzureConfigService({required SecureStorage secureStorage})
      : _secure = secureStorage;

  // ── Credential persistence ──────────────────────────────────────────────────

  Future<Map<String, String>?> readCredentials() async {
    try {
      return await _secure.readMap(_credKey);
    } catch (e) {
      _log.warn('Error reading Azure credentials', e);
      return null;
    }
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    try {
      await _secure.writeMap(_credKey, creds);
    } catch (e) {
      _log.error('Error saving Azure credentials', e);
      rethrow;
    }
  }

  Future<void> clearCredentials() async {
    try {
      await _secure.delete(_credKey);
    } catch (e) {
      _log.warn('Error clearing Azure credentials', e);
    }
  }

  // ── Endpoint helpers ─────────────────────────────────────────────────────────

  /// Returns the blob service endpoint for the given account name.
  /// e.g. "myaccount" → "https://myaccount.blob.core.windows.net"
  static String getEndpoint(String accountName) =>
      'https://$accountName.blob.core.windows.net';

  // ── SAS token helpers ────────────────────────────────────────────────────────

  /// Extracts the SAS query string from a full SAS URL.
  ///
  /// Given:
  ///   https://myaccount.blob.core.windows.net/container/blob?sv=2023-11-03&sig=...
  /// Returns:
  ///   sv=2023-11-03&sig=...
  ///
  /// Returns null if the URL has no query string or cannot be parsed.
  static String? parseSasToken(String sasUrl) {
    try {
      final uri = Uri.parse(sasUrl);
      if (uri.query.isEmpty) return null;
      return uri.query;
    } catch (e) {
      return null;
    }
  }

  /// Appends a SAS token to a base URL, handling existing query strings.
  static String appendSasToken(String baseUrl, String sasToken) {
    if (sasToken.isEmpty) return baseUrl;
    final sep = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl$sep$sasToken';
  }

  // ── Connection string parsing ─────────────────────────────────────────────────

  /// Parses an Azure Storage connection string of the canonical form:
  ///   DefaultEndpointsProtocol=https;AccountName=foo;AccountKey=bar==;EndpointSuffix=core.windows.net
  ///
  /// Returns null if the string cannot be parsed or is missing required fields.
  static AzureConnectionInfo? parseConnectionString(String connStr) {
    try {
      final parts = <String, String>{};
      for (final segment in connStr.split(';')) {
        final idx = segment.indexOf('=');
        if (idx < 0) continue;
        final key = segment.substring(0, idx).trim();
        // Value may itself contain '=' (base64 keys), so take everything after first '='
        final value = segment.substring(idx + 1).trim();
        if (key.isNotEmpty) parts[key] = value;
      }

      final accountName = parts['AccountName'];
      final accountKey = parts['AccountKey'];
      if (accountName == null || accountName.isEmpty) return null;
      if (accountKey == null || accountKey.isEmpty) return null;

      final protocol = parts['DefaultEndpointsProtocol'] ?? 'https';
      final suffix = parts['EndpointSuffix'] ?? 'core.windows.net';

      return AzureConnectionInfo(
        accountName: accountName,
        accountKey: accountKey,
        endpointSuffix: suffix,
        defaultEndpointsProtocol: protocol,
      );
    } catch (e) {
      return null;
    }
  }

  /// Extracts the account name from a blob endpoint URL.
  /// e.g. "https://myaccount.blob.core.windows.net" → "myaccount"
  static String? accountNameFromEndpoint(String endpoint) {
    try {
      final host = Uri.parse(endpoint).host; // myaccount.blob.core.windows.net
      final dot = host.indexOf('.');
      if (dot < 0) return null;
      return host.substring(0, dot);
    } catch (_) {
      return null;
    }
  }
}
