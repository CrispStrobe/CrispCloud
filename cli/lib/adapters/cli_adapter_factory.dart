// lib/adapters/cli_adapter_factory.dart
//
// Creates provider adapter instances from a CLI config map.
// Only providers whose dependencies are pure Dart are supported here:
//   - S3  (http + crypto)
//   - SFTP (dartssh2)
//   - WebDAV (http)

import '../config/cli_config.dart';
import 'cli_storage_client.dart';
import 's3_adapter.dart';
import 'sftp_adapter.dart';
import 'webdav_adapter.dart';

/// Create a [CliStorageClient] for the named provider.
///
/// [config] is the raw provider map from the CLI config file.
/// Throws [CliConfigException] for unknown or misconfigured providers.
CliStorageClient createAdapter(String providerName, Map<String, dynamic> config) {
  final type = config['type'] as String?;
  if (type == null) {
    throw CliConfigException(
      'Provider "$providerName" has no "type" field in config.',
    );
  }

  switch (type.toLowerCase()) {
    case 's3':
      return S3CliAdapter.fromConfig(config);
    case 'sftp':
      return SftpCliAdapter.fromConfig(config);
    case 'webdav':
      return WebDavCliAdapter.fromConfig(config);
    default:
      throw CliConfigException(
        'Unsupported provider type "$type". '
        'Supported types: s3, sftp, webdav.',
      );
  }
}
